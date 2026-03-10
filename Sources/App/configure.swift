//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziLLMOpenAI
import SpeziLLMOpenAIRealtime
import SpeziVapor
import Vapor

/// Configure the application
public func configure(_ app: Application) async throws {
    let featureFlags = FeatureFlags()

    let openAIKey = try requireEnvInProd(name: "OPENAI_API_KEY")
    let openAIWebhookSecret = try requireEnvInProd(name: "OPENAI_WEBHOOK_SECRET")

    let encryptionKey = try requireEnvInProd(name: "ENCRYPTION_KEY").flatMap { key -> String? in
        guard let keyData = Data(base64Encoded: key), keyData.count == 32 else {
            throw Abort(
                .internalServerError,
                reason: "Invalid ENCRYPTION_KEY (must be base64-encoded and 32 bytes when decoded)."
            )
        }
        return key
    }

    let recordingsDecryptionKey = Environment.get("RECORDINGS_DECRYPTION_KEY")
    let twilioAccountSid = Environment.get("TWILIO_ACCOUNT_SID")
    let twilioAPIKey = Environment.get("TWILIO_API_KEY") ?? Environment.get("TWILIO_ACCOUNT_SID")
    let twilioSecret = Environment.get("TWILIO_SECRET")

    await MainActor.run {
        app.spezi.configure {
            AppConfigModule(
                openAIKey: openAIKey,
                openAIWebhookSecret: openAIWebhookSecret,
                encryptionKey: encryptionKey,
                recordingsDecryptionKey: recordingsDecryptionKey,
                twilioAccountSid: twilioAccountSid,
                twilioAPIKey: twilioAPIKey,
                twilioSecret: twilioSecret,
                featureFlags: featureFlags
            )
            LLMOpenAIRealtimePlatform(
                configuration: LLMOpenAIPlatformConfiguration(
                    authToken: .constant(openAIKey ?? "")
                )
            )
        }
    }

    // Configure server
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 5000

    // Register routes
    try routes(app)
}

private func requireEnvInProd(name: String) throws -> String? {
    if let value = Environment.get(name), !value.isEmpty {
        return value
    } else {
        #if !DEBUG
            throw Abort(
                .internalServerError,
                reason:
                    "Missing required environment variable \(name). Please set it in the .env file."
            )
        #else
            return nil
        #endif
    }
}
