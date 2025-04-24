//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor


enum FileService {
    private static let dataDirectory: String = {
        let fileManager = FileManager.default
        let currentDirectoryPath = fileManager.currentDirectoryPath
        return "\(currentDirectoryPath)/Data"
    }()
    
    static let kccq12DirectoryPath: String = {
        "\(dataDirectory)/kccq12_questionnairs/"
    }()
    
    static let vitalSignsDirectoryPath: String = {
        "\(dataDirectory)/vital_signs/"
    }()
    
    static func vitalSignsFilePath(phoneNumber: String) -> String {
        "\(vitalSignsDirectoryPath)\(hashPhoneNumber(phoneNumber)).json"
    }
    
    static func kccq12FilePath(phoneNumber: String) -> String {
        "\(kccq12DirectoryPath)\(hashPhoneNumber(phoneNumber)).json"
    }
    
    private static func hashPhoneNumber (_ phoneNumber: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let combinedString = phoneNumber + today
        
        // swiftlint:disable:next force_unwrapping
        let data = combinedString.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}
