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

@Suite("EnableWhen Tests")
struct EnableWhenTests {
    // MARK: - enableWhen with exists operator

    @Test("enableWhen exists=true shows item only when answer exists")
    @MainActor
    func enableWhenExistsTrue() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let condition = FHIRBuilder.enableWhenExists(question: "systolic", exists: true)

            #expect(!engine.evaluateCondition(condition))

            try engine.answerQuestion(linkId: "systolic", answer: 120)
            #expect(engine.evaluateCondition(condition))
        }
    }

    @Test("enableWhen exists=false shows item only when answer does NOT exist")
    @MainActor
    func enableWhenExistsFalse() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let condition = FHIRBuilder.enableWhenExists(question: "systolic", exists: false)

            #expect(engine.evaluateCondition(condition))

            try engine.answerQuestion(linkId: "systolic", answer: 120)
            #expect(!engine.evaluateCondition(condition))
        }
    }

    // MARK: - Integer comparisons

    @Test("enableWhen integer greater-than comparison")
    @MainActor
    func enableWhenIntegerGreaterThan() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let condition = FHIRBuilder.enableWhen(
                question: "heart-rate", operator: .greaterThan, answerInteger: 100
            )

            #expect(!engine.evaluateCondition(condition))

            try engine.answerQuestion(linkId: "heart-rate", answer: 80)
            #expect(!engine.evaluateCondition(condition))

            try engine.answerQuestion(linkId: "heart-rate", answer: 150)
            #expect(engine.evaluateCondition(condition))
        }
    }

    @Test("enableWhen integer less-than-or-equal comparison")
    @MainActor
    func enableWhenIntegerLessThanOrEqual() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let condition = FHIRBuilder.enableWhen(
                question: "weight", operator: .lessThanOrEqual, answerInteger: 200
            )

            try engine.answerQuestion(linkId: "weight", answer: 200)
            #expect(engine.evaluateCondition(condition))

            try engine.answerQuestion(linkId: "weight", answer: 150)
            #expect(engine.evaluateCondition(condition))

            try engine.answerQuestion(linkId: "weight", answer: 250)
            #expect(!engine.evaluateCondition(condition))
        }
    }

    // MARK: - String/coding comparisons

    @Test("enableWhen coding equality with string response")
    @MainActor
    func enableWhenCodingEqual() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "q17", app: app)

            let condition = FHIRBuilder.enableWhen(
                question: "wellbeing-comparison", operator: .equal, answerCoding: "1"
            )

            try engine.answerQuestion(linkId: "wellbeing-comparison", answer: "much-worse")
            #expect(engine.evaluateCondition(condition))
        }
    }

    @Test("enableWhen coding not-equal")
    @MainActor
    func enableWhenCodingNotEqual() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "q17", app: app)

            let condition = FHIRBuilder.enableWhen(
                question: "wellbeing-comparison", operator: .notEqual, answerCoding: "1"
            )

            try engine.answerQuestion(linkId: "wellbeing-comparison", answer: "much-worse")
            #expect(!engine.evaluateCondition(condition))

            try engine.answerQuestion(
                linkId: "wellbeing-comparison", answer: "slightly-better"
            )
            #expect(engine.evaluateCondition(condition))
        }
    }

    // MARK: - isEnabled with enableBehavior

    @Test("Item with no enableWhen is always enabled")
    @MainActor
    func itemWithoutEnableWhenIsEnabled() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)
            let item = FHIRBuilder.integerItem(linkId: "q1", text: "Question 1")
            #expect(engine.isEnabled(item))
        }
    }

    @Test("enableBehavior .any — enabled when at least one condition met")
    @MainActor
    func enableBehaviorAny() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)
            try engine.answerQuestion(linkId: "systolic", answer: 150)

            let item = FHIRBuilder.integerItem(linkId: "alert", text: "Alert")
            item.enableWhen = [
                FHIRBuilder.enableWhen(
                    question: "systolic", operator: .greaterThan, answerInteger: 140
                ),
                FHIRBuilder.enableWhen(
                    question: "heart-rate", operator: .greaterThan, answerInteger: 100
                )
            ]
            item.enableBehavior = FHIRPrimitive(.any)

            #expect(engine.isEnabled(item))
        }
    }

    @Test("enableBehavior .all — disabled when only one condition met")
    @MainActor
    func enableBehaviorAllPartial() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)
            try engine.answerQuestion(linkId: "systolic", answer: 150)

            let item = FHIRBuilder.integerItem(linkId: "alert", text: "Alert")
            item.enableWhen = [
                FHIRBuilder.enableWhen(
                    question: "systolic", operator: .greaterThan, answerInteger: 140
                ),
                FHIRBuilder.enableWhen(
                    question: "heart-rate", operator: .greaterThan, answerInteger: 100
                )
            ]
            item.enableBehavior = FHIRPrimitive(.all)

            #expect(!engine.isEnabled(item))
        }
    }

    @Test("enableBehavior .all — enabled when all conditions met")
    @MainActor
    func enableBehaviorAllMet() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)
            try engine.answerQuestion(linkId: "systolic", answer: 150)
            try engine.answerQuestion(linkId: "heart-rate", answer: 110)

            let item = FHIRBuilder.integerItem(linkId: "alert", text: "Alert")
            item.enableWhen = [
                FHIRBuilder.enableWhen(
                    question: "systolic", operator: .greaterThan, answerInteger: 140
                ),
                FHIRBuilder.enableWhen(
                    question: "heart-rate", operator: .greaterThan, answerInteger: 100
                )
            ]
            item.enableBehavior = FHIRPrimitive(.all)

            #expect(engine.isEnabled(item))
        }
    }

    @Test("Default enableBehavior (none set) acts as .all")
    @MainActor
    func defaultEnableBehaviorIsAll() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)
            try engine.answerQuestion(linkId: "systolic", answer: 150)

            let item = FHIRBuilder.integerItem(linkId: "alert", text: "Alert")
            item.enableWhen = [
                FHIRBuilder.enableWhen(
                    question: "systolic", operator: .greaterThan, answerInteger: 140
                ),
                FHIRBuilder.enableWhen(
                    question: "heart-rate", operator: .greaterThan, answerInteger: 100
                )
            ]

            #expect(!engine.isEnabled(item))
        }
    }

    // MARK: - Number comparison helper

    @Test("compareNumbers covers all operators")
    @MainActor
    func compareNumbersAllOperators() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            #expect(engine.compareNumbers(5, 5, comparison: .equal))
            #expect(!engine.compareNumbers(5, 6, comparison: .equal))
            #expect(engine.compareNumbers(5, 6, comparison: .notEqual))
            #expect(engine.compareNumbers(6, 5, comparison: .greaterThan))
            #expect(!engine.compareNumbers(5, 5, comparison: .greaterThan))
            #expect(engine.compareNumbers(5, 6, comparison: .lessThan))
            #expect(!engine.compareNumbers(6, 6, comparison: .lessThan))
            #expect(engine.compareNumbers(5, 5, comparison: .greaterThanOrEqual))
            #expect(engine.compareNumbers(6, 5, comparison: .greaterThanOrEqual))
            #expect(engine.compareNumbers(5, 5, comparison: .lessThanOrEqual))
            #expect(engine.compareNumbers(5, 6, comparison: .lessThanOrEqual))
        }
    }

    // MARK: - Hierarchical response building

    @Test("Hierarchical response preserves group structure")
    @MainActor
    func hierarchicalResponseStructure() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            try engine.answerQuestion(linkId: "systolic", answer: 120)
            try engine.answerQuestion(linkId: "diastolic", answer: 80)
            try engine.answerQuestion(linkId: "heart-rate", answer: 65)
            try engine.answerQuestion(linkId: "weight", answer: 180)

            let hierarchical = engine.hierarchicalResponse()
            let topItems = hierarchical.item ?? []

            #expect(topItems.count == 3)

            let group = topItems[0]
            #expect(group.linkId.value?.string == "blood-pressure-group")
            #expect(group.item?.count == 2)

            #expect(topItems[1].linkId.value?.string == "heart-rate")
            #expect(topItems[1].answer?.first != nil)

            #expect(topItems[2].linkId.value?.string == "weight")
        }
    }

    @Test("Flat response has all items at top level")
    @MainActor
    func flatResponseIsFlat() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            try engine.answerQuestion(linkId: "systolic", answer: 120)
            try engine.answerQuestion(linkId: "diastolic", answer: 80)

            let flat = engine.currentResponse()
            let items = flat.item ?? []
            for item in items {
                #expect(item.item == nil || item.item?.isEmpty == true)
            }
        }
    }
}
