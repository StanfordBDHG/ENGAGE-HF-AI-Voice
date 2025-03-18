//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

enum ConversationType {
    case bloodPressure
    case heartRate
    case weight
}

actor ConversationState {
    /// The current state of the conversation
    private var currentState: ConversationType
    
    init() {
        self.currentState = .bloodPressure
    }
    
    /// Get the current conversation state
    func getCurrentState() -> ConversationType {
        return currentState
    }
    
    /// Update the conversation state
    func updateState(_ newState: ConversationType) {
        currentState = newState
    }
}
