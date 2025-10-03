//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ -> HTTPStatus in
            .ok
    }
    
    app.post("incoming-call") { req async -> Response in
        guard let body = req.body.data else {
            return Response(status: .badRequest)
        }
        
        Task<Void, Never> {
            let logger = app.logger
            
            do {
                let event = try JSONDecoder().decode(OpenAICAllIncomingEvent.self, from: body)
                let callId = event.data.callId
                let phoneNumber = extractPhoneNumberFromSIPHeaders(event.data.sipHeaders) ?? ""
                
                logger.info("About to create session handler for call \"\(callId)\" from \"\(phoneNumber)\"")
                let handler = await CallHandler(callId: callId, phoneNumber: phoneNumber, app: app)
                logger.info("About to accept call \"\(callId)\" from \"\(phoneNumber)\".")
                try await handler.accept()
                logger.info("About to open websocket for call \"\(callId)\" from \"\(phoneNumber)\".")
                try await handler.openWebsocket()
            } catch {
                logger.error("Call task failed: \(error)")
            }
        }
        
        return Response(status: .ok)
    }
}

private struct OpenAICAllIncomingEvent: Decodable {
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
    
    let id: String
    let data: ContainedData
}

private func extractPhoneNumberFromSIPHeaders(_ headers: [OpenAICAllIncomingEvent.SIPHeader]) -> String? {
    headers
        .first { $0.name == "From" }?.value
        .components(separatedBy: ";")
        .first?
        .trimmingPrefix { $0 != "<" }
        .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        .trimmingPrefix("sip:")
        .components(separatedBy: "@")
        .first
}
