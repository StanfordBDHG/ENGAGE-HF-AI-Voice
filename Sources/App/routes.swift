//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Crypto
import Foundation
import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ -> HTTPStatus in
        .ok
    }

    app.post("update-recordings") { req async -> Response in
        await handleUpdateRecordings(app: app, req: req)
    }

    app.post("incoming-call") { req async -> Response in
        await handleIncomingCall(app: app, req: req)
    }
}

private func handleUpdateRecordings(app: Application, req: Request) async -> Response {
    guard let twilioAccountSid = app.storage[TwilioAccountSidStorageKey.self],
        let twilioAPIKey = app.storage[TwilioAPIKeyStorageKey.self],
        let twilioSecret = app.storage[TwilioSecretStorageKey.self]
    else {
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

        let recordingService = try CallRecordingService(
            api: twilioAPI,
            decryptionKey: app.storage[RecordingsDecryptionKeyStorageKey.self],
            encryptionKey: app.storage[EncryptionKeyStorageKey.self],
            logger: req.logger
        )
        try await recordingService.storeNewestRecordings()
    } catch {
        req.logger.error("Failed to update newest recordings: \(error)")
        return Response(status: .internalServerError)
    }

    return Response(status: .ok)
}

private func handleIncomingCall(app: Application, req: Request) async -> Response {
    guard let body = req.body.data else {
        return Response(status: .badRequest)
    }
    let bodyData = Data(buffer: body)

    // Verify webhook signature per Standard Webhooks spec if secret is configured
    // https://github.com/standard-webhooks/standard-webhooks/blob/main/spec/standard-webhooks.md
    if let webhookSecret = app.storage[OpenAIWebhookSecretStorageKey.self] {
        guard
            verifyWebhookSignature(
                payload: bodyData,
                headers: req.headers,
                secret: webhookSecret,
                logger: req.logger
            )
        else {
            req.logger.error("Invalid webhook signature encountered.")
            return Response(status: .unauthorized)
        }

        req.logger.info("Successfully verified webhook signature")
    }

    do {
        let logger = app.logger
        let event = try JSONDecoder().decode(OpenAICAllIncomingEvent.self, from: bodyData)
        let callId = event.data.callId
        let phoneNumber =
            extractPhoneNumberFromSIPHeaders(event.data.sipHeaders)
            ?? "Unknown-\(UUID().uuidString)"

        logger.info(
            "About to create session handler for call \"\(callId)\" from \"\(phoneNumber)\""
        )
        let handler = try await CallHandler(callId: callId, phoneNumber: phoneNumber, app: app)
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

/// Verifies an incoming webhook request using the Standard Webhooks HMAC-SHA256 spec.
/// The signed content is: "{webhook-id}.{webhook-timestamp}.{body}"
private func verifyWebhookSignature(
    payload: Data,
    headers: HTTPHeaders,
    secret: String,
    logger: Logger
) -> Bool {
    guard let webhookId = headers.first(name: "webhook-id"),
        let timestampString = headers.first(name: "webhook-timestamp"),
        let signatureHeader = headers.first(name: "webhook-signature")
    else {
        logger.warning(
            "Missing Standard Webhooks headers (webhook-id, webhook-timestamp, webhook-signature)."
        )
        return false
    }

    guard let timestamp = TimeInterval(timestampString) else {
        logger.warning("Invalid webhook-timestamp header value: \(timestampString)")
        return false
    }
    // Reject timestamps older than 5 minutes to prevent replay attacks
    let age = Date().timeIntervalSince1970 - timestamp
    if abs(age) > 300 {
        logger.warning("Webhook timestamp too old or too far in the future (age: \(age)s).")
        return false
    }

    // The secret from OpenAI is base64-encoded with a "whsec_" prefix
    let base64Key = secret.hasPrefix("whsec_") ? String(secret.dropFirst(6)) : secret
    guard let keyData = Data(base64Encoded: base64Key) else {
        logger.error("Failed to decode webhook secret from base64.")
        return false
    }

    // signed_content = "{webhook-id}.{webhook-timestamp}.{body}"
    let signedContent = Data("\(webhookId).\(timestampString).".utf8) + payload
    let key = SymmetricKey(data: keyData)
    let expectedMAC = HMAC<SHA256>.authenticationCode(for: signedContent, using: key)
    let expectedSignature = "v1," + Data(expectedMAC).base64EncodedString()

    // The header may contain multiple space-separated signatures for key rotation
    let signatures = signatureHeader.split(separator: " ").map(String.init)
    if signatures.contains(expectedSignature) {
        return true
    }

    logger.warning("Webhook signature verification failed.")
    return false
}

private func extractPhoneNumberFromSIPHeaders(_ headers: [OpenAICAllIncomingEvent.SIPHeader])
    -> String? {
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
