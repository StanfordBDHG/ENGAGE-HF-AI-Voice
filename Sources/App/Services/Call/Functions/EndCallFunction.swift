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

    /// Called after a delay once the AI signals end-of-call, allowing the AI to finish its goodbye before the session is torn down.
    nonisolated(unsafe) var onEnd: (@Sendable () async -> Void)?

    func execute() async throws -> String? {
        if let onEnd {
            Task {
                try? await Task.sleep(for: .seconds(15))
                await onEnd()
            }
        }
        return "Call end acknowledged."
    }
}
