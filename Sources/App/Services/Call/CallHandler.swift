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
    let callId: String
    let phoneNumber: String
    let openAIKey: String
    let twilioAccountSid: String?
    let twilioAPIKey: String?
    let twilioSecret: String?

    let encryptionKey: String?
    let recordingsDecryptionKey: String?

    let eventLoopGroup: any EventLoopGroup
    let httpClient: HTTPClient
    let logger: Logger
    let coordinator: CallFlowCoordinator

    init(
        callId: String,
        phoneNumber: String,
        app: Application
    ) async throws {
        self.encryptionKey = app.storage[EncryptionKeyStorageKey.self]
        self.recordingsDecryptionKey = app.storage[RecordingsDecryptionKeyStorageKey.self]

        self.callId = callId
        self.phoneNumber = phoneNumber
        self.openAIKey = app.storage[OpenAIKeyStorageKey.self] ?? ""
        self.twilioAccountSid = app.storage[TwilioAccountSidStorageKey.self]
        self.twilioAPIKey = app.storage[TwilioAPIKeyStorageKey.self]
        self.twilioSecret = app.storage[TwilioSecretStorageKey.self]

        self.eventLoopGroup = app.eventLoopGroup
        self.httpClient = app.http.client.shared
        self.logger = app.logger

        let featureFlags = app.featureFlags
        let sections: [any QuestionnaireSection] = [
            VitalSignsSection(),
            KCCQ12Section(internalTestingMode: featureFlags.internalTestingMode),
            Q17Section(),
        ]
        self.coordinator = try await CallFlowCoordinator.create(
            sections: sections,
            phoneNumber: phoneNumber,
            logger: logger,
            featureFlags: featureFlags,
            encryptionKey: encryptionKey,
            feedbackProvider: EngageHFFeedbackProvider()
        )
    }

    func accept() async throws {
        do {
            let systemMessage = await coordinator.initialSystemMessage()
            let config = try Constants.loadSessionConfig(systemMessage: systemMessage)
            let configObject = try JSONSerialization.jsonObject(
                with: config.data(using: .utf8) ?? Data())
            let configData = try JSONSerialization.data(withJSONObject: configObject)
            let request = try HTTPClient.Request(
                url: "https://api.openai.com/v1/realtime/calls/\(callId)/accept",
                method: .POST,
                headers: [
                    "Authorization": "Bearer \(openAIKey)",
                    "Content-Type": "application/json",
                ],
                body: .data(configData)
            )
            let response = try await httpClient.execute(request: request).get()
            var responseBody = response.body
            let bodyString =
                responseBody?.readString(length: response.body?.readableBytes ?? 0, encoding: .utf8)
                .map { string in
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
                    "Content-Type": "application/json",
                ]
            )
            _ = try await httpClient.execute(request: request).get()
            await updateCallRecordings()
        } catch {
            await updateCallRecordings()
            throw error
        }
    }

    // swiftlint:disable:next function_body_length
    func openWebsocket() async throws {
        do {
            try await WebSocket.connect(
                to:
                    "wss://api.openai.com/v1/realtime?call_id=\(callId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? callId)",
                headers: ["Authorization": "Bearer \(openAIKey)"],
                on: eventLoopGroup
            ) { [self] webSocket async in
                let session = CallSession(
                    phoneNumber: phoneNumber,
                    coordinator: coordinator,
                    webSocket: webSocket,
                    logger: logger
                )
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

                Task {
                    try? await Task.sleep(for: .seconds(1))
                    do {
                        try await session.sendJSON([
                            "type": "response.create"
                        ])
                    } catch {
                        logger.error("Couldn't send initial message to OpenAI \(error)")
                    }
                }
            }
        } catch let error as WebSocketClient.Error {
            if case .invalidResponseStatus(let head) = error {
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

    private func updateCallRecordings() async {
        #if !DEBUG
            guard let twilioAccountSid,
                let twilioAPIKey,
                let twilioSecret
            else {
                logger.warning(
                    "Couldn't update newest recordings due to missing Twilio credentials.")
                return
            }

            do {
                let twilioAPI = try TwilioAPI(
                    accountSid: twilioAccountSid,
                    apiKey: twilioAPIKey,
                    secret: twilioSecret,
                    httpClient: httpClient
                )

                let recordingService = try CallRecordingService(
                    api: twilioAPI,
                    decryptionKey: recordingsDecryptionKey,
                    encryptionKey: encryptionKey,
                    logger: logger
                )

                try await recordingService.storeNewestRecordings()
            } catch {
                logger.error("Failed to update newest recordings: \(error)")
            }
        #endif
    }
}
