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

/// Service for managing Q17 data storage
enum Q17Service: QuestionnaireService {
    static let service = QuestionnaireStorageService(
        questionnaireName: "q17",
        filePath: FileService.q17FilePath,
        directoryPath: FileService.q17DirectoryPath
    )

    static func setQuestionnaireResponseLoader(_ loader: QuestionnaireResponseLoader) async {
        await service.setQuestionnaireResponseLoader(loader)
    }
    
    static func setupFile(phoneNumber: String, logger: Logger) {
        service.setupFile(phoneNumber: phoneNumber, logger: logger)
    }
    
    static func initializeQuestions(phoneNumber: String, logger: Logger) async {
        await service.initializeQuestions(phoneNumber: phoneNumber, logger: logger)
    }
    
    static func getNextQuestion(phoneNumber: String, logger: Logger) async -> String? {
        await service.getNextQuestion(phoneNumber: phoneNumber, logger: logger)
    }
    
    static func loadQuestionnaireResponse(phoneNumber: String, logger: Logger) async -> QuestionnaireResponse {
        await service.loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
    }
    
    static func saveQuestionnaireResponse<T>(linkId: String, answer: T, phoneNumber: String, logger: Logger) async -> Bool {
        await service.saveQuestionnaireResponse(linkId: linkId, answer: answer, phoneNumber: phoneNumber, logger: logger)
    }

    static func countAnsweredQuestions(phoneNumber: String, logger: Logger) async -> Int {
        await service.countAnsweredQuestions(phoneNumber: phoneNumber, logger: logger)
    }
}
