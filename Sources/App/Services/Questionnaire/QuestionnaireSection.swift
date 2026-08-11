//
// This source file is part of the ENGAGE-HF AI-Voice open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation

/// Defines a single section of a questionnaire-based call flow.
///
/// Each section corresponds to one FHIR Questionnaire resource and its associated configuration
/// (storage directory, system prompt, behavioral flags). Study-specific call flows are built by
/// composing an array of `QuestionnaireSection` values.
protocol QuestionnaireSection: Sendable {
    /// The display name used in system prompts (e.g. "Vital Signs").
    var title: String { get }

    /// The base name of the JSON resource in the bundle (without extension).
    var resourceName: String { get }

    /// The directory path where responses for this section are stored.
    var directoryURL: URL { get }

    /// The system prompt fragment appended when this section is active.
    var instructions: String { get }

    /// When true, the first question payload includes all remaining questions
    /// so the AI can handle related questions together (e.g. blood pressure).
    var sharesAllQuestions: Bool { get }
}
