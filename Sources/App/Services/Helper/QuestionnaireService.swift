//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4
import Vapor


/// Protocol for questionnaire services.
/// It delegates the management of the questionnaire response to the `QuestionnaireManager` and the persistent storage of the questionnaire response to the `QuestionnaireStorageService`.
@MainActor
protocol QuestionnaireService {
    /// The questionnaire storage service used to save the questionnaire response to a file
    static var storage: QuestionnaireStorageService { get }
    
    /// The questionnaire manager used to manage the questionnaire response
    static var manager: QuestionnaireManager { get }
    
    /// Creates the file to save the questionnaire's response
    /// - Parameters:
    ///   - phoneNumber: The caller's phone number used in the hash of the file name
    ///   - logger: The logger to use for logging
    static func setupFile(phoneNumber: String, logger: Logger)
    
    /// Get the next question from the questionnaire
    /// - Returns: The next question as a JSON string if available, nil if no more questions
    static func getNextQuestion(logger: Logger) async -> String?
    
    /// Save the questionnaire response to the file by delegating to the storage service
    /// - Parameters:
    ///   - phoneNumber: The caller's phone number used in the hash of the file name
    ///   - logger: The logger to use for logging
    /// - Returns: The FHIR `QuestionnaireResponse` object loaded from the JSON file
    static func saveQuestionnaireResponseToFile(phoneNumber: String, logger: Logger) async
    
    /// Save the answer to a question to the questionnaire response managed by the manager
    /// - Parameters:
    ///   - linkId: The question's identifier
    ///   - answer: The answer to the question
    ///   - logger: The logger to use for logging
    /// - Returns: True if the answer was saved successfully, false otherwise
    static func saveQuestionnaireAnswer<T>(linkId: String, answer: T, logger: Logger) -> Bool
    
    /// Count the number of answered questions
    /// - Returns: The number of answered questions
    static func countAnsweredQuestions() -> Int
    
    /// Check if there are any unanswered questions left
    /// - Returns: True if there are any unanswered questions left, false otherwise
    static func unansweredQuestionsLeft() -> Bool
}
