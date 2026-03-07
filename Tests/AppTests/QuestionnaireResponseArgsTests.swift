//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Testing

@testable import App

@Suite("QuestionnaireResponseArgs Tests")
struct QuestionnaireResponseArgsTests {
    // MARK: - Decoding

    @Test("Decode integer answer")
    func decodeInteger() throws {
        let json = #"{"linkId": "q1", "answer": 42}"#
        let args = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: Data(json.utf8))
        #expect(args.linkId == "q1")
        if case .number(let value) = args.answer {
            #expect(value == 42)
        } else {
            Issue.record("Expected .number(42), got \(String(describing: args.answer))")
        }
    }

    @Test("Decode decimal answer")
    func decodeDecimal() throws {
        let json = #"{"linkId": "q1", "answer": 98.6}"#
        let args = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: Data(json.utf8))
        #expect(args.linkId == "q1")
        if case .decimal(let value) = args.answer {
            #expect(abs(value - 98.6) < 0.001)
        } else {
            Issue.record("Expected .decimal(98.6), got \(String(describing: args.answer))")
        }
    }

    @Test("Decode integer-looking decimal (e.g. 5.0) as integer")
    func decodeIntegerLookingDecimal() throws {
        // JSON `5` without decimal point should decode as integer
        let json = #"{"linkId": "q1", "answer": 5}"#
        let args = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: Data(json.utf8))
        if case .number(let value) = args.answer {
            #expect(value == 5)
        } else {
            Issue.record("Expected .number(5), got \(String(describing: args.answer))")
        }
    }

    @Test("Decode text answer")
    func decodeText() throws {
        let json = #"{"linkId": "q1", "answer": "hello world"}"#
        let args = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: Data(json.utf8))
        if case .text(let value) = args.answer {
            #expect(value == "hello world")
        } else {
            Issue.record("Expected .text, got \(String(describing: args.answer))")
        }
    }

    @Test("Decode null answer")
    func decodeNull() throws {
        let json = #"{"linkId": "q1", "answer": null}"#
        let args = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: Data(json.utf8))
        #expect(args.linkId == "q1")
        #expect(args.answer == nil)
    }

    @Test("Decode valueCoding wrapper as text")
    func decodeCodingWrapper() throws {
        let json = #"{"linkId": "q1", "answer": {"valueCoding": {"code": "abc-123"}}}"#
        let args = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: Data(json.utf8))
        if case .text(let value) = args.answer {
            #expect(value == "abc-123")
        } else {
            Issue.record("Expected .text(abc-123), got \(String(describing: args.answer))")
        }
    }

    @Test("Decode unsupported type throws error")
    func decodeUnsupportedType() throws {
        let json = #"{"linkId": "q1", "answer": [1, 2, 3]}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: Data(json.utf8))
        }
    }

    // MARK: - Encoding

    @Test("Encode integer answer round-trips")
    func encodeInteger() throws {
        let json = #"{"linkId": "q1", "answer": 42}"#
        let args = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(args)
        let decoded = try JSONDecoder().decode(
            QuestionnaireResponseArgs.self, from: encoded
        )
        #expect(decoded.linkId == "q1")
        if case .number(let value) = decoded.answer {
            #expect(value == 42)
        } else {
            Issue.record("Round-trip failed for integer")
        }
    }

    @Test("Encode decimal answer round-trips")
    func encodeDecimal() throws {
        let json = #"{"linkId": "q1", "answer": 3.14}"#
        let args = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(args)
        let decoded = try JSONDecoder().decode(
            QuestionnaireResponseArgs.self, from: encoded
        )
        if case .decimal(let value) = decoded.answer {
            #expect(abs(value - 3.14) < 0.001)
        } else {
            Issue.record("Round-trip failed for decimal")
        }
    }

    @Test("Encode null answer round-trips")
    func encodeNull() throws {
        let json = #"{"linkId": "q1", "answer": null}"#
        let args = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(args)
        let decoded = try JSONDecoder().decode(
            QuestionnaireResponseArgs.self, from: encoded
        )
        #expect(decoded.answer == nil)
    }

    @Test("Encode text answer round-trips")
    func encodeText() throws {
        let json = #"{"linkId": "q1", "answer": "some text"}"#
        let args = try JSONDecoder().decode(QuestionnaireResponseArgs.self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(args)
        let decoded = try JSONDecoder().decode(
            QuestionnaireResponseArgs.self, from: encoded
        )
        if case .text(let value) = decoded.answer {
            #expect(value == "some text")
        } else {
            Issue.record("Round-trip failed for text")
        }
    }
}
