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

    func getNextQuestion(includeAllQuestions: Bool) async -> String?
    func saveQuestionnaireAnswer<T>(linkId: String, answer: T) async -> Bool
    func countAnsweredQuestions() -> Int
    func unansweredQuestionsLeft() -> Bool
}

extension QuestionnaireResponseItemAnswer {
    func integerAnswerValue() -> Int? {
        guard let value else {
            return nil
        }
        switch value {
        case .integer(let integerValue):
            return (integerValue.value?.integer).flatMap(Int.init)
        case .string(let stringValue):
            return (stringValue.value?.string).flatMap(Int.init)
        default:
            return nil
        }
    }
}
