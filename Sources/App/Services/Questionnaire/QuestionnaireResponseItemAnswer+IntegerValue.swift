//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4
import Vapor

extension QuestionnaireResponseItemAnswer {
    func integerAnswerValue() -> Int? {
        guard let value else {
            return nil
        }
        switch value {
        case .integer(let integerValue):
            return (integerValue.value?.integer).flatMap(Int.init)
        case .string(let stringValue):
            return (stringValue.value?.string).flatMap(Int.init)
        default:
            return nil
        }
    }
}
