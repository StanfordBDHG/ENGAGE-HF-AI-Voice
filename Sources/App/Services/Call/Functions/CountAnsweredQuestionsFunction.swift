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


final class CountAnsweredQuestionsFunction: LLMFunction, @unchecked Sendable {
    static let name = "count_answered_questions"
    static let description = "Returns the number of questions already answered in the current section."

    private let coordinator: CallFlowCoordinator
    private let logger: Logger

    init(coordinator: CallFlowCoordinator, logger: Logger) {
        self.coordinator = coordinator
        self.logger = logger
    }

    func execute() async throws -> String? {
        let count = await coordinator.currentEngine.answeredCount()
        logger.info("Count of answered questions of current engine: \(count)")
        return "The patient has answered \(count) questions."
    }
}
