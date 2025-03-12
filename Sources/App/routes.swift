//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Vapor
import Foundation

actor ConnectionState {
    var streamSid: String?
    var latestMediaTimestamp: Int? = 0
    var lastAssistantItem: String?
    var markQueue: [String] = []
    var responseStartTimestampTwilio: Int?
}

// Extend actor to update state safely
extension ConnectionState {
    func updateTimestamp(_ timestamp: Int?) {
        latestMediaTimestamp = timestamp
    }
    
    func updateStreamSid(_ sid: String) {
        streamSid = sid
    }
    
    func updateResponseStartTimestampTwilio(_ timestamp: Int?) {
        responseStartTimestampTwilio = timestamp
    }
    
    func updateLastAssistantItem(_ item: String?) {
        lastAssistantItem = item
    }
    
    func removeFirstFromMarkQueue() {
        if !markQueue.isEmpty {
            markQueue.removeFirst()
        }
    }
    
    func removeAllFromMarkQueue() {
        markQueue = []
    }
    
    func appendToMarkQueue(_ item: String) {
        markQueue.append(item)
    }
}

func routes(_ app: Application) throws {
    // Constants
    let systemMessage = """
        You are a helpful and professional AI assistant who is trained to help users record their daily health measurements over the phone. \
        You will ask for today's Blood Pressure measurement, today's heart rate measurement and today's weight measurement. \
        After each response of the user, you swiftly reply the recorded answer. After all the measurements are recorded, \
        you will ask the user to confirm the data by reading the data back to them. If the user confirms the data, \
        you will say 'Thank you for using our service. Goodbye!' and end the call.
        In the beginning, start by opening the conversation with 'Hello and welcome to our health data entry service, who am I speaking to?'.
        """
    let voice = "alloy"
    
    let logEventTypes = [
        "error",
        "response.content.done",
        "rate_limits.updated",
        "response.done",
        "input_audio_buffer.committed",
        "input_audio_buffer.speech_stopped",
        "input_audio_buffer.speech_started",
        "session.created"
    ]
    
    let showTimingMath = false
    
    app.get { req async in
        "It works!"
    }

    app.post("incoming-call") { req async -> Response in
        req.logger.info("\(req.headers)")
        req.logger.info("\(req.headers.first(name: "host") ?? "")")
        let twimlResponse =
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Response>
            <Connect>
                <Stream url="wss://\(req.headers.first(name: "host") ?? "")/voice-stream" />
            </Connect>
        </Response>
        """
        req.logger.info("\(twimlResponse)")
        return Response(
            status: .ok,
            headers: ["Content-Type": "text/xml"],
            body: .init(string: twimlResponse)
        )
    }
    
    app.webSocket("voice-stream") { req, connection async in
        req.logger.info("Client connected!")
        let state = ConnectionState()
        
        connection.onText { connection, text async in
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
                    req.logger.info("Incoming stream started: \(start.streamSid)")
                    
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
        
        // Connect to OpenAI WebSocket
        guard let openAIKey = app.storage[OpenAIKeyStorageKey.self] else {
            req.logger.info("OpenAI API key not found")
            return
        }
        
        // Create OpenAI WebSocket connection
        let openAIWSURL = "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01"
        guard let _ = URL(string: openAIWSURL) else {
            req.logger.info("Invalid OpenAI WebSocket URL")
            return
        }
        
        var headers = HTTPHeaders()
        headers.add(name: "Authorization", value: "Bearer \(openAIKey)")
        headers.add(name: "OpenAI-Beta", value: "realtime=v1")
        
        do {
            let _ = try await WebSocket.connect(to: openAIWSURL, headers: headers, on: req.eventLoop) { ws async in
                // Connected WebSocket.
                req.logger.info("Connected to the OpenAI Realtime API!")
                req.logger.info("\(ws)")
                initializeSession(ws: ws)
                
                ws.onText { ws, text async in
                    req.logger.info("Received message from OpenAI: \(text)")
                    do {
                        guard let jsonData = text.data(using: .utf8) else {
                            throw Abort(.badRequest, reason: "Failed to convert string to data")
                        }
                        req.logger.info("\(jsonData.debugDescription)")
                        let response = try JSONDecoder().decode(OpenAIResponse.self, from: jsonData)
                        
                        if logEventTypes.contains(response.type) {
                            print("Received event: \(response.type)", response)
                        }
                        
                        if response.type == "response.audio.delta", let delta = response.delta {
                            req.logger.info("Audio delta received")
                            let streamSid = await state.streamSid
                            req.logger.info("streamSid: \(streamSid ?? "")")
                            let audioDelta: [String: Any] = [
                                "event": "media",
                                "streamSid": streamSid ?? "",
                                "media": ["payload": delta]
                            ]
                            req.logger.info("\(audioDelta)")
                            let jsonData = try JSONSerialization.data(withJSONObject: audioDelta)
                            if let jsonString = String(data: jsonData, encoding: .utf8) {
                                try await connection.send(jsonString)
                                req.logger.info("Sent Audio delta to Connection WS")
                            }
                            
                            // First delta from a new response starts the elapsed time counter
                            let responseStartTimestampTwilio = await state.responseStartTimestampTwilio
                            if responseStartTimestampTwilio == nil {
                                let latestMediaTimestamp = await state.latestMediaTimestamp
                                await state.updateResponseStartTimestampTwilio(latestMediaTimestamp)
                                
                                let responseStartTimestampTwilio = await state.responseStartTimestampTwilio
                                if showTimingMath {
                                    req.logger.info("Setting start timestamp for new response: \(responseStartTimestampTwilio!)ms")
                                }
                            }
                            
                            if let itemId = response.itemId {
                                await state.updateLastAssistantItem(itemId)
                            }
                            
                            try await sendMark(ws: connection, streamSid: streamSid)
                        }
                        
                        if response.type == "input_audio_buffer.speech_started" {
                            req.logger.info("Speech started")
                            await handleSpeechStartedEvent(ws: ws)
                        }
                        
                        if response.type == "error", let error = response.error {
                            req.logger.error("OpenAI Error: \(error.message) (Code: \(error.code ?? "unknown"))")
                        }
                    } catch {
                        req.logger.info("Error processing OpenAI message: \(error)")
                    }
                }
                
                connection.onText { connection, text async in
                    do {
                        guard let data = text.data(using: .utf8) else { return }
                                let twilioEvent = try JSONDecoder().decode(TwilioEvent.self, from: data)
                        
                        switch twilioEvent.event {
                        case "media":
                            guard let media = twilioEvent.media else {
                                            req.logger.error("Media event missing media data")
                                            return
                                        }
                            
                            req.logger.info("Successfully parsed media event - timestamp: \(media.timestamp), payload length: \(media.payload.count)")
                            
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
                                try await ws.send(jsonString)
                                req.logger.info("Sent message to OpenAPI WS successfully")
                            }
                        default:
                            req.logger.info("Received non-media event: \(twilioEvent.event)")
                        }
                    } catch {
                        req.logger.info("Error processing message: \(error)")
                    }
                }
                
                // Handle WebSocket disconnect
                ws.onClose.whenComplete { _ in
                    req.logger.info("Disconnected from the OpenAI Realtime API")
                }
                
                connection.onClose.whenComplete { _ in
                    ws.close().whenComplete { _ in
                        req.logger.info("Client disconnected")
                    }
                }
            }
        } catch {
            req.logger.error("Error connecting to the OpenAI Realtime API: \(error)")
        }
        
        // Initialize OpenAI session
        @Sendable func initializeSession(ws: WebSocket) {
            let sessionUpdate: [String: Any] = [
                "type": "session.update",
                "session": [
                    "turn_detection": ["type": "server_vad"],
                    "input_audio_format": "g711_ulaw",
                    "output_audio_format": "g711_ulaw",
                    "voice": voice,
                    "instructions": systemMessage,
                    "modalities": ["text", "audio"]
                ]
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: sessionUpdate)
                req.logger.info("\(jsonData)")
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    ws.send(jsonString)
                    req.logger.info("Initialized Realtime API session!")
                }
            } catch {
                req.logger.info("Failed to serialize session update: \(error)")
            }
        }
        
        // Handle speech started event
        @Sendable func handleSpeechStartedEvent(ws: WebSocket) async {
            let markQueue = await state.markQueue
            guard !markQueue.isEmpty,
                  let responseStart = await state.responseStartTimestampTwilio,
                  let lastItem = await state.lastAssistantItem else {
                return
            }
            
            let latestMediaTimestamp = await state.latestMediaTimestamp
            let elapsedTime = latestMediaTimestamp ?? 0 - responseStart
            
            let truncateEvent: [String: Any] = [
                "type": "conversation.item.truncate",
                "item_id": lastItem,
                "content_index": 0,
                "audio_end_ms": elapsedTime
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: truncateEvent)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    try await ws.send(jsonString)
                }
            } catch {
                req.logger.info("Failed to serialize truncate event: \(error)")
            }
            
            // Reset state
            await state.removeAllFromMarkQueue()
            await state.updateLastAssistantItem(nil)
            await state.updateResponseStartTimestampTwilio(nil)
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

// Supporting structures
struct OpenAIResponse: Codable {
    let type: String
    let delta: String?
    let itemId: String?
    let error: OpenAIError?
    
    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case itemId = "item_id"
        case error
    }
}

struct OpenAIError: Codable {
    let message: String
    let code: String?
}


struct TwilioEvent: Decodable {
    let event: String
    let media: MediaData?
    let start: StartData?
    
    // Add custom decoding if needed
    enum CodingKeys: String, CodingKey {
        case event
        case media
        case start
    }
}

struct MediaData: Decodable {
    let timestamp: String
    let payload: String
    let chunk: String
    let track: String
}

struct StartData: Decodable {
    let streamSid: String
}
