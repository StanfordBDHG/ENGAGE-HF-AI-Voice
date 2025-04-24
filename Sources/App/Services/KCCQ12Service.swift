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


/// A struct to wrap the question and progress
struct QuestionWithProgress: Codable {
    enum CodingKeys: String, CodingKey {
        case question, progress
    }

    let question: QuestionnaireItem
    let progress: String
}

/// Actor to manage concurrent access to questions
private actor QuestionManager {
    var remainingQuestions: [QuestionnaireItem] = []
    var totalQuestions: Int = 0
    
    
    func initializeQuestions(_ questions: [QuestionnaireItem], phoneNumber: String, logger: Logger) {
        let items = flattenQuestionnaireItems(questions)
        let answeredQuestionLinkIds = KCCQ12Service
            .loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
            .item?.map { $0.linkId.value?.string } ?? []
        let filteredItems = items.filter { !answeredQuestionLinkIds.contains($0.linkId.value?.string) }
        totalQuestions = items.count
        logger.info("Initializing remaining questions with \(filteredItems.count) questions")
        remainingQuestions = filteredItems
    }
    
    func getNextQuestionAsJSON(logger: Logger) async throws -> String? {
        guard !remainingQuestions.isEmpty else {
            logger.info("No more questions available")
            return nil
        }
        logger.info("remainingQuestions: \(remainingQuestions.count)")
        logger.info("\(remainingQuestions.map { $0.linkId })")
        let nextQuestion = remainingQuestions[0]

        let progressString = "Question \(totalQuestions - remainingQuestions.count + 1) of \(totalQuestions)"

        let questionWithProgress = QuestionWithProgress(question: nextQuestion, progress: progressString)
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(questionWithProgress)
        
        return String(data: jsonData, encoding: .utf8)
    }
    
    func isEmpty() -> Bool {
        remainingQuestions.isEmpty
    }
    
    func removeRemainingQuestion(linkId: String) {
        remainingQuestions.removeAll { $0.linkId.value?.string == linkId }
    }
    
    private func flattenQuestionnaireItems(_ items: [QuestionnaireItem]) -> [QuestionnaireItem] {
        var flattenedItems: [QuestionnaireItem] = []
        
        for item in items {
            if item.type.value == .choice {
                flattenedItems.append(item)
            }
            
            if let nestedItems = item.item {
                flattenedItems.append(contentsOf: flattenQuestionnaireItems(nestedItems))
            }
        }
        
        return flattenedItems
    }
}

