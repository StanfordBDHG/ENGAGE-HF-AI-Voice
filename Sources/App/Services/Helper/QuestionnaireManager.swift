//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4
import ToonFormat
import Vapor


/// Errors that can occur during questionnaire management
enum QuestionnaireManagerError: Error {
    case unsupportedAnswerType
}

/// A generalized questionnaire manager that handles the state and progression of answering a questionnaire.
/// It maintains an internal FHIR questionnaire response that is populated as answers are provided.
@MainActor
class QuestionnaireManager: Sendable {
    // MARK: - Constants
    
    private static let noteExtensionURL = "http://bdh.stanford.edu/fhir/StructureDefinition/note"
    private static let minValueURL = "http://hl7.org/fhir/StructureDefinition/minValue"
    private static let maxValueURL = "http://hl7.org/fhir/StructureDefinition/maxValue"
    
    // MARK: - Properties
    
    /// The questionnaire being managed
    private let questionnaire: Questionnaire
    
    private let sharesAllQuestionsIfNeeded: Bool
    
    /// The current questionnaire response being built
    private var response: QuestionnaireResponse
    
    /// Mapping from [linkId: [descriptiveCode: originalNumericCode]] for resolving descriptive answer codes
    private var codeMapping: [String: [String: String]] = [:]
    
    /// Whether all required questions have been answered
    private(set) var isFinished: Bool = false
    
    // MARK: - Initializer
    
