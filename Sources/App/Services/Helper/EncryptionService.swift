//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Vapor


/// Errors that can occur during encryption/decryption
enum EncryptionError: Error {
    case invalidKey
}

/// Service for encrypting questionnaire responses using symmetric encryption
@MainActor
class EncryptionService: Sendable {
    private let encryptionKey: SymmetricKey
    
    /// Initialize with a base64-encoded encryption key
    /// - Parameter encryptionKeyBase64: The encryption key in base64 format
    init(encryptionKeyBase64: String) throws {
        guard let keyData = Data(base64Encoded: encryptionKeyBase64),
              keyData.count == 32 else {
            throw EncryptionError.invalidKey
        }
        self.encryptionKey = SymmetricKey(data: keyData)
    }
    
    /// Encrypt data using the encryption key
    /// - Parameters:
    ///   - data: The data to encrypt
    /// - Returns: Encrypted data
    func encrypt(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        return sealedBox.combined ?? Data()
    }
    
    /// Decrypt data using the encryption key
    /// - Parameters:
    ///   - encryptedData: The encrypted data
    /// - Returns: Decrypted data
    func decrypt(_ encryptedData: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: encryptionKey)
    }
}
