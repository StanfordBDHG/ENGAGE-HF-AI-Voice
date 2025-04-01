//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Vapor


public func configure(_ app: Application) async throws {
    // Environment variables
    guard let openAIKey = Environment.get("OPENAI_API_KEY") else {
        app.logger.error("Missing OpenAI API key. Please set it in the .env file.")
        exit(1)
    }
    
    // Store API key in application storage for access in routes
    app.storage[OpenAIKeyStorageKey.self] = openAIKey
    
    // Configure server
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 5000
    
    // Register routes
    try routes(app)
}

// Storage key for OpenAI API key
struct OpenAIKeyStorageKey: StorageKey {
    typealias Value = String
}
