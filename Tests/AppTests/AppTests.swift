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


final class MockQuestionnaireResponseLoader: QuestionnaireResponseLoader {
    func loadQuestionnaireResponse(phoneNumber: String, logger: Logger) async -> QuestionnaireResponse {
        let mockResponse = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.completed))
        mockResponse.item = [
            createResponseItem(linkId: "a459b804-35bf-4792-f1eb-0b52c4e176e1", value: "3"),
            createResponseItem(linkId: "cf9c5031-1ed5-438a-fc7d-dc69234015a0", value: "2"),
            createResponseItem(linkId: "1fad0f81-b2a9-4c8f-9a78-4b2a5d7aef07", value: "2"),
            createResponseItem(linkId: "692bda7d-a616-43d1-8dc6-8291f6460ab2", value: "3"),
            createResponseItem(linkId: "b1734b9e-1d16-4238-8556-5ae3fa0ba913", value: "4"),
            createResponseItem(linkId: "57f37fb3-a0ad-4b1f-844e-3f67d9b76946", value: "5"),
            createResponseItem(linkId: "396164df-d045-4c56-d710-513297bdc6f2", value: "2"),
            createResponseItem(linkId: "75e3f62e-e37d-48a2-f4d9-af2db8922da0", value: "3"),
            createResponseItem(linkId: "fce3a16e-c6d8-4bac-8ab5-8f4aee4adc08", value: "4"),
            createResponseItem(linkId: "8649bc8c-f908-487d-87a4-a97106b1a4c3", value: "2"),
            createResponseItem(linkId: "1eee7259-da1c-4cba-80a9-e67e684573a1", value: "3"),
            createResponseItem(linkId: "883a22a8-2f6e-4b41-84b7-0028ed543192", value: "4")
        ]
        
        return mockResponse
    }
    
    private func createResponseItem(linkId: String, value: String) -> QuestionnaireResponseItem {
        let item = QuestionnaireResponseItem(linkId: FHIRPrimitive(FHIRString(linkId)))
        let answer = QuestionnaireResponseItemAnswer()
        answer.value = .string(FHIRPrimitive(FHIRString(value)))
        item.answer = [answer]
        return item
    }
}

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
                    try req.content.encode(["From": "+15551234567"])
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
            await KCCQ12Service.setQuestionnaireResponseLoader(MockQuestionnaireResponseLoader())
            
            let score = await KCCQ12Service.computeSymptomScore(phoneNumber: "1234567890", logger: app.logger)
            print(score)
            #expect(score == 48.4375, "Score should be 48.4375 with mocked responses")
        }
    }
    
    @Test("Test User Feedback Generation")
    func testUserFeedback() async throws {
        try await withApp { _ in
            let feedback = FeedbackService.feedback()
            print(feedback)
            #expect(feedback == """
            Your blood pressure is high and pulse is normal.
            Your symptom score is ***, which means your heart failure doesn’t stop you much from doing your normal daily activities.
            You feel [Q17 response] compared to 3 months ago.
            """)
        }
    }
}
