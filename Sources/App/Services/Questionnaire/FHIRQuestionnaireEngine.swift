//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4
import ToonFormat
import Vapor

/// Errors that can occur during questionnaire engine operations.
enum QuestionnaireEngineError: Error, LocalizedError {
    case questionnaireNotFound
    case unsupportedAnswerType
    case cannotSkipRequiredQuestion
    case unknownLinkId(String)
    case valueTooHigh(Int, max: Int)
    case valueTooLow(Int, min: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedAnswerType:
            return "Unsupported answer type."
        case .questionnaireNotFound:
            return "Questions could not be found."
        case .cannotSkipRequiredQuestion:
            return "This question is required and can therefore not be skipped."
        case .unknownLinkId(let linkId):
            return "Encountered unknown linkId: \(linkId)."
        case .valueTooLow(_, let minValue):
            return "Value too low, minValue is \(minValue)."
        case .valueTooHigh(_, let maxValue):
            return "Value too high, maxValue is \(maxValue)."
        }
    }
}

/// Validation errors returned when an answer fails constraint checks.
enum AnswerValidationError: Error, CustomStringConvertible {
    case belowMinimum(Double)
    case aboveMaximum(Double)
    case exceedsMaxLength(Int)

    var description: String {
        switch self {
        case .belowMinimum(let min): return "Value must be at least \(min)"
        case .aboveMaximum(let max): return "Value must be at most \(max)"
        case .exceedsMaxLength(let max): return "Text must be at most \(max) characters"
        }
    }
}

/// A generic FHIR R4 questionnaire engine that manages the state of answering
/// any compliant questionnaire.
///
/// The engine is fully driven by the FHIR Questionnaire definition — it makes no
/// assumptions about specific questions or answer types beyond what the R4 spec provides.
/// It pairs with a `QuestionnaireResponseStore` for persistence and a
/// `QuestionnaireSection` for configuration.
@MainActor
class FHIRQuestionnaireEngine: Sendable {
    // MARK: - Constants

    static let noteExtensionURL = "http://bdh.stanford.edu/fhir/StructureDefinition/note"
    static let minValueURL = "http://hl7.org/fhir/StructureDefinition/minValue"
    static let maxValueURL = "http://hl7.org/fhir/StructureDefinition/maxValue"
    static let unitURL = "http://hl7.org/fhir/StructureDefinition/questionnaire-unit"
    static let hiddenURL = "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden"
    static let itemControlURL =
        "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl"

    // MARK: - Properties

    let store: QuestionnaireResponseStore
    let section: any QuestionnaireSection
    let phoneNumber: String

    let questionnaire: Questionnaire
    var response: QuestionnaireResponse
    var codeMapping: [String: [String: String]] = [:]
    private(set) var isFinished: Bool = false

    // MARK: - Initializer

    init(
        section: any QuestionnaireSection,
        phoneNumber: String,
        logger: Logger,
        featureFlags: FeatureFlags,
        encryptionKey: String? = nil
    ) throws {
        self.section = section
        self.phoneNumber = phoneNumber

        self.store = try QuestionnaireResponseStore(
            resourceName: section.resourceName,
            directoryPath: section.directoryPath,
            featureFlags: featureFlags,
            encryptionKey: encryptionKey
        )

        guard let questionnaire = store.loadQuestionnaire() else {
            throw QuestionnaireEngineError.questionnaireNotFound
        }
        self.questionnaire = questionnaire

        // Flatten the loaded response in case it was saved with hierarchical nesting
        let loaded = store.loadResponse(phoneNumber: phoneNumber, logger: logger)
        if let items = loaded.item {
            loaded.item = Self.flattenResponseItems(items)
        }
        self.response = loaded

        let allItems = Self.flattenItems(questionnaire.item ?? [])
        for item in allItems {
            buildCodeMapping(for: item)
        }
        prePopulateInitialValues()
        updateFinishedState()
    }

    // MARK: - Type Methods

    static func flattenItems(_ items: [QuestionnaireItem]) -> [QuestionnaireItem] {
        items.flatMap { item -> [QuestionnaireItem] in
            if let subItems = item.item, !subItems.isEmpty {
                return flattenItems(subItems)
            } else if item.type.value?.rawValue != "display" && !isHidden(item) {
                return [item]
            }
            return []
        }
    }

    /// Recursively flattens nested QuestionnaireResponseItems into a single-level array.
    static func flattenResponseItems(
        _ items: [QuestionnaireResponseItem]
    ) -> [QuestionnaireResponseItem] {
        items.flatMap { item -> [QuestionnaireResponseItem] in
            if let subItems = item.item, !subItems.isEmpty {
                return flattenResponseItems(subItems)
            } else if item.answer != nil {
                return [item]
            }
            return []
        }
    }

