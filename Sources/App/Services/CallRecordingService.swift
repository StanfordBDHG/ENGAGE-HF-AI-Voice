//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor

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
            let fileName = recording.sid + ".wav"
            
            if existingFileNames.contains(fileName) {
                continue
            }
            
            do {
                let fileURL = directory.appendingPathComponent(fileName)
                let data = try await api.fetchMediaFile(sid: recording.sid)
                try data.write(to: fileURL)
                logger.info("Successfully downloaded recording file for \(recording.sid).")
            } catch {
                logger.error("Failed to download and store recording file for \(recording.sid): \(error.localizedDescription)")
            }
        }
    }
}
