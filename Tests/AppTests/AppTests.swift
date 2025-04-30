//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import App
import VaporTesting
import XCTest


final class AppTests: XCTestCase {
    private func withApp(_ test: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        // Set up mock OpenAI key
        app.storage[OpenAIKeyStorageKey.self] = "mock-key"
        do {
            try await configure(app)
            try await test(app)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
    
    func testIncomingCall() async throws {
        try await withApp { app in
            // Set up mock host header
            var headers = HTTPHeaders()
            headers.add(name: "host", value: "localhost:8080")
            headers.add(name: "Content-Type", value: "application/json")
            
            try await app.testing().test(
                .POST,
                "test",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(["From": "+15551234567"])
                    app.logger.info("Request prepared with phone number")
                },
                afterResponse: { res async in
                    app.logger.info("Received response with status: \(res.status)")
                    XCTAssertEqual(res.status, .ok)
                    // Verify response is XML
                    XCTAssertEqual(res.headers.first(name: "Content-Type"), "text/xml")
                }
            )
        }
    }
}
