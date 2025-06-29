//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4


/// A struct to wrap the question and progress
struct QuestionWithProgress: Codable {
    enum CodingKeys: String, CodingKey {
        case question, progress
    }

    let question: QuestionnaireItem
    let progress: String
}