    static func isHidden(_ item: QuestionnaireItem) -> Bool {
        guard let extensions = item.`extension` else {
            return false
        }
        return extensions.contains { ext in
            guard ext.url.value?.url.absoluteString == hiddenURL,
                case .boolean(let val) = ext.value
            else {
                return false
            }
            return val.value?.bool ?? false
        }
    }

    static func extractNote(from extensions: [ModelsR4.Extension]) -> String? {
        extensions
            .first { $0.url.value?.url.absoluteString == noteExtensionURL }
            .flatMap { ext in
                if case .string(let str) = ext.value {
                    return str.value?.string
                }
                return nil
            }
    }

    static func descriptiveCode(from display: String) -> String {
        display.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    // MARK: - Public Interface

    /// Returns the next unanswered question as a JSON string, or nil if finished.
    func nextQuestionJSON(includeAllQuestions: Bool) -> String? {
        guard let payload = nextQuestionPayload(includeAllQuestions: includeAllQuestions) else {
            return nil
        }
        guard let data = try? TOONEncoder().encode(payload),
            let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return json
    }

    /// Record an answer for a given linkId.
    func answerQuestion<T>(linkId: String, answer: T) throws {
        // Validate the answer against questionnaire constraints before saving
        if let validationError = validateAnswer(linkId: linkId, answer: answer) {
            throw validationError
        }

        let responseItem = QuestionnaireResponseItem(
            linkId: FHIRPrimitive(FHIRString(linkId))
        )
        let answerItem = QuestionnaireResponseItemAnswer()

        guard let questionnaireItem = findQuestionnaireItem(linkId: linkId) else {
            throw QuestionnaireEngineError.unknownLinkId(linkId)
        }

        answerItem.value = try extractAnswerItemValue(from: answer, item: questionnaireItem)
        responseItem.answer = [answerItem]

        if let index = response.item?.firstIndex(where: { $0.linkId.value?.string == linkId }) {
            response.item?[index] = responseItem
        } else if response.item != nil {
            response.item?.append(responseItem)
        } else {
            response.item = [responseItem]
        }

        updateFinishedState()
    }

    private func extractAnswerItemValue<T>(from answer: T, item: QuestionnaireItem) throws
        -> QuestionnaireResponseItemAnswer.ValueX? {
        switch answer {
        case let string as String:
            let resolved = resolveAnswer(linkId: item.linkId.value?.string ?? "", answer: string)
            return .string(FHIRPrimitive(FHIRString(resolved)))
        case let integer as Int:
            if let max = maxValue(item: item), integer > max {
                throw QuestionnaireEngineError.valueTooHigh(integer, max: max)
            }
            if let min = minValue(item: item), integer < min {
                throw QuestionnaireEngineError.valueTooLow(integer, min: min)
            }
            return .integer(integer.asFHIRIntegerPrimitive())
        case let double as Double:
            return .decimal(double.asFHIRDecimalPrimitive())
        case let bool as Bool:
            return .boolean(FHIRPrimitive(FHIRBool(bool)))
        case is NSNull:
            if item.required?.value?.bool ?? false {
                throw QuestionnaireEngineError.cannotSkipRequiredQuestion
            }
            return .none
        default:
            throw QuestionnaireEngineError.unsupportedAnswerType
        }
    }

    /// Persist the current response to disk.
    func save(logger: Logger) {
        store.saveResponse(
            phoneNumber: phoneNumber,
            response: hierarchicalResponse(),
            logger: logger
        )
    }

    /// Returns the internal flat response (e.g. for scoring calculations).
    func currentResponse() -> QuestionnaireResponse {
        response
    }

    /// Returns a FHIR-compliant QuestionnaireResponse with hierarchically nested items
    /// matching the questionnaire structure.
    func hierarchicalResponse() -> QuestionnaireResponse {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        guard let data = try? encoder.encode(response),
            let result = try? decoder.decode(QuestionnaireResponse.self, from: data)
        else {
            return response
        }
        let lookup = buildAnswerLookup()
        result.item = buildResponseHierarchy(for: questionnaire.item ?? [], lookup: lookup)
        return result
    }

    /// Number of questions that have been answered.
    func answeredCount() -> Int {
        response.item?.count ?? 0
    }

    /// Whether there are still unanswered questions.
    func hasUnansweredQuestions() -> Bool {
        !isFinished
    }
}

extension FHIRQuestionnaireEngine {
    // MARK: - Question Navigation

