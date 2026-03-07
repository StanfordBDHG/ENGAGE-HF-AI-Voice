//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Crypto
import Foundation

enum FileNaming {
    static func fileName(phoneNumber: String, date: Date, internalTestingMode: Bool) -> String {
        #if DEBUG
            return "1"
        #else
            let formatter = DateFormatter()
            if internalTestingMode {
                // For internal testing, allow for multiple responses per day by including timestamp
                formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            } else {
                formatter.dateFormat = "yyyy-MM-dd"
            }
            let today = formatter.string(from: date)
            let combinedString = phoneNumber + today

            // swiftlint:disable:next force_unwrapping
            let data = combinedString.data(using: .utf8)!
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
        #endif
    }
}
