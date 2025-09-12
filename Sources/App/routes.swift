//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor

// swiftlint:disable file_length
// swiftlint:disable:next function_body_length
func routes(_ app: Application) throws {
    app.get("health") { _ -> HTTPStatus in
            .ok
    }
    
    app.post("incoming-call") { req async -> Response in
        req.logger.info("\(req.content)")
        do {
            let callerPhoneNumber = try req.content.get(String.self, at: "From")
            // swiftlint:disable:next force_unwrapping
            let encodedCallerPhoneNumber = callerPhoneNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            
            let twimlResponse =
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <Response>
                <Connect>
                    <Stream url="wss://\(req.headers.first(name: "host") ?? "")/voice-stream/\(encodedCallerPhoneNumber)" />
                </Connect>
            </Response>
            """
            return Response(
                status: .ok,
                headers: ["Content-Type": "text/xml"],
                body: .init(string: twimlResponse)
            )
        } catch {
            req.logger.info("Could not find phone number")
            return Response(status: .badRequest)
        }
    }
    
    // swiftlint:disable:next closure_body_length
    app.webSocket("voice-stream", ":phoneNumber") { req, twilioWs async in
        guard let callerPhoneNumber = req.parameters.get("phoneNumber") else {
            req.logger.info("Caller phone number not provided")
            return
        }
        let connectionState = ConnectionState()
        
        // Get encryption key from app storage
        let encryptionKey = app.storage[EncryptionKeyStorageKey.self]
        
        let serviceState = await ServiceState(services: [
            VitalSignsService(phoneNumber: callerPhoneNumber, logger: req.logger, featureFlags: app.featureFlags, encryptionKey: encryptionKey),
            KCCQ12Service(phoneNumber: callerPhoneNumber, logger: req.logger, featureFlags: app.featureFlags, encryptionKey: encryptionKey),
            Q17Service(phoneNumber: callerPhoneNumber, logger: req.logger, featureFlags: app.featureFlags, encryptionKey: encryptionKey)
        ])
        
        // Handle incoming start messages from Twilio
        twilioWs.onText { _, text async in
            await handleTwilioStartMessage(text: text)
        }
        
        guard let openAIKey = app.storage[OpenAIKeyStorageKey.self] else {
            req.logger.info("OpenAI API key not found")
            return
        }
        let openAIWsURL = "wss://api.openai.com/v1/realtime?model=gpt-realtime"
        guard URL(string: openAIWsURL) != nil else {
            req.logger.info("Invalid OpenAI WebSocket URL")
            return
        }
        var headers = HTTPHeaders()
        headers.add(name: "Authorization", value: "Bearer \(openAIKey)")
        headers.add(name: "OpenAI-Beta", value: "realtime=v1")
        
        do {
            _ = try await WebSocket.connect(to: openAIWsURL, headers: headers, on: req.eventLoop) { openAIWs async in
                await initializeSession(webSocket: openAIWs)
                
                // Handle incoming messages from Twilio
                twilioWs.onText { _, text async in
                    await handleTwilioMessage(openAIWs: openAIWs, text: text)
                }
                
                // Handle incoming messages from OpenAI
                openAIWs.onText { openAIWs, text async in
                    await handleOpenAIMessage(twilioWs: twilioWs, openAIWs: openAIWs, text: text, phoneNumber: callerPhoneNumber)
                }
                
                openAIWs.onClose.whenComplete { result in
                    switch result {
                    case .success(let closeCode):
                        req.logger.info("OpenAI WebSocket closed successfully with code: \(closeCode)")
                    case .failure(let error):
                        req.logger.error("OpenAI WebSocket closed with error: \(error)")
                    }
                }
                
                twilioWs.onClose.whenComplete { result in
                    switch result {
                    case .success(let closeCode):
                        req.logger.info("Twilio WebSocket closed successfully with code: \(closeCode)")
                    case .failure(let error):
                        req.logger.error("Twilio WebSocket closed with error: \(error)")
                    }
                    openAIWs.close().whenComplete { _ in
                        req.logger.info("Clients (OpenAI and Twilio) have both disconnected")
                    }
                }
            }
        } catch {
            req.logger.error("Error connecting to the OpenAI Realtime API: \(error)")
        }
        
        
        @Sendable
        func initializeSession(webSocket: WebSocket) async {
            do {
                let hasUnansweredQuestions = await serviceState.initializeCurrentService()
                if !hasUnansweredQuestions {
                    req.logger.info("No services have unanswered questions. Updating session with feedback.")
                    let systemMessage = Constants.initialSystemMessage + Constants.feedback
                    await updateSession(webSocket: webSocket, systemMessage: systemMessage)
                } else {
                    let initialQuestion = await serviceState.current.getNextQuestion()
                    let initialSystemMessage = await Constants.getSystemMessageForService(
                        serviceState.current,
                        initialQuestion: initialQuestion ?? "No question found."
                    )
                    await updateSession(webSocket: webSocket, systemMessage: initialSystemMessage ?? "")
                }
                let responseRequest: [String: Any] = [
                    "type": "response.create"
                ]
                try await sendJSON(responseRequest, webSocket)
            } catch {
                req.logger.error("Failed to serialize session update: \(error)")
            }
        }
        
        @Sendable
        func updateSession(webSocket: WebSocket, systemMessage: String) async {
            let sessionConfigJSONString = Constants.loadSessionConfig(systemMessage: systemMessage)
            do {
                req.logger.info("Updating session with: \(sessionConfigJSONString)")
                try await webSocket.send(sessionConfigJSONString)
            } catch {
                req.logger.error("Failed to update session: \(error). Closing web socket.")
                try? await webSocket.close()
            }
        }
        
        @Sendable
        func handleTwilioStartMessage(text: String) async {
            do {
                guard let data = text.data(using: .utf8) else {
                    return
                }
                let twilioEvent = try JSONDecoder().decode(TwilioEvent.self, from: data)
                
                switch twilioEvent.event {
                case "start":
                    guard let start = twilioEvent.start else {
                        req.logger.error("Start event missing start data")
                        return
                    }
                    await connectionState.updateStreamSid(start.streamSid)
                    await connectionState.updateResponseStartTimestampTwilio(nil)
                    await connectionState.updateTimestamp(0)
                default:
                    req.logger.info("Received non-media event: \(twilioEvent.event)")
                }
            } catch {
                req.logger.info("Error processing message: \(error)")
            }
        }
        
        @Sendable
        func handleTwilioMessage(openAIWs: WebSocket, text: String) async {
            do {
                guard let data = text.data(using: .utf8) else {
                    return
                }
                let twilioEvent = try JSONDecoder().decode(TwilioEvent.self, from: data)
                switch twilioEvent.event {
                case "media":
                    guard let media = twilioEvent.media else {
                        req.logger.error("Media event missing media data")
                        return
                    }
                    // Convert timestamp from String to Int
                    guard let timestampInt = Int(media.timestamp) else {
                        req.logger.error("Failed to convert timestamp to Int")
                        return
                    }
                    await connectionState.updateTimestamp(timestampInt)
                    let audioAppend: [String: String] = [
                        "type": "input_audio_buffer.append",
                        "audio": media.payload
                    ]
                    let jsonData = try JSONSerialization.data(withJSONObject: audioAppend)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        try await openAIWs.send(jsonString)
                    }
                case "mark":
                    let markQueue = await connectionState.markQueue
                    if !markQueue.isEmpty {
                        await connectionState.removeFirstFromMarkQueue()
                    }
                default:
                    req.logger.info("Received non-media event: \(twilioEvent.event)")
                }
            } catch {
                req.logger.info("Error processing message: \(error)")
            }
        }
        
        @Sendable
        func handleOpenAIMessage(twilioWs: WebSocket, openAIWs: WebSocket, text: String, phoneNumber: String) async {
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
                
                // Handling for Audio
                if response.type == "response.audio.delta", let delta = response.delta {
                    let streamSid = await connectionState.streamSid
                    let audioDelta: [String: Any] = [
                        "event": "media",
                        "streamSid": streamSid ?? "",
                        "media": ["payload": delta]
                    ]
                    do {
                        try await sendJSON(audioDelta, twilioWs)
                    } catch {
                        req.logger.error("Failed to send audio delta: \(error)")
                    }
                    
                    // First delta from a new response starts the elapsed time counter
                    let currentTimestamp = await connectionState.responseStartTimestampTwilio
                    if currentTimestamp == nil {
                        let latestMediaTimestamp = await connectionState.latestMediaTimestamp
                        await connectionState.updateResponseStartTimestampTwilio(latestMediaTimestamp)
                        
                        let responseStartTimestampTwilio = await connectionState.responseStartTimestampTwilio
                        req.logger.info("Setting start timestamp for new response: \(responseStartTimestampTwilio ?? 0)ms")
                    }
                    
                    if let itemId = response.itemId {
                        await connectionState.updateLastAssistantItem(itemId)
                    }
                    
                    try await sendMark(webSocket: twilioWs, streamSid: streamSid)
                }
                
                // Handling for interuptions of the caller
                if response.type == "input_audio_buffer.speech_started" {
                    try await handleSpeechStartedEvent(webSocket: openAIWs)
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
            case "get_feedback":
                try await getFeedback(response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
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
            let responseRequest: [String: Any] = [
                "type": "response.create"
            ]
            
            await connectionState.updateResponseStartTimestampTwilio(nil)
            await connectionState.updateLastAssistantItem(nil)
            await connectionState.removeAllFromMarkQueue()
            
            try await sendJSON(functionResponse, openAIWs)
            try await sendJSON(responseRequest, openAIWs)
        }
        
        @Sendable
        func getFeedback(response: OpenAIResponse, openAIWs: WebSocket, phoneNumber: String) async throws {
            // Get existing service instances to avoid creating duplicates
            guard let vitalSignsService = await serviceState.getVitalSignsService(),
                  let kccq12Service = await serviceState.getKCCQ12Service(),
                  let q17Service = await serviceState.getQ17Service() else {
                req.logger.error("Failed to get service instances for feedback")
                throw Abort(.internalServerError, reason: "Service instances not available")
            }
            
            let feedbackService = await FeedbackService(
                phoneNumber: phoneNumber,
                logger: req.logger,
                vitalSignsService: vitalSignsService,
                kccq12Service: kccq12Service,
                q17Service: q17Service
            )
            let feedback = await feedbackService.feedback()
            
            let functionResponse: [String: Any] = [
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": response.callId ?? "",
                    "output": feedback ?? "No feedback available."
                ]
            ]
            
            req.logger.info("Feedback functionResponse: \(functionResponse)")
            
            let responseRequest: [String: Any] = [
                "type": "response.create"
            ]
            
            try await sendJSON(functionResponse, openAIWs)
            try await sendJSON(responseRequest, openAIWs)
            
            await connectionState.updateResponseStartTimestampTwilio(nil)
            await connectionState.updateLastAssistantItem(nil)
            
            // Log the connection state after function response
            req.logger.info("Function response sent, connection state: \(openAIWs.isClosed ? "closed" : "open")")
        }
        
        @Sendable
        func handleSpeechStartedEvent(webSocket: WebSocket) async throws {
            let markQueue = await connectionState.markQueue
            let responseStart = await connectionState.responseStartTimestampTwilio
            let lastItem = await connectionState.lastAssistantItem
            let streamSid = await connectionState.streamSid
            
            guard !markQueue.isEmpty,
                  let responseStart = responseStart,
                  let lastItem = lastItem,
                  let streamSid = streamSid else {
                req.logger.info("Speech started but missing required state for interruption")
                return
            }
            
            let latestMediaTimestamp = await connectionState.latestMediaTimestamp ?? 0
            let elapsedTime = latestMediaTimestamp - responseStart
            req.logger.info("Calculating elapsed time for truncation: \(latestMediaTimestamp) - \(responseStart) = \(elapsedTime)ms")
            
            // Send truncate event to OpenAI
            let truncateEvent: [String: Any] = [
                "type": "conversation.item.truncate",
                "item_id": lastItem,
                "content_index": 0,
                "audio_end_ms": elapsedTime
            ]
            
            do {
                await connectionState.removeAllFromMarkQueue()
                await connectionState.updateLastAssistantItem(nil)
                await connectionState.updateResponseStartTimestampTwilio(nil)
                
                try await sendJSON(truncateEvent, webSocket)
                
                let clearEvent: [String: Any] = [
                    "event": "clear",
                    "streamSid": streamSid
                ]
                try await sendJSON(clearEvent, twilioWs)
            } catch {
                req.logger.error("Failed to handle speech started event: \(error)")
            }
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
        func sendMark(webSocket: WebSocket, streamSid: String?) async throws {
            guard let streamSid = streamSid else {
                return
            }
            
            let markEvent: [String: Any] = [
                "event": "mark",
                "streamSid": streamSid,
                "mark": ["name": "responsePart"]
            ]
            
            try await sendJSON(markEvent, webSocket)
            await connectionState.appendToMarkQueue("responsePart")
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
            let responseRequest: [String: Any] = [
                "type": "response.create"
            ]
            
            try await sendJSON(functionResponse, openAIWs)
            try await sendJSON(responseRequest, openAIWs)
            
            await connectionState.updateResponseStartTimestampTwilio(nil)
            await connectionState.updateLastAssistantItem(nil)
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
            let responseRequest: [String: Any] = [
                "type": "response.create"
            ]
            
            await connectionState.updateResponseStartTimestampTwilio(nil)
            await connectionState.updateLastAssistantItem(nil)
            await connectionState.removeAllFromMarkQueue()
            
            try await sendJSON(functionResponse, openAIWs)
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
            await updateSession(webSocket: openAIWs, systemMessage: systemMessage)
            let functionResponse: [String: Any] = [
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": response.callId ?? "",
                    "output": initialQuestion
                ]
            ]
            let responseRequest: [String: Any] = [
                "type": "response.create"
            ]
            await connectionState.updateResponseStartTimestampTwilio(nil)
            await connectionState.updateLastAssistantItem(nil)
            await connectionState.removeAllFromMarkQueue()
            
            try await sendJSON(functionResponse, openAIWs)
            try await sendJSON(responseRequest, openAIWs)
        }
        
        @Sendable
        func handleNoNextService(response: OpenAIResponse, openAIWs: WebSocket) async throws {
            let systemMessage = Constants.feedback
            await updateSession(webSocket: openAIWs, systemMessage: systemMessage)
            
            let responseRequest: [String: Any] = [
                "type": "response.create"
            ]
            await connectionState.updateResponseStartTimestampTwilio(nil)
            await connectionState.updateLastAssistantItem(nil)
            await connectionState.removeAllFromMarkQueue()
            
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
}
