//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

struct OpenAIResponse: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case itemId = "item_id"
        case arguments
        case name
        case callId = "call_id"
        case error
    }
    
    let type: String
    let delta: String?
    let itemId: String?
    let arguments: String?
    let name: String?
    let callId: String?
    let error: OpenAIError?
}
