//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoExtras
import Foundation
import Vapor


enum CallRecordingDecryptionError: Error {
    case invalidInput
    case invalidInitialVectorLength
    case invalidCiphertextLength
}

class CallRecordingDecryptor {
    let privateKey: _RSA.Encryption.PrivateKey
        
    init(privateKey: _RSA.Encryption.PrivateKey) throws {
        self.privateKey = privateKey
    }
        
    func decrypt(_ data: Data, initialVector: String, encryptedCEK: String) throws -> Data {
        guard let ivData = Data(base64Encoded: initialVector),
              let encryptedCEKData = Data(base64Encoded: encryptedCEK) else {
            throw CallRecordingDecryptionError.invalidInput
        }
        
        guard ivData.count == 12 else {
            throw CallRecordingDecryptionError.invalidInitialVectorLength
        }
        
        let cekData = try (try? privateKey.decrypt(encryptedCEKData, padding: .PKCS1_OAEP_SHA256))
            ?? privateKey.decrypt(encryptedCEKData, padding: .PKCS1_OAEP)
        
        
        let tagLength = 16
        guard data.count >= tagLength else {
            throw CallRecordingDecryptionError.invalidCiphertextLength
        }
        
        let tag = data.suffix(tagLength)
        let ciphertext = data.prefix(data.count - tagLength)
        
        let key = SymmetricKey(data: cekData)
        let nonce = try AES.GCM.Nonce(data: ivData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        return plaintext
    }
}
