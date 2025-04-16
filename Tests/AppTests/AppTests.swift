//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import App
import Testing
import VaporTesting


@Suite("App Tests")
struct AppTests {
    private func withApp(_ test: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await test(app)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
    
    @Test("Test Incomming Call Route")
    func incomingCall() async throws {
        try await withApp { app in
            try await app.testing().test(.POST, "incoming-call", afterResponse: { res async in
                #expect(res.status == .ok)
            })
        }
    }
}