/// Service for managing KCCQ12 data storage
enum KCCQ12Service {
    private static let questionManager = QuestionManager()

    
    /// Creats the file to save KCCQ12 responses
    /// - Parameters:
    ///   - phoneNumber: The caller's phone number
    ///   - logger: The logger to use for logging
    static func setupKCCQ12File(phoneNumber: String, logger: Logger) {
        logger.info("Attempting to create KCCQ12 file at: \(FileService.kccq12FilePath(phoneNumber: phoneNumber))")
        do {
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                atPath: FileService.kccq12DirectoryPath,
                withIntermediateDirectories: true
            )
            
            let filePath = FileService.kccq12FilePath(phoneNumber: phoneNumber)
            
            // Check if file already exists
            if FileManager.default.fileExists(atPath: filePath) {
                logger.info("KCCQ12 file already exists for this participant")
                return
            }
            
            // Create initial kccq12 QuestionnaireResponse with phoneNumber in subject
            let questionnaireResponse = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.completed))
            questionnaireResponse.subject = .init(reference: FHIRPrimitive(FHIRString(phoneNumber)))
            
            // Write to file
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(questionnaireResponse)
            try jsonData.write(to: URL(fileURLWithPath: filePath))
            logger.info("Created new KCCQ12 file for this participant")
            
            return
        } catch {
            logger.error("Failed to setup vital signs file: \(error)")
            return
        }
    }
    
    /// Initialize the questions from the KCCQ12 file
    static func initializeQuestions(phoneNumber: String, logger: Logger) async {
        if let questionnaire = loadQuestionnaire(logger: logger) {
            await questionManager.initializeQuestions(questionnaire.item ?? [], phoneNumber: phoneNumber, logger: logger)
        } else {
            logger.info("Questions could not be loaded and initialized")
        }
    }
    
    /// Get the next question from the questionnaire
    /// - Returns: The next question as a JSON string if available, nil if no more questions
    static func getNextQuestion(phoneNumber: String, logger: Logger) async -> String? {
        if await questionManager.isEmpty() {
            await initializeQuestions(phoneNumber: phoneNumber, logger: logger)
        }
        do {
            guard let questionJSON = try await questionManager.getNextQuestionAsJSON(logger: logger) else {
                logger.error("No more questions available")
                return nil
            }
            return questionJSON
        } catch {
            logger.error("Failed to process next question")
            return nil
        }
    }
    
    /// Load the questionnaire from the file
    /// - Returns: The FHIR `Questionnaire` object loaded from the JSON file
    private static func loadQuestionnaire(logger: Logger) -> Questionnaire? {
        guard let path = Bundle.module.path(forResource: "kccq12", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            logger.info("Could not read data from kccq12 file")
            return nil
        }
        
        do {
            let questionnaire = try JSONDecoder().decode(Questionnaire.self, from: data)
            logger.info("Successfully decoded questionnaire")
            return questionnaire
        } catch {
            logger.error("Failed to decode questionnaire: \(error)")
            if let dataString = String(data: data, encoding: .utf8) {
                logger.debug("Raw JSON data: \(dataString)")
            }
            return nil
        }
    }
    
    /// Load the questionnaire response from the file
    /// - Returns: The FHIR `QuestionnaireResponse` object loaded from the JSON file
    static func loadQuestionnaireResponse(phoneNumber: String, logger: Logger) -> QuestionnaireResponse {
        logger.info("Loading questionnaire response from file")
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: FileService.kccq12FilePath(phoneNumber: phoneNumber)) else {
            let questionnaireResponse = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.completed))
            questionnaireResponse.subject = .init(reference: FHIRPrimitive(FHIRString(phoneNumber)))
            return questionnaireResponse
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: FileService.kccq12FilePath(phoneNumber: phoneNumber)))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(QuestionnaireResponse.self, from: data)
        } catch {
            let questionnaireResponse = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.completed))
            questionnaireResponse.subject = .init(reference: FHIRPrimitive(FHIRString(phoneNumber)))
            return questionnaireResponse
        }
    }
    
    /// Save or update a response to a question to the file
    /// - Parameters:
    ///   - linkId: The question's identifier
    ///   - code: The answer code
    /// - Returns: The FHIR `QuestionnaireResponse` object loaded from the JSON file
    static func saveQuestionnaireResponse(linkId: String, code: String, phoneNumber: String, logger: Logger) async -> Bool {
        do {
            logger.info("Attempting to save questionnaire response for linkId: \(linkId) with code: \(code)")
            
            let response = loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
            
            // Create or update the answer for the given linkId
            let responseItem = QuestionnaireResponseItem(linkId: FHIRPrimitive(FHIRString(linkId)))
            let answerItem = QuestionnaireResponseItemAnswer()
            answerItem.value = .string(FHIRPrimitive(FHIRString(code)))
            responseItem.answer = [answerItem]
            
            if let index = response.item?.firstIndex(where: { $0.linkId.value?.string == linkId }) {
                response.item?[index] = responseItem
                logger.info("Updated existing response for linkId: \(linkId)")
            } else {
                if response.item != nil {
                    response.item?.append(responseItem)
                } else {
                    response.item = [responseItem]
                }
                logger.info("Added new response for linkId: \(linkId)")
            }
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let jsonData = try encoder.encode(response)
            try jsonData.write(to: URL(fileURLWithPath: FileService.kccq12FilePath(phoneNumber: phoneNumber)))
            
            await questionManager.removeRemainingQuestion(linkId: linkId)
            
            logger.info("Successfully saved questionnaire response to \(FileService.kccq12FilePath(phoneNumber: phoneNumber))")
            return true
        } catch {
            logger.error("Failed to save questionnaire response: \(error)")
            return false
        }
    }

    /// Count the number of answered questions
    /// - Parameters:
    ///   - phoneNumber: The phone number of the caller
    ///   - logger: The logger to use for logging
    /// - Returns: The number of answered questions
    static func countAnsweredQuestions(phoneNumber: String, logger: Logger) -> Int {
        let response = loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
        return response.item?.count ?? 0
    }
}
