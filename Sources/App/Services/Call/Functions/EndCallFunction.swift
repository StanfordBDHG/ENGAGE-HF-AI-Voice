//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziLLMOpenAI


final class EndCallFunction: LLMFunction, @unchecked Sendable {
    static let name = "end_call"
    static let description = "Acknowledge the end of the call."

    func execute() async throws -> String? {
        "Call end acknowledged."
    }
}
