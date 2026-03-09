//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4

extension FHIRQuestionnaireEngine {
    // MARK: - Initial Value Conversion

    static func initialValueString(_ initial: QuestionnaireItemInitial) -> String? {
        switch initial.value {
        case .string(let val):
            return val.value?.string
        case .integer(let val):
            return val.value.map { String($0.integer) }
        case .decimal(let val):
            return val.value.map { NSDecimalNumber(decimal: $0.decimal).stringValue }
        case .boolean(let val):
            return val.value.map { String($0.bool) }
        case .coding(let coding):
            return coding.code?.value?.string
        default:
            return nil
        }
    }

    // MARK: - Simplification

    func simplify(_ item: QuestionnaireItem) -> SimplifiedQuestion {
        let linkId = item.linkId.value?.string ?? ""
        let type = item.type.value?.rawValue ?? ""
        let text = item.text?.value?.string ?? ""
        let required = item.required?.value?.bool ?? false
        let readOnly = item.readOnly?.value?.bool ?? false
        let note = Self.extractNote(from: item.`extension` ?? [])
        let maxLength: Int? = item.maxLength?.value.map { Int($0.integer) }
        let isOpenChoice = type == "open-choice"
        let initialValue: String? = item.initial?.first.flatMap { Self.initialValueString($0) }
        let answerOptions = extractAnswerOptions(from: item)
        let bounds = extractBounds(from: item)

        return SimplifiedQuestion(
            linkId: linkId,
            type: isOpenChoice ? "open-choice" : type,
            text: text,
            required: required,
            note: note,
            answerOptions: answerOptions,
            minValue: bounds.min,
            maxValue: bounds.max,
            allowsOtherText: isOpenChoice,
            readOnly: readOnly,
            initialValue: initialValue,
            maxLength: maxLength,
            unit: extractUnit(from: item)
        )
    }

    func extractAnswerOptions(from item: QuestionnaireItem) -> [SimplifiedAnswerOption] {
        guard let options = item.answerOption else {
            return []
        }
        return options.compactMap { option -> SimplifiedAnswerOption? in
            if case .coding(let coding) = option.value {
                let display = coding.display?.value?.string ?? ""
                let code = Self.descriptiveCode(from: display)
                let optionNote = Self.extractNote(from: option.`extension` ?? [])
                return SimplifiedAnswerOption(code: code, display: display, note: optionNote)
            } else if case .integer(let intVal) = option.value {
                let display = String(intVal.value?.integer ?? 0)
                return SimplifiedAnswerOption(code: display, display: display, note: nil)
            } else if case .string(let strVal) = option.value {
                let display = strVal.value?.string ?? ""
                let code = Self.descriptiveCode(from: display)
                return SimplifiedAnswerOption(code: code, display: display, note: nil)
            }
            return nil
        }
    }

    func extractBounds(from item: QuestionnaireItem) -> (min: Double?, max: Double?) {
        var minValue: Double?
        var maxValue: Double?
        guard let extensions = item.`extension` else {
            return (nil, nil)
        }
        for ext in extensions {
            let url = ext.url.value?.url.absoluteString ?? ""
            if url == Self.minValueURL {
                if case .integer(let val) = ext.value {
                    minValue = Double(val.value?.integer ?? 0)
                } else if case .decimal(let val) = ext.value {
                    minValue = NSDecimalNumber(decimal: val.value?.decimal ?? 0).doubleValue
                }
            } else if url == Self.maxValueURL {
                if case .integer(let val) = ext.value {
                    maxValue = Double(val.value?.integer ?? 0)
                } else if case .decimal(let val) = ext.value {
                    maxValue = NSDecimalNumber(decimal: val.value?.decimal ?? 0).doubleValue
                }
            }
        }
        return (minValue, maxValue)
    }

    func extractUnit(from item: QuestionnaireItem) -> String? {
        item.`extension`?.compactMap { ext -> String? in
            guard ext.url.value?.url.absoluteString == Self.unitURL,
                case .coding(let coding) = ext.value
            else {
                return nil
            }
            return coding.display?.value?.string ?? coding.code?.value?.string
        }.first
    }

    // MARK: - Validation

    /// Validates an answer against the questionnaire item's constraints.
    func validateAnswer<T>(linkId: String, answer: T) -> AnswerValidationError? {
        let items = Self.flattenItems(questionnaire.item ?? [])
        guard let item = items.first(where: { $0.linkId.value?.string == linkId }) else {
            return nil
        }
        let simplified = simplify(item)

        if let numericValue = (answer as? Int).map({ Double($0) }) ?? (answer as? Double) {
            if let min = simplified.minValue, numericValue < min {
                return .belowMinimum(min)
            }
            if let max = simplified.maxValue, numericValue > max {
                return .aboveMaximum(max)
            }
        }

        if let stringValue = answer as? String, let maxLen = simplified.maxLength {
            if stringValue.count > maxLen {
                return .exceedsMaxLength(maxLen)
            }
        }

        return nil
    }
}
