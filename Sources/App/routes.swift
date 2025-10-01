//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor

struct OpenAICAllIncomingEvent: Decodable {
    struct ContainedData: Decodable {
        enum CodingKeys: String, CodingKey {
            case callId = "call_id"
            case sipHeaders = "sip_headers"
        }
        
        let callId: String
        let sipHeaders: [SIPHeader]
    }
    
    struct SIPHeader: Decodable {
        let name: String
        let value: String
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case data = "data"
    }
    
    let id: String
    let data: ContainedData
}

// swiftlint:disable file_length
// swiftlint:disable:next function_body_length
func routes(_ app: Application) throws {
    app.get("health") { _ -> HTTPStatus in
            .ok
    }
    
    app.post("incoming-call") { req async -> Response in
        guard let body = req.body.data,
              let openAIKey = app.storage[OpenAIKeyStorageKey.self] else {
            return Response(status: .ok)
        }
        
        guard let event = try? JSONDecoder().decode(OpenAICAllIncomingEvent.self, from: body) else {
            req.logger.error("Could not decode event from request body \"\(req.body.string ?? "")\".")
            return Response(status: .internalServerError)
        }
        let callId = event.data.callId
        req.logger.info("Call Id: \(callId)")
        
        // Get encryption key from app storage
        let encryptionKey = app.storage[EncryptionKeyStorageKey.self]
        
        let serviceState = await ServiceState(services: [
            VitalSignsService(phoneNumber: callId, logger: req.logger, featureFlags: app.featureFlags, encryptionKey: encryptionKey),
            KCCQ12Service(phoneNumber: callId, logger: req.logger, featureFlags: app.featureFlags, encryptionKey: encryptionKey),
            Q17Service(phoneNumber: callId, logger: req.logger, featureFlags: app.featureFlags, encryptionKey: encryptionKey)
        ])
        
        @Sendable
        func getFeedback() async -> String {
            do {
                guard let vitalSignsService = await serviceState.getVitalSignsService(),
                      let kccq12Service = await serviceState.getKCCQ12Service(),
                      let q17Service = await serviceState.getQ17Service() else {
                    req.logger.error("Failed to get service instances for feedback")
                    throw Abort(.internalServerError, reason: "Service instances not available")
                }
                
                let feedbackService = await FeedbackService(
                    phoneNumber: callId,
                    logger: req.logger,
                    vitalSignsService: vitalSignsService,
                    kccq12Service: kccq12Service,
                    q17Service: q17Service
                )
                return await feedbackService.feedback() ?? "No feedback available."
            } catch {
                req.logger.debug("\(error)")
                return "An error occurred while fetching patient feedback."
            }
        }
                
        let systemMessage = await {
            let hasUnansweredQuestions = await serviceState.initializeCurrentService()
            if !hasUnansweredQuestions {
                let feedback = await getFeedback()
                req.logger.info("No services have unanswered questions. Updating session with feedback.")
                return Constants.initialSystemMessage
                    + Constants.noUnansweredQuestionsLeft
                    + Constants.feedback(content: feedback)
            } else {
                let initialQuestion = await serviceState.current.getNextQuestion()
                let initialSystemMessage = await Constants.getSystemMessageForService(
                    serviceState.current,
                    initialQuestion: initialQuestion
                )
                return initialSystemMessage ?? (
                    Constants.initialSystemMessage
                        + Constants.noUnansweredQuestionsLeft
                )
            }
        }()
        let config = Constants.loadSessionConfig(systemMessage: systemMessage)
        let configObject = try! JSONSerialization.jsonObject(with: config.data(using: .utf8)!)
        let configData = try! JSONSerialization.data(withJSONObject: configObject)
        let request = try! HTTPClient.Request(
            url: "https://api.openai.com/v1/realtime/calls/\(callId)/accept",
            method: .POST,
            headers: [
                "Authorization": "Bearer \(openAIKey)",
                "Content-Type": "application/json"
            ],
            body: .data(configData),
        )
        let response = try! await app.http.client.shared.execute(request: request).get()
        var responseBody = response.body
        let bodyString = responseBody?.readString(length: response.body?.readableBytes ?? 0, encoding: .utf8).map { string in
            var string = string
            string.makeContiguousUTF8()
            return string
        } ?? ""
        req.logger.info("/accept responded: \(response.status.code) \(bodyString)")
        
        Task.detached {
            do {
                let url = "wss://api.openai.com/v1/realtime?call_id=\(callId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"
                try await WebSocket.connect(
                    to: url,
                    headers: [
                        "Authorization": "Bearer \(openAIKey)"
                    ],
                    on: app.eventLoopGroup.next()
                ) { openAIWs async in
                    print("websocket connected!!")
                    let responseRequest: [String: Any] = [
                        "type": "response.create"
                    ]
                    try! await sendJSON(responseRequest, openAIWs)
                    
                    // Handle incoming messages from OpenAI
                    openAIWs.onText { openAIWs, text async in
                        await handleOpenAIMessage(openAIWs: openAIWs, text: text, phoneNumber: callId)
                    }
                    
                    openAIWs.onClose.whenComplete { result in
                        switch result {
                        case .success(let closeCode):
                            req.logger.info("OpenAI WebSocket closed successfully with code: \(closeCode)")
                        case .failure(let error):
                            req.logger.error("OpenAI WebSocket closed with error: \(error)")
                        }
                    }
                }
            } catch let error as WebSocketClient.Error {
                if case let .invalidResponseStatus(head) = error {
                    req.logger.error("OpenAI Realtime API returned \(head.status.code).")
                } else {
                    req.logger.error("Error connecting to the OpenAI Realtime API: \(error)")
                }
            } catch {
                req.logger.error("Error connecting to the OpenAI Realtime API: \(error)")
            }
            
            
            @Sendable
            func updateSession(openAIWs: WebSocket, systemMessage: String) async {
                let sessionConfigJSONString = Constants.loadSessionConfig(systemMessage: systemMessage)
                do {
                    req.logger.info("Updating session with: \(sessionConfigJSONString)")
                    try await openAIWs.send(sessionConfigJSONString)
                } catch {
                    req.logger.error("Failed to update session: \(error). Closing web socket.")
                    try? await openAIWs.close()
                }
            }
            
            @Sendable
            func handleOpenAIMessage(openAIWs: WebSocket, text: String, phoneNumber: String) async {
                do {
                    guard let jsonData = text.data(using: .utf8) else {
                        throw Abort(.badRequest, reason: "Failed to convert string to data")
                    }
                    let response = try JSONDecoder().decode(OpenAIResponse.self, from: jsonData)
                    
                    if Constants.logEventTypes.contains(response.type) {
                        req.logger.info("Received event: \(response.type)")
                    }
                    
                    if response.type == "response.function_call_arguments.done" {
                        try await handleOpenAIFunctionCall(response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                    }
                    
                    if response.type == "error", let error = response.error {
                        req.logger.error("OpenAI Error: \(error.message) (Code: \(error.code ?? "unknown"))")
                    }
                } catch {
                    req.logger.info("Error processing OpenAI message: \(error)")
                }
            }
            
            @Sendable
            func handleOpenAIFunctionCall(response: OpenAIResponse, openAIWs: WebSocket, phoneNumber: String) async throws {
                let currentService = await serviceState.current
                switch response.name {
                case "save_response":
                    try await saveResponse(service: currentService, response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                case "count_answered_questions":
                    try await countAnsweredQuestions(service: currentService, response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                case "end_call":
                    let request = try HTTPClient.Request(
                        url: "https://api.openai.com/v1/realtime/calls/\(callId)/hangup",
                        method: .POST,
                        headers: [
                            "Authorization": "Bearer \(openAIKey)",
                            "Content-Type": "application/json"
                        ],
                        body: .data(configData),
                    )
                    _ = try await app.http.client.shared.execute(request: request).get()
                default:
                    req.logger.error("Unknown function call: \(String(describing: response.name))")
                }
            }
            
            @Sendable
            func saveResponse(
                service: QuestionnaireService,
                response: OpenAIResponse,
                openAIWs: WebSocket,
                phoneNumber: String
            ) async throws {
                do {
                    req.logger.info("Attempting to save response...")
                    guard let arguments = response.arguments else {
                        throw Abort(.badRequest, reason: "No arguments provided")
                    }
                    let argumentsData = arguments.data(using: .utf8) ?? Data()
                    
                    req.logger.debug("Received arguments: \(arguments)")
                    
                    do {
                        let parsedArgs = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: argumentsData)
                        req.logger.info("Parsed arguments: \(parsedArgs)")
                        let saveResult = await saveQuestionnaireAnswer(service: service, parsedArgs: parsedArgs)
                        if !saveResult {
                            try await handleSaveFailure(response: response, openAIWs: openAIWs)
                        } else {
                            try await handleSaveSuccess(service: service, response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                        }
                    } catch {
                        req.logger.error("Decoding error details: \(error)")
                        let errorResponse: [String: Any] = [
                            "type": "function_response",
                            "id": response.callId ?? "",
                            "error": [
                                "message": "Failed to decode parameters; please adhere to the JSON schema definitions."
                            ]
                        ]
                        try await sendJSON(errorResponse, openAIWs)
                    }
                } catch {
                    try await handleProcessingError(error: error, response: response, openAIWs: openAIWs)
                }
            }
            
            @Sendable
            func countAnsweredQuestions(
                service: QuestionnaireService,
                response: OpenAIResponse,
                openAIWs: WebSocket,
                phoneNumber: String
            ) async throws {
                let count = await service.countAnsweredQuestions()
                req.logger.info("Count of answered questions of current service: \(count)")
                let functionResponse: [String: Any] = [
                    "type": "conversation.item.create",
                    "item": [
                        "type": "function_call_output",
                        "call_id": response.callId ?? "",
                        "output": "The patient has answered \(count) questions."
                    ]
                ]
                try await sendJSON(functionResponse, openAIWs)
                
                let responseRequest: [String: Any] = [
                    "type": "response.create"
                ]
                try await sendJSON(responseRequest, openAIWs)
            }
            
            @Sendable
            func sendJSON(_ object: [String: Any], _ webSocket: WebSocket) async throws {
                let jsonData = try JSONSerialization.data(withJSONObject: object)
                guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                    throw Abort(.internalServerError, reason: "Failed to encode JSON")
                }
                try await webSocket.send(jsonString)
            }
            
            @Sendable
            func saveQuestionnaireAnswer(service: QuestionnaireService, parsedArgs: QuestionnaireResponseArgs) async -> Bool {
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
            
            @Sendable
            func handleSaveFailure(response: OpenAIResponse, openAIWs: WebSocket) async throws {
                let functionResponse: [String: Any] = [
                    "type": "conversation.item.create",
                    "item": [
                        "type": "function_call_output",
                        "call_id": response.callId ?? "",
                        "output": "The response could not be saved. Try again."
                    ]
                ]
                try await sendJSON(functionResponse, openAIWs)
                let responseRequest: [String: Any] = [
                    "type": "response.create"
                ]
                try await sendJSON(responseRequest, openAIWs)
            }
            
            @Sendable
            func handleSaveSuccess(
                service: QuestionnaireService,
                response: OpenAIResponse,
                openAIWs: WebSocket,
                phoneNumber: String
            ) async throws {
                if let nextQuestion = await service.getNextQuestion() {
                    try await handleNextQuestionAvailable(nextQuestion: nextQuestion, response: response, openAIWs: openAIWs)
                } else {
                    try await handleQuestionnaireComplete(service: service, response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                }
            }
            
            @Sendable
            func handleNextQuestionAvailable(nextQuestion: String, response: OpenAIResponse, openAIWs: WebSocket) async throws {
                let functionResponse: [String: Any] = [
                    "type": "conversation.item.create",
                    "item": [
                        "type": "function_call_output",
                        "call_id": response.callId ?? "",
                        "output": nextQuestion
                    ]
                ]
                try await sendJSON(functionResponse, openAIWs)
                
                let responseRequest: [String: Any] = [
                    "type": "response.create"
                ]
                try await sendJSON(responseRequest, openAIWs)
            }
            
            @Sendable
            func handleQuestionnaireComplete(
                service: QuestionnaireService,
                response: OpenAIResponse,
                openAIWs: WebSocket,
                phoneNumber: String
            ) async throws {
                await service.saveQuestionnaireResponseToFile()
                
                if let nextService = await serviceState.next(),
                   let initialQuestion = await nextService.getNextQuestion(),
                   let systemMessage = Constants.getSystemMessageForService(nextService, initialQuestion: initialQuestion) {
                    try await handleNextServiceAvailable(
                        nextService: nextService,
                        initialQuestion: initialQuestion,
                        systemMessage: systemMessage,
                        response: response,
                        openAIWs: openAIWs
                    )
                } else {
                    try await handleNoNextService(response: response, openAIWs: openAIWs)
                }
            }
            
            @Sendable
            func handleNextServiceAvailable(
                nextService: QuestionnaireService,
                initialQuestion: String,
                systemMessage: String,
                response: OpenAIResponse,
                openAIWs: WebSocket
            ) async throws {
                await updateSession(openAIWs: openAIWs, systemMessage: systemMessage)
                let functionResponse: [String: Any] = [
                    "type": "conversation.item.create",
                    "item": [
                        "type": "function_call_output",
                        "call_id": response.callId ?? "",
                        "output": initialQuestion
                    ]
                ]
                try await sendJSON(functionResponse, openAIWs)
                
                let responseRequest: [String: Any] = [
                    "type": "response.create"
                ]
                try await sendJSON(responseRequest, openAIWs)
            }
            
            @Sendable
            func handleNoNextService(response: OpenAIResponse, openAIWs: WebSocket) async throws {
                let feedback = await getFeedback()
                let systemMessage = Constants.feedback(content: feedback)
                await updateSession(openAIWs: openAIWs, systemMessage: systemMessage)
                
                let responseRequest: [String: Any] = [
                    "type": "response.create"
                ]
                try await sendJSON(responseRequest, openAIWs)
            }
            
            @Sendable
            func handleProcessingError(error: Error, response: OpenAIResponse, openAIWs: WebSocket) async throws {
                req.logger.error("Error processing questionnaire: \(error)")
                let errorResponse: [String: Any] = [
                    "type": "function_response",
                    "id": response.callId ?? "",
                    "error": [
                        "message": "Failed to process questionnaire"
                    ]
                ]
                try await sendJSON(errorResponse, openAIWs)
            }
        }
        
        return Response(status: .ok)
    }
}
