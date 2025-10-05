//
//  TwilioAPI.swift
//  ENGAGE-HF-AI-Voice
//
//  Created by Paul Kraft on 05.10.2025.
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
        let response = try await httpClient.get(url: baseURL.appending(path: "Recordings.json").absoluteString).get()
        let body = try JSONDecoder().decode(TwilioRecordingList.self, from: response.body ?? ByteBuffer())
        return body.recordings
    }
    
    func fetchRecording(sid: String) async throws -> TwilioRecording {
        let response = try await httpClient.get(url: baseURL.appending(path: "Recordings/\(sid).json").absoluteString).get()
        let body = try JSONDecoder().decode(TwilioRecording.self, from: response.body ?? ByteBuffer())
        return body
    }
    
    func fetchMediaFile(sid: String) async throws -> Data {
        let response = try await httpClient.get(url: baseURL.appending(path: "Recordings/\(sid).wav").absoluteString).get()
        var body = response.body ?? ByteBuffer()
        return body.readData(length: body.readableBytes) ?? Data()
    }
}
