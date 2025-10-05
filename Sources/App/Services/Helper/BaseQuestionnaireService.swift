//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Vapor


@MainActor
class BaseQuestionnaireService: QuestionnaireService, Sendable {
    let storage: QuestionnaireStorageService
    let manager: QuestionnaireManager
    let phoneNumber: String
    let logger: Logger
    
    /// Initialize a new questionnaire service
    /// - Parameters:
    ///   - questionnaireName: The name of the questionnaire
    ///   - filePath: The closure to get the file path for the questionnaire response
    ///   - directoryPath: The path to the directory where the questionnaire response file is stored
    ///   - phoneNumber: The caller's phone number used in the hash of the file name
    ///   - logger: The logger to use for logging
    init(
        questionnaireName: String,
        directoryPath: String,
        phoneNumber: String,
        logger: Logger,
        featureFlags: FeatureFlags,
        encryptionKey: String? = nil
    ) {
        self.phoneNumber = phoneNumber
        self.logger = logger
        self.storage = QuestionnaireStorageService(
            questionnaireName: questionnaireName,
            directoryPath: directoryPath,
            featureFlags: featureFlags,
            encryptionKey: encryptionKey
        )
        self.manager = QuestionnaireManager(
            questionnaire: storage.loadQuestionnaire(),
            initialResponse: storage.loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
        )
    }
    
    /// Get the next question from the questionnaire
    /// - Returns: The next question as a JSON string if available, nil if no more questions
    func getNextQuestion() async -> String? {
        manager.getNextQuestionString()
    }
    
    /// Save the questionnaire response to the file by delegating to the storage service
    func saveQuestionnaireResponseToFile() async {
        let response = manager.getCurrentResponse()
        await storage.saveQuestionnaireResponse(phoneNumber: phoneNumber, response: response, logger: logger)
    }
    
    /// Save the answer to a question to the questionnaire response managed by the manager
    /// - Parameters:
    ///   - linkId: The question's identifier
    ///   - answer: The answer to the question
    /// - Returns: True if the answer was saved successfully, false otherwise
    func saveQuestionnaireAnswer<T>(linkId: String, answer: T) -> Bool {
        do {
            try manager.answerQuestion(linkId: linkId, answer: answer)
            Task {
                await saveQuestionnaireResponseToFile()
            }
            return true
        } catch {
            logger.error("Error saving Questionnaire Answer: \(error)")
        }
        return false
    }
    
    /// Count the number of answered questions
    /// - Returns: The number of answered questions
    func countAnsweredQuestions() -> Int {
        manager.countAnsweredQuestions()
    }
    
    /// Check if there are any unanswered questions left
    /// - Returns: True if there are any unanswered questions left, false otherwise
    func unansweredQuestionsLeft() -> Bool {
        !manager.isFinished
    }
}
