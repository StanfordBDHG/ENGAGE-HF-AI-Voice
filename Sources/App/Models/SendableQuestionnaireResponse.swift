//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor
import ModelsR4

/// A thread-safe wrapper for QuestionnaireResponse that ensures safe concurrent access
actor SendableQuestionnaireResponse {
    private var response: QuestionnaireResponse
    private let filePath: String
    private let logger: Logger
    
    init(response: QuestionnaireResponse, filePath: String, logger: Logger) {
        self.response = response
        self.filePath = filePath
        self.logger = logger
    }
    
    /// Get the current response
    func getResponse() -> QuestionnaireResponse {
        response
    }
    
    /// Update an answer for a specific question
    func updateAnswer<T>(linkId: String, answer: T) async throws {
        // Create or update the answer for the given linkId
        let responseItem = QuestionnaireResponseItem(linkId: FHIRPrimitive(FHIRString(linkId)))
        let answerItem = QuestionnaireResponseItemAnswer()
        
        // Set the value based on the generic type
        switch answer {
        case let stringAnswer as String:
            answerItem.value = .string(FHIRPrimitive(FHIRString(stringAnswer)))
        case let intAnswer as Int:
            answerItem.value = .integer(FHIRPrimitive(FHIRInteger(FHIRInteger.IntegerLiteralType(intAnswer))))
        default:
            throw QuestionnaireError.unsupportedAnswerType
        }
        
        responseItem.answer = [answerItem]
        
        if let index = response.item?.firstIndex(where: { $0.linkId.value?.string == linkId }) {
            response.item?[index] = responseItem
            logger.info("Updated existing response for linkId: \(linkId)")
        } else {
            if response.item != nil {
                response.item?.append(responseItem)
            } else {
                response.item = [responseItem]
            }
            logger.info("Added new response for linkId: \(linkId)")
        }
        
        // Save to file
        try await saveToFile()
    }
    
    /// Save the current response to file
    private func saveToFile() async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let jsonData = try encoder.encode(response)
        try jsonData.write(to: URL(fileURLWithPath: filePath))
    }
    
    /// Count the number of answered questions
    func countAnsweredQuestions() -> Int {
        response.item?.count ?? 0
    }
    
    /// Get the next unanswered question from a list of questions
    func getNextQuestion(from questions: [QuestionnaireItem]) -> QuestionnaireItem? {
        let answeredLinkIds = response.item?.map { $0.linkId.value?.string } ?? []
        return questions.first { !answeredLinkIds.contains($0.linkId.value?.string) }
    }
}

/// Errors that can occur when working with questionnaire responses
enum QuestionnaireError: Error {
    case unsupportedAnswerType
}
