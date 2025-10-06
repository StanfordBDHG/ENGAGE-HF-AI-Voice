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
    
    app.post("update-recordings") { req async -> Response in
        guard let twilioAccountSid = app.storage[TwilioAccountSidStorageKey.self],
              let twilioAPIKey = app.storage[TwilioAPIKeyStorageKey.self],
              let twilioSecret = app.storage[TwilioSecretStorageKey.self] else {
                  req.logger.warning("Couldn't update newest recordings due to missing Twilio credentials.")
                  return Response(status: .internalServerError)
        }
        
        do {
            let twilioAPI = try TwilioAPI(
                accountSid: twilioAccountSid,
                apiKey: twilioAPIKey,
                secret: twilioSecret,
                httpClient: app.http.client.shared
            )
            
            let recordingService = CallRecordingService(api: twilioAPI, logger: req.logger)
            try await recordingService.storeNewestRecordings()
        } catch {
            req.logger.error("Failed to update newest recordings: \(error)")
        }
        
        return Response(status: .ok)
    }
    
    app.post("incoming-call") { req async -> Response in
        guard let body = req.body.data else {
            return Response(status: .badRequest)
        }
        
        do {
            let logger = app.logger
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
            req.logger.error("Failed to accept call: \(error)")
            return Response(status: .internalServerError)
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
