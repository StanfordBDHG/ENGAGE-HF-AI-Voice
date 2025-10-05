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
    let cek: String
    let iv: String // swiftlint:disable:this identifier_name
}

actor CallRecordingService {
    let api: TwilioAPI
    let directory: URL
    let logger: Logger
    
    init(
        api: TwilioAPI,
        logger: Logger,
        directory: URL = URL(fileURLWithPath: Constants.callRecordingsDirectoryPath)
    ) {
        self.api = api
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
            let fileNameSuffixWAV = "_" + recording.sid + ".wav"
            let fileNameSuffixJSON = "_" + recording.sid + ".json"
            
            if existingFileNames.contains(where: { $0.hasSuffix(fileNameSuffixWAV) }) {
                continue
            }
                        
            do {
                let call = try await api.fetchCall(sid: recording.callSid)
                let wavURL = directory.appending(component: call.from + fileNameSuffixWAV)
                let jsonURL = directory.appending(component: call.from + fileNameSuffixJSON)
                let data = try await api.fetchMediaFile(sid: recording.sid)
                try data.write(to: wavURL)
                
                if let encryptionDetails = recording.encryptionDetails {
                    let jsonData = try JSONEncoder().encode(
                        CallRecordingMetadata(
                            cek: encryptionDetails.encryptedCEK,
                            iv: encryptionDetails.initialVector
                        )
                    )
                    try jsonData.write(to: jsonURL)
                }
                logger.info("Successfully downloaded recording file for \(recording.sid) at \(wavURL).")
            } catch {
                logger.error("Failed to download and store recording file for \(recording.sid): \(error.localizedDescription)")
            }
        }
    }
}
