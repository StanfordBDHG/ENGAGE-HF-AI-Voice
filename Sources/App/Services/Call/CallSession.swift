//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor

actor CallSession {
    let phoneNumber: String
    let coordinator: CallFlowCoordinator
    let logger: Logger
    let webSocket: WebSocket

    init(
        phoneNumber: String, coordinator: CallFlowCoordinator, webSocket: WebSocket, logger: Logger
    ) {
        self.phoneNumber = phoneNumber
        self.coordinator = coordinator
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
        logger.debug("Function call \"\(response.name ?? "")\"")
        let engine = await coordinator.currentEngine
        switch response.name {
        case "save_response":
            try await saveResponse(engine: engine, response: response)
        case "count_answered_questions":
            try await countAnsweredQuestions(engine: engine, response: response)
        case "end_call":
            // Closing the web socket is currently disabled due to https://github.com/StanfordBDHG/ENGAGE-HF-AI-Voice/issues/45
            try await sendFunctionOutput(
                callId: response.callId ?? "",
                output: "Call end acknowledged."
            )
            try await sendResponseCreate()
        default:
            logger.error("Unknown function call: \(String(describing: response.name))")
        }
    }

    private func saveResponse(
        engine: FHIRQuestionnaireEngine,
        response: OpenAIResponse
    ) async throws {
        do {
            logger.info("Attempting to save response...")
            guard let arguments = response.arguments else {
                throw Abort(.badRequest, reason: "No arguments provided")
            }
            let argumentsData = arguments.data(using: .utf8) ?? Data()

            do {
                let parsedArgs = try JSONDecoder().decode(
                    QuestionnaireResponseArgs.self, from: argumentsData
                )
                try await saveQuestionnaireAnswer(
                    engine: engine, parsedArgs: parsedArgs
                )
                try await handleSaveSuccess(engine: engine, response: response)
            } catch {
                logger.error("Decoding error details: \(error)")
                try await sendFunctionOutput(
                    callId: response.callId ?? "",
                    output: "ERROR: [\(error.localizedDescription)]"
                )
                try await sendResponseCreate()
            }
        } catch {
            try await handleProcessingError(error: error, response: response)
        }
    }

    func sendFunctionOutput(callId: String, output: String) async throws {
        try await sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": output
            ]
        ])
    }

    func sendResponseCreate() async throws {
        try await sendJSON(["type": "response.create"])
    }

    private func countAnsweredQuestions(
        engine: FHIRQuestionnaireEngine,
        response: OpenAIResponse
    ) async throws {
        let count = await engine.answeredCount()
        logger.info("Count of answered questions of current engine: \(count)")
        try await sendFunctionOutput(
            callId: response.callId ?? "",
            output: "The patient has answered \(count) questions."
        )
        try await sendResponseCreate()
    }

    private func saveQuestionnaireAnswer(
        engine: FHIRQuestionnaireEngine, parsedArgs: QuestionnaireResponseArgs
    ) async throws {
        switch parsedArgs.answer {
        case .number(let number):
            try await engine.answerQuestion(
                linkId: parsedArgs.linkId,
                answer: number
            )
            return
        case .decimal(let decimal):
            try await engine.answerQuestion(
                linkId: parsedArgs.linkId,
                answer: decimal
            )
            return
        case .text(let text):
            try await engine.answerQuestion(
                linkId: parsedArgs.linkId,
                answer: text
            )
            return
        case .none:
            try await engine.answerQuestion(
                linkId: parsedArgs.linkId,
                answer: NSNull()
            )
            return
        }
    }

    private func handleSaveSuccess(
        engine: FHIRQuestionnaireEngine,
        response: OpenAIResponse
    ) async throws {
        if let nextQuestion = await engine.nextQuestionString(includeAllQuestions: false) {
            try await handleNextQuestionAvailable(nextQuestion: nextQuestion, response: response)
        } else {
            try await handleQuestionnaireComplete(response: response)
        }
    }

    private func handleNextQuestionAvailable(nextQuestion: String, response: OpenAIResponse)
        async throws {
        try await sendFunctionOutput(callId: response.callId ?? "", output: nextQuestion)
        try await sendResponseCreate()
    }
}
