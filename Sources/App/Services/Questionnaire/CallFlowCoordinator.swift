//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4
import Vapor

/// Coordinates the progression through an ordered list of questionnaire sections
/// during a single call, including system message generation and feedback delivery.
///
/// The coordinator is agnostic to the specific questionnaires — it only depends on
/// `QuestionnaireSection` definitions and a `FeedbackProvider` implementation.
actor CallFlowCoordinator {
    private let engines: [FHIRQuestionnaireEngine]
    private let feedbackProvider: (any FeedbackProvider)?
    private let logger: Logger
    private var currentIndex: Int

    /// The total number of sections in this call flow.
    var sectionCount: Int { engines.count }

    /// The engine for the currently active section.
    var currentEngine: FHIRQuestionnaireEngine {
        engines[currentIndex]
    }

    init(
        engines: [FHIRQuestionnaireEngine],
        logger: Logger,
        feedbackProvider: (any FeedbackProvider)? = nil
    ) {
        self.engines = engines
        self.feedbackProvider = feedbackProvider
        self.logger = logger
        self.currentIndex = 0
    }

    // MARK: - Convenience Factory

    /// Create a coordinator from section definitions.
    @MainActor
    static func create(
        sections: [any QuestionnaireSection],
        phoneNumber: String,
        logger: Logger,
        featureFlags: FeatureFlags,
        encryptionKey: String? = nil,
        feedbackProvider: (any FeedbackProvider)? = nil
    ) throws -> CallFlowCoordinator {
        let engines = try sections.map { section in
            try FHIRQuestionnaireEngine(
                section: section,
                phoneNumber: phoneNumber,
                logger: logger,
                featureFlags: featureFlags,
                encryptionKey: encryptionKey
            )
        }
        return CallFlowCoordinator(
            engines: engines,
            logger: logger,
            feedbackProvider: feedbackProvider
        )
    }

    // MARK: - Section Navigation

    /// Advance currentIndex to the first section that still has unanswered questions.
    /// Returns false if every section is already complete.
    func initializeToFirstIncomplete() async -> Bool {
        for (index, engine) in engines.enumerated() where await engine.hasUnansweredQuestions() {
            currentIndex = index
            return true
        }
        return false
    }

    /// Advance to the next section. Returns the engine if available, nil if all sections done.
    func advanceToNextSection() async -> FHIRQuestionnaireEngine? {
        guard currentIndex < engines.count - 1 else {
            return nil
        }
        currentIndex += 1
        return currentEngine
    }

    // MARK: - System Message Generation

    /// Build the initial system message for the start of a call.
    func initialSystemMessage() async -> String {
        let hasUnanswered = await initializeToFirstIncomplete()
        if !hasUnanswered {
            let feedback = await generateFeedback()
            return Constants.initialSystemMessage
                + Constants.noUnansweredQuestionsLeft
                + Constants.feedback(content: feedback ?? "Feedback failed to be retrieved.")
        }

        let engine = currentEngine
        let question = await engine.nextQuestionJSON(includeAllQuestions: true)
        let sectionMessage = await sectionSystemMessage(for: engine, initialQuestion: question)
        return Constants.initialSystemMessage
            + (sectionMessage ?? Constants.noUnansweredQuestionsLeft)
    }

    /// Build the system message for a specific engine/section, including progress context.
    func sectionSystemMessage(
        for engine: FHIRQuestionnaireEngine,
        initialQuestion: String?
    ) async -> String? {
        let answered = await engine.answeredCount()
        let initialInstruction =
            answered == 0
            ? "Inform the patient that you will start with the first question."
            : "Inform the patient about their progress and that you will continue with the remaining questions."

        let sectionIndex = engines.firstIndex(where: { $0 === engine }) ?? currentIndex
        let sectionNumber = sectionIndex + 1
        let instructions = engine.section.instructions
            .replacingOccurrences(
                of: Constants.initialInstructionsPlaceholder,
                with: initialInstruction
            )
            .replacingOccurrences(
                of: Constants.sectionIndexPlaceholder,
                with: String(sectionNumber)
            )
            .replacingOccurrences(
                of: Constants.sectionCountPlaceholder,
                with: String(sectionCount)
            )

        let questionSuffix = initialQuestion.map { "\n\n\($0)" } ?? ""
        return instructions + questionSuffix
    }

    /// Generate feedback using the registered provider.
    func generateFeedback() async -> String? {
        guard let feedbackProvider else {
            return nil
        }
        return await feedbackProvider.feedback(from: engines)
    }

    /// Access all engines (e.g. for score calculations).
    func allEngines() -> [FHIRQuestionnaireEngine] {
        engines
    }

    /// Find the engine for a specific section type.
    func engine<S: QuestionnaireSection>(for sectionType: S.Type) -> FHIRQuestionnaireEngine? {
        engines.first { $0.section is S }
    }
}
