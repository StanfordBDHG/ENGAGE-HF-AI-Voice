//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziLLMOpenAI
import SpeziVapor
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
    let functions: [String: any LLMFunction]

    init(
        callId: String,
        phoneNumber: String,
        app: Application
    ) async throws {
        let config = app.spezi[AppConfigModule.self]

        self.encryptionKey = config.encryptionKey
        self.recordingsDecryptionKey = config.recordingsDecryptionKey

        self.callId = callId
        self.phoneNumber = phoneNumber
        self.openAIKey = config.openAIKey ?? ""
        self.twilioAccountSid = config.twilioAccountSid
        self.twilioAPIKey = config.twilioAPIKey
        self.twilioSecret = config.twilioSecret

        self.eventLoopGroup = app.eventLoopGroup
        self.httpClient = app.http.client.shared
        self.logger = app.logger

        let featureFlags = config.featureFlags
        let sections: [any QuestionnaireSection] = [
            VitalSignsSection(),
            KCCQ12Section(internalTestingMode: featureFlags.internalTestingMode),
            Q17Section()
        ]
        let coordinator = try await CallFlowCoordinator(
            sections: sections,
            phoneNumber: phoneNumber,
            logger: app.logger,
            featureFlags: featureFlags,
            feedbackProvider: EngageHFFeedbackProvider(),
            encryptionKey: encryptionKey
        )
        self.coordinator = coordinator

        let saveResponseFn = SaveResponseFunction(coordinator: coordinator, logger: app.logger)
        let countFn = CountAnsweredQuestionsFunction(coordinator: coordinator, logger: app.logger)
        let endCallFn = EndCallFunction()
        self.functions = [
            SaveResponseFunction.name: saveResponseFn,
            CountAnsweredQuestionsFunction.name: countFn,
            EndCallFunction.name: endCallFn
        ]
    }

    func accept() async throws {
        do {
            let systemMessage = await coordinator.initialSystemMessage()
            let payload = buildAcceptPayload(systemMessage: systemMessage)
            let configData = try JSONSerialization.data(withJSONObject: payload)
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
                    functions: functions,
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

    private func buildAcceptPayload(systemMessage: String) -> [String: Any] {
        [
            "type": "realtime",
            "model": "gpt-realtime",
            "instructions": systemMessage,
            "audio": [
                "input": [
                    "format": ["type": "audio/pcmu"],
                    "turn_detection": ["type": "semantic_vad", "eagerness": "high"],
                    "noise_reduction": ["type": "far_field"]
                ],
                "output": [
                    "format": ["type": "audio/pcmu"],
                    "voice": "alloy",
                    "speed": 1.0
                ]
            ],
            "tools": buildToolDefinitions(),
            "tool_choice": "auto"
        ]
    }

    private func buildToolDefinitions() -> [[String: Any]] {
        [
            [
                "type": "function",
                "name": SaveResponseFunction.name,
                "description": SaveResponseFunction.description,
                "parameters": SaveResponseFunction.parameterSchema
            ],
            [
                "type": "function",
                "name": CountAnsweredQuestionsFunction.name,
                "description": CountAnsweredQuestionsFunction.description
            ],
            [
                "type": "function",
                "name": EndCallFunction.name,
                "description": EndCallFunction.description
            ]
        ]
    }

    private func updateCallRecordings() async {
        #if !DEBUG
            guard let twilioAccountSid,
                let twilioAPIKey,
                let twilioSecret
            else {
                logger.warning(
                    "Couldn't update newest recordings due to missing Twilio credentials."
                )
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
