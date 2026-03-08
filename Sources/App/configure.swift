//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Vapor

/// Configure the application
public func configure(_ app: Application) async throws {
    // Initialize feature flags
    let featureFlags = FeatureFlags()
    app.featureFlags = featureFlags

    // Store keys in application storage for access in routes
    app.storage[OpenAIKeyStorageKey.self] = try requireEnvInProd(name: "OPENAI_API_KEY")
    app.storage[OpenAIWebhookSecretStorageKey.self] = try requireEnvInProd(
        name: "OPENAI_WEBHOOK_SECRET"
    )

    app.storage[EncryptionKeyStorageKey.self] =
        try requireEnvInProd(name: "ENCRYPTION_KEY").flatMap { key in
            guard let keyData = Data(base64Encoded: key), keyData.count == 32 else {
                throw Abort(
                    .internalServerError,
                    reason:
                        "Invalid ENCRYPTION_KEY (must be base64-encoded and 32 bytes when decoded)."
                )
            }
            return key
        }
    app.storage[RecordingsDecryptionKeyStorageKey.self] = Environment.get(
        "RECORDINGS_DECRYPTION_KEY"
    )

    app.storage[TwilioAccountSidStorageKey.self] = Environment.get("TWILIO_ACCOUNT_SID")
    app.storage[TwilioAPIKeyStorageKey.self] =
        Environment.get("TWILIO_API_KEY") ?? Environment.get("TWILIO_ACCOUNT_SID")
    app.storage[TwilioSecretStorageKey.self] = Environment.get("TWILIO_SECRET")

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
