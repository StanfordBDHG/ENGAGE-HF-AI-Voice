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
            
            // Create files for responses of caller
            VitalSignsService.setupVitalSignsFile(phoneNumber: callerPhoneNumber, logger: req.logger)
            KCCQ12Service.setupKCCQ12File(phoneNumber: callerPhoneNumber, logger: req.logger)
            Q17Service.setupQ17File(phoneNumber: callerPhoneNumber, logger: req.logger)
            
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
        let state = ConnectionState()
        
        // Handle incoming start messages from Twilio
        twilioWs.onText { _, text async in
            await handleTwilioStartMessage(text: text)
        }
        
        guard let openAIKey = app.storage[OpenAIKeyStorageKey.self] else {
            req.logger.info("OpenAI API key not found")
            return
        }
        let openAIWsURL = "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01"
        guard URL(string: openAIWsURL) != nil else {
            req.logger.info("Invalid OpenAI WebSocket URL")
            return
        }
        var headers = HTTPHeaders()
        headers.add(name: "Authorization", value: "Bearer \(openAIKey)")
        headers.add(name: "OpenAI-Beta", value: "realtime=v1")
        
        do {
            _ = try await WebSocket.connect(to: openAIWsURL, headers: headers, on: req.eventLoop) { openAIWs async in
                initializeSession(webSocket: openAIWs)
                
                // Handle incoming messages from Twilio
                twilioWs.onText { _, text async in
                    await handleTwilioMessage(openAIWs: openAIWs, text: text)
                }
                
                // Handle incoming messages from OpenAI
                openAIWs.onText { openAIWs, text async in
                    await handleOpenAIMessage(twilioWs: twilioWs, openAIWs: openAIWs, text: text, phoneNumber: callerPhoneNumber)
                }
                
                openAIWs.onClose.whenComplete { _ in
                    req.logger.info("Disconnected from the OpenAI Realtime API")
                }
                
                twilioWs.onClose.whenComplete { _ in
                    openAIWs.close().whenComplete { _ in
                        req.logger.info("Clients (OpenAI and Twilio) have both disconnected")
                    }
                }
            }
        } catch {
            req.logger.error("Error connecting to the OpenAI Realtime API: \(error)")
        }
        
        
        @Sendable
        func initializeSession(webSocket: WebSocket) {
            do {
                let sessionConfigJSONString = Constants.loadSessionConfig(systemMessage: Constants.initialSystemMessage)
                req.logger.info("\(sessionConfigJSONString)")
                webSocket.send(sessionConfigJSONString)
                let responseRequest: [String: Any] = [
                    "type": "response.create"
                ]
                let responseData = try JSONSerialization.data(withJSONObject: responseRequest)
                if let jsonString = String(data: responseData, encoding: .utf8) {
                    webSocket.send(jsonString)
                }
            } catch {
                req.logger.error("Failed to serialize session update: \(error)")
            }
        }
        
        @Sendable
        func updateSession(webSocket: WebSocket, systemMessage: String) async {
            let sessionConfigJSONString = Constants.loadSessionConfig(systemMessage: systemMessage)
            do {
                print("Updading session with:")
                print(sessionConfigJSONString)
                try await webSocket.send(sessionConfigJSONString)
            } catch {
                print("Failed to serialize update request: \(error)")
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
                    await state.updateStreamSid(start.streamSid)
                    await state.updateResponseStartTimestampTwilio(nil)
                    await state.updateTimestamp(0)
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
                    await state.updateTimestamp(timestampInt)
                    let audioAppend: [String: String] = [
                        "type": "input_audio_buffer.append",
                        "audio": media.payload
                    ]
                    let jsonData = try JSONSerialization.data(withJSONObject: audioAppend)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        try await openAIWs.send(jsonString)
                    }
                case "mark":
                    let markQueue = await state.markQueue
                    if !markQueue.isEmpty {
                        await state.removeFirstFromMarkQueue()
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
                    print("Received event: \(response.type)", response)
                }
                
                try await handleOpenAIFunctionCall(response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                
                
                // Handling for Audio
                if response.type == "response.audio.delta", let delta = response.delta {
                    let streamSid = await state.streamSid
                    let audioDelta: [String: Any] = [
                        "event": "media",
                        "streamSid": streamSid ?? "",
                        "media": ["payload": delta]
                    ]
                    let jsonData = try JSONSerialization.data(withJSONObject: audioDelta)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        try await twilioWs.send(jsonString)
                    }
                    
                    // First delta from a new response starts the elapsed time counter
                    let responseStartTimestampTwilio = await state.responseStartTimestampTwilio
                    if responseStartTimestampTwilio == nil {
                        let latestMediaTimestamp = await state.latestMediaTimestamp
                        await state.updateResponseStartTimestampTwilio(latestMediaTimestamp)
                        
                        let responseStartTimestampTwilio = await state.responseStartTimestampTwilio
                        req.logger.info("Setting start timestamp for new response: \(responseStartTimestampTwilio ?? 0)ms")
                    }
                    
                    if let itemId = response.itemId {
                        await state.updateLastAssistantItem(itemId)
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
            if response.type == "response.function_call_arguments.done" {
                switch response.name {
                case "get_vitalSign_question":
                    try await getVitalSignQuestion(response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                case "save_vitalSign_response":
                    try await saveVitalSignResponse(response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                case "count_answered_vitalSign_questions":
                    try await countAnsweredVitalSignQuestions(response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                case "get_kccq12_question":
                    try await getKCCQ12Question(response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                case "save_kccq12_response":
                    try await saveKCCQ12Response(response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                case "count_answered_kccq12_questions":
                    try await countAnsweredKCCQ12Questions(response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                case "get_q17_question":
                    try await getQ17Question(response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                case "save_q17_response":
                    try await saveQ17Response(response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                case "count_answered_q17_questions":
                    try await countAnsweredQ17Questions(response: response, openAIWs: openAIWs, phoneNumber: phoneNumber)
                default:
                    req.logger.error("Unknown function call: \(String(describing: response.name))")
                }
            }
        }
        
        // Vital Signs
        
        @Sendable
        func getVitalSignQuestion(response: OpenAIResponse, openAIWs: WebSocket, phoneNumber: String) async throws {
            let question = await VitalSignsService.getNextQuestion(phoneNumber: phoneNumber, logger: req.logger)
            
            let functionResponse: [String: Any] = [
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": response.callId ?? "",
                    "output": question ?? "No more questions available."
                ]
            ]
            
            req.logger.info("VitalSigns question functionResponse: \(functionResponse)")
            
            let responseRequest: [String: Any] = [
                "type": "response.create"
            ]
            
            if question == nil {
                // when there are no questions left, we also update the session instructions
                await updateSession(webSocket: openAIWs, systemMessage: Constants.kccq12Instructions)
                try await sendJSON(functionResponse, openAIWs)
            } else {
                try await sendJSON(functionResponse, openAIWs)
            }
            try await sendJSON(responseRequest, openAIWs)
            
            await state.updateResponseStartTimestampTwilio(nil)
            await state.updateLastAssistantItem(nil)
            
            // Log the connection state after function response
            req.logger.info("Function response sent, connection state: \(openAIWs.isClosed ? "closed" : "open")")
        }
        
        @Sendable
        func saveVitalSignResponse(response: OpenAIResponse, openAIWs: WebSocket, phoneNumber: String) async throws {
            do {
                req.logger.info("Attempting to save VitalSign Response...")
                guard let arguments = response.arguments else {
                    throw Abort(.badRequest, reason: "No arguments provided")
                }
                let argumentsData = arguments.data(using: .utf8) ?? Data()
                
                if let parsedArgs = try? JSONDecoder().decode(VitalSignResponseArgs.self, from: argumentsData) {
                    req.logger.info("Parsed arguments: \(parsedArgs)")
                    
                    let saveResult = await VitalSignsService.saveQuestionnaireResponse(
                        linkId: parsedArgs.linkId,
                        answer: parsedArgs.answer,
                        phoneNumber: phoneNumber,
                        logger: req.logger
                    )
                    
                    let functionResponse: [String: Any] = [
                        "type": "conversation.item.create",
                        "item": [
                            "type": "function_call_output",
                            "call_id": response.callId ?? "",
                            "output": saveResult ?
                            "Vital signs survey response saved successfully." :
                                "Failed to save vital signs survey response. Please try again."
                        ]
                    ]
                    let responseRequest: [String: Any] = [
                        "type": "response.create"
                    ]
                    
                    try await sendJSON(functionResponse, openAIWs)
                    try await sendJSON(responseRequest, openAIWs)
                    
                    await state.updateResponseStartTimestampTwilio(nil)
                    await state.updateLastAssistantItem(nil)
                } else {
                    do {
                        _ = try JSONDecoder().decode(VitalSignResponseArgs.self, from: argumentsData)
                    } catch let decodingError as DecodingError {
                        req.logger.error("Decoding error details: \(decodingError)")
                    }
                }
            } catch {
                req.logger.error("Error processing vital signs survey: \(error)")
                let errorResponse: [String: Any] = [
                    "type": "function_response",
                    "id": response.callId ?? "",
                    "error": [
                        "message": "Failed to process vital signs survey"
                    ]
                ]
                try await sendJSON(errorResponse, openAIWs)
            }
        }

        @Sendable
        func countAnsweredVitalSignQuestions(response: OpenAIResponse, openAIWs: WebSocket, phoneNumber: String) async throws {
            let count = await VitalSignsService.countAnsweredQuestions(phoneNumber: phoneNumber, logger: req.logger)
            req.logger.info("Count of answered vital sign questions: \(count)")
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

            try await sendJSON(functionResponse, openAIWs)
            try await sendJSON(responseRequest, openAIWs)

            await state.updateResponseStartTimestampTwilio(nil)
            await state.updateLastAssistantItem(nil)
        }
        
        
        // KCCQ-12
        
        @Sendable
        func getKCCQ12Question(response: OpenAIResponse, openAIWs: WebSocket, phoneNumber: String) async throws {
            let question = await KCCQ12Service.getNextQuestion(phoneNumber: phoneNumber, logger: req.logger)
            
            let functionResponse: [String: Any] = [
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": response.callId ?? "",
                    "output": question ?? "No more questions available."
                ]
            ]
            
            req.logger.info("KCCQ-12 question functionResponse: \(functionResponse)")
            
            let responseRequest: [String: Any] = [
                "type": "response.create"
            ]
            
            if question == nil {
                // when there are no questions left, we also update the session instructions
                await updateSession(webSocket: openAIWs, systemMessage: Constants.q17Instructions)
                try await sendJSON(functionResponse, openAIWs)
            } else {
               try await sendJSON(functionResponse, openAIWs)
            }
            try await sendJSON(responseRequest, openAIWs)
            
            await state.updateResponseStartTimestampTwilio(nil)
            await state.updateLastAssistantItem(nil)
            
            // Log the connection state after function response
            req.logger.info("Function response sent, connection state: \(openAIWs.isClosed ? "closed" : "open")")
        }
        
        @Sendable
        func saveKCCQ12Response(response: OpenAIResponse, openAIWs: WebSocket, phoneNumber: String) async throws {
            do {
                req.logger.info("Attempting to save KCCQ12 Response...")
                guard let arguments = response.arguments else {
                    throw Abort(.badRequest, reason: "No arguments provided")
                }
                let argumentsData = arguments.data(using: .utf8) ?? Data()
                
                if let parsedArgs = try? JSONDecoder().decode(KCCQ12ResponseArgs.self, from: argumentsData) {
                    req.logger.info("Parsed arguments: \(parsedArgs)")
                    
                    let saveResult = await KCCQ12Service.saveQuestionnaireResponse(
                        linkId: parsedArgs.linkId,
                        code: parsedArgs.code,
                        phoneNumber: phoneNumber,
                        logger: req.logger
                    )
                    
                    let functionResponse: [String: Any] = [
                        "type": "conversation.item.create",
                        "item": [
                            "type": "function_call_output",
                            "call_id": response.callId ?? "",
                            "output": saveResult ?
                            "KCCQ-12 survey response saved successfully." :
                                "Failed to save KCCQ-12 survey response. Please try again."
                        ]
                    ]
                    let responseRequest: [String: Any] = [
                        "type": "response.create"
                    ]
                    
                    try await sendJSON(functionResponse, openAIWs)
                    try await sendJSON(responseRequest, openAIWs)
                    
                    await state.updateResponseStartTimestampTwilio(nil)
                    await state.updateLastAssistantItem(nil)
                } else {
                    do {
                        _ = try JSONDecoder().decode(KCCQ12ResponseArgs.self, from: argumentsData)
                    } catch let decodingError as DecodingError {
                        req.logger.error("Decoding error details: \(decodingError)")
                    }
                }
            } catch {
                req.logger.error("Error processing KCCQ-12 survey: \(error)")
                let errorResponse: [String: Any] = [
                    "type": "function_response",
                    "id": response.callId ?? "",
                    "error": [
                        "message": "Failed to process KCCQ-12 survey"
                    ]
                ]
                try await sendJSON(errorResponse, openAIWs)
            }
        }

        @Sendable
        func countAnsweredKCCQ12Questions(response: OpenAIResponse, openAIWs: WebSocket, phoneNumber: String) async throws {
            let count = await KCCQ12Service.countAnsweredQuestions(phoneNumber: phoneNumber, logger: req.logger)
            req.logger.info("Count of answered KCCQ-12 questions: \(count)")
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

            try await sendJSON(functionResponse, openAIWs)
            try await sendJSON(responseRequest, openAIWs)

            await state.updateResponseStartTimestampTwilio(nil)
            await state.updateLastAssistantItem(nil)
        }
        
        // Q17
        
        @Sendable
        func getQ17Question(response: OpenAIResponse, openAIWs: WebSocket, phoneNumber: String) async throws {
            let question = await Q17Service.getNextQuestion(phoneNumber: phoneNumber, logger: req.logger)
            
            let functionResponse: [String: Any] = [
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": response.callId ?? "",
                    "output": question ?? "No more questions available."
                ]
            ]
            
            req.logger.info("Q17 question functionResponse: \(functionResponse)")
            
            let responseRequest: [String: Any] = [
                "type": "response.create"
            ]
            
            
            if question == nil {
                // when there are no questions left, we also update the session instructions
                await updateSession(webSocket: openAIWs, systemMessage: Constants.endCall)
            } else {
                try await sendJSON(functionResponse, openAIWs)
            }
            try await sendJSON(responseRequest, openAIWs)
            
            await state.updateResponseStartTimestampTwilio(nil)
            await state.updateLastAssistantItem(nil)
            
            // Log the connection state after function response
            req.logger.info("Function response sent, connection state: \(openAIWs.isClosed ? "closed" : "open")")
        }
        
        @Sendable
        func saveQ17Response(response: OpenAIResponse, openAIWs: WebSocket, phoneNumber: String) async throws {
            do {
                req.logger.info("Attempting to save Q17 Response...")
                guard let arguments = response.arguments else {
                    throw Abort(.badRequest, reason: "No arguments provided")
                }
                let argumentsData = arguments.data(using: .utf8) ?? Data()
                
                if let parsedArgs = try? JSONDecoder().decode(Q17ResponseArgs.self, from: argumentsData) {
                    req.logger.info("Parsed arguments: \(parsedArgs)")
                    
                    let saveResult = await Q17Service.saveQuestionnaireResponse(
                        linkId: parsedArgs.linkId,
                        code: parsedArgs.code,
                        phoneNumber: phoneNumber,
                        logger: req.logger
                    )
                    
                    let functionResponse: [String: Any] = [
                        "type": "conversation.item.create",
                        "item": [
                            "type": "function_call_output",
                            "call_id": response.callId ?? "",
                            "output": saveResult ?
                            "Q17 survey response saved successfully." :
                                "Failed to save Q17 survey response. Please try again."
                        ]
                    ]
                    let responseRequest: [String: Any] = [
                        "type": "response.create"
                    ]
                    
                    try await sendJSON(functionResponse, openAIWs)
                    try await sendJSON(responseRequest, openAIWs)
                    
                    await state.updateResponseStartTimestampTwilio(nil)
                    await state.updateLastAssistantItem(nil)
                } else {
                    do {
                        _ = try JSONDecoder().decode(Q17ResponseArgs.self, from: argumentsData) // todo Args
                    } catch let decodingError as DecodingError {
                        req.logger.error("Decoding error details: \(decodingError)")
                    }
                }
            } catch {
                req.logger.error("Error processing Q17 survey: \(error)")
                let errorResponse: [String: Any] = [
                    "type": "function_response",
                    "id": response.callId ?? "",
                    "error": [
                        "message": "Failed to process Q17 survey"
                    ]
                ]
                try await sendJSON(errorResponse, openAIWs)
            }
        }

        @Sendable
        func countAnsweredQ17Questions(response: OpenAIResponse, openAIWs: WebSocket, phoneNumber: String) async throws {
            let count = await Q17Service.countAnsweredQuestions(phoneNumber: phoneNumber, logger: req.logger)
            req.logger.info("Count of answered Q17 questions: \(count)")
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

            try await sendJSON(functionResponse, openAIWs)
            try await sendJSON(responseRequest, openAIWs)

            await state.updateResponseStartTimestampTwilio(nil)
            await state.updateLastAssistantItem(nil)
        }
        
        @Sendable
        func handleSpeechStartedEvent(webSocket: WebSocket) async throws {
            let markQueue = await state.markQueue
            let responseStart = await state.responseStartTimestampTwilio
            let lastItem = await state.lastAssistantItem
            let streamSid = await state.streamSid
            
            guard !markQueue.isEmpty,
                  let responseStart = responseStart,
                  let lastItem = lastItem,
                  let streamSid = streamSid else {
                req.logger.info("Speech started but missing required state for interruption")
                return
            }
            
            let latestMediaTimestamp = await state.latestMediaTimestamp ?? 0
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
                try await sendJSON(truncateEvent, webSocket)
                
                let clearEvent: [String: Any] = [
                    "event": "clear",
                    "streamSid": streamSid
                ]
                try await sendJSON(clearEvent, twilioWs)
                
                await state.removeAllFromMarkQueue()
                await state.updateLastAssistantItem(nil)
                await state.updateResponseStartTimestampTwilio(nil)
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
            await state.appendToMarkQueue("responsePart")
        }
    }
}
