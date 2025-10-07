//
//  CallRecordingDecryptor.swift
//  ENGAGE-HF-AI-Voice
//
//  Created by Paul Kraft on 07.10.2025.
//

import CryptoKit
import Foundation
import Security

enum CallRecordingDecryptionError: Error {
    case invalidInput
    case invalidInitialVectorLength
    case invalidCiphertextLength
}

class CallRecordingDecryptor {
    // MARK: Stored Properties
    
    let privateKey: SecKey
    
    // MARK: Initialization
    
    init(privateKey: SecKey) {
        self.privateKey = privateKey
    }
    
    // MARK: Methods
    
    func decrypt(_ data: Data, initialVector: String, encryptedCEK: String) throws -> Data {
        guard let ivData = Data(base64Encoded: initialVector),
              let encryptedCEKData = Data(base64Encoded: encryptedCEK) else {
            throw CallRecordingDecryptionError.invalidInput
        }
        
        guard ivData.count == 12 else {
            throw CallRecordingDecryptionError.invalidInitialVectorLength
        }
        
        let cekData = try (try? privateKey.decrypt(encryptedCEKData, using: .rsaEncryptionOAEPSHA256))
            ?? privateKey.decrypt(encryptedCEKData, using: .rsaEncryptionOAEPSHA1)
        
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
