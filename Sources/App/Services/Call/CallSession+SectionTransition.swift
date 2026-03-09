//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Vapor

extension CallSession {
    func handleQuestionnaireComplete(
        response: OpenAIResponse
    ) async throws {
        if let nextEngine = await coordinator.advanceToNextSection() {
            let initialQuestion = await nextEngine.nextQuestionString(includeAllQuestions: true)
            if let systemMessage = await coordinator.sectionSystemMessage(
                for: nextEngine, initialQuestion: initialQuestion
            ) {
                try await handleNextSectionAvailable(
                    initialQuestion: initialQuestion,
                    systemMessage: systemMessage,
                    response: response
                )
            } else {
                try await handleAllSectionsComplete(response: response)
            }
        } else {
            try await handleAllSectionsComplete(response: response)
        }
    }

    func handleNextSectionAvailable(
        initialQuestion: String?,
        systemMessage: String,
        response: OpenAIResponse
    ) async throws {
        try await updateSession(systemMessage: systemMessage)
        if let initialQuestion {
            try await sendFunctionOutput(callId: response.callId ?? "", output: initialQuestion)
        }
        try await sendResponseCreate()
    }

    func handleAllSectionsComplete(response: OpenAIResponse) async throws {
        let feedback = await coordinator.generateFeedback()
        let systemMessage = Constants.feedback(
            content: feedback ?? "Feedback failed to be retrieved."
        )
        try await updateSession(systemMessage: systemMessage)
        try await sendResponseCreate()
    }

    func handleProcessingError(error: any Error, response: OpenAIResponse) async throws {
        logger.error("Error processing questionnaire: \(error)")
        try await sendFunctionOutput(
            callId: response.callId ?? "",
            output: "Failed to process questionnaire"
        )
    }
}
