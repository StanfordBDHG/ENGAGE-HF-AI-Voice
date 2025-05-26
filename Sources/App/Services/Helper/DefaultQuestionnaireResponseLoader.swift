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


/// Default implementation of QuestionnaireResponseLoader
struct DefaultQuestionnaireResponseLoader: QuestionnaireResponseLoader {
    typealias FilePathClosure = @Sendable (String) -> String
    let filePath: FilePathClosure
    
    func loadQuestionnaireResponse(phoneNumber: String, logger: Logger) async -> QuestionnaireResponse {
        logger.info("Loading questionnaire response from file")
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: filePath(phoneNumber)) else {
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
            let questionnaireResponse = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.completed))
            questionnaireResponse.subject = .init(reference: FHIRPrimitive(FHIRString(phoneNumber)))
            return questionnaireResponse
        }
    }
}
