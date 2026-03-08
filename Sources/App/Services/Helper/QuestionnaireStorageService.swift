//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4
import Vapor

/// Service for managing questionnaire data storage on disk
@MainActor
class QuestionnaireStorageService: Sendable {
    private let questionnaireName: String
    private let directoryPath: String
    private let encryptionService: EncryptionService?
    private let featureFlags: FeatureFlags
    private let dateTimeCreated: Date

    /// Initialize a new questionnaire storage service
    /// - Parameters:
    ///   - questionnaireName: The name of the questionnaire
    ///   - directoryPath: The path to the directory where the questionnaire response file is stored
    ///   - encryptionKey: Optional base64-encoded master encryption key. If provided, responses will be encrypted.
    init(
        questionnaireName: String,
        directoryPath: String,
        featureFlags: FeatureFlags,
        encryptionKey: String? = nil
    ) throws {
        self.questionnaireName = questionnaireName
        self.directoryPath = directoryPath
        self.encryptionService = try encryptionKey.map {
            try EncryptionService(encryptionKeyBase64: $0)
        }
        self.featureFlags = featureFlags
        
        // save the timestamp when the storage service has been created to load the correct questionnaire response files during a internal testing session
        self.dateTimeCreated = Date()
    }

    /// Loads the questionnaire from the file
    /// - Parameters:
    ///   - logger: The logger to use for logging
    /// - Returns: The questionnaire if it was loaded successfully, nil otherwise
    func loadQuestionnaire() -> Questionnaire? {
        guard let path = Bundle.module.path(forResource: questionnaireName, ofType: "json"),
            let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        else {
            return nil
        }

        let questionnaire = try? JSONDecoder().decode(Questionnaire.self, from: data)
        return questionnaire
    }

    /// Loads the questionnaire response from the file
    /// - Parameters:
    ///   - phoneNumber: The caller's phone number used in the hash of the file name
    ///   - logger: The logger to use for logging
    /// - Returns: The questionnaire response if it was loaded successfully, nil otherwise
    func loadQuestionnaireResponse(phoneNumber: String, logger: Logger) -> QuestionnaireResponse {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: filePath(phoneNumber)) else {
            logger.info("Could not read data from \(filePath(phoneNumber)) file")
            return makeEmptyResponse(phoneNumber: phoneNumber)
        }

        do {
            let encryptedData = try Data(contentsOf: URL(fileURLWithPath: filePath(phoneNumber)))

            // Decrypt the data if encryption service is available
            let jsonData: Data
            if let encryptionService = encryptionService {
                jsonData = try encryptionService.decrypt(encryptedData)
                logger.info("Decrypted questionnaire response using encryption key")
            } else {
                jsonData = encryptedData
                logger.info("Loading questionnaire response without decryption")
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(QuestionnaireResponse.self, from: jsonData)
        } catch {
            logger.error("Failed to load questionnaire response: \(error)")
            return makeEmptyResponse(phoneNumber: phoneNumber)
        }
    }

    /// Saves the questionnaire response to the file
    /// - Parameters:
    ///   - phoneNumber: The caller's phone number used in the hash of the file name
    ///   - response: The questionnaire response to save
    ///   - logger: The logger to use for logging
    func saveQuestionnaireResponse(
        phoneNumber: String, response: QuestionnaireResponse, logger: Logger
    ) async {
        // Create directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(
                atPath: directoryPath,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("Failed to create directory: \(error)")
        }
        response.authored = try? FHIRPrimitive(DateTime(date: dateTimeCreated))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let jsonData = try encoder.encode(response)

            // Encrypt the data if encryption service is available
            let dataToWrite: Data
            if let encryptionService = encryptionService {
                dataToWrite = try encryptionService.encrypt(jsonData)
                logger.info("Encrypted questionnaire response using encryption key")
            } else {
                dataToWrite = jsonData
                logger.info("Saving questionnaire response without encryption")
            }

            let path = filePath(phoneNumber)
            try dataToWrite.write(to: URL(fileURLWithPath: path))
        } catch {
            logger.error("Failed to save questionnaire response: \(error)")
        }
    }

    /// Get the file path for the questionnaire response based on the phone number (and current date)
    private func filePath(_ phoneNumber: String) -> String {
        "\(directoryPath)\(self.hashPhoneNumber(phoneNumber)).json"
    }

    /// Hash the phone number for file naming (includes date for daily rotation)
    private func hashPhoneNumber(_ phoneNumber: String) -> String {
        FileNaming.fileName(
            phoneNumber: phoneNumber,
            date: dateTimeCreated,
            internalTestingMode: featureFlags.internalTestingMode
        )
    }

    private func makeEmptyResponse(phoneNumber: String) -> QuestionnaireResponse {
        let questionnaireResponse = QuestionnaireResponse(
            status: FHIRPrimitive(QuestionnaireResponseStatus.completed)
        )
        questionnaireResponse.subject = .init(reference: FHIRPrimitive(FHIRString(phoneNumber)))
        return questionnaireResponse
    }
}
