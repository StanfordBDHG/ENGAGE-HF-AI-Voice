//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor

struct TwilioRecording: Decodable {
    enum CodingKeys: String, CodingKey {
        case callSid = "call_sid"
        case dateCreated = "date_created"
        case dateUpdated = "date_updated"
        case duration
        case sid
    }
    
    let callSid: String
    let dateCreated: String
    let dateUpdated: String
    let duration: String
    let sid: String
}

private struct TwilioRecordingList: Decodable {
    let recordings: [TwilioRecording]
}

actor TwilioAPI {
    let baseURL: URL
    let authorizationHeaderValue: String
    let httpClient: HTTPClient
    
    init(accountSid: String, apiKey: String, secret: String, httpClient: HTTPClient) throws {
        guard let baseURL = URL(string: "https://api.twilio.com/2010-04-01/Accounts/\(accountSid)") else {
            throw Abort(.badRequest)
        }
        self.baseURL = baseURL
        self.authorizationHeaderValue = "Basic " + "\(apiKey):\(secret)".base64String()
        self.httpClient = httpClient
    }

    func fetchRecordings() async throws -> [TwilioRecording] {
        let request = try HTTPClient.Request(
            url: baseURL.appending(path: "Recordings.json"),
            headers: [
                "Authorization": authorizationHeaderValue
            ]
        )
        let response = try await httpClient.execute(request: request).get()
        guard let responseBody = response.body else {
            throw Abort(.badRequest, reason: "Twilio response body was nil")
        }
        let body = try JSONDecoder().decode(TwilioRecordingList.self, from: responseBody)
        return body.recordings
    }
    
    func fetchRecording(sid: String) async throws -> TwilioRecording {
        let request = try HTTPClient.Request(
            url: baseURL.appending(path: "Recordings/\(sid).json"),
            headers: [
                "Authorization": authorizationHeaderValue
            ]
        )
        let response = try await httpClient.execute(request: request).get()
        guard let responseBody = response.body else {
            throw Abort(.badRequest, reason: "Twilio response body was nil")
        }
        let body = try JSONDecoder().decode(TwilioRecording.self, from: responseBody)
        return body
    }
    
    func fetchMediaFile(sid: String) async throws -> Data {
        let request = try HTTPClient.Request(
            url: baseURL.appending(path: "Recordings/\(sid).wav"),
            headers: [
                "Authorization": authorizationHeaderValue
            ]
        )
        let response = try await httpClient.execute(request: request).get()
        guard var responseBody = response.body else {
            throw Abort(.badRequest, reason: "Twilio response body was nil")
        }
        return responseBody.readData(length: responseBody.readableBytes) ?? Data()
    }
}
