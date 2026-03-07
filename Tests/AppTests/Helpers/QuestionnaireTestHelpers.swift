//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Logging
import ModelsR4
import VaporTesting

@testable import App

// MARK: - Shared Test Utilities

/// Creates and configures a Vapor Application for testing, then tears it down after the closure.
@MainActor
func withTestApp(
    _ test: @MainActor @Sendable (Application) async throws -> Void
) async throws {
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

/// Convenience factory for `FHIRQuestionnaireEngine` in tests.
@MainActor
func makeTestEngine(
    resourceName: String,
    app: Application,
    sharesAllQuestions: Bool = false
) throws -> FHIRQuestionnaireEngine {
    try FHIRQuestionnaireEngine(
        section: TestQuestionnaireSection(
            resourceName: resourceName,
            sharesAllQuestions: sharesAllQuestions
        ),
        phoneNumber: "+10000000000",
        logger: app.logger,
        featureFlags: FeatureFlags(internalTestingMode: true)
    )
}

// MARK: - Test QuestionnaireSection

/// A minimal `QuestionnaireSection` for unit tests that uses a bundled resource by name.
struct TestQuestionnaireSection: QuestionnaireSection {
    let resourceName: String
    let title: String
    let directoryPath: String
    let instructions: String
    let sharesAllQuestions: Bool

    init(
        resourceName: String,
        title: String = "Test Section",
        directoryPath: String = NSTemporaryDirectory() + "test-questionnaires/",
        instructions: String = "Test instructions",
        sharesAllQuestions: Bool = false
    ) {
        self.resourceName = resourceName
        self.title = title
        self.directoryPath = directoryPath
        self.instructions = instructions
        self.sharesAllQuestions = sharesAllQuestions
    }
}

// MARK: - FHIR Builder Helpers

/// Convenience helpers for building FHIR questionnaire structures in tests.
enum FHIRBuilder {
    // FHIR extension URLs (duplicated to avoid @MainActor isolation)
    private static let minValueURL = "http://hl7.org/fhir/StructureDefinition/minValue"
    private static let maxValueURL = "http://hl7.org/fhir/StructureDefinition/maxValue"
    private static let unitURL = "http://hl7.org/fhir/StructureDefinition/questionnaire-unit"
    private static let hiddenURL = "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden"
    private static let itemControlURL =
        "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl"

    /// Create a Questionnaire from a JSON string.
    static func questionnaire(from json: String) throws -> Questionnaire {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(Questionnaire.self, from: data)
    }

    /// Create a minimal integer question item.
    static func integerItem(
        linkId: String,
        text: String,
        required: Bool = true,
        minValue: Int? = nil,
        maxValue: Int? = nil,
        readOnly: Bool = false,
        unit: String? = nil
    ) -> QuestionnaireItem {
        var extensions: [ModelsR4.Extension] = []
        if let minValue {
            extensions.append(
                ModelsR4.Extension(
                    url: FHIRPrimitive(FHIRURI(stringLiteral: minValueURL)),
                    value: .integer(minValue.asFHIRIntegerPrimitive())
                )
            )
        }
        if let maxValue {
            extensions.append(
                ModelsR4.Extension(
                    url: FHIRPrimitive(FHIRURI(stringLiteral: maxValueURL)),
                    value: .integer(maxValue.asFHIRIntegerPrimitive())
                )
            )
        }
        if let unit {
            extensions.append(
                ModelsR4.Extension(
                    url: FHIRPrimitive(FHIRURI(stringLiteral: unitURL)),
                    value: .coding(
                        Coding(
                            code: FHIRPrimitive(FHIRString(unit)),
                            display: FHIRPrimitive(FHIRString(unit))
                        )
                    )
                )
            )
        }
        let item = QuestionnaireItem(
            linkId: FHIRPrimitive(FHIRString(linkId)),
            type: FHIRPrimitive(.integer)
        )
        item.text = FHIRPrimitive(FHIRString(text))
        item.required = FHIRPrimitive(FHIRBool(required))
        item.readOnly = readOnly ? FHIRPrimitive(FHIRBool(true)) : nil
        item.`extension` = extensions.isEmpty ? nil : extensions
        return item
    }

    /// Create a choice question item with coding answer options.
    static func choiceItem(
        linkId: String,
        text: String,
        options: [(code: String, display: String)],
        required: Bool = true
    ) -> QuestionnaireItem {
        let item = QuestionnaireItem(
            linkId: FHIRPrimitive(FHIRString(linkId)),
            type: FHIRPrimitive(.choice)
        )
        item.text = FHIRPrimitive(FHIRString(text))
        item.required = FHIRPrimitive(FHIRBool(required))
        item.answerOption = options.map { option in
            QuestionnaireItemAnswerOption(
                value: .coding(
                    Coding(
                        code: FHIRPrimitive(FHIRString(option.code)),
                        display: FHIRPrimitive(FHIRString(option.display))
                    )
                )
            )
        }
        return item
    }

    /// Create a string question item.
    static func stringItem(
        linkId: String,
        text: String,
        required: Bool = true,
        maxLength: Int? = nil
    ) -> QuestionnaireItem {
        let item = QuestionnaireItem(
            linkId: FHIRPrimitive(FHIRString(linkId)),
            type: FHIRPrimitive(.string)
        )
        item.text = FHIRPrimitive(FHIRString(text))
        item.required = FHIRPrimitive(FHIRBool(required))
        if let maxLength {
            item.maxLength = FHIRPrimitive(FHIRInteger(Int32(maxLength)))
        }
        return item
    }

    /// Create a group item containing sub-items.
    static func groupItem(
        linkId: String,
        text: String,
        items: [QuestionnaireItem]
    ) -> QuestionnaireItem {
        let item = QuestionnaireItem(
            linkId: FHIRPrimitive(FHIRString(linkId)),
            type: FHIRPrimitive(.group)
        )
        item.text = FHIRPrimitive(FHIRString(text))
        item.item = items
        return item
    }

    /// Create a display item (informational, not answerable).
    static func displayItem(linkId: String, text: String) -> QuestionnaireItem {
        let item = QuestionnaireItem(
            linkId: FHIRPrimitive(FHIRString(linkId)),
            type: FHIRPrimitive(.display)
        )
        item.text = FHIRPrimitive(FHIRString(text))
        return item
    }

    /// Create an enableWhen condition for a question item.
    static func enableWhen(
        question: String,
        operator: QuestionnaireItemOperator,
        answerCoding code: String
    ) -> QuestionnaireItemEnableWhen {
        QuestionnaireItemEnableWhen(
            answer: .coding(Coding(code: FHIRPrimitive(FHIRString(code)))),
            operator: FHIRPrimitive(`operator`),
            question: FHIRPrimitive(FHIRString(question))
        )
    }

    /// Create an enableWhen condition with an integer answer.
    static func enableWhen(
        question: String,
        operator: QuestionnaireItemOperator,
        answerInteger value: Int
    ) -> QuestionnaireItemEnableWhen {
        QuestionnaireItemEnableWhen(
            answer: .integer(value.asFHIRIntegerPrimitive()),
            operator: FHIRPrimitive(`operator`),
            question: FHIRPrimitive(FHIRString(question))
        )
    }

    /// Create an enableWhen condition with a boolean exists check.
    static func enableWhenExists(
        question: String,
        exists: Bool
    ) -> QuestionnaireItemEnableWhen {
        QuestionnaireItemEnableWhen(
            answer: .boolean(FHIRPrimitive(FHIRBool(exists))),
            operator: FHIRPrimitive(.exists),
            question: FHIRPrimitive(FHIRString(question))
        )
    }

    /// Create a Questionnaire programmatically.
    static func makeQuestionnaire(items: [QuestionnaireItem]) -> Questionnaire {
        let questionnaire = Questionnaire(status: FHIRPrimitive(.draft))
        questionnaire.item = items
        return questionnaire
    }

    /// Create a QuestionnaireResponse item with a string answer.
    static func responseItem(linkId: String, answerString: String) -> QuestionnaireResponseItem {
        let item = QuestionnaireResponseItem(linkId: FHIRPrimitive(FHIRString(linkId)))
        let answer = QuestionnaireResponseItemAnswer()
        answer.value = .string(FHIRPrimitive(FHIRString(answerString)))
        item.answer = [answer]
        return item
    }

    /// Create a QuestionnaireResponse item with an integer answer.
    static func responseItem(linkId: String, answerInteger: Int) -> QuestionnaireResponseItem {
        let item = QuestionnaireResponseItem(linkId: FHIRPrimitive(FHIRString(linkId)))
        let answer = QuestionnaireResponseItemAnswer()
        answer.value = .integer(answerInteger.asFHIRIntegerPrimitive())
        item.answer = [answer]
        return item
    }

    /// Create a page group with the `questionnaire-itemControl` "page" extension.
    static func pageGroup(
        linkId: String,
        items: [QuestionnaireItem]
    ) -> QuestionnaireItem {
        let item = QuestionnaireItem(
            linkId: FHIRPrimitive(FHIRString(linkId)),
            type: FHIRPrimitive(.group)
        )
        item.item = items
        item.`extension` = [
            ModelsR4.Extension(
                url: FHIRPrimitive(
                    FHIRURI(stringLiteral: itemControlURL)
                ),
                value: .codeableConcept(
                    CodeableConcept(
                        coding: [Coding(code: FHIRPrimitive(FHIRString("page")))]
                    )
                )
            )
        ]
        return item
    }

    /// Add a hidden extension to a questionnaire item.
    static func makeHidden(_ item: QuestionnaireItem) -> QuestionnaireItem {
        var existing = item.`extension` ?? []
        existing.append(
            ModelsR4.Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: hiddenURL)),
                value: .boolean(FHIRPrimitive(FHIRBool(true)))
            )
        )
        item.`extension` = existing
        return item
    }

    /// Add an initial value to a questionnaire item.
    static func withInitialValue(
        _ item: QuestionnaireItem,
        string: String
    ) -> QuestionnaireItem {
        item.initial = [
            QuestionnaireItemInitial(value: .string(FHIRPrimitive(FHIRString(string))))
        ]
        return item
    }

    /// Add an initial value (integer) to a questionnaire item.
    static func withInitialValue(
        _ item: QuestionnaireItem,
        integer: Int
    ) -> QuestionnaireItem {
        item.initial = [
            QuestionnaireItemInitial(value: .integer(integer.asFHIRIntegerPrimitive()))
        ]
        return item
    }
}
