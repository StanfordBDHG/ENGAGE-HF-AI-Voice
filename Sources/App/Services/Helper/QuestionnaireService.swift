//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4
import Vapor


@MainActor
protocol QuestionnaireService: Sendable {
    var storage: QuestionnaireStorageService { get }
    var manager: QuestionnaireManager { get }
    var phoneNumber: String { get }
    var logger: Logger { get }
    
    func getNextQuestion() async -> String?
    func saveQuestionnaireResponseToFile() async
    func saveQuestionnaireAnswer<T>(linkId: String, answer: T) -> Bool
    func countAnsweredQuestions() -> Int
    func unansweredQuestionsLeft() -> Bool
}
