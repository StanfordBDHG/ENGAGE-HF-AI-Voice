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
    // MARK: - enableWhen Evaluation

    /// Evaluates whether a questionnaire item is currently enabled based on its enableWhen conditions.
    func isEnabled(_ item: QuestionnaireItem) -> Bool {
        guard let enableWhens = item.enableWhen, !enableWhens.isEmpty else {
            return true
        }
        let behavior = item.enableBehavior?.value
        if behavior == .any {
            return enableWhens.contains { evaluateCondition($0) }
        } else {
            return enableWhens.allSatisfy { evaluateCondition($0) }
        }
    }

    func evaluateCondition(_ condition: QuestionnaireItemEnableWhen) -> Bool {
        let questionLinkId = condition.question.value?.string ?? ""
        let comparison = condition.`operator`.value ?? .equal

        let answeredItem = response.item?.first { $0.linkId.value?.string == questionLinkId }

        if comparison == .exists {
            if case .boolean(let expected) = condition.answer {
                let exists = answeredItem?.answer?.first?.value != nil
                return exists == (expected.value?.bool ?? true)
            }
            return answeredItem != nil
        }

        guard let responseAnswer = answeredItem?.answer?.first else {
            return false
        }

        return compareAnswerValues(
            responseAnswer: responseAnswer,
            conditionAnswer: condition.answer,
            comparison: comparison
        )
    }

    func compareAnswerValues(
        responseAnswer: QuestionnaireResponseItemAnswer,
        conditionAnswer: QuestionnaireItemEnableWhen.AnswerX,
        comparison: QuestionnaireItemOperator
    ) -> Bool {
        switch conditionAnswer {
        case .coding(let coding):
            return compareCodingAnswer(responseAnswer, expected: coding, comparison: comparison)
        case .integer(let integer):
            return compareIntegerAnswer(responseAnswer, expected: integer, comparison: comparison)
        case .decimal(let decimal):
            return compareDecimalAnswer(responseAnswer, expected: decimal, comparison: comparison)
        case .boolean(let boolean):
            return compareBooleanAnswer(responseAnswer, expected: boolean, comparison: comparison)
        case .string(let string):
            return compareStringAnswer(responseAnswer, expected: string, comparison: comparison)
        default:
            return true
        }
    }

    // MARK: - Type-Specific Comparisons

    func compareCodingAnswer(
        _ responseAnswer: QuestionnaireResponseItemAnswer,
        expected: Coding,
        comparison: QuestionnaireItemOperator
    ) -> Bool {
        let conditionCode = expected.code?.value?.string ?? ""
        guard let responseValue = responseAnswer.value else {
            return false
        }
        switch responseValue {
        case .string(let str):
            return compareStrings(str.value?.string ?? "", conditionCode, comparison: comparison)
        case .coding(let coding):
            return compareStrings(
                coding.code?.value?.string ?? "", conditionCode, comparison: comparison
            )
        default:
            return false
        }
    }

    func compareIntegerAnswer(
        _ responseAnswer: QuestionnaireResponseItemAnswer,
        expected: FHIRPrimitive<FHIRInteger>,
        comparison: QuestionnaireItemOperator
    ) -> Bool {
        guard let responseInt = responseAnswer.integerAnswerValue() else {
            return false
        }
        return compareNumbers(
            Double(responseInt), Double(expected.value?.integer ?? 0), comparison: comparison
        )
    }

    func compareDecimalAnswer(
        _ responseAnswer: QuestionnaireResponseItemAnswer,
        expected: FHIRPrimitive<FHIRDecimal>,
        comparison: QuestionnaireItemOperator
    ) -> Bool {
        guard let responseValue = responseAnswer.value,
            case .decimal(let responseDecimal) = responseValue
        else {
            return false
        }
        let lhs = NSDecimalNumber(decimal: responseDecimal.value?.decimal ?? 0).doubleValue
        let rhs = NSDecimalNumber(decimal: expected.value?.decimal ?? 0).doubleValue
        return compareNumbers(lhs, rhs, comparison: comparison)
    }

    func compareBooleanAnswer(
        _ responseAnswer: QuestionnaireResponseItemAnswer,
        expected: FHIRPrimitive<FHIRBool>,
        comparison: QuestionnaireItemOperator
    ) -> Bool {
        guard let responseValue = responseAnswer.value,
            case .boolean(let responseBool) = responseValue
        else {
            return false
        }
        let lhs = responseBool.value?.bool ?? false
        let rhs = expected.value?.bool ?? false
        return comparison == .equal ? lhs == rhs : lhs != rhs
    }

    func compareStringAnswer(
        _ responseAnswer: QuestionnaireResponseItemAnswer,
        expected: FHIRPrimitive<FHIRString>,
        comparison: QuestionnaireItemOperator
    ) -> Bool {
        guard let responseValue = responseAnswer.value,
            case .string(let responseStr) = responseValue
        else {
            return false
        }
        return compareStrings(
            responseStr.value?.string ?? "", expected.value?.string ?? "", comparison: comparison
        )
    }

    func compareStrings(
        _ lhs: String, _ rhs: String, comparison: QuestionnaireItemOperator
    ) -> Bool {
        switch comparison {
        case .equal: return lhs == rhs
        case .notEqual: return lhs != rhs
        default: return lhs == rhs
        }
    }

    func compareNumbers(
        _ lhs: Double, _ rhs: Double, comparison: QuestionnaireItemOperator
    ) -> Bool {
        switch comparison {
        case .equal: return lhs == rhs
        case .notEqual: return lhs != rhs
        case .greaterThan: return lhs > rhs
        case .lessThan: return lhs < rhs
        case .greaterThanOrEqual: return lhs >= rhs
        case .lessThanOrEqual: return lhs <= rhs
        default: return false
        }
    }

    // MARK: - Initial Values

    /// Pre-populates the response with initial values defined in the questionnaire.
    func prePopulateInitialValues() {
        let allItems = Self.flattenItems(questionnaire.item ?? [])
        for item in allItems {
            guard let linkId = item.linkId.value?.string,
                let initialValues = item.initial,
                let first = initialValues.first
            else {
                continue
            }
            if response.item?.contains(where: { $0.linkId.value?.string == linkId }) == true {
                continue
            }
            let responseItem = QuestionnaireResponseItem(linkId: FHIRPrimitive(FHIRString(linkId)))
            let answerItem = QuestionnaireResponseItemAnswer()

            switch first.value {
            case .string(let val): answerItem.value = .string(val)
            case .integer(let val): answerItem.value = .integer(val)
            case .decimal(let val): answerItem.value = .decimal(val)
            case .boolean(let val): answerItem.value = .boolean(val)
            default: continue
            }

            responseItem.answer = [answerItem]
            if response.item != nil {
                response.item?.append(responseItem)
            } else {
                response.item = [responseItem]
            }
        }
    }

    // MARK: - Hierarchical Response

    func buildAnswerLookup() -> [String: QuestionnaireResponseItem] {
        var lookup: [String: QuestionnaireResponseItem] = [:]
        for item in response.item ?? [] {
            if let linkId = item.linkId.value?.string {
                lookup[linkId] = item
            }
        }
        return lookup
    }

    func buildResponseHierarchy(
        for items: [QuestionnaireItem],
        lookup: [String: QuestionnaireResponseItem]
    ) -> [QuestionnaireResponseItem] {
        var result: [QuestionnaireResponseItem] = []
        for item in items {
            let linkId = item.linkId.value?.string ?? ""
            let type = item.type.value?.rawValue ?? ""

            if type == "display" { continue }

            if let subItems = item.item, !subItems.isEmpty {
                let children = buildResponseHierarchy(for: subItems, lookup: lookup)
                if !children.isEmpty {
                    let groupItem = QuestionnaireResponseItem(
                        linkId: FHIRPrimitive(FHIRString(linkId))
                    )
                    groupItem.item = children
                    result.append(groupItem)
                }
            } else if let answerItem = lookup[linkId] {
                result.append(answerItem)
            }
        }
        return result
    }
}
