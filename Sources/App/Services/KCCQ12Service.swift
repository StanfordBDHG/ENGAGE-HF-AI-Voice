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

    /// Load questions from the KCCQ12 file
    /// - Returns: A string in JSON format
    static func getQuestions() -> String {
        guard let path = Bundle.module.path(forResource: "kccq12", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return jsonString
    }
    
    private static func loadQuestionnaire() -> Questionnaire? {
        guard let path = Bundle.module.path(forResource: "kccq12", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        
        return try? JSONDecoder().decode(Questionnaire.self, from: data)
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
