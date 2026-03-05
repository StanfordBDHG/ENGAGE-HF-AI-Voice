//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A simplified answer option with a descriptive code instead of a numeric one
struct SimplifiedAnswerOption: Encodable {
    /// A descriptive code derived from the display text (e.g. "extremely-limited")
    let code: String
    /// The display text for this answer option
    let display: String
    /// An optional note providing additional context for this answer option
    let note: String?
}


/// A simplified question extracted from a FHIR QuestionnaireItem
struct SimplifiedQuestion: Encodable {
    /// The unique identifier for the question
    let linkId: String
    /// The type of question (e.g. "choice", "integer")
    let type: String
    /// The question text to present to the patient
    let text: String
    /// Whether a response is required
    let required: Bool
    /// An optional note providing additional context for the question
    let note: String?
    /// The available answer options (for choice-type questions)
    let answerOptions: [SimplifiedAnswerOption]?
    /// The minimum allowed value (for integer-type questions)
    let minValue: Int?
    /// The maximum allowed value (for integer-type questions)
    let maxValue: Int?
}
