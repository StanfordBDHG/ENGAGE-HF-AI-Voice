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


/// Service for managing vital signs storage
enum VitalSignsService: QuestionnaireService {
    static let storage = QuestionnaireStorageService(
        questionnaireName: "vitalSigns",
        filePath: FileService.vitalSignsFilePath,
        directoryPath: FileService.vitalSignsDirectoryPath
    )
    static let manager = QuestionnaireManager(questionnaire: storage.loadQuestionnaire())

    
    static func loadAnsweredQuestions(phoneNumber: String, logger: Logger) {
        let currentResponse = storage.loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
        manager.setCurrentResponse(currentResponse)
    }
    
    static func setupFile(phoneNumber: String, logger: Logger) {
        storage.setupFile(phoneNumber: phoneNumber, logger: logger)
    }
    
    static func getNextQuestion(logger: Logger) async -> String? {
        manager.getNextQuestionString()
    }
    
    static func saveQuestionnaireResponseToFile(phoneNumber: String, logger: Logger) async {
        let response = manager.getCurrentResponse()
        await storage.saveQuestionnaireResponse(phoneNumber: phoneNumber, response: response, logger: logger)
    }
    
    static func saveQuestionnaireAnswer<T>(linkId: String, answer: T, logger: Logger) -> Bool {
        do {
            try manager.answerQuestion(linkId: linkId, answer: answer)
            return true
        } catch {
            logger.error("Error saving Questionnaire Answer: \(error)")
        }
        return false
    }

    static func countAnsweredQuestions() -> Int {
        manager.countAnsweredQuestions()
    }

    static func unansweredQuestionsLeft() -> Bool {
        !manager.isFinished
    }
}
