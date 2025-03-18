//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

actor ConnectionState {
    var streamSid: String?
    var latestMediaTimestamp: Int? = 0
    var lastAssistantItem: String?
    var markQueue: [String] = []
    var responseStartTimestampTwilio: Int?
}

extension ConnectionState {
    func updateTimestamp(_ timestamp: Int?) {
        latestMediaTimestamp = timestamp
    }
    
    func updateStreamSid(_ sid: String) {
        streamSid = sid
    }
    
    func updateResponseStartTimestampTwilio(_ timestamp: Int?) {
        responseStartTimestampTwilio = timestamp
    }
    
    func updateLastAssistantItem(_ item: String?) {
        lastAssistantItem = item
    }
    
    func removeFirstFromMarkQueue() {
        if !markQueue.isEmpty {
            markQueue.removeFirst()
        }
    }
    
    func removeAllFromMarkQueue() {
        markQueue = []
    }
    
    func appendToMarkQueue(_ item: String) {
        markQueue.append(item)
    }
}
