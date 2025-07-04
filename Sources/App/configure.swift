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
    
    // Environment variables
    let openAIKey: String
    if app.environment == .testing {
        openAIKey = "dummy-key-for-testing"
    } else {
        guard let key = Environment.get("OPENAI_API_KEY") else {
            app.logger.error("Missing OpenAI API key. Please set it in the .env file.")
            exit(1)
        }
        openAIKey = key
    }
    
    // Encryption key (optional for development)
    var encryptionKey: String?
    if app.environment == .testing {
        encryptionKey = nil // No encryption in testing
    } else {
        encryptionKey = Environment.get("ENCRYPTION_KEY")
        if encryptionKey == nil {
            app.logger.warning("No encryption key provided. Questionnaire responses will be stored unencrypted.")
        } else {
            // swiftlint:disable:next force_unwrapping
            guard let keyData = Data(base64Encoded: encryptionKey!),
                  keyData.count == 32 else {
                app.logger.warning(
                    """
                    Invalid encryption key provided (must be base64-encoded and 32 bytes when decoded).
                    Questionnaire responses will be stored unencrypted.
                    """
                )
                encryptionKey = nil
                return
            }
        }
    }
    
    // Store keys in application storage for access in routes
    app.storage[OpenAIKeyStorageKey.self] = openAIKey
    app.storage[EncryptionKeyStorageKey.self] = encryptionKey
    
    // Configure server
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 5000
    
    // Register routes
    try routes(app)
}
