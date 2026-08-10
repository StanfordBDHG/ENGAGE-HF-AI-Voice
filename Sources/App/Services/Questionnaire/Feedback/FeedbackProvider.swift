//
// This source file is part of the ENGAGE-HF AI-Voice open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4
import Vapor

/// Produces a feedback message after all questionnaire sections are complete.
///
/// Conforming types receive the array of engines (in section order) and return
/// a feedback string, or `nil` if feedback cannot be generated.
protocol FeedbackProvider: Sendable {
    @MainActor
    func feedback(from engines: [FHIRQuestionnaireEngine]) async -> String?
}
