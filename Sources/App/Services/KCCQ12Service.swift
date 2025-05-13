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

/// Protocol for loading questionnaire responses
protocol QuestionnaireResponseLoader: Sendable {
    func loadQuestionnaireResponse(phoneNumber: String, logger: Logger) async -> QuestionnaireResponse
}

/// Default implementation of QuestionnaireResponseLoader
private struct DefaultQuestionnaireResponseLoader: QuestionnaireResponseLoader {
    func loadQuestionnaireResponse(phoneNumber: String, logger: Logger) async -> QuestionnaireResponse {
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
}

/// Actor to manage concurrent access to questions
private actor QuestionManager {
    var remainingQuestions: [QuestionnaireItem] = []
    var totalQuestions: Int = 0
    var questionnaireResponseLoader: QuestionnaireResponseLoader = DefaultQuestionnaireResponseLoader()
    
    
    func initializeQuestions(_ questions: [QuestionnaireItem], phoneNumber: String, logger: Logger) async {
        let items = flattenQuestionnaireItems(questions)
        let answeredQuestionLinkIds = await questionnaireResponseLoader
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
    
    func setQuestionnaireResponseLoader(_ loader: QuestionnaireResponseLoader) {
        questionnaireResponseLoader = loader
    }
    
    func loadQuestionnaireResponse(_ phoneNumber: String, _ logger: Logger) async -> QuestionnaireResponse {
        await questionnaireResponseLoader.loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
    }
}

/// Service for managing KCCQ12 data storage
enum KCCQ12Service {
    private static let questionManager = QuestionManager()

    static func setQuestionnaireResponseLoader(_ loader: QuestionnaireResponseLoader) async {
        await KCCQ12Service.questionManager.setQuestionnaireResponseLoader(loader)
    }
    
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
    static func loadQuestionnaireResponse(phoneNumber: String, logger: Logger) async -> QuestionnaireResponse {
        await questionManager.loadQuestionnaireResponse(phoneNumber, logger)
    }
    
    /// Save or update a response to a question to the file
    /// - Parameters:
    ///   - linkId: The question's identifier
    ///   - code: The answer code
    /// - Returns: The FHIR `QuestionnaireResponse` object loaded from the JSON file
    static func saveQuestionnaireResponse(linkId: String, code: String, phoneNumber: String, logger: Logger) async -> Bool {
        do {
            logger.info("Attempting to save questionnaire response for linkId: \(linkId) with code: \(code)")
            
            let response = await loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
            
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
    static func countAnsweredQuestions(phoneNumber: String, logger: Logger) async -> Int {
        let response = await questionManager.loadQuestionnaireResponse(phoneNumber, logger)
        return response.item?.count ?? 0
    }

    /// Compute the symptom score from the KCCQ12 questionnaire responses
    /// - Parameters:
    ///   - phoneNumber: The phone number of the caller
    ///   - logger: The logger to use for logging
    /// - Returns: The overall symptom score value
    static func computeSymptomScore(phoneNumber: String, logger: Logger) async -> Double {
        let response = await questionManager.loadQuestionnaireResponse(phoneNumber, logger)
        
        guard let response = response.item else {
            return 0
        }
        
        let physicalLimitsScore = calculatePhysicalLimitsScore(response)
        let symptomFrequencyScore = calculateSymptomFrequencyScore(response)
        let qualityOfLifeScore = calculateQualityOfLifeScore(response)
        let socialLimitsScore = calculateSocialLimitsScore(response)
        
        var domainScores: [Double] = []
        if let score = physicalLimitsScore { domainScores.append(score) }
        if let score = symptomFrequencyScore { domainScores.append(score) }
        if let score = qualityOfLifeScore { domainScores.append(score) }
        if let score = socialLimitsScore { domainScores.append(score) }
        
        return self.average(domainScores) ?? 0
    }
    
    private static func calculatePhysicalLimitsScore(_ response: [QuestionnaireResponseItem]) -> Double? {
        let physicalLinkIds = [
            "a459b804-35bf-4792-f1eb-0b52c4e176e1",
            "cf9c5031-1ed5-438a-fc7d-dc69234015a0",
            "1fad0f81-b2a9-4c8f-9a78-4b2a5d7aef07"
        ]
        let physicalLimitsAnswers = response.filter { physicalLinkIds.contains($0.linkId.value?.string ?? "") }
            .filter { $0.answer?.first?.value != QuestionnaireResponseItemAnswer(value: .string("6")).value }
            .map { item in
                guard let value = item.answer?.first?.value,
                      case .string(let stringValue) = value,
                      let intValue = Int(stringValue.value?.string ?? "") else {
                    return 0.0
                }
                return (100.0 * Double(intValue - 1)) / 4.0
            }
        return physicalLimitsAnswers.count >= 2 ? self.average(physicalLimitsAnswers) : nil
    }
    
    private static func calculateSymptomFrequencyScore(_ response: [QuestionnaireResponseItem]) -> Double? {
        let linkIds = [
            "692bda7d-a616-43d1-8dc6-8291f6460ab2",
            "b1734b9e-1d16-4238-8556-5ae3fa0ba913",
            "57f37fb3-a0ad-4b1f-844e-3f67d9b76946",
            "396164df-d045-4c56-d710-513297bdc6f2"
        ]
        let answers = linkIds.compactMap { linkId in
            response.first(where: { $0.linkId.value?.string == linkId }).flatMap(getAnswerValue)
        }
        guard answers.count == 4 else {
            return nil
        }
        
        let scores = [
            Double(answers[0] - 1) / 4.0,
            Double(answers[1] - 1) / 6.0,
            Double(answers[2] - 1) / 6.0,
            Double(answers[3] - 1) / 4.0
        ].map { $0 * 100.0 }
        return self.average(scores)
    }
    
    private static func calculateQualityOfLifeScore(_ response: [QuestionnaireResponseItem]) -> Double? {
        let linkIds = [
            "75e3f62e-e37d-48a2-f4d9-af2db8922da0",
            "fce3a16e-c6d8-4bac-8ab5-8f4aee4adc08"
        ]
        let answers = linkIds.compactMap { linkId in
            response.first(where: { $0.linkId.value?.string == linkId }).flatMap(getAnswerValue)
        }
        guard answers.count == 2 else {
            return nil
        }
        
        let scores = answers.map { (100.0 * Double($0 - 1)) / 4.0 }
        return self.average(scores)
    }
    
    private static func calculateSocialLimitsScore(_ response: [QuestionnaireResponseItem]) -> Double? {
        let linkIds = [
            "8649bc8c-f908-487d-87a4-a97106b1a4c3",
            "1eee7259-da1c-4cba-80a9-e67e684573a1",
            "883a22a8-2f6e-4b41-84b7-0028ed543192"
        ]
        let answers = linkIds.compactMap { linkId in
            response.first(where: { $0.linkId.value?.string == linkId }).flatMap(getAnswerValue)
        }
        guard answers.count == 3 else {
            return nil
        }
        
        let scores = answers.filter { $0 != 6 }.map { (100.0 * Double($0 - 1)) / 4.0 }
        return scores.count >= 2 ? self.average(scores) : nil
    }

    // Helper function for calculating average
    private static func average(_ numbers: [Double]) -> Double? {
        guard !numbers.isEmpty else {
            return nil
        }
        let sum = numbers.reduce(0, +)
        return sum / Double(numbers.count)
    }
    
    private static func getAnswerValue(_ item: QuestionnaireResponseItem) -> Int? {
        guard let value = item.answer?.first?.value,
              case .string(let stringValue) = value,
              let intValue = Int(stringValue.value?.string ?? "") else {
            return nil
        }
        return intValue
    }
}

extension QuestionnaireResponse: @unchecked @retroactive Sendable {}
