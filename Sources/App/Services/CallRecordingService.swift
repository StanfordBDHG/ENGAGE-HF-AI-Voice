//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor

private struct CallRecordingMetadata: Encodable {
    let callDuration: String?
    let recordingDuration: String?
    let channels: Int?
    let callStart: String?
    let callEnd: String?
    let callSid: String?
    let recordingSid: String?
    let from: String?
    let to: String?
    let queueTime: String?
    let trunkSid: String?
}

@MainActor
class CallRecordingService: Sendable {
    let api: TwilioAPI
    let decryptor: CallRecordingDecryptor?
    let encryptor: EncryptionService?
    let directory: URL
    let logger: Logger
    
    init(
        api: TwilioAPI,
        decryptionKey: String?,
        encryptionKey: String?,
        logger: Logger,
        directory: URL = URL(fileURLWithPath: Constants.callRecordingsDirectoryPath)
    ) {
        self.api = api
        self.decryptor = decryptionKey.flatMap {
            try? CallRecordingDecryptor(privateKey: .fromPEM($0))
        }
        self.encryptor = encryptionKey.flatMap {
            try? EncryptionService(encryptionKeyBase64: $0)
        }
        self.directory = directory
        self.logger = logger
    }
    
    func storeNewestRecordings() async throws {
        let fileManager = FileManager.default
        let existingFileNames: [String]
        if fileManager.fileExists(atPath: directory.path()) {
            existingFileNames = try fileManager.contentsOfDirectory(atPath: directory.path())
        } else {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            existingFileNames = []
        }
        logger.info("Found \(existingFileNames.count) existing recordings")
        
        let recordings = try await api.fetchRecordings()
        logger.info("Found \(recordings.count) recordings in Twilio")
        
        for recording in recordings {
            if existingFileNames.contains(where: { $0.hasSuffix(recording.sid + ".wav") }) || recording.errorCode != nil {
                continue
            }
                        
            do {
                let outputURL = try await storeRecording(recording)
                logger.info("Successfully downloaded recording file for \(recording.sid) in \(outputURL).")
            } catch {
                logger.error("Failed to download and store recording file for \(recording.sid): \(error.localizedDescription)")
            }
        }
    }
    
    private func storeRecording(_ recording: TwilioRecording) async throws -> URL {
        let call = try await api.fetchCall(sid: recording.callSid)
        guard let twilioDate = parseTwilioDate(from: recording.dateCreated) else {
            throw Abort(.badRequest)
        }
        
        let mediaData = try await api.fetchMediaFile(sid: recording.sid)
                                        
        let decryptedMediaData = try recording.encryptionDetails.map { encryptionDetails in
            guard let decryptor else {
                throw Abort(.badRequest, reason: "Decryptor is missing for storing encrypted recording")
            }
            return try decryptor.decrypt(
                mediaData,
                initialVector: encryptionDetails.iv,
                encryptedCEK: encryptionDetails.encryptedCek
            )
        } ?? { () -> Data in
            throw Abort(.badRequest)
        }()
                
        let fileNamePrefix = fileName(phoneNumber: call.from, date: twilioDate, internalTestingMode: false)
        let wavURL = directory.appending(component: fileNamePrefix + "_" + recording.sid + ".wav")
        let jsonURL = directory.appending(component: fileNamePrefix + "_" + recording.sid + ".json")
        
        let encryptedMediaData = try encryptor?.encrypt(decryptedMediaData) ?? decryptedMediaData
        logger.info("\(recording.sid) - Media size: \(mediaData.count) --> \(encryptedMediaData.count)")
        try encryptedMediaData.write(to: wavURL)
        
        let metadata = CallRecordingMetadata(
            callDuration: call.duration,
            recordingDuration: recording.duration,
            channels: recording.channels,
            callStart: rewriteTwilioDate(call.startTime),
            callEnd: rewriteTwilioDate(call.endTime),
            callSid: call.sid,
            recordingSid: recording.sid,
            from: call.from,
            to: call.to,
            queueTime: call.queueTime,
            trunkSid: call.trunkSid
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(metadata)
        let encryptedJsonData = try encryptor?.encrypt(jsonData) ?? jsonData
        logger.info("\(recording.sid) - Json size: \(jsonData.count) --> \(encryptedJsonData.count)")
        try encryptedJsonData.write(to: jsonURL)
        return wavURL
    }
    
    private func rewriteTwilioDate(_ string: String) -> String {
        parseTwilioDate(from: string).map(filePathUsableDateString) ?? string
    }
    
    private func filePathUsableDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.string(from: date)
    }
    
    private func parseTwilioDate(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: string)
    }
}
