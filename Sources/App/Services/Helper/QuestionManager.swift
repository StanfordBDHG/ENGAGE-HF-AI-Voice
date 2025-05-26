//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4
import Vapor


/// Actor to manage concurrent access to questions
@MainActor
class QuestionManager {
    var remainingQuestions: [QuestionnaireItem] = []
    var totalQuestions: Int = 0
    var questionnaireResponseLoader: QuestionnaireResponseLoader
    
    init(questionnaireResponseLoader: QuestionnaireResponseLoader) {
        self.questionnaireResponseLoader = questionnaireResponseLoader
    }
    
    func initializeQuestions(_ questions: [QuestionnaireItem], phoneNumber: String, logger: Logger) async {
        let items = flattenQuestionnaireItems(questions)
        let answeredQuestionLinkIds = await questionnaireResponseLoader
            .loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
            .item?.map { $0.linkId.value?.string } ?? []
        let filteredItems = items.filter { !answeredQuestionLinkIds.contains($0.linkId.value?.string) }
        totalQuestions = items.count
        logger.info("Initializing remaining questions with \(filteredItems.count) questions")
        remainingQuestions = filteredItems
    }
    
    func getNextQuestionAsJSON(logger: Logger) async throws -> String? {
        guard !remainingQuestions.isEmpty else {
            logger.info("No more questions available")
            return nil
        }
        logger.info("remainingQuestions: \(remainingQuestions.count)")
        logger.info("\(remainingQuestions.map { $0.linkId })")
        let nextQuestion = remainingQuestions[0]

        let progressString = "Question \(totalQuestions - remainingQuestions.count + 1) of \(totalQuestions)"

        let questionWithProgress = QuestionWithProgress(question: nextQuestion, progress: progressString)
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(questionWithProgress)
        
        return String(data: jsonData, encoding: .utf8)
    }
    
    func isEmpty() -> Bool {
        remainingQuestions.isEmpty
    }
    
    func removeRemainingQuestion(linkId: String) {
        remainingQuestions.removeAll { $0.linkId.value?.string == linkId }
    }
    
    private func flattenQuestionnaireItems(_ items: [QuestionnaireItem]) -> [QuestionnaireItem] {
        var flattenedItems: [QuestionnaireItem] = []
        
        for item in items {
            if item.type.value == .choice || item.type.value == .integer {
                flattenedItems.append(item)
            }
            
            if let nestedItems = item.item {
                flattenedItems.append(contentsOf: flattenQuestionnaireItems(nestedItems))
            }
        }
        
        return flattenedItems
    }
    
    func setQuestionnaireResponseLoader(_ loader: QuestionnaireResponseLoader) {
        questionnaireResponseLoader = loader
    }
    
    func loadQuestionnaireResponse(_ phoneNumber: String, _ logger: Logger) async -> QuestionnaireResponse {
        await questionnaireResponseLoader.loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
    }
}
