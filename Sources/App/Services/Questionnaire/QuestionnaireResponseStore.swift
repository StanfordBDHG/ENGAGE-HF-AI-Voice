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

/// Persistent storage for FHIR QuestionnaireResponse files.
///
/// Handles loading questionnaire definitions from the app bundle, and loading/saving
/// encrypted questionnaire responses to disk. This layer is independent of question
/// flow logic and can be reused for any FHIR questionnaire.
@MainActor
class QuestionnaireResponseStore: Sendable {
    private let resourceName: String
    private let directoryPath: String
    private let encryptionService: EncryptionService?
    private let featureFlags: FeatureFlags
    private let dateTimeCreated: Date

    init(
        resourceName: String,
        directoryPath: String,
        featureFlags: FeatureFlags,
        encryptionKey: String? = nil
    ) throws {
        self.resourceName = resourceName
        self.directoryPath = directoryPath
        self.encryptionService = try encryptionKey.map {
            try EncryptionService(encryptionKeyBase64: $0)
        }
        self.featureFlags = featureFlags
        self.dateTimeCreated = Date()
    }

    // MARK: - Questionnaire Definition

    func loadQuestionnaire() -> Questionnaire? {
        guard let path = Bundle.module.path(forResource: resourceName, ofType: "json"),
            let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        else {
            return nil
        }
        return try? JSONDecoder().decode(Questionnaire.self, from: data)
    }

    // MARK: - Response Persistence

    func loadResponse(phoneNumber: String, logger: Logger) -> QuestionnaireResponse {
        let path = filePath(phoneNumber)
        guard FileManager.default.fileExists(atPath: path) else {
            logger.info("No existing response at \(path)")
            return makeEmptyResponse(phoneNumber: phoneNumber)
        }

        do {
            let raw = try Data(contentsOf: URL(fileURLWithPath: path))
            let jsonData = try decryptIfNeeded(raw, logger: logger)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(QuestionnaireResponse.self, from: jsonData)
        } catch {
            logger.error("Failed to load questionnaire response: \(error)")
            return makeEmptyResponse(phoneNumber: phoneNumber)
        }
    }

    func saveResponse(phoneNumber: String, response: QuestionnaireResponse, logger: Logger) {
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
            let dataToWrite = try encryptIfNeeded(jsonData, logger: logger)
            try dataToWrite.write(to: URL(fileURLWithPath: filePath(phoneNumber)))
        } catch {
            logger.error("Failed to save questionnaire response: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func filePath(_ phoneNumber: String) -> String {
        let name = FileNaming.fileName(
            phoneNumber: phoneNumber,
            date: dateTimeCreated,
            internalTestingMode: featureFlags.internalTestingMode
        )
        return "\(directoryPath)\(name).json"
    }

    private func decryptIfNeeded(_ data: Data, logger: Logger) throws -> Data {
        guard let encryptionService else {
            return data
        }
        logger.info("Decrypting questionnaire response")
        return try encryptionService.decrypt(data)
    }

    private func encryptIfNeeded(_ data: Data, logger: Logger) throws -> Data {
        guard let encryptionService else {
            return data
        }
        logger.info("Encrypting questionnaire response")
        return try encryptionService.encrypt(data)
    }

    private func makeEmptyResponse(phoneNumber: String) -> QuestionnaireResponse {
        let response = QuestionnaireResponse(
            status: FHIRPrimitive(QuestionnaireResponseStatus.completed)
        )
        response.subject = .init(reference: FHIRPrimitive(FHIRString(phoneNumber)))
        return response
    }
}
