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
class QuestionnaireStorageService {
    typealias FilePathClosure = @Sendable (String) -> String
    
    private let questionnaireName: String
    private let filePath: FilePathClosure
    private let directoryPath: String
    
    
    /// Initialize a new questionnaire storage service
    /// - Parameters:
    ///   - questionnaireName: The name of the questionnaire
    ///   - filePath: The closure to get the file path for the questionnaire response
    ///   - directoryPath: The path to the directory where the questionnaire response file is stored
    init(questionnaireName: String, filePath: @escaping FilePathClosure, directoryPath: String) {
        self.questionnaireName = questionnaireName
        self.filePath = filePath
        self.directoryPath = directoryPath
    }
    
    /// Creates the file to save the questionnaire's response
    /// - Parameters:
    ///   - phoneNumber: The caller's phone number used in the hash of the file name
    ///   - logger: The logger to use for logging
    func setupFile(phoneNumber: String, logger: Logger) {
        logger.info("Attempting to create \(questionnaireName) file at: \(filePath(phoneNumber))")
        do {
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                atPath: directoryPath,
                withIntermediateDirectories: true
            )
            
            let filePath = filePath(phoneNumber)
            
            // Check if file already exists
            if FileManager.default.fileExists(atPath: filePath) {
                logger.info("\(questionnaireName) file already exists for this participant")
                return
            }
            
            // Create initial QuestionnaireResponse with phoneNumber in subject
            let questionnaireResponse = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.inProgress))
            questionnaireResponse.subject = .init(reference: FHIRPrimitive(FHIRString(phoneNumber)))
            
            // Write to file
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(questionnaireResponse)
            try jsonData.write(to: URL(fileURLWithPath: filePath))
            logger.info("Created new \(questionnaireName) file for this participant")
            
            return
        } catch {
            logger.error("Failed to setup \(questionnaireName) file: \(error)")
            return
        }
    }
    
    /// Loads the questionnaire from the file
    /// - Parameters:
    ///   - logger: The logger to use for logging
    /// - Returns: The questionnaire if it was loaded successfully, nil otherwise
    func loadQuestionnaire() -> Questionnaire? {
        guard let path = Bundle.module.path(forResource: questionnaireName, ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
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
            let questionnaireResponse = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.completed))
            questionnaireResponse.subject = .init(reference: FHIRPrimitive(FHIRString(phoneNumber)))
            return questionnaireResponse
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath(phoneNumber)))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(QuestionnaireResponse.self, from: data)
        } catch {
            logger.error("Failed to load questionnaire response: \(error)")
            let questionnaireResponse = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.completed))
            questionnaireResponse.subject = .init(reference: FHIRPrimitive(FHIRString(phoneNumber)))
            return questionnaireResponse
        }
    }
    
    /// Saves the questionnaire response to the file
    /// - Parameters:
    ///   - phoneNumber: The caller's phone number used in the hash of the file name
    ///   - response: The questionnaire response to save
    ///   - logger: The logger to use for logging
    func saveQuestionnaireResponse(phoneNumber: String, response: QuestionnaireResponse, logger: Logger) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        do {
            let jsonData = try encoder.encode(response)
            try jsonData.write(to: URL(fileURLWithPath: filePath(phoneNumber)))
        } catch {
            logger.error("Failed to save questionnaire response: \(error)")
        }
    }
}
