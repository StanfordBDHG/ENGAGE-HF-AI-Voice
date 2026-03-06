//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A struct to wrap the question(s) and progress.
/// When `allQuestions` is set, only `allQuestions` and `progress` are encoded.
/// When `allQuestions` is nil, only `question` and `progress` are encoded.
struct QuestionWithProgress: Encodable {
    enum CodingKeys: String, CodingKey {
        case question, progress, allQuestions
    }

    let question: SimplifiedQuestion
    let progress: String
    // swiftlint:disable:next discouraged_optional_collection
    let allQuestions: [SimplifiedQuestion]?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(progress, forKey: .progress)
        if let allQuestions = allQuestions {
            try container.encode(allQuestions, forKey: .allQuestions)
        } else {
            try container.encode(question, forKey: .question)
        }
    }
}
