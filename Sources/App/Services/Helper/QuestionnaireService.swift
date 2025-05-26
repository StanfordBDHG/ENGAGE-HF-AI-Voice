//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4
import Vapor


/// Protocol for questionnaire services
@MainActor
protocol QuestionnaireService {
    static var service: QuestionnaireStorageService { get }
    
    static func setQuestionnaireResponseLoader(_ loader: QuestionnaireResponseLoader) async
    
    static func setupFile(phoneNumber: String, logger: Logger)
    
    static func initializeQuestions(phoneNumber: String, logger: Logger) async
    
    static func getNextQuestion(phoneNumber: String, logger: Logger) async -> String?
    
    static func loadQuestionnaireResponse(phoneNumber: String, logger: Logger) async -> QuestionnaireResponse
    
    static func saveQuestionnaireResponse<T>(linkId: String, answer: T, phoneNumber: String, logger: Logger) async -> Bool

    static func countAnsweredQuestions(phoneNumber: String, logger: Logger) async -> Int
}
