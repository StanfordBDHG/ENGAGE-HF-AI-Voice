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

@Suite("Simplification Tests")
struct SimplificationTests {
    // MARK: - Integer question simplification

    @Test("Simplify integer item extracts min/max values")
    @MainActor
    func simplifyIntegerItem() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            // systolic has min=70, max=250
            let items = FHIRQuestionnaireEngine.flattenItems(engine.questionnaire.item ?? [])
            let systolic = items.first { $0.linkId.value?.string == "systolic" }
            #expect(systolic != nil)

            // swiftlint:disable:next force_unwrapping
            let simplified = engine.simplify(systolic!)

            #expect(simplified.linkId == "systolic")
            #expect(simplified.type == "integer")
            #expect(simplified.required)
            #expect(simplified.minValue == 70)
            #expect(simplified.maxValue == 250)
        }
    }

    // MARK: - Choice question simplification

    @Test("Simplify choice item extracts answer options")
    @MainActor
    func simplifyChoiceItem() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "q17", app: app)

            let items = FHIRQuestionnaireEngine.flattenItems(engine.questionnaire.item ?? [])
            let question = items.first { $0.linkId.value?.string == "wellbeing-comparison" }
            #expect(question != nil)
            // swiftlint:disable:next force_unwrapping
            let simplified = engine.simplify(question!)

            #expect(simplified.type == "choice")
            #expect(simplified.answerOptions.count == 5)
            #expect(simplified.answerOptions[0].display == "Much worse")
            #expect(simplified.answerOptions[0].code == "much-worse")
            #expect(simplified.answerOptions[4].display == "Much better")
        }
    }

    // MARK: - Extract bounds helper

    @Test("extractBounds returns nil when no extensions present")
    @MainActor
    func extractBoundsNil() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "q17", app: app)

            let item = FHIRBuilder.choiceItem(
                linkId: "test", text: "Test", options: [("a", "A")]
            )
            let bounds = engine.extractBounds(from: item)
            #expect(bounds.min == nil)
            #expect(bounds.max == nil)
        }
    }

    @Test("extractBounds reads integer min/max extensions")
    @MainActor
    func extractBoundsInteger() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let item = FHIRBuilder.integerItem(
                linkId: "test", text: "Test", minValue: 10, maxValue: 100
            )
            let bounds = engine.extractBounds(from: item)
            #expect(bounds.min == 10)
            #expect(bounds.max == 100)
        }
    }

    // MARK: - Extract unit helper

    @Test("extractUnit returns unit string from extension")
    @MainActor
    func extractUnit() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let item = FHIRBuilder.integerItem(
                linkId: "test", text: "Test", unit: "mmHg"
            )
            let unit = engine.extractUnit(from: item)
            #expect(unit == "mmHg")
        }
    }

    @Test("extractUnit returns nil when no unit extension")
    @MainActor
    func extractUnitNil() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let item = FHIRBuilder.integerItem(linkId: "test", text: "Test")
            let unit = engine.extractUnit(from: item)
            #expect(unit == nil)
        }
    }

    // MARK: - Extract answer options helper

    @Test("extractAnswerOptions handles coding options")
    @MainActor
    func extractCodingOptions() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "q17", app: app)

            let item = FHIRBuilder.choiceItem(
                linkId: "test",
                text: "Test",
                options: [("1", "Option A"), ("2", "Option B")]
            )
            let options = engine.extractAnswerOptions(from: item)
            #expect(options.count == 2)
            #expect(options[0].display == "Option A")
            #expect(options[0].code == "option-a")
            #expect(options[1].display == "Option B")
        }
    }

    @Test("extractAnswerOptions returns empty for integer items")
    @MainActor
    func extractOptionsEmpty() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let item = FHIRBuilder.integerItem(linkId: "test", text: "Test")
            let options = engine.extractAnswerOptions(from: item)
            #expect(options.isEmpty)
        }
    }

    // MARK: - Descriptive code generation

    @Test("descriptiveCode creates hyphen-separated lowercase codes")
    @MainActor
    func descriptiveCode() {
        #expect(FHIRQuestionnaireEngine.descriptiveCode(from: "Much worse") == "much-worse")
        #expect(
            FHIRQuestionnaireEngine.descriptiveCode(from: "Slightly Better") == "slightly-better"
        )
        #expect(FHIRQuestionnaireEngine.descriptiveCode(from: "A & B") == "a-b")
        #expect(FHIRQuestionnaireEngine.descriptiveCode(from: "  spaces  ") == "spaces")
    }

    // MARK: - Initial value conversion

    @Test("initialValueString handles string, integer, boolean, coding")
    @MainActor
    func initialValueConversions() {
        let stringInitial = QuestionnaireItemInitial(
            value: .string(FHIRPrimitive(FHIRString("hello")))
        )
        #expect(FHIRQuestionnaireEngine.initialValueString(stringInitial) == "hello")

        let intInitial = QuestionnaireItemInitial(
            value: .integer(42.asFHIRIntegerPrimitive())
        )
        #expect(FHIRQuestionnaireEngine.initialValueString(intInitial) == "42")

        let boolInitial = QuestionnaireItemInitial(
            value: .boolean(FHIRPrimitive(FHIRBool(true)))
        )
        #expect(FHIRQuestionnaireEngine.initialValueString(boolInitial) == "true")

        let codingInitial = QuestionnaireItemInitial(
            value: .coding(Coding(code: FHIRPrimitive(FHIRString("abc"))))
        )
        #expect(FHIRQuestionnaireEngine.initialValueString(codingInitial) == "abc")
    }

    // MARK: - ReadOnly field

    @Test("Simplify readOnly item sets readOnly flag")
    @MainActor
    func simplifyReadOnly() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let readOnlyItem = FHIRBuilder.integerItem(
                linkId: "ro-test", text: "Read only", readOnly: true
            )
            let simplified = engine.simplify(readOnlyItem)
            #expect(simplified.readOnly)

            let editableItem = FHIRBuilder.integerItem(
                linkId: "edit-test", text: "Editable"
            )
            let editableSimplified = engine.simplify(editableItem)
            #expect(!editableSimplified.readOnly)
        }
    }

    // MARK: - MaxLength field

    @Test("Simplify string item with maxLength")
    @MainActor
    func simplifyMaxLength() async throws {
        try await withTestApp { app in
            let engine = try makeTestEngine(resourceName: "vitalSigns", app: app)

            let item = FHIRBuilder.stringItem(
                linkId: "comment", text: "Comment", maxLength: 200
            )
            let simplified = engine.simplify(item)
            #expect(simplified.maxLength == 200)
            #expect(simplified.type == "string")
        }
    }
}
