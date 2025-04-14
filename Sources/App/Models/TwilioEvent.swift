//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

struct MediaData: Decodable {
    let timestamp: String
    let payload: String
    let chunk: String
    let track: String
}

struct StartData: Decodable {
    let streamSid: String
}

struct TwilioEvent: Decodable {
    enum CodingKeys: String, CodingKey {
        case event
        case media
        case start
    }

    let event: String
    let media: MediaData?
    let start: StartData?
}
