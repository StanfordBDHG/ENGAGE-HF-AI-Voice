//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Security

enum SecKeyError: Error {
    case invalidBase64Data
    case unableToCreate
    case unableToDecrypt
}

extension SecKey {
    static func fromPEM(_ pem: String) throws -> SecKey {
        // Strip headers/footers and whitespace.
        let lines = pem
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.hasPrefix("-----BEGIN") && !$0.hasPrefix("-----END") }
        let base64Body = lines.joined()
        
        guard let der = Data(base64Encoded: base64Body) else {
            throw SecKeyError.invalidBase64Data
        }
        
        // Try PKCS#8 -> PKCS#1 unwrapping first
        if der.count > 26, let key = try? fromDER(der.dropFirst(26)) {
            return key
        }
        
        // Try PKCS#8 directly
        return try fromDER(der)
    }
    
    private static func fromDER(_ data: Data) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? SecKeyError.unableToCreate
        }
        return key
    }
    
    func decrypt(_ data: Data, using algorithm: SecKeyAlgorithm) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCreateDecryptedData(self, algorithm, data as CFData, &error) as Data? else {
            throw error?.takeRetainedValue() ?? SecKeyError.unableToDecrypt
        }
        return data
    }
}
