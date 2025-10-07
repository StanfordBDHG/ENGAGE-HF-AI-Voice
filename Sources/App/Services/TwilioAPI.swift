//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor

struct TwilioCall: Decodable {
    let sid: String
    let from: String
    let to: String
    let startTime: String
    let endTime: String
    let duration: String?
    let trunkSid: String?
    let queueTime: String?
}

struct TwilioRecording: Decodable {
    struct EncryptionDetails: Decodable {
        let encryptedCek: String
        let iv: String // swiftlint:disable:this identifier_name
    }
    
    let sid: String
    let callSid: String
    let channels: Int?
    let dateCreated: String
    let dateUpdated: String
    let duration: String?
    let errorCode: Int?
    let encryptionDetails: EncryptionDetails?
}

private struct TwilioRecordingList: Decodable {
    let recordings: [TwilioRecording]
}

actor TwilioAPI {
    let baseURL: URL
    let authorizationHeaderValue: String
    let decoder: JSONDecoder
    let httpClient: HTTPClient
    
    init(accountSid: String, apiKey: String, secret: String, httpClient: HTTPClient) throws {
        guard let baseURL = URL(string: "https://api.twilio.com/2010-04-01/Accounts/\(accountSid)") else {
            throw Abort(.badRequest)
        }
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.baseURL = baseURL
        self.authorizationHeaderValue = "Basic " + "\(apiKey):\(secret)".base64String()
        self.httpClient = httpClient
    }
    
    func fetchCall(sid: String) async throws -> TwilioCall {
        let request = try HTTPClient.Request(
            url: baseURL.appending(path: "Calls/\(sid).json"),
            headers: [
                "Authorization": authorizationHeaderValue
            ]
        )
        let response = try await httpClient.execute(request: request).get()
        guard let responseBody = response.body else {
            throw Abort(.badRequest, reason: "Twilio response body was nil")
        }
        return try decoder.decode(TwilioCall.self, from: responseBody)
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
        let body = try decoder.decode(TwilioRecordingList.self, from: responseBody)
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
        return try decoder.decode(TwilioRecording.self, from: responseBody)
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
