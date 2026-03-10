//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziLLMOpenAI
import Vapor


final class SaveResponseFunction: LLMFunction, @unchecked Sendable {
    static let name = "save_response"
    static let description = """
        Saves a patient response and returns the next question. \
        This function should be called after a response is recorded to save it. \
        Calling this function multiple times for the same linkId will override the answer value.
        """
    static let answerDescription = """
        The patient's answer. \
        A `null` value must ONLY be used if the patient explicitly asks to skip the \
        question or clearly states they do not have the information. \
        Never use `null` because of silence, filler words, or unclear responses.
        """

    @Parameter(description: "The question's linkId") var linkId: String

    @Parameter(description: answerDescription) var answer: QuestionnaireAnswerParameter

    private let coordinator: CallFlowCoordinator
    private let logger: Logger

    init(coordinator: CallFlowCoordinator, logger: Logger) {
        self.coordinator = coordinator
        self.logger = logger
    }

    func execute() async throws -> String? {
        logger.info("Attempting to save response for linkId: \(linkId)")

        let engine = await coordinator.currentEngine
        switch answer.value {
        case .number(let number):
            try await engine.answerQuestion(linkId: linkId, answer: number)
        case .text(let text):
            try await engine.answerQuestion(linkId: linkId, answer: text)
        case .none:
            try await engine.answerQuestion(linkId: linkId, answer: NSNull())
        }

        if let nextQuestion = await engine.nextQuestionJSON(includeAllQuestions: false) {
            return nextQuestion
        }

        return await handleSectionCompletion()
    }

    private func handleSectionCompletion() async -> String {
        if let nextEngine = await coordinator.advanceToNextSection() {
            let initialQuestion = await nextEngine.nextQuestionJSON(includeAllQuestions: true)
            if let systemMessage = await coordinator.sectionSystemMessage(
                for: nextEngine, initialQuestion: initialQuestion
            ) {
                return "Response saved. Please now follow these updated instructions:\n\n\(systemMessage)"
            }
        }
        let feedback = await coordinator.generateFeedback()
        return "Response saved. All questionnaires complete. Please now follow these updated instructions:\n\n\(Constants.feedback(content: feedback))"
    }
}
