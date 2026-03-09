//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziLLMOpenAI
import Vapor

actor CallSession {
    let phoneNumber: String
    let coordinator: CallFlowCoordinator
    let functions: [String: any LLMFunction]
    let logger: Logger
    let webSocket: WebSocket

    init(
        phoneNumber: String,
        coordinator: CallFlowCoordinator,
        functions: [String: any LLMFunction],
        webSocket: WebSocket,
        logger: Logger
    ) {
        self.phoneNumber = phoneNumber
        self.coordinator = coordinator
        self.functions = functions
        self.webSocket = webSocket
        self.logger = logger
    }

    func handleMessage(_ text: String) async {
        do {
            guard let jsonData = text.data(using: .utf8) else {
                throw Abort(.badRequest, reason: "Failed to convert string to data")
            }
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: jsonData)

            if Constants.logEventTypes.contains(response.type) {
                logger.info("Received event: \(response.type)")
            }

            if response.type == "response.function_call_arguments.done" {
                try await handleFunctionCall(response: response)
            }

            if response.type == "error", let error = response.error {
                logger.error("OpenAI Error: \(error.message) (Code: \(error.code ?? "unknown"))")
            }
        } catch {
            logger.error("Error processing OpenAI message: \(error)")
        }
    }

    func sendJSON(_ object: [String: Any]) async throws {
        let jsonData = try JSONSerialization.data(withJSONObject: object)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Failed to encode JSON")
        }
        logger.info("\(#function) \(jsonString)")
        try await webSocket.send(jsonString)
    }

    func updateSession(systemMessage: String) async throws {
        do {
            logger.info("Updating session with new instructions.")
            try await sendJSON([
                "type": "session.update",
                "session": [
                    "type": "realtime",
                    "instructions": systemMessage
                ]
            ])
        } catch {
            logger.error("Failed to update session: \(error). Closing web socket.")
            try? await webSocket.close()
        }
    }

    private func handleFunctionCall(response: OpenAIResponse) async throws {
        let name = response.name ?? ""
        logger.debug("Function call \"\(name)\"")

        guard let function = functions[name] else {
            logger.error("Unknown function call: \(name)")
            try await sendFunctionOutput(callId: response.callId ?? "", output: "Unknown function.")
            try await sendResponseCreate()
            return
        }

        do {
            if let saveResponseFn = function as? SaveResponseFunction {
                saveResponseFn.rawArguments = response.arguments ?? "{}"
            }

            let output: String
            if let result = try await function.execute() {
                output = result
            } else {
                // SaveResponseFunction returns nil when the current section is complete
                output = try await handleSectionCompletion(response: response)
            }
            try await sendFunctionOutput(callId: response.callId ?? "", output: output)
        } catch {
            logger.error("Error processing function call: \(error)")
            try await sendFunctionOutput(
                callId: response.callId ?? "",
                output: "ERROR: \(error.localizedDescription)"
            )
        }
        try await sendResponseCreate()
    }

    private func sendFunctionOutput(callId: String, output: String) async throws {
        try await sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": output
            ]
        ])
    }

    private func sendResponseCreate() async throws {
        try await sendJSON(["type": "response.create"])
    }

    private func handleSectionCompletion(response: OpenAIResponse) async throws -> String {
        if let nextEngine = await coordinator.advanceToNextSection() {
            let initialQuestion = await nextEngine.nextQuestionJSON(includeAllQuestions: true)
            if let systemMessage = await coordinator.sectionSystemMessage(
                for: nextEngine, initialQuestion: initialQuestion
            ) {
                try await updateSession(systemMessage: systemMessage)
                return "The response was saved. Moving to the next section."
            }
        }
        // All sections complete (or no section system message available)
        let feedback = await coordinator.generateFeedback()
        try await updateSession(systemMessage: Constants.feedback(content: feedback))
        return "The response was saved. All questionnaires are complete."
    }
}
