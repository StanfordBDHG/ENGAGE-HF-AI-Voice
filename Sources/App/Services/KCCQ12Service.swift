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


/// Service for managing KCCQ12 questionnaire
@MainActor
class KCCQ12Service: BaseQuestionnaireService, Sendable {
    init(phoneNumber: String, logger: Logger, encryptionKey: String? = nil) {
        super.init(
            questionnaireName: "kccq12",
            directoryPath: Constants.kccq12DirectoryPath,
            phoneNumber: phoneNumber,
            logger: logger,
            encryptionKey: encryptionKey
        )
    }

    /// Compute the symptom score from the KCCQ12 questionnaire responses
    /// - Parameters:
    ///   - phoneNumber: The phone number of the caller
    ///   - logger: The logger to use for logging
    /// - Returns: The overall symptom score value
    func computeSymptomScore() async -> Double? {
        let response = storage.loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
        
        guard let response = response.item else {
            return nil
        }
        
        let physicalLimitsScore = calculatePhysicalLimitsScore(response)
        let symptomFrequencyScore = calculateSymptomFrequencyScore(response)
        let qualityOfLifeScore = calculateQualityOfLifeScore(response)
        let socialLimitsScore = calculateSocialLimitsScore(response)
        
        var domainScores: [Double] = []
        if let score = physicalLimitsScore {
            domainScores.append(score)
        }
        if let score = symptomFrequencyScore {
            domainScores.append(score)
        }
        if let score = qualityOfLifeScore {
            domainScores.append(score)
        }
        if let score = socialLimitsScore {
            domainScores.append(score)
        }
        
        return self.average(domainScores)
    }
    
    private func calculatePhysicalLimitsScore(_ response: [QuestionnaireResponseItem]) -> Double? {
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
    
    private func calculateSymptomFrequencyScore(_ response: [QuestionnaireResponseItem]) -> Double? {
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
    
    private func calculateQualityOfLifeScore(_ response: [QuestionnaireResponseItem]) -> Double? {
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
    
    private func calculateSocialLimitsScore(_ response: [QuestionnaireResponseItem]) -> Double? {
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

    private func average(_ numbers: [Double]) -> Double? {
        guard !numbers.isEmpty else {
            return nil
        }
        let sum = numbers.reduce(0, +)
        return sum / Double(numbers.count)
    }
    
    private nonisolated func getAnswerValue(_ item: QuestionnaireResponseItem) -> Int? {
        guard let value = item.answer?.first?.value,
              case .string(let stringValue) = value,
              let intValue = Int(stringValue.value?.string ?? "") else {
            return nil
        }
        return intValue
    }
}
