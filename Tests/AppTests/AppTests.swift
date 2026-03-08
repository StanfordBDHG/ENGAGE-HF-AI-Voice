//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4
import Testing
import VaporTesting

@testable import App

@Suite("App Tests")
struct AppTests {
    @MainActor
    private func withApp(_ test: @MainActor @Sendable (Application) async throws -> Void)
        async throws {
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
    @MainActor
    func health() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "health") { @Sendable res in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("Test Symptom Score Calculation")
    @MainActor
    func testSymptomScoreCalculation() async throws {
        try await withApp { app in
            let section = KCCQ12Section(internalTestingMode: app.featureFlags.internalTestingMode)
            let engine = try FHIRQuestionnaireEngine(
                section: section,
                phoneNumber: "+16502341234",
                logger: app.logger,
                featureFlags: app.featureFlags
            )
            let items = engine.currentResponse().item ?? []
            let score = KCCQ12ScoreCalculator.computeSymptomScore(from: items)

            #expect(score == 50.0, "Score should be 50.0 with mocked responses")
        }
    }

    @Test("Test User Feedback Generation")
    @MainActor
    func testUserFeedback() async throws {
        try await withApp { app in
            let featureFlags = app.featureFlags
            let sections: [any QuestionnaireSection] = [
                VitalSignsSection(),
                KCCQ12Section(internalTestingMode: featureFlags.internalTestingMode),
                Q17Section()
            ]
            let coordinator = try CallFlowCoordinator(
                sections: sections,
                phoneNumber: "+16502341234",
                logger: app.logger,
                featureFlags: featureFlags,
                feedbackProvider: EngageHFFeedbackProvider()
            )
            let feedback = await coordinator.generateFeedback()

            let expected = """
                Your blood pressure and pulse are normal.
                Your symptom score is 50.0, which means you have a lot of symptoms \
                from your heart failure that make it hard to do everyday activities.
                You feel worse compared to 3 months ago.
                """
            #expect(feedback == expected)
        }
    }
}
