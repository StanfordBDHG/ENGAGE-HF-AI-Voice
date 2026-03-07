//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

enum QuestionnaireResponseAnswer {
    case number(Int)
    case text(String)
}

private struct CodingWrapper: Codable {
    struct Coding: Codable {
        var code: String
    }

    var valueCoding: Coding
}


struct QuestionnaireResponseArgs: Codable {
    enum CodingKeys: String, CodingKey {
        case linkId
        case answer
    }

    let linkId: String
    let answer: QuestionnaireResponseAnswer?


    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        linkId = try container.decode(String.self, forKey: .linkId)
        
        if let number = try? container.decode(Int.self, forKey: .answer) {
            answer = .number(number)
        } else if let text = try? container.decode(String.self, forKey: .answer) {
            answer = .text(text)
        } else if let codingWrapper = try? container.decode(CodingWrapper.self, forKey: .answer) {
            answer = .text(codingWrapper.valueCoding.code)
        } else if try container.decodeNil(forKey: .answer) {
            answer = nil
        } else {
            throw DecodingError.typeMismatch(
                QuestionnaireResponseArgs.self,
                .init(codingPath: decoder.codingPath + [CodingKeys.answer], debugDescription: "Unknown type")
            )
        }
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(linkId, forKey: .linkId)
        
        switch answer {
        case .number(let value):
            try container.encode(value, forKey: .answer)
        case .text(let value):
            try container.encode(value, forKey: .answer)
        case nil:
            try container.encodeNil(forKey: .answer)
        }
    }
}
