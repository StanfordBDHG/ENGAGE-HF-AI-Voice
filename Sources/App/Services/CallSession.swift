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
    // MARK: Stored Properties
    
    let phoneNumber: String
    let serviceState: ServiceState
    let logger: Logger
    let webSocket: WebSocket

    // MARK: Initialization
    
    init(phoneNumber: String, serviceState: ServiceState, webSocket: WebSocket, logger: Logger) {
        self.phoneNumber = phoneNumber
        self.serviceState = serviceState
        self.webSocket = webSocket
        self.logger = logger
    }
    
    // MARK: Methods
    
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
            logger.info("Error processing OpenAI message: \(error)")
        }
    }
    
    func sendJSON(_ object: [String: Any]) async throws {
        let jsonData = try JSONSerialization.data(withJSONObject: object)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Failed to encode JSON")
        }
        try await webSocket.send(jsonString)
    }
    
    func updateSession(systemMessage: String) async throws {
        let sessionConfigJSONString = Constants.loadSessionConfig(systemMessage: systemMessage)
        do {
            logger.info("Updating session with: \(sessionConfigJSONString)")
            let object = try JSONSerialization.jsonObject(with: sessionConfigJSONString.data(using: .utf8) ?? Data())
            try await sendJSON([
                "type": "session.update",
                "session": object
            ])
        } catch {
            logger.error("Failed to update session: \(error). Closing web socket.")
            try? await webSocket.close()
        }
    }
    
    // MARK: Methods - Helpers
    
    private func handleFunctionCall(response: OpenAIResponse) async throws {
        logger.debug("Function call \"\(response.name ?? "")\"")
        let currentService = await serviceState.current
        switch response.name {
        case "save_response":
            try await saveResponse(service: currentService, response: response)
        case "count_answered_questions":
            try await countAnsweredQuestions(service: currentService, response: response)
        case "end_call":
            try await webSocket.close()
        default:
            logger.error("Unknown function call: \(String(describing: response.name))")
        }
    }
    
    private func saveResponse(
        service: any QuestionnaireService,
        response: OpenAIResponse
    ) async throws {
        do {
            logger.info("Attempting to save response...")
            guard let arguments = response.arguments else {
                throw Abort(.badRequest, reason: "No arguments provided")
            }
            let argumentsData = arguments.data(using: .utf8) ?? Data()
            
            logger.debug("Received arguments: \(arguments)")
            
            do {
                let parsedArgs = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: argumentsData)
                logger.info("Parsed arguments: \(parsedArgs)")
                let saveResult = await saveQuestionnaireAnswer(service: service, parsedArgs: parsedArgs)
                if !saveResult {
                    try await handleSaveFailure(response: response)
                } else {
                    try await handleSaveSuccess(service: service, response: response)
                }
            } catch {
                logger.error("Decoding error details: \(error)")
                try await sendJSON([
                    "type": "function_response",
                    "id": response.callId ?? "",
                    "error": [
                        "message": "Failed to decode parameters; please adhere to the JSON schema definitions."
                    ]
                ])
            }
        } catch {
            try await handleProcessingError(error: error, response: response)
        }
    }
    
    private func countAnsweredQuestions(
        service: any QuestionnaireService,
        response: OpenAIResponse
    ) async throws {
        let count = await service.countAnsweredQuestions()
        logger.info("Count of answered questions of current service: \(count)")

        try await sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": response.callId ?? "",
                "output": "The patient has answered \(count) questions."
            ]
        ])
        
        try await sendJSON([
            "type": "response.create"
        ])
    }
    
    private func saveQuestionnaireAnswer(service: any QuestionnaireService, parsedArgs: QuestionnaireResponseArgs) async -> Bool {
        switch parsedArgs.answer {
        case .number(let number):
            return await service.saveQuestionnaireAnswer(
                linkId: parsedArgs.linkId,
                answer: number
            )
        case .text(let text):
            return await service.saveQuestionnaireAnswer(
                linkId: parsedArgs.linkId,
                answer: text
            )
        case .none:
            return await service.saveQuestionnaireAnswer(
                linkId: parsedArgs.linkId,
                answer: NSNull()
            )
        }
    }
    
    private func handleSaveFailure(response: OpenAIResponse) async throws {
        try await sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": response.callId ?? "",
                "output": "The response could not be saved. Try again."
            ]
        ])
        try await sendJSON([
            "type": "response.create"
        ])
    }
    
    private func handleSaveSuccess(
        service: any QuestionnaireService,
        response: OpenAIResponse
    ) async throws {
        // Save progress incrementally after each answer
        await service.saveQuestionnaireResponseToFile()
        
        if let nextQuestion = await service.getNextQuestion() {
            try await handleNextQuestionAvailable(nextQuestion: nextQuestion, response: response)
        } else {
            try await handleQuestionnaireComplete(service: service, response: response)
        }
    }
    
    private func handleNextQuestionAvailable(nextQuestion: String, response: OpenAIResponse) async throws {
        try await sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": response.callId ?? "",
                "output": nextQuestion
            ]
        ])
        
        try await sendJSON([
            "type": "response.create"
        ])
    }
    
    private func handleQuestionnaireComplete(
        service: any QuestionnaireService,
        response: OpenAIResponse
    ) async throws {
        await service.saveQuestionnaireResponseToFile()
        
        if let nextService = await serviceState.next(),
           let initialQuestion = await nextService.getNextQuestion() {
            let sectionProgress = await serviceState.getSectionProgress()
            if let systemMessage = Constants.getSystemMessageForService(
                nextService,
                initialQuestion: initialQuestion,
                sectionProgress: sectionProgress
            ) {
                try await handleNextServiceAvailable(
                    nextService: nextService,
                    initialQuestion: initialQuestion,
                    systemMessage: systemMessage,
                    response: response
                )
            }
        } else {
            try await handleNoNextService(response: response)
        }
    }
    
    private func handleNextServiceAvailable(
        nextService: any QuestionnaireService,
        initialQuestion: String,
        systemMessage: String,
        response: OpenAIResponse
    ) async throws {
        try await updateSession(systemMessage: systemMessage)
        try await sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": response.callId ?? "",
                "output": initialQuestion
            ]
        ])
        
        try await sendJSON([
            "type": "response.create"
        ])
    }
    
    private func handleNoNextService(response: OpenAIResponse) async throws {
        let feedback = try await serviceState.getFeedback(phoneNumber: phoneNumber, logger: logger)
        let systemMessage = Constants.feedback(content: feedback)
        try await updateSession(systemMessage: systemMessage)
        
        try await sendJSON([
            "type": "response.create"
        ])
    }
    
    private func handleProcessingError(error: any Error, response: OpenAIResponse) async throws {
        logger.error("Error processing questionnaire: \(error)")
        try await sendJSON([
            "type": "function_response",
            "id": response.callId ?? "",
            "error": [
                "message": "Failed to process questionnaire"
            ]
        ])
    }
}
