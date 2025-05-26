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
    static let service = QuestionnaireStorageService(
        questionnaireName: "vitalSigns",
        filePath: FileService.vitalSignsFilePath,
        directoryPath: FileService.vitalSignsDirectoryPath
    )

    static func setQuestionnaireResponseLoader(_ loader: QuestionnaireResponseLoader) async {
        await service.setQuestionnaireResponseLoader(loader)
    }
    
    /// Creats the file to save VitalSigns response
    /// - Parameters:
    ///   - phoneNumber: The caller's phone number
    ///   - logger: The logger to use for logging
    static func setupFile(phoneNumber: String, logger: Logger) {
        service.setupFile(phoneNumber: phoneNumber, logger: logger)
    }
    
    /// Initialize the questions from the VitalSigns file
    static func initializeQuestions(phoneNumber: String, logger: Logger) async {
        await service.initializeQuestions(phoneNumber: phoneNumber, logger: logger)
    }
    
    /// Get the next question from the questionnaire
    /// - Returns: The next question as a JSON string if available, nil if no more questions
    static func getNextQuestion(phoneNumber: String, logger: Logger) async -> String? {
        await service.getNextQuestion(phoneNumber: phoneNumber, logger: logger)
    }
    
    /// Load the questionnaire response from the file
    /// - Returns: The FHIR `QuestionnaireResponse` object loaded from the JSON file
    static func loadQuestionnaireResponse(phoneNumber: String, logger: Logger) async -> QuestionnaireResponse {
        await service.loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
    }
    
    /// Save or update a response to a question to the file
    /// - Parameters:
    ///   - linkId: The question's identifier
    ///   - answer: The answer
    /// - Returns: The FHIR `QuestionnaireResponse` object loaded from the JSON file
    static func saveQuestionnaireResponse<T>(linkId: String, answer: T, phoneNumber: String, logger: Logger) async -> Bool {
        await service.saveQuestionnaireResponse(linkId: linkId, answer: answer, phoneNumber: phoneNumber, logger: logger)
    }

    /// Count the number of answered questions
    /// - Parameters:
    ///   - phoneNumber: The phone number of the caller
    ///   - logger: The logger to use for logging
    /// - Returns: The number of answered questions
    static func countAnsweredQuestions(phoneNumber: String, logger: Logger) async -> Int {
        await service.countAnsweredQuestions(phoneNumber: phoneNumber, logger: logger)
    }
}
