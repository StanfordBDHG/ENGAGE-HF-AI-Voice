//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor

actor CallHandler {
    // MARK: Stored Properties
    
    let callId: String
    let phoneNumber: String
    let openAIKey: String
    let twilioAccountSid: String?
    let twilioAPIKey: String?
    let twilioSecret: String?
    
    let eventLoopGroup: any EventLoopGroup
    let httpClient: HTTPClient
    let logger: Logger
    let serviceState: ServiceState
    
    // MARK: Initialization
    
    init(
        callId: String,
        phoneNumber: String,
        app: Application,
    ) async {
        let encryptionKey = app.storage[EncryptionKeyStorageKey.self]
        let featureFlags = app.featureFlags
        
        self.callId = callId
        self.phoneNumber = phoneNumber
        self.openAIKey = app.storage[OpenAIKeyStorageKey.self] ?? ""
        self.twilioAccountSid = app.storage[TwilioAccountSidStorageKey.self]
        self.twilioAPIKey = app.storage[TwilioAPIKeyStorageKey.self]
        self.twilioSecret = app.storage[TwilioSecretStorageKey.self]
        
        self.eventLoopGroup = app.eventLoopGroup
        self.httpClient = app.http.client.shared
        self.logger = app.logger
        self.serviceState = await ServiceState(services: [
            VitalSignsService(phoneNumber: phoneNumber, logger: logger, featureFlags: featureFlags, encryptionKey: encryptionKey),
            KCCQ12Service(phoneNumber: phoneNumber, logger: logger, featureFlags: featureFlags, encryptionKey: encryptionKey),
            Q17Service(phoneNumber: phoneNumber, logger: logger, featureFlags: featureFlags, encryptionKey: encryptionKey)
        ])
    }
    
    // MARK: Methods - Connection
    
    func accept() async throws {
        do {
            let systemMessage = await initialSystemMessage()
            let config = Constants.loadSessionConfig(systemMessage: systemMessage)
            let configObject = try JSONSerialization.jsonObject(with: config.data(using: .utf8) ?? Data())
            let configData = try JSONSerialization.data(withJSONObject: configObject)
            let request = try HTTPClient.Request(
                url: "https://api.openai.com/v1/realtime/calls/\(callId)/accept",
                method: .POST,
                headers: [
                    "Authorization": "Bearer \(openAIKey)",
                    "Content-Type": "application/json"
                ],
                body: .data(configData)
            )
            let response = try await httpClient.execute(request: request).get()
            var responseBody = response.body
            let bodyString = responseBody?.readString(length: response.body?.readableBytes ?? 0, encoding: .utf8).map { string in
                var string = string
                string.makeContiguousUTF8()
                return string
            } ?? ""
            logger.info("/accept responded: \(response.status.code) \(bodyString)")
        } catch {
            logger.error("/accept failed: \(error)")
            throw error
        }
    }
    
    func hangup() async throws {
        do {
            let request = try HTTPClient.Request(
                url: "https://api.openai.com/v1/realtime/calls/\(callId)/hangup",
                method: .POST,
                headers: [
                    "Authorization": "Bearer \(openAIKey)",
                    "Content-Type": "application/json"
                ]
            )
            _ = try await httpClient.execute(request: request).get()
            await updateCallRecordings()
        } catch {
            await updateCallRecordings()
            throw error
        }
    }
    
    func openWebsocket() async throws {
        do {
            try await WebSocket.connect(
                to: "wss://api.openai.com/v1/realtime?call_id=\(callId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? callId)",
                headers: ["Authorization": "Bearer \(openAIKey)"],
                on: eventLoopGroup
            ) { [self] webSocket async in
                let session = CallSession(
                    phoneNumber: phoneNumber,
                    serviceState: serviceState,
                    webSocket: webSocket,
                    logger: logger
                )
                do {
                    try await session.sendJSON([
                        "type": "response.create"
                    ])
                } catch {
                    logger.error("Couldn't send initial message to OpenAI \(error)")
                }
                // Handle incoming messages from OpenAI
                webSocket.onText { _, text async in
                    await session.handleMessage(text)
                }
                
                webSocket.onClose.whenComplete { [self] result in
                    switch result {
                    case .success:
                        logger.info("OpenAI WebSocket closed successfully")
                    case .failure(let error):
                        logger.error("OpenAI WebSocket closed with error: \(error)")
                    }
                    Task { [self] in
                        do {
                            try await hangup()
                            logger.info("Successfully hung up")
                        } catch {
                            logger.error("Failed to hang up: \(error)")
                        }
                    }
                }
            }
        } catch let error as WebSocketClient.Error {
            if case let .invalidResponseStatus(head) = error {
                logger.error("OpenAI Realtime API returned \(head.status.code).")
            } else {
                logger.error("Error connecting to the OpenAI Realtime API: \(error)")
            }
            throw error
        } catch {
            logger.error("Error connecting to the OpenAI Realtime API: \(error)")
            throw error
        }
    }
    
    // Methods: Helpers
    
    private func initialSystemMessage() async -> String {
        let hasUnansweredQuestions = await serviceState.initializeCurrentService()
        if !hasUnansweredQuestions {
            let feedback = try? await serviceState.getFeedback(phoneNumber: phoneNumber, logger: logger)
            logger.info("No services have unanswered questions. Updating session with feedback.")
            return Constants.initialSystemMessage
            + Constants.noUnansweredQuestionsLeft
            + Constants.feedback(content: feedback ?? "Feedback failed to be retrieved.")
        } else {
            let initialQuestion = await serviceState.current.getNextQuestion()
            let initialSystemMessage = await Constants.getSystemMessageForService(
                serviceState.current,
                initialQuestion: initialQuestion
            )
            return Constants.initialSystemMessage + (
                initialSystemMessage ?? Constants.noUnansweredQuestionsLeft
            )
        }
    }
    
    private func updateCallRecordings() async {
        guard let twilioAccountSid,
              let twilioAPIKey,
              let twilioSecret else {
            logger.warning("Couldn't update newest recordings due to missing Twilio credentials.")
            return
        }
        
        do {
            let twilioAPI = try TwilioAPI(
                accountSid: twilioAccountSid,
                apiKey: twilioAPIKey,
                secret: twilioSecret,
                httpClient: httpClient
            )
            
            let recordingService = CallRecordingService(api: twilioAPI)
            
            try await recordingService.storeNewestRecordings()
        } catch {
            logger.error("Failed to update newest recordings: \(error)")
        }
    }
}
