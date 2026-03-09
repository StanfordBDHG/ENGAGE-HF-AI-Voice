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

    nonisolated(unsafe) static let parameterSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "linkId": [
                "type": "string",
                "description": "The question's linkId"
            ],
            "answer": [
                "anyOf": [
                    ["type": "string"],
                    ["type": "number"],
                    ["type": "null"]
                ],
                "description": """
                    The patient's answer. \
                    A `null` value must ONLY be used if the patient explicitly asks to skip the \
                    question or clearly states they do not have the information. \
                    Never use `null` because of silence, filler words, or unclear responses.
                    """
            ]
        ],
        "required": ["linkId", "answer"],
        "additionalProperties": false
    ]

    /// Raw JSON arguments set by `CallSession` before each `execute()` call.
    nonisolated(unsafe) var rawArguments: String = ""

    private let coordinator: CallFlowCoordinator
    private let logger: Logger

    init(coordinator: CallFlowCoordinator, logger: Logger) {
        self.coordinator = coordinator
        self.logger = logger
    }

    func execute() async throws -> String? {
        let argumentsData = Data(rawArguments.utf8)
        let parsedArgs = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: argumentsData)

        logger.info("Attempting to save response for linkId: \(parsedArgs.linkId)")

        let engine = await coordinator.currentEngine
        switch parsedArgs.answer {
        case .number(let number):
            try await engine.answerQuestion(linkId: parsedArgs.linkId, answer: number)
        case .text(let text):
            try await engine.answerQuestion(linkId: parsedArgs.linkId, answer: text)
        case .none:
            try await engine.answerQuestion(linkId: parsedArgs.linkId, answer: NSNull())
        }

        return await engine.nextQuestionJSON(includeAllQuestions: false)
    }
}
