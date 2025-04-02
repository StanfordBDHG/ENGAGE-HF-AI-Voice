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


// Add a struct to wrap the question and progress
struct QuestionWithProgress: Codable {
    let question: QuestionnaireItem
    let progress: String
    
    enum CodingKeys: String, CodingKey {
        case question, progress
    }
}

/// Actor to manage concurrent access to questions
private actor QuestionManager {
    var remainingQuestions: [QuestionnaireItem] = []
    var totalQuestions: Int = 0
    
    
    func initializeQuestions(_ questions: [QuestionnaireItem], logger: Logger) {
        let items = flattenQuestionnaireItems(questions)
        totalQuestions = items.count
        logger.info("Initializing remaining questions array with \(totalQuestions) questions")
        remainingQuestions = items
    }
    
    func getNextQuestionAsJSON(logger: Logger) async throws -> String? {
        guard !remainingQuestions.isEmpty else { return nil }
        logger.info("remainingQuestions: \(remainingQuestions.count)")
        logger.info("\(remainingQuestions.map { $0.linkId })")
        let nextQuestion = remainingQuestions.removeFirst()
        
        let currentQuestion = totalQuestions - remainingQuestions.count
        let progressString = "Question \(currentQuestion) of \(totalQuestions)"

        let questionWithProgress = QuestionWithProgress(question: nextQuestion, progress: progressString)
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(questionWithProgress)
        
        return String(data: jsonData, encoding: .utf8)
    }
    
    func getCurrentCount() -> Int {
        remainingQuestions.count
    }
    
    func isEmpty() -> Bool {
        remainingQuestions.isEmpty
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
class KCCQ12Service {
    private static let dataDirectory: String = {
        let fileManager = FileManager.default
        let currentDirectoryPath = fileManager.currentDirectoryPath
        return "\(currentDirectoryPath)/Data"
    }()
    
    private static let kccq12FilePath: String = {
        return "\(dataDirectory)/kccq12.json"
    }()
    
    private static let questionManager = QuestionManager()
    
    /// Initialize the questions from the KCCQ12 file
    static func initializeQuestions(logger: Logger) async {
        if let questionnaire = loadQuestionnaire(logger: logger) {
            await questionManager.initializeQuestions(questionnaire.item ?? [], logger: logger)
        } else {
            logger.info("Questions could not be loaded and initialized")
        }
    }
    
    /// Get the next question from the questionnaire
    /// - Returns: The next question as a JSON string if available, nil if no more questions
    static func getNextQuestion(logger: Logger) async -> String? {
        if await questionManager.isEmpty() {
            await initializeQuestions(logger: logger)
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
    
    /// Creates a QestionnaireResponse object
    /// - Parameters:
    ///   - answers: A answers dictionary including the answers with questionIDs and answerIds as key/value pairs
    ///   - logger: The logger to use for logging
    /// - Returns: A QuestionnaireResponse object
    static func createQuestionnaireResponse(answers: [String: String], logger: Logger) -> QuestionnaireResponse? {
        logger.info("Creating QuestionnaireResponse with \(answers.count) answers")
        
        let response = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.completed))
        response.authored = FHIRPrimitive(stringLiteral: Date().ISO8601Format())
        
        var items: [QuestionnaireResponseItem] = []
        
        for (linkId, answerValue) in answers {
            let responseItem = QuestionnaireResponseItem(linkId: FHIRPrimitive(FHIRString(linkId)))
            let answerItem = QuestionnaireResponseItemAnswer()
            answerItem.value = .string(FHIRPrimitive(FHIRString(answerValue)))
            responseItem.answer = [answerItem]
            
            items.append(responseItem)
        }
        response.item = items
        
        logger.info("Successfully created QuestionnaireResponse with \(items.count) items")
        return response
    }
    
    /// Saves a QestionnaireResponse object to the KCCQ12 data file
    /// - Parameters:
    ///   - response: The QuestionnaireResponse object that can be generated using `createQuestionnaireResponse`
    ///   - logger: The logger to use for logging
    /// - Returns: A boolean indicating whether the save was successful
    static func saveQuestionnaireResponse(_ response: QuestionnaireResponse, logger: Logger) throws -> Bool {
        logger.info("Saving KCCQ-12 questionnaire response")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let jsonData = try encoder.encode(response)
        logger.info("\(jsonData.debugDescription)")
        
        try jsonData.write(to: URL(fileURLWithPath: kccq12FilePath))
        
        logger.info("Successfully saved questionnaire data to \(kccq12FilePath)")
        return true
    }
}

