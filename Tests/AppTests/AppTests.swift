//
// This source file is part of the ENGAGE-HF AI-Voice open-source project
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

    @Test(
        "extractPhoneNumberFromSIPHeader extracts E.164 numbers",
        arguments: [
            // Standard E.164 in SIP From header
            ("<sip:+14155551234@gateway.twilio.com>;tag=abc123", "+14155551234"),
            // Minimal — just the SIP URI
            ("<sip:+14155551234@10.0.0.1>", "+14155551234"),
            // International numbers
            ("<sip:+442071234567@gateway.twilio.com>;tag=xyz", "+442071234567"),
            ("<sip:+4930123456@gateway.twilio.com>", "+4930123456"),
            ("<sip:+61291234567@gateway.twilio.com>", "+61291234567"),
            // Short numbers (some countries)
            ("<sip:+1234@gateway.twilio.com>", "+1234"),
            // Maximum length E.164 (15 digits)
            ("<sip:+123456789012345@gateway.twilio.com>", "+123456789012345")
        ]
    )
    func extractPhoneNumberValid(input: String, expected: String) {
        #expect(extractPhoneNumberFromSIPHeader(value: input) == expected)
    }

    @Test(
        "extractPhoneNumberFromSIPHeader returns nil for anonymous/invalid callers",
        arguments: [
            // Anonymous per RFC 3323
            "<sip:anonymous@anonymous.invalid>",
            // Common carrier-specific anonymous values
            "<sip:anonymous@gateway.twilio.com>;tag=abc",
            "<sip:restricted@gateway.twilio.com>",
            "<sip:unknown@gateway.twilio.com>",
            "<sip:unavailable@gateway.twilio.com>",
            "<sip:private@gateway.twilio.com>",
            "<sip:blocked@gateway.twilio.com>",
            "<sip:withheld@gateway.twilio.com>",
            // Missing + prefix (not E.164)
            "<sip:14155551234@gateway.twilio.com>",
            // Number too long (16+ digits)
            "<sip:+1234567890123456@gateway.twilio.com>",
            // Number with only + (no digits)
            "<sip:+@gateway.twilio.com>",
            // Leading zero after + (not valid E.164)
            "<sip:+0123456789@gateway.twilio.com>",
            // Empty string
            ""
        ]
    )
    func extractPhoneNumberNil(input: String) {
        #expect(extractPhoneNumberFromSIPHeader(value: input) == nil)
    }
}
