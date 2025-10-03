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


/// Errors that can occur during questionnaire management
enum QuestionnaireManagerError: Error {
    case unsupportedAnswerType
}

/// A generalized questionnaire manager that handles the state and progression of answering a questionnaire.
/// It maintains an internal FHIR questionnaire response that is populated as answers are provided.
@MainActor
class QuestionnaireManager: Sendable {
    /// The questionnaire being managed
    private let questionnaire: Questionnaire
    
    /// The current questionnaire response being built
    private var response: QuestionnaireResponse
    
    /// Whether all required questions have been answered
    private(set) var isFinished: Bool = false
    
    /// Initialize a new questionnaire manager
    /// - Parameters:
    ///   - questionnaire: The FHIR questionnaire to manage
    ///   - initialResponse: Optional initial response to start from
    init(questionnaire: Questionnaire?, initialResponse: QuestionnaireResponse? = nil) {
        guard let questionnaire else {
            fatalError("QuestionnaireManager initialized with nil questionnaire")
        }
        self.questionnaire = questionnaire
        
        if let initialResponse = initialResponse {
            self.response = initialResponse
        } else {
            self.response = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.inProgress))
        }
        
        updateFinishedState()
    }
    
    /// Get the next unanswered question
    /// - Returns: The next question to be answered in JSON string format, or nil if all required questions are answered
    func getNextQuestionString() -> String? {
        let nextQuestion = getNextQuestion()
        guard let nextQuestion else {
            return nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(nextQuestion), let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return nil
    }
    
    private func getNextQuestion() -> QuestionWithProgress? {
        let questions = getAllQuestions(from: questionnaire.item ?? [])
        
        let answeredLinkIds = Set(response.item?.compactMap { $0.linkId.value?.string } ?? [])
        
        // Find first required question that hasn't been answered
        let nextQuestion = questions.first { question in
            guard let linkId = question.linkId.value?.string else {
                return false
            }
            return question.required?.value?.bool ?? false && !answeredLinkIds.contains(linkId)
        } ?? questions.first { question in
            // If no required questions left, return first unanswered optional question
            guard let linkId = question.linkId.value?.string else {
                return false
            }
            return !answeredLinkIds.contains(linkId)
        }
        
        guard let nextQuestion = nextQuestion else {
            return nil
        }
        
        // Calculate progress
        let totalQuestions = questions.count
        let answeredCount = answeredLinkIds.count
        let progress = "\(answeredCount + 1) of \(totalQuestions)"
        
        // Include all questions on the first question only
        let allQuestions = answeredCount == 0 ? questions : nil
        
        return QuestionWithProgress(question: nextQuestion, progress: progress, allQuestions: allQuestions)
    }
    
    /// Answer a question in the questionnaire
    /// - Parameters:
    ///   - linkId: The linkId of the question being answered
    ///   - answer: The answer value (String or Int)
    /// - Throws: QuestionnaireManagerError if answer type is unsupported
    func answerQuestion<T>(linkId: String, answer: T) throws {
        // Create response item
        let responseItem = QuestionnaireResponseItem(linkId: FHIRPrimitive(FHIRString(linkId)))
        let answerItem = QuestionnaireResponseItemAnswer()
        
        // Set value based on type
        switch answer {
        case let stringAnswer as String:
            answerItem.value = .string(FHIRPrimitive(FHIRString(stringAnswer)))
        case let intAnswer as Int:
            answerItem.value = .integer(FHIRPrimitive(FHIRInteger(FHIRInteger.IntegerLiteralType(intAnswer))))
        case _ as NSNull:
            answerItem.value = .none
        default:
            throw QuestionnaireManagerError.unsupportedAnswerType
        }
        
        responseItem.answer = [answerItem]
        
        // Update or add the answer
        if let index = response.item?.firstIndex(where: { $0.linkId.value?.string == linkId }) {
            response.item?[index] = responseItem
        } else {
            if response.item != nil {
                response.item?.append(responseItem)
            } else {
                response.item = [responseItem]
            }
        }
        
        updateFinishedState()
    }
    
    /// Get the current questionnaire response
    /// - Returns: The current FHIR QuestionnaireResponse
    func getCurrentResponse() -> QuestionnaireResponse {
        response
    }
    
    /// Count the number of answered questions
    /// - Returns: The number of answered questions
    func countAnsweredQuestions() -> Int {
        response.item?.count ?? 0
    }
    
    // MARK: - Private Helpers
    
    /// Recursively get all questions from a questionnaire
    private func getAllQuestions(from items: [QuestionnaireItem]) -> [QuestionnaireItem] {
        items.flatMap { item -> [QuestionnaireItem] in
            if let subItems = item.item {
                return getAllQuestions(from: subItems)
            } else if item.type.value?.rawValue != "display" {
                return [item]
            }
            return []
        }
    }
    
    /// Update the finished state based on required questions
    private func updateFinishedState() {
        let questions = getAllQuestions(from: questionnaire.item ?? [])
        let answeredLinkIds = Set(response.item?.compactMap { $0.linkId.value?.string } ?? [])
        
        // Check if all required questions are answered
        isFinished = questions.allSatisfy { question in
            guard let linkId = question.linkId.value?.string else {
                return true
            }
            return !(question.required?.value?.bool ?? false) || answeredLinkIds.contains(linkId)
        }
        
        response.status = FHIRPrimitive(isFinished ? QuestionnaireResponseStatus.completed : QuestionnaireResponseStatus.inProgress)
    }
}
