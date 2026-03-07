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

@Suite("Navigation Tests")
struct NavigationTests {
    // MARK: - Basic question progression

    @Test("Next question returns first unanswered required question")
    @MainActor
    func nextQuestionReturnsFirstUnanswered() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let payload = engine.nextQuestionPayload(includeAllQuestions: false)
            #expect(payload != nil)
            #expect(payload?.question.linkId == "systolic")
            #expect(payload?.progress == "1 of 4")
        }
    }

    @Test("Progress increments as questions are answered")
    @MainActor
    func progressIncrements() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            try engine.answerQuestion(linkId: "systolic", answer: 120)
            let payload = engine.nextQuestionPayload(includeAllQuestions: false)
            #expect(payload?.progress == "2 of 4")

            try engine.answerQuestion(linkId: "diastolic", answer: 80)
            let payload2 = engine.nextQuestionPayload(includeAllQuestions: false)
            #expect(payload2?.progress == "3 of 4")
        }
    }

    @Test("Returns nil when all questions answered")
    @MainActor
    func returnsNilWhenComplete() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            try engine.answerQuestion(linkId: "systolic", answer: 120)
            try engine.answerQuestion(linkId: "diastolic", answer: 80)
            try engine.answerQuestion(linkId: "heart-rate", answer: 65)
            try engine.answerQuestion(linkId: "weight", answer: 180)

            let payload = engine.nextQuestionPayload(includeAllQuestions: false)
            #expect(payload == nil)
            #expect(engine.isFinished)
        }
    }

    // MARK: - String output

    @Test("nextQuestionString returns non-nil encoded string")
    @MainActor
    func nextQuestionStringReturnsString() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let output = engine.nextQuestionString(includeAllQuestions: false)
            #expect(output != nil)
            #expect(output?.contains("progress") ?? false)
            #expect(output?.contains("1 of 4") ?? false)
        }
    }

    @Test("nextQuestionString includes allQuestions when sharesAllQuestions is true")
    @MainActor
    func allQuestionsShared() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(
                resourceName: "vitalSigns", app: app, sharesAllQuestions: true
            )

            let output = engine.nextQuestionString(includeAllQuestions: true)
            #expect(output != nil)
            #expect(output?.contains("allQuestions") ?? false)
        }
    }

    // MARK: - Display items are skipped

    @Test("Display items are not included as answerable questions")
    @MainActor
    func displayItemsSkipped() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let items = FHIRQuestionnaireEngine.flattenItems(engine.questionnaire.item ?? [])
            for item in items {
                #expect(item.type.value?.rawValue != "display")
            }
        }
    }

    // MARK: - Hidden items are skipped

    @Test("Hidden items are excluded from flattened list")
    @MainActor
    func hiddenItemsSkipped() async throws {
        let hidden = FHIRBuilder.makeHidden(
            FHIRBuilder.integerItem(linkId: "hidden-q", text: "Hidden question")
        )
        let visible = FHIRBuilder.integerItem(linkId: "visible-q", text: "Visible question")

        let flattened = FHIRQuestionnaireEngine.flattenItems([hidden, visible])
        #expect(flattened.count == 1)
        #expect(flattened[0].linkId.value?.string == "visible-q")
    }

    // MARK: - Page group detection

    @Test("isPageGroup correctly identifies page groups")
    @MainActor
    func pageGroupDetection() async throws {
        let page = FHIRBuilder.pageGroup(
            linkId: "page1",
            items: [
                FHIRBuilder.integerItem(linkId: "q1", text: "Question 1")
            ]
        )
        let notPage = FHIRBuilder.groupItem(
            linkId: "group1",
            text: "Regular Group",
            items: [
                FHIRBuilder.integerItem(linkId: "q2", text: "Question 2")
            ]
        )

        #expect(FHIRQuestionnaireEngine.isPageGroup(page))
        #expect(!FHIRQuestionnaireEngine.isPageGroup(notPage))
    }

    // MARK: - Overwriting answers

    @Test("Answering same linkId overwrites previous answer")
    @MainActor
    func overwriteAnswer() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            try engine.answerQuestion(linkId: "systolic", answer: 120)
            try engine.answerQuestion(linkId: "systolic", answer: 130)

            let items = engine.currentResponse().item ?? []
            let systolicItems = items.filter { $0.linkId.value?.string == "systolic" }
            #expect(systolicItems.count == 1)

            let value = systolicItems[0].answer?.first?.integerAnswerValue()
            #expect(value == 130)
        }
    }

    // MARK: - answeredCount

    @Test("answeredCount tracks number of answered questions")
    @MainActor
    func answeredCountTracking() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            #expect(engine.answeredCount() == 0)

            try engine.answerQuestion(linkId: "systolic", answer: 120)
            #expect(engine.answeredCount() == 1)

            try engine.answerQuestion(linkId: "diastolic", answer: 80)
            #expect(engine.answeredCount() == 2)
        }
    }
}
