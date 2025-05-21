//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import App
import ModelsR4
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
    
    @Test("Test Health Route")
    func health() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "health") { res in
                #expect(res.status == .ok)
            }
        }
    }
    
    @Test("Test Incoming Call Route")
    func incomingCall() async throws {
        try await withApp { app in
            try await app.testing().test(
                .POST,
                "incoming-call",
                beforeRequest: { req in
                    try req.content.encode(["From": "+16502341234"])
                    app.logger.info("Request prepared with phone number")
                },
                afterResponse: { res async in
                    app.logger.info("Received response with status: \(res.status)")
                    #expect(res.status == .ok)
                }
            )
        }
    }
    
    @Test("Test Symptom Score Calculation")
    func testSymptomScoreCalculation() async throws {
        try await withApp { app in
            let score = await KCCQ12Service.computeSymptomScore(phoneNumber: "+16502341234", logger: app.logger)
            
            #expect(score == 50.0, "Score should be 50.0 with mocked responses")
        }
    }
    
    @Test("Test User Feedback Generation")
    func testUserFeedback() async throws {
        try await withApp { app in
            let feedback = await FeedbackService.feedback(phoneNumber: "+16502341234", logger: app.logger)
            
            #expect(feedback == """
            Your blood pressure and pulse are normal.
            Your symptom score is 50.0, which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel worse compared to 3 months ago.
            """)
        }
    }
}
