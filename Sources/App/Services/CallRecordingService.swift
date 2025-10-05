//
//  RecordingsService.swift
//  ENGAGE-HF-AI-Voice
//
//  Created by Paul Kraft on 05.10.2025.
//

import Foundation

actor CallRecordingService {
    let api: TwilioAPI
    let directory: URL
    
    // swiftlint:disable:next force_unwrapping
    init(api: TwilioAPI, directory: URL = URL(string: Constants.callRecordingsDirectoryPath)!) {
        self.api = api
        self.directory = directory
    }
    
    func storeNewestRecordings() async throws {
        let fileManager = FileManager.default
        let existingFileNames = fileManager.fileExists(atPath: directory.path())
            ? try fileManager.contentsOfDirectory(atPath: directory.path())
            : []
        let recordings = try await api.fetchRecordings()
        
        for recording in recordings {
            let fileName = recording.sid + ".wav"
            
            if existingFileNames.contains(fileName) {
                continue
            }
            
            let fileURL = directory
                .appendingPathComponent(fileName)
            let data = try await api.fetchMediaFile(sid: recording.sid)
            try data.write(to: fileURL)
        }
    }
}
