//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Vapor
import Foundation


func routes(_ app: Application) throws {
    app.post("incoming-call") { req async -> Response in
        let twimlResponse =
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Response>
            <Connect>
                <Stream url="wss://\(req.headers.first(name: "host") ?? "")/voice-stream" />
            </Connect>
        </Response>
        """
        return Response(
            status: .ok,
            headers: ["Content-Type": "text/xml"],
            body: .init(string: twimlResponse)
        )
    }
    
    app.webSocket("voice-stream") { req, twilioWs async in
        let state = ConnectionState()
        
        // Handle incoming messages from Twilio
        twilioWs.onText { twilioWs, text async in
            do {
                guard let data = text.data(using: .utf8) else { return }
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
        
        guard let openAIKey = app.storage[OpenAIKeyStorageKey.self] else {
            req.logger.info("OpenAI API key not found")
            return
        }
        let openAIWsURL = "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01"
        guard let _ = URL(string: openAIWsURL) else {
            req.logger.info("Invalid OpenAI WebSocket URL")
            return
        }
        var headers = HTTPHeaders()
        headers.add(name: "Authorization", value: "Bearer \(openAIKey)")
        headers.add(name: "OpenAI-Beta", value: "realtime=v1")
        
        do {
            let _ = try await WebSocket.connect(to: openAIWsURL, headers: headers, on: req.eventLoop) { openAIWs async in
                initializeSession(ws: openAIWs)
                
                // Handle incoming messages from Twilio
                twilioWs.onText { twilioWs, text async in
                    await handleTwilioMessage(openAIWs: openAIWs, text: text)
                }
                
                // Handle incoming messages from OpenAI
                openAIWs.onText { openAIWs, text async in
                    await handleOpenAIMessage(twilioWs: twilioWs, openAIWs: openAIWs, text: text)
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
        
        
        @Sendable func initializeSession(ws: WebSocket) {
            let sessionUpdate: [String: Any] = [
                "type": "session.update",
                "event_id": "event_\(String(UUID().uuidString.prefix(8)))",
                "session": [
                    "modalities": ["text", "audio"],
                    "instructions": Constants.SYSTEM_MESSAGE_ONLY_KCCQ12,
                    "voice": Constants.VOICE,
                    "output_audio_format": "g711_ulaw",
                    "input_audio_format": "g711_ulaw",
                    "turn_detection": ["type": "server_vad"],
                    "tools": [
                        [
                            "type": "function",
                            "name": "save_blood_pressure",
                            "description": "Saves the blood pressure measurement of the patient to the database.",
                            "parameters": [
                                "type": "object",
                                "properties": [
                                    "systolicBloodPressure": [
                                        "type": "number",
                                        "description": "Blood pressure in mmHg/mmHg"
                                    ],
                                    "diastolicBloodPressure": [
                                        "type": "number",
                                        "description": "Blood pressure in mmHg/mmHg"
                                    ]
                                ],
                                "required": ["systolicBloodPressure", "diastolicBloodPressure"],
                                "additionalProperties": false
                            ]
                        ],
                        [
                            "type": "function",
                            "name": "save_heart_rate",
                            "description": "Saves the heart rate measurement of the patient to the database.",
                            "parameters": [
                                "type": "object",
                                "properties": [
                                    "heartRate": [
                                        "type": "number",
                                        "description": "Heart rate in beats per minute"
                                    ]
                                ],
                                "required": ["heartRate"],
                                "additionalProperties": false
                            ]
                        ],
                        [
                            "type": "function",
                            "name": "save_weight",
                            "description": "Saves the weight measurement of the patient to the database.",
                            "parameters": [
                                "type": "object",
                                "properties": [
                                    "weight": [
                                        "type": "number",
                                        "description": "Weight in pounds"
                                    ]
                                ],
                                "required": ["weight"],
                                "additionalProperties": false
                            ]
                        ],
                        [
                            "type": "function",
                            "name": "get_kccq12_question",
                            "description": "Retrieves the next question and current progress from the KCCQ-12 heart failure quality of life survey. This function should be called repeatedly to get each question one at a time. When no more questions are available, it will return a message indicating that the survey is complete.",
                            "parameters": [
                                "type": "object",
                                "properties": [:],
                            ]
                        ],
                        [
                            "type": "function",
                            "name": "save_kccq12_response",
                            "description": "Saves a patient response of the KCCQ-12 heart failure quality of life survey. This function should be called after a response is recorded to save it.",
                            "parameters": [
                                "type": "object",
                                "properties": [
                                    "linkId": [
                                        "type": "string",
                                        "description": "The KCCQ-12 question's linkId",
                                    ],
                                    "code": [
                                        "type": "string",
                                        "description": "The KCCQ-12 question's corresponding answer code.",
                                    ]
                                ],
                                "required": ["linkId", "code"],
                                "additionalProperties": false
                            ]
                        ]
                    ],
                    "tool_choice": "auto"
                ]
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: sessionUpdate)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    ws.send(jsonString)
                    let responseRequest: [String: Any] = [
                        "type": "response.create"
                    ]
                    let responseData = try JSONSerialization.data(withJSONObject: responseRequest)
                    if let jsonString = String(data: responseData, encoding: .utf8) {
                        ws.send(jsonString)
                    }
                }
            } catch {
                req.logger.error("Failed to serialize session update: \(error)")
            }
        }
        
        @Sendable func handleTwilioMessage(openAIWs: WebSocket, text: String) async {
            do {
                guard let data = text.data(using: .utf8) else { return }
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
        
        @Sendable func handleOpenAIMessage(twilioWs: WebSocket, openAIWs: WebSocket, text: String) async {
            do {
                guard let jsonData = text.data(using: .utf8) else {
                    throw Abort(.badRequest, reason: "Failed to convert string to data")
                }
                let response = try JSONDecoder().decode(OpenAIResponse.self, from: jsonData)
                
                if Constants.LOG_EVENT_TYPES.contains(response.type) {
                    print("Received event: \(response.type)", response)
                }
                
                try await handleOpenAIFunctionCall(response: response, openAIWs: openAIWs)
                
                
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
                    
                    try await sendMark(ws: twilioWs, streamSid: streamSid)
                }
                
                // Handling for interuptions of the caller
                if response.type == "input_audio_buffer.speech_started" {
                    try await handleSpeechStartedEvent(ws: openAIWs)
                }
                
                if response.type == "error", let error = response.error {
                    req.logger.error("OpenAI Error: \(error.message) (Code: \(error.code ?? "unknown"))")
                }
            } catch {
                req.logger.info("Error processing OpenAI message: \(error)")
            }
        }
        
        @Sendable func handleOpenAIFunctionCall(response: OpenAIResponse, openAIWs: WebSocket) async throws {
            if response.type == "response.function_call_arguments.done" {
                switch response.name {
                case "save_blood_pressure":
                    try await saveBloodPressure(response: response, openAIWs: openAIWs)
                case "save_heart_rate":
                    try await saveHeartRate(response: response, openAIWs: openAIWs)
                case "save_weight":
                    try await saveWeight(response: response, openAIWs: openAIWs)
                case "get_kccq12_question":
                    try await getKCCQ12Question(response: response, openAIWs: openAIWs)
                case "save_kccq12_response":
                    try await saveKCCQ12Response(response: response, openAIWs: openAIWs)
                default:
                    req.logger.error("Unknown function call: \(String(describing: response.name))")
                }
            }
        }
        
        @Sendable func saveBloodPressure(response: OpenAIResponse, openAIWs: WebSocket) async throws {
            do {
                req.logger.info("Attempting to save blood pressure...")
                let argumentsData = response.arguments?.data(using: .utf8) ?? Data()
                if let parsedArgs = try? JSONDecoder().decode(BloodPressureArgs.self, from: argumentsData) {
                    
                    let saveResult = HealthDataService.saveBloodPressure(
                        bloodPressureSystolic: parsedArgs.systolicBloodPressure,
                        bloodPressureDiastolic: parsedArgs.diastolicBloodPressure,
                        logger: req.logger
                    )
                    
                    let functionResponse: [String: Any] = [
                        "type": "conversation.item.create",
                        "item": [
                            "type": "function_call_output",
                            "call_id": response.callId ?? "",
                            "output": saveResult ?
                            "Blood pressure saved successfully." :
                                "Failed to save blood pressure. Please try again."
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
            } catch {
                req.logger.error("Error processing blood pressure: \(error)")
                // Send error response back to OpenAI
                let errorResponse: [String: Any] = [
                    "type": "function_response",
                    "id": response.callId ?? "",
                    "error": [
                        "message": "Failed to process blood pressure"
                    ]
                ]
                try await sendJSON(errorResponse, openAIWs)
            }
        }
        
        @Sendable func saveHeartRate(response: OpenAIResponse, openAIWs: WebSocket) async throws {
            do {
                req.logger.info("Attempting to save heart rate...")
                let argumentsData = response.arguments?.data(using: .utf8) ?? Data()
                if let parsedArgs = try? JSONDecoder().decode(HeartRateArgs.self, from: argumentsData) {
                    
                    let saveResult = HealthDataService.saveHeartRate(parsedArgs.heartRate, logger: req.logger)
                    
                    let functionResponse: [String: Any] = [
                        "type": "conversation.item.create",
                        "item": [
                            "type": "function_call_output",
                            "call_id": response.callId ?? "",
                            "output": saveResult ?
                            "Heart rate saved successfully." :
                                "Failed to save heart rate. Please try again."
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
            } catch {
                req.logger.error("Error processing heart rate: \(error)")
                // Send error response back to OpenAI
                let errorResponse: [String: Any] = [
                    "type": "function_response",
                    "id": response.callId ?? "",
                    "error": [
                        "message": "Failed to process heart rate"
                    ]
                ]
                try await sendJSON(errorResponse, openAIWs)
            }
        }
        
        @Sendable func saveWeight(response: OpenAIResponse, openAIWs: WebSocket) async throws {
            do {
                req.logger.info("Attempting to save weight...")
                let argumentsData = response.arguments?.data(using: .utf8) ?? Data()
                if let parsedArgs = try? JSONDecoder().decode(WeightArgs.self, from: argumentsData) {
                    
                    let saveResult = HealthDataService.saveWeight(parsedArgs.weight, logger: req.logger)
                    
                    let functionResponse: [String: Any] = [
                        "type": "conversation.item.create",
                        "item": [
                            "type": "function_call_output",
                            "call_id": response.callId ?? "",
                            "output": saveResult ?
                            "Weight saved successfully." :
                                "Failed to save weight. Please try again."
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
            } catch {
                req.logger.error("Error processing weight: \(error)")
                // Send error response back to OpenAI
                let errorResponse: [String: Any] = [
                    "type": "function_response",
                    "id": response.callId ?? "",
                    "error": [
                        "message": "Failed to process weight"
                    ]
                ]
                try await sendJSON(errorResponse, openAIWs)
            }
        }
        
        @Sendable func getKCCQ12Question(response: OpenAIResponse, openAIWs: WebSocket) async throws {
            let question = await KCCQ12Service.getNextQuestion(logger: req.logger)
            
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
            
            try await sendJSON(functionResponse, openAIWs)
            try await sendJSON(responseRequest, openAIWs)
            
            await state.updateResponseStartTimestampTwilio(nil)
            await state.updateLastAssistantItem(nil)
            
            // Log the connection state after function response
            req.logger.info("Function response sent, connection state: \(openAIWs.isClosed ? "closed" : "open")")
        }
        
        @Sendable func saveKCCQ12Response(response: OpenAIResponse, openAIWs: WebSocket) async throws {
            do {
                req.logger.info("Attempting to save KCCQ12 Response...")
                guard let arguments = response.arguments else {
                    req.logger.error("Arguments are nil")
                    throw Abort(.badRequest, reason: "No arguments provided")
                }
                let argumentsData = arguments.data(using: .utf8) ?? Data()
                
                // Try to print as UTF8 string
                if let dataAsString = String(data: argumentsData, encoding: .utf8) {
                    req.logger.info("Data as UTF8 string: '\(dataAsString)'")
                } else {
                    req.logger.error("Could not convert data back to UTF8 string")
                }
                
                req.logger.info("\(argumentsData)")
                req.logger.info("\(argumentsData.debugDescription)")
                if let parsedArgs = try? JSONDecoder().decode(KCCQ12ResponseArgs.self, from: argumentsData) {
                    req.logger.info("Parsed arguments: \(parsedArgs)")
                    
                    let saveResult = KCCQ12Service.saveQuestionnaireResponse(linkId: parsedArgs.linkId, code: parsedArgs.code, logger: req.logger)
                    
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
                    req.logger.error("Failed to parse KCCQ12Args")
                    do {
                        let _ = try JSONDecoder().decode(KCCQ12ResponseArgs.self, from: argumentsData)
                    } catch let decodingError {
                        req.logger.error("Decoding error details: \(decodingError)")
                    }
                }
            } catch {
                req.logger.error("Error processing KCCQ-12 survey: \(error)")
                // Send error response back to OpenAI
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
        
        @Sendable func handleSpeechStartedEvent(ws: WebSocket) async throws {
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
                try await sendJSON(truncateEvent, ws)
                
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
        
        @Sendable func sendJSON(_ object: [String: Any], _ ws: WebSocket) async throws {
            let jsonData = try JSONSerialization.data(withJSONObject: object)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw Abort(.internalServerError, reason: "Failed to encode JSON")
            }
            try await ws.send(jsonString)
        }
        
        @Sendable func sendMark(ws: WebSocket, streamSid: String?) async throws {
            guard let streamSid = streamSid else { return }
            
            let markEvent: [String: Any] = [
                "event": "mark",
                "streamSid": streamSid,
                "mark": ["name": "responsePart"]
            ]
            
            try await sendJSON(markEvent, ws)
            await state.appendToMarkQueue("responsePart")
        }
    }
}