    private func nextQuestionPayload(includeAllQuestions: Bool) -> QuestionWithProgress? {
        let items = Self.flattenItems(questionnaire.item ?? [])
        let answeredIds = Set(response.item?.compactMap { $0.linkId.value?.string } ?? [])

        let nextItem =
            items.first { item in
                guard let linkId = item.linkId.value?.string else {
                    return false
                }
                return (item.required?.value?.bool ?? false) && !answeredIds.contains(linkId)
            }
            ?? items.first { item in
                guard let linkId = item.linkId.value?.string else {
                    return false
                }
                return !answeredIds.contains(linkId)
            }

        guard let nextItem else {
            return nil
        }

        let progress = "\(answeredIds.count + 1) of \(items.count)"

        let allQuestions: [SimplifiedQuestion]
        if section.sharesAllQuestions && includeAllQuestions {
            allQuestions =
                items
                .filter { item in
                    guard let linkId = item.linkId.value?.string else {
                        return false
                    }
                    return !answeredIds.contains(linkId)
                }
                .map { simplify($0) }
        } else {
            allQuestions = []
        }

        return QuestionWithProgress(
            question: simplify(nextItem),
            progress: progress,
            allQuestions: allQuestions.isEmpty ? nil : allQuestions
        )
    }

    // MARK: - Code Mapping

    private func buildCodeMapping(for item: QuestionnaireItem) {
        let linkId = item.linkId.value?.string ?? ""
        guard let options = item.answerOption else {
            return
        }

        var mapping: [String: String] = [:]
        for option in options {
            guard case .coding(let coding) = option.value else { continue }
            let original = coding.code?.value?.string ?? ""
            let display = coding.display?.value?.string ?? ""
            mapping[Self.descriptiveCode(from: display)] = original
        }
        if !mapping.isEmpty {
            codeMapping[linkId] = mapping
        }
    }

    private func resolveAnswer(linkId: String, answer: String) -> String {
        codeMapping[linkId]?[answer] ?? answer
    }

    // MARK: - Simplification

    private func simplify(_ item: QuestionnaireItem) -> SimplifiedQuestion {
        let linkId = item.linkId.value?.string ?? ""
        let type = item.type.value?.rawValue ?? ""
        let text = item.text?.value?.string ?? ""
        let required = item.required?.value?.bool ?? false
        let note = Self.extractNote(from: item.`extension` ?? [])

        var answerOptions: [SimplifiedAnswerOption] = []
        if let options = item.answerOption {
            answerOptions = options.compactMap { option -> SimplifiedAnswerOption? in
                guard case .coding(let coding) = option.value else {
                    return nil
                }
                let display = coding.display?.value?.string ?? ""
                let code = Self.descriptiveCode(from: display)
                let optionNote = Self.extractNote(from: option.`extension` ?? [])
                return SimplifiedAnswerOption(code: code, display: display, note: optionNote)
            }
        }

        var minValue: Int?
        var maxValue: Int?
        if type == "integer", let extensions = item.`extension` {
            for ext in extensions {
                let url = ext.url.value?.url.absoluteString ?? ""
                if url == Self.minValueURL, case .integer(let val) = ext.value {
                    minValue = Int(val.value?.integer ?? 0)
                } else if url == Self.maxValueURL, case .integer(let val) = ext.value {
                    maxValue = Int(val.value?.integer ?? 0)
                }
            }
        }

        return SimplifiedQuestion(
            linkId: linkId,
            type: type,
            text: text,
            required: required,
            note: note,
            answerOptions: answerOptions,
            minValue: minValue,
            maxValue: maxValue
        )
    }

    private func minValue(item: QuestionnaireItem) -> Int? {
        item.extensions(for: Self.minValueURL)
            .compactMap { ext in
                if case .integer(let value) = ext.value {
                    return (value.value?.integer).map(Int.init)
                }
                return nil
            }
            .first
    }

    private func maxValue(item: QuestionnaireItem) -> Int? {
        item.extensions(for: Self.maxValueURL)
            .compactMap { ext in
                if case .integer(let value) = ext.value {
                    return (value.value?.integer).map(Int.init)
                }
                return nil
            }
            .first
    }

    private func findQuestionnaireItem(linkId: String) -> QuestionnaireItem? {
        let questions = Self.flattenItems(questionnaire.item ?? [])
        return questions.first { $0.linkId.value?.string == linkId }
    }

    // MARK: - State

    private func updateFinishedState() {
        let items = Self.flattenItems(questionnaire.item ?? [])
        let answeredIds = Set(response.item?.compactMap { $0.linkId.value?.string } ?? [])
        isFinished = items.allSatisfy { item in
            guard let linkId = item.linkId.value?.string else {
                return true
            }
            let isReadOnly = item.readOnly?.value?.bool ?? false
            if !isEnabled(item) || isReadOnly {
                return true
            }
            return !(item.required?.value?.bool ?? false) || answeredIds.contains(linkId)
        }
        response.status = FHIRPrimitive(
            isFinished
                ? QuestionnaireResponseStatus.completed : QuestionnaireResponseStatus.inProgress
        )
    }
}
