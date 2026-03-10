//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziLLMOpenAI
import SpeziLLMOpenAIRealtime
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

    let httpClient: HTTPClient
    let logger: Logger
    let coordinator: CallFlowCoordinator
    let session: LLMOpenAIRealtimeSession

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

        self.httpClient = app.http.client.shared
        self.logger = app.logger

        let featureFlags = config.featureFlags
        let sections: [any QuestionnaireSection] = [
            VitalSignsSection(),
            KCCQ12Section(internalTestingMode: featureFlags.internalTestingMode),
            Q17Section()
        ]
        self.coordinator = try await CallFlowCoordinator(
            sections: sections,
            phoneNumber: phoneNumber,
            logger: app.logger,
            featureFlags: featureFlags,
            feedbackProvider: EngageHFFeedbackProvider(),
            encryptionKey: encryptionKey
        )
        let saveResponseFn = SaveResponseFunction(coordinator: coordinator, logger: app.logger)
        let countFn = CountAnsweredQuestionsFunction(coordinator: coordinator, logger: app.logger)
        let endCallFn = EndCallFunction()

        let escapedCallId = callId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? callId
        let wsURL = URL(string: "wss://api.openai.com/v1/realtime?call_id=\(escapedCallId)")
        let schema = LLMOpenAIRealtimeSchema(
            parameters: LLMOpenAIRealtimeParameters(
                modelType: .gptRealtime1_5,
                systemPrompt: nil, // system prompt is configured via the /accept endpoint
                turnDetectionSettings: .semantic(.init(eagerness: .high)),
                transcriptionSettings: nil,
                voice: .alloy,
                webSocketURL: wsURL
            )
        ) {
            saveResponseFn
            countFn
            endCallFn
        }

        let platform = await MainActor.run { app.spezi[LLMOpenAIRealtimePlatform.self] }
        let session = platform(with: schema)
        self.session = session

        endCallFn.onEnd = { [session] in
            session.cancel()
        }
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

    func openSession() async throws {
        do {
            try await session.ensureSetup()

            // Trigger the initial AI greeting after a brief delay
            Task {
                try? await Task.sleep(for: .seconds(1))
                do {
                    try await session.endUserTurn()
                } catch {
                    logger.error("Couldn't trigger initial AI response: \(error)")
                }
            }

            // Monitor session lifecycle: hang up when the WebSocket closes
            Task { [self] in
                do {
                    for try await _ in await session.listen() { }
                } catch {
                    logger.error("Session listen error: \(error)")
                }
                do {
                    try await hangup()
                } catch {
                    logger.error("Failed to hang up: \(error)")
                }
            }
        } catch {
            logger.error("Error setting up OpenAI Realtime session: \(error)")
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
                    "noise_reduction": ["type": "far_field"]
                ],
                "output": [
                    "format": ["type": "audio/pcmu"],
                    "speed": 1.0
                ]
            ],
            "tool_choice": "auto"
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
