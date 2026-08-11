//
// This source file is part of the ENGAGE-HF AI-Voice open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4

/// Computes the KCCQ-12 symptom score from a completed FHIR QuestionnaireResponse.
///
/// This is a pure calculation utility with no state — it operates on a snapshot
/// of the response items and returns the overall score.
enum KCCQ12ScoreCalculator {
    static func computeSymptomScore(from items: [QuestionnaireResponseItem]) -> Double? {
        let physicalLimits = calculatePhysicalLimitsScore(items)
        let symptomFrequency = calculateSymptomFrequencyScore(items)
        let qualityOfLife = calculateQualityOfLifeScore(items)
        let socialLimits = calculateSocialLimitsScore(items)

        var domainScores: [Double] = []
        if let score = physicalLimits { domainScores.append(score) }
        if let score = symptomFrequency { domainScores.append(score) }
        if let score = qualityOfLife { domainScores.append(score) }
        if let score = socialLimits { domainScores.append(score) }

        return average(domainScores)
    }

    // MARK: - Domain Scores

    private static func calculatePhysicalLimitsScore(
        _ items: [QuestionnaireResponseItem]
    ) -> Double? {
        let linkIds = [
            "a459b804-35bf-4792-f1eb-0b52c4e176e1",
            "cf9c5031-1ed5-438a-fc7d-dc69234015a0",
            "1fad0f81-b2a9-4c8f-9a78-4b2a5d7aef07"
        ]
        let answers =
            items
            .filter { linkIds.contains($0.linkId.value?.string ?? "") }
            .filter { $0.answer?.first?.integerAnswerValue() != 6 }
            .compactMap { item -> Double? in
                guard let value = item.answer?.first?.integerAnswerValue() else {
                    return nil
                }
                return (100.0 * Double(value - 1)) / 4.0
            }
        return answers.count >= 2 ? average(answers) : nil
    }

    private static func calculateSymptomFrequencyScore(
        _ items: [QuestionnaireResponseItem]
    ) -> Double? {
        let linkIds = [
            "692bda7d-a616-43d1-8dc6-8291f6460ab2",
            "b1734b9e-1d16-4238-8556-5ae3fa0ba913",
            "57f37fb3-a0ad-4b1f-844e-3f67d9b76946",
            "396164df-d045-4c56-d710-513297bdc6f2"
        ]
        let answers = linkIds.compactMap { linkId in
            items.first { $0.linkId.value?.string == linkId }
                .flatMap { $0.answer?.first?.integerAnswerValue() }
        }
        guard answers.count == 4 else {
            return nil
        }

        let denominators = [4.0, 6.0, 6.0, 4.0]
        let scores = zip(answers, denominators).map { answer, denom in
            (Double(answer - 1) / denom) * 100.0
        }
        return average(scores)
    }

    private static func calculateQualityOfLifeScore(
        _ items: [QuestionnaireResponseItem]
    ) -> Double? {
        let linkIds = [
            "75e3f62e-e37d-48a2-f4d9-af2db8922da0",
            "fce3a16e-c6d8-4bac-8ab5-8f4aee4adc08"
        ]
        let answers = linkIds.compactMap { linkId in
            items.first { $0.linkId.value?.string == linkId }
                .flatMap { $0.answer?.first?.integerAnswerValue() }
        }
        guard answers.count == 2 else {
            return nil
        }
        return average(answers.map { (100.0 * Double($0 - 1)) / 4.0 })
    }

    private static func calculateSocialLimitsScore(
        _ items: [QuestionnaireResponseItem]
    ) -> Double? {
        let linkIds = [
            "8649bc8c-f908-487d-87a4-a97106b1a4c3",
            "1eee7259-da1c-4cba-80a9-e67e684573a1",
            "883a22a8-2f6e-4b41-84b7-0028ed543192"
        ]
        let answers = linkIds.compactMap { linkId in
            items.first { $0.linkId.value?.string == linkId }
                .flatMap { $0.answer?.first?.integerAnswerValue() }
        }
        guard answers.count == 3 else {
            return nil
        }
        let scores = answers.filter { $0 != 6 }.map { (100.0 * Double($0 - 1)) / 4.0 }
        return scores.count >= 2 ? average(scores) : nil
    }

    // MARK: - Helpers

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }
}