    /// Initialize a new questionnaire manager
    /// - Parameters:
    ///   - questionnaire: The FHIR questionnaire to manage
    ///   - initialResponse: Optional initial response to start from
    init(questionnaire: Questionnaire?, sharesAllQuestionsIfNeeded: Bool, initialResponse: QuestionnaireResponse? = nil) {
        self.sharesAllQuestionsIfNeeded = sharesAllQuestionsIfNeeded
        guard let questionnaire else {
            fatalError("QuestionnaireManager initialized with nil questionnaire")
        }
        self.questionnaire = questionnaire
        
        if let initialResponse = initialResponse {
            self.response = initialResponse
        } else {
            self.response = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.inProgress))
        }
        
        // Build code mapping for all questions upfront so descriptive codes can be resolved when answers arrive
        let allQuestions = getAllQuestions(from: questionnaire.item ?? [])
        for question in allQuestions {
            buildCodeMapping(for: question)
        }
        
        updateFinishedState()
    }
    
    // MARK: - Type Methods
    
    /// Extract a note string from a FHIR extension array matching the note URL
    private static func extractNote(from extensions: [ModelsR4.Extension]) -> String? {
        extensions
            .first { ext in
                ext.url.value?.url.absoluteString == noteExtensionURL
            }
            .flatMap { ext in
                if case .string(let str) = ext.value {
                    return str.value?.string
                }
                return nil
            }
    }
    
    /// Generate a descriptive, URL-safe code from a display string
    /// e.g. "Extremely Limited" -> "extremely-limited"
    private static func descriptiveCode(from display: String) -> String {
        display.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
    
    // MARK: - Instance Methods
    
    /// Get the next unanswered question
    /// - Returns: The next question to be answered in JSON string format, or nil if all required questions are answered
    func getNextQuestionString(includeAllQuestions: Bool) -> String? {
        let nextQuestion = getNextQuestion(includeAllQuestions: includeAllQuestions)
        guard let nextQuestion else {
            return nil
        }
        let encoder = TOONEncoder()
        if let data = try? encoder.encode(nextQuestion), let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return nil
    }
    
    private func getNextQuestion(includeAllQuestions: Bool) -> QuestionWithProgress? {
        let questions = getAllQuestions(from: questionnaire.item ?? [])
        
        let answeredLinkIds = Set(response.item?.compactMap { $0.linkId.value?.string } ?? [])
        
        // Find first required question that hasn't been answered
        let nextQuestion = questions.first { question in
            guard let linkId = question.linkId.value?.string else {
                return false
            }
            return question.required?.value?.bool ?? false && !answeredLinkIds.contains(linkId)
        } ?? questions.first { question in
            // If no required questions left, return first unanswered optional question
            guard let linkId = question.linkId.value?.string else {
                return false
            }
            return !answeredLinkIds.contains(linkId)
        }
        
        guard let nextQuestion = nextQuestion else {
            return nil
        }
        
        // Calculate progress
        let totalQuestions = questions.count
        let answeredCount = answeredLinkIds.count
        let progress = "\(answeredCount + 1) of \(totalQuestions)"
        
        let allQuestions: [SimplifiedQuestion]
        
        if sharesAllQuestionsIfNeeded && includeAllQuestions {
            allQuestions = questions
                .filter { question in
                    guard let linkId = question.linkId.value?.string else {
                        return false
                    }
                    return !answeredLinkIds.contains(linkId)
                }
                .map { simplify($0) }
        } else {
            allQuestions = []
        }
        
        return QuestionWithProgress(
            question: simplify(nextQuestion),
            progress: progress,
            allQuestions: allQuestions.isEmpty ? nil : allQuestions
        )
    }
    
    /// Answer a question in the questionnaire
    /// - Parameters:
    ///   - linkId: The linkId of the question being answered
    ///   - answer: The answer value (String or Int)
    /// - Throws: QuestionnaireManagerError if answer type is unsupported
    func answerQuestion<T>(linkId: String, answer: T) throws {
        // Create response item
        let responseItem = QuestionnaireResponseItem(linkId: FHIRPrimitive(FHIRString(linkId)))
        let answerItem = QuestionnaireResponseItemAnswer()
        
        // Set value based on type, resolving descriptive codes back to numeric codes for string answers
        switch answer {
        case let stringAnswer as String:
            let resolvedAnswer = resolveAnswer(linkId: linkId, answer: stringAnswer)
            answerItem.value = .string(FHIRPrimitive(FHIRString(resolvedAnswer)))
        case let intAnswer as Int:
            answerItem.value = .integer(FHIRPrimitive(FHIRInteger(FHIRInteger.IntegerLiteralType(intAnswer))))
        case _ as NSNull:
            answerItem.value = .none
        default:
            throw QuestionnaireManagerError.unsupportedAnswerType
        }
        
        responseItem.answer = [answerItem]
        
        // Update or add the answer
        if let index = response.item?.firstIndex(where: { $0.linkId.value?.string == linkId }) {
            response.item?[index] = responseItem
        } else {
            if response.item != nil {
                response.item?.append(responseItem)
            } else {
                response.item = [responseItem]
            }
        }
        
        updateFinishedState()
    }
    
    /// Get the current questionnaire response
    /// - Returns: The current FHIR QuestionnaireResponse
    func getCurrentResponse() -> QuestionnaireResponse {
        response
    }
    
    /// Count the number of answered questions
    /// - Returns: The number of answered questions
    func countAnsweredQuestions() -> Int {
        response.item?.count ?? 0
    }
        
    /// Recursively get all questions from a questionnaire
    private func getAllQuestions(from items: [QuestionnaireItem]) -> [QuestionnaireItem] {
        items.flatMap { item -> [QuestionnaireItem] in
            if let subItems = item.item {
                return getAllQuestions(from: subItems)
            } else if item.type.value?.rawValue != "display" {
                return [item]
            }
            return []
        }
    }
    
    // MARK: - Question Simplification
    
    /// Build and store the code mapping for a question's answer options
    private func buildCodeMapping(for item: QuestionnaireItem) {
        let linkId = item.linkId.value?.string ?? ""
        guard let options = item.answerOption else {
            return
        }
        
        var linkCodeMapping: [String: String] = [:]
        for option in options {
            guard case .coding(let coding) = option.value else { continue }
            let originalCode = coding.code?.value?.string ?? ""
            let display = coding.display?.value?.string ?? ""
            let descriptiveCode = Self.descriptiveCode(from: display)
            linkCodeMapping[descriptiveCode] = originalCode
        }
        
        if !linkCodeMapping.isEmpty {
            codeMapping[linkId] = linkCodeMapping
        }
    }
    
    /// Convert a FHIR QuestionnaireItem into a SimplifiedQuestion with inlined notes and descriptive codes
    private func simplify(_ item: QuestionnaireItem) -> SimplifiedQuestion {
        let linkId = item.linkId.value?.string ?? ""
        let type = item.type.value?.rawValue ?? ""
        let text = item.text?.value?.string ?? ""
        let required = item.required?.value?.bool ?? false
        
        // Extract note from item-level extensions
        let note = Self.extractNote(from: item.`extension` ?? [])
        
        // Process answer options for choice questions
        var answerOptions: [SimplifiedAnswerOption] = []
        if let options = item.answerOption {
            answerOptions = options.compactMap { option -> SimplifiedAnswerOption? in
                guard case .coding(let coding) = option.value else {
                    return nil
                }
                let display = coding.display?.value?.string ?? ""
                let descriptiveCode = Self.descriptiveCode(from: display)
                
                // Extract note from answer option extensions
                let optionNote = Self.extractNote(from: option.`extension` ?? [])
                
                return SimplifiedAnswerOption(code: descriptiveCode, display: display, note: optionNote)
            }
        }
        
        // Extract min/max values from extensions for integer types
        var minValue: Int?
        var maxValue: Int?
        if type == "integer", let extensions = item.`extension` {
            for ext in extensions {
                let url = ext.url.value?.url.absoluteString ?? ""
                if url == Self.minValueURL, case .integer(let val) = ext.value {
                    minValue = Int(val.value?.integer ?? 0)
                } else if url == Self.maxValueURL, case .integer(let val) = ext.value {
                    maxValue = Int(val.value?.integer ?? 0)
                }
            }
        }
        
        return SimplifiedQuestion(
            linkId: linkId,
            type: type,
            text: text,
            required: required,
            note: note,
            answerOptions: answerOptions,
            minValue: minValue,
            maxValue: maxValue
        )
    }
    
    /// Resolve a descriptive answer code back to the original numeric code
    /// If no mapping is found, the answer is returned as-is
    private func resolveAnswer(linkId: String, answer: String) -> String {
        if let mapping = codeMapping[linkId], let originalCode = mapping[answer] {
            return originalCode
        }
        return answer
    }
    
    /// Update the finished state based on required questions
    private func updateFinishedState() {
        let questions = getAllQuestions(from: questionnaire.item ?? [])
        let answeredLinkIds = Set(response.item?.compactMap { $0.linkId.value?.string } ?? [])
        
        // Check if all required questions are answered
        isFinished = questions.allSatisfy { question in
            guard let linkId = question.linkId.value?.string else {
                return true
            }
            return !(question.required?.value?.bool ?? false) || answeredLinkIds.contains(linkId)
        }
        
        response.status = FHIRPrimitive(isFinished ? QuestionnaireResponseStatus.completed : QuestionnaireResponseStatus.inProgress)
    }
}
