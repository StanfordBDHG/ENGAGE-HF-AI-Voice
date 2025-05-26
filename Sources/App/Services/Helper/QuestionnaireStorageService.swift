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


/// Generic service for managing questionnaire data storage
@MainActor
class QuestionnaireStorageService {
    typealias FilePathClosure = @Sendable (String) -> String
    
    private let questionManager: QuestionManager
    private let questionnaireName: String
    private let filePath: FilePathClosure
    private let directoryPath: String
    
    init(questionnaireName: String, filePath: @escaping FilePathClosure, directoryPath: String) {
        self.questionnaireName = questionnaireName
        self.filePath = filePath
        self.directoryPath = directoryPath
        self.questionManager = QuestionManager(questionnaireResponseLoader: DefaultQuestionnaireResponseLoader(filePath: filePath))
    }
    
    func setQuestionnaireResponseLoader(_ loader: QuestionnaireResponseLoader) async {
        await questionManager.setQuestionnaireResponseLoader(loader)
    }
    
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
            let questionnaireResponse = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.completed))
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
    
    func initializeQuestions(phoneNumber: String, logger: Logger) async {
        if let questionnaire = loadQuestionnaire(logger: logger) {
            await questionManager.initializeQuestions(questionnaire.item ?? [], phoneNumber: phoneNumber, logger: logger)
        } else {
            logger.info("Questions could not be loaded and initialized")
        }
    }
    
    func getNextQuestion(phoneNumber: String, logger: Logger) async -> String? {
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
    
    private func loadQuestionnaire(logger: Logger) -> Questionnaire? {
        guard let path = Bundle.module.path(forResource: questionnaireName, ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            logger.info("Could not read data from \(questionnaireName) file")
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
    
    func loadQuestionnaireResponse(phoneNumber: String, logger: Logger) async -> QuestionnaireResponse {
        await questionManager.loadQuestionnaireResponse(phoneNumber, logger)
    }
    
    func saveQuestionnaireResponse<T>(linkId: String, answer: T, phoneNumber: String, logger: Logger) async -> Bool {
        do {
            logger.info("Attempting to save questionnaire response for linkId: \(linkId) with answer: \(answer)")
            
            let response = await loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
            
            // Create or update the answer for the given linkId
            let responseItem = QuestionnaireResponseItem(linkId: FHIRPrimitive(FHIRString(linkId)))
            let answerItem = QuestionnaireResponseItemAnswer()
            
            // Set the value based on the generic type
            switch answer {
            case let stringAnswer as String:
                answerItem.value = .string(FHIRPrimitive(FHIRString(stringAnswer)))
            case let intAnswer as Int:
                answerItem.value = .integer(FHIRPrimitive(FHIRInteger(FHIRInteger.IntegerLiteralType(intAnswer))))
            default:
                logger.error("Unsupported answer type: \(type(of: answer))")
                return false
            }
            
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
            try jsonData.write(to: URL(fileURLWithPath: filePath(phoneNumber)))
            
            await questionManager.removeRemainingQuestion(linkId: linkId)
            
            logger.info("Successfully saved questionnaire response to \(filePath(phoneNumber))")
            return true
        } catch {
            logger.error("Failed to save questionnaire response: \(error)")
            return false
        }
    }
    
    func countAnsweredQuestions(phoneNumber: String, logger: Logger) async -> Int {
        let response = await questionManager.loadQuestionnaireResponse(phoneNumber, logger)
        return response.item?.count ?? 0
    }
}
