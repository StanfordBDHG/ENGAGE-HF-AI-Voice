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
    
    @Test("Test Symptom Score Calculation")
    func testSymptomScoreCalculation() async throws {
        try await withApp { app in
            let kccq12Service = await KCCQ12Service(phoneNumber: "+16502341234", logger: app.logger, featureFlags: app.featureFlags)
            let score = await kccq12Service.computeSymptomScore()
            
            #expect(score == 50.0, "Score should be 50.0 with mocked responses")
        }
    }
    
    @Test("Test User Feedback Generation")
    func testUserFeedback() async throws {
        try await withApp { app in
            let vitalSignsService = await VitalSignsService(phoneNumber: "+16502341234", logger: app.logger, featureFlags: app.featureFlags)
            let kccq12Service = await KCCQ12Service(phoneNumber: "+16502341234", logger: app.logger, featureFlags: app.featureFlags)
            let q17Service = await Q17Service(phoneNumber: "+16502341234", logger: app.logger, featureFlags: app.featureFlags)
            
            let feedbackService = await FeedbackService(
                phoneNumber: "+16502341234",
                logger: app.logger,
                vitalSignsService: vitalSignsService,
                kccq12Service: kccq12Service,
                q17Service: q17Service
            )
            let feedback = await feedbackService.feedback()
            
            #expect(feedback == """
            Your blood pressure and pulse are normal.
            Your symptom score is 50.0, which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel worse compared to 3 months ago.
            """)
        }
    }
    
    @Test("Test Section Progress Reporting")
    func testSectionProgressReporting() async throws {
        try await withApp { app in
            let vitalSignsService = await VitalSignsService(phoneNumber: "+16502341234", logger: app.logger, featureFlags: app.featureFlags)
            let kccq12Service = await KCCQ12Service(phoneNumber: "+16502341234", logger: app.logger, featureFlags: app.featureFlags)
            let q17Service = await Q17Service(phoneNumber: "+16502341234", logger: app.logger, featureFlags: app.featureFlags)
            
            let serviceState = await ServiceState(services: [vitalSignsService, kccq12Service, q17Service])
            
            // Initialize to find services with unanswered questions
            _ = await serviceState.initializeCurrentService()
            
            // Test initial state (section 1 of total)
            var progress = await serviceState.getSectionProgress()
            #expect(progress.currentSectionNumber == 1, "Should start at section 1")
            #expect(progress.totalSectionCount > 0, "Should have at least 1 total section")
            
            // Test that total remains constant
            let initialTotal = progress.totalSectionCount
            
            // Test after moving to next service
            if await serviceState.hasNext {
                _ = await serviceState.next()
                progress = await serviceState.getSectionProgress()
                #expect(progress.currentSectionNumber == 2, "Should be at section 2 after next()")
                #expect(progress.totalSectionCount == initialTotal, "Total should remain constant")
            }
        }
    }
    
    @Test("Test Dynamic Section Message Generation")
    func testDynamicSectionMessages() async throws {
        try await withApp { app in
            let vitalSignsService = await VitalSignsService(phoneNumber: "+16502341234", logger: app.logger, featureFlags: app.featureFlags)
            let kccq12Service = await KCCQ12Service(phoneNumber: "+16502341234", logger: app.logger, featureFlags: app.featureFlags)
            let q17Service = await Q17Service(phoneNumber: "+16502341234", logger: app.logger, featureFlags: app.featureFlags)
            
            // Test message for section 1 of 3
            let message1 = Constants.getSystemMessageForService(
                vitalSignsService,
                initialQuestion: nil,
                sectionProgress: (currentSectionNumber: 1, totalSectionCount: 3)
            )
            #expect(message1?.contains("Section 1 of 3") ?? false, "Should contain 'Section 1 of 3'")
            
            // Test message for section 2 of 3
            let message2 = Constants.getSystemMessageForService(
                kccq12Service,
                initialQuestion: nil,
                sectionProgress: (currentSectionNumber: 2, totalSectionCount: 3)
            )
            #expect(message2?.contains("Section 2 of 3") ?? false, "Should contain 'Section 2 of 3'")
            
            // Test message for section 3 of 3
            let message3 = Constants.getSystemMessageForService(
                q17Service,
                initialQuestion: nil,
                sectionProgress: (currentSectionNumber: 3, totalSectionCount: 3)
            )
            #expect(message3?.contains("Section 3 of 3") ?? false, "Should contain 'Section 3 of 3'")
            
            // Test with adjusted total (e.g., if first section already complete)
            let message4 = Constants.getSystemMessageForService(
                kccq12Service,
                initialQuestion: nil,
                sectionProgress: (currentSectionNumber: 1, totalSectionCount: 2)
            )
            #expect(message4?.contains("Section 1 of 2") ?? false, "Should contain 'Section 1 of 2' when total is adjusted")
        }
    }
}
