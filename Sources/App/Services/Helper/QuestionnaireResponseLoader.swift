//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4
import Vapor


/// Protocol for loading questionnaire responses
protocol QuestionnaireResponseLoader: Sendable {
    func loadQuestionnaireResponse(phoneNumber: String, logger: Logger) async -> QuestionnaireResponse
}
