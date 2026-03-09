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
    // MARK: - Page Group Detection

    static func isPageGroup(_ item: QuestionnaireItem) -> Bool {
        item.`extension`?.contains { ext in
            guard ext.url.value?.url.absoluteString == itemControlURL,
                case .codeableConcept(let concept) = ext.value
            else {
                return false
            }
            return concept.coding?.contains { $0.code?.value?.string == "page" } ?? false
        } ?? false
    }

    // MARK: - Question Navigation

    func nextQuestionPayload(includeAllQuestions: Bool) -> QuestionWithProgress? {
        let items = Self.flattenItems(questionnaire.item ?? [])
        let answeredIds = Set(response.item?.compactMap { $0.linkId.value?.string } ?? [])

        let enabledItems = items.filter { isEnabled($0) }

        let nextItem =
            enabledItems.first { item in
                guard let linkId = item.linkId.value?.string else {
                    return false
                }
                let isReadOnly = item.readOnly?.value?.bool ?? false
                return !isReadOnly && (item.required?.value?.bool ?? false)
                    && !answeredIds.contains(linkId)
            }
            ?? enabledItems.first { item in
                guard let linkId = item.linkId.value?.string else {
                    return false
                }
                let isReadOnly = item.readOnly?.value?.bool ?? false
                return !isReadOnly && !answeredIds.contains(linkId)
            }

        guard let nextItem else {
            return nil
        }

        let totalEnabled = enabledItems.filter {
            !($0.readOnly?.value?.bool ?? false)
        }.count
        let answeredEnabled = enabledItems.filter {
            guard let lid = $0.linkId.value?.string else {
                return false
            }
            let isReadOnly = $0.readOnly?.value?.bool ?? false
            return !isReadOnly && answeredIds.contains(lid)
        }.count
        let progress = "\(answeredEnabled + 1) of \(totalEnabled)"

        let allQuestions: [SimplifiedQuestion]
        if section.sharesAllQuestions && includeAllQuestions {
            allQuestions = unansweredEnabledItems(
                enabledItems: enabledItems, answeredIds: answeredIds
            ).map { simplify($0) }
        } else if includeAllQuestions {
            allQuestions = currentPageQuestions(
                nextItem: nextItem, enabledItems: enabledItems, answeredIds: answeredIds
            )
        } else {
            allQuestions = []
        }

        return QuestionWithProgress(
            question: simplify(nextItem),
            progress: progress,
            allQuestions: allQuestions.isEmpty ? nil : allQuestions
        )
    }

    func unansweredEnabledItems(
        enabledItems: [QuestionnaireItem],
        answeredIds: Set<String>
    ) -> [QuestionnaireItem] {
        enabledItems.filter { item in
            guard let linkId = item.linkId.value?.string else {
                return false
            }
            let isReadOnly = item.readOnly?.value?.bool ?? false
            return !isReadOnly && !answeredIds.contains(linkId)
        }
    }

    // MARK: - Page-Aware Navigation

    /// Returns all unanswered questions on the same page as `nextItem`, or empty if no page structure.
    func currentPageQuestions(
        nextItem: QuestionnaireItem,
        enabledItems: [QuestionnaireItem],
        answeredIds: Set<String>
    ) -> [SimplifiedQuestion] {
        let nextLinkId = nextItem.linkId.value?.string ?? ""
        guard
            let pageGroup = findPageGroup(
                containing: nextLinkId, in: questionnaire.item ?? []
            )
        else {
            return []
        }

        let pageItemIds = Set(
            Self.flattenItems(pageGroup.item ?? []).compactMap { $0.linkId.value?.string }
        )
        let pageQuestions = enabledItems.filter { item in
            guard let linkId = item.linkId.value?.string else {
                return false
            }
            let isReadOnly = item.readOnly?.value?.bool ?? false
            return !isReadOnly && pageItemIds.contains(linkId) && !answeredIds.contains(linkId)
        }

        return pageQuestions.count > 1 ? pageQuestions.map { simplify($0) } : []
    }

    func findPageGroup(
        containing linkId: String, in items: [QuestionnaireItem]
    ) -> QuestionnaireItem? {
        for item in items {
            if Self.isPageGroup(item) {
                let flatChildren = Self.flattenItems(item.item ?? [])
                if flatChildren.contains(where: { $0.linkId.value?.string == linkId }) {
                    return item
                }
            }
            if let subItems = item.item,
                let found = findPageGroup(containing: linkId, in: subItems) {
                return found
            }
        }
        return nil
    }
}
