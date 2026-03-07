//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4
import Vapor

/// ENGAGE-HF-specific feedback generation from completed questionnaire engines.
///
/// Reads vital signs, KCCQ-12 scores, and condition change from the engines,
/// then generates personalized feedback using the decision tree.
struct EngageHFFeedbackProvider: FeedbackProvider {
    @MainActor
    func feedback(from engines: [FHIRQuestionnaireEngine]) async -> String? {
        let vitalSigns = Self.loadVitalSigns(from: engines)
        let symptomScore = Self.loadSymptomScore(from: engines)
        let conditionChange = Self.loadConditionChange(from: engines)

        guard let vitalSigns, let symptomScore, let conditionChange else {
            return nil
        }

        let data = PatientData(
            systolicBP: vitalSigns.systolicBP,
            diastolicBP: vitalSigns.diastolicBP,
            heartRate: vitalSigns.heartRate,
            symptomScore: symptomScore,
            conditionChange: conditionChange
        )
        let dataMap: [String: String] = [
            "bp": data.bloodPressureCategory.rawValue,
            "heartRate": data.pulseCategory.rawValue,
            "symptomScore": data.symptomScoreCategory.rawValue,
            "conditionChange": conditionChange.rawValue
        ]
        return FeedbackDecisionTreeBuilder.buildTree(data: data).decide(data: dataMap)
    }

    // MARK: - Vital Signs

    private struct VitalSigns {
        let systolicBP: Int
        let diastolicBP: Int
        let heartRate: Int
    }

    @MainActor
    private static func loadVitalSigns(from engines: [FHIRQuestionnaireEngine]) -> VitalSigns? {
        guard let engine = engines.first(where: { $0.section is VitalSignsSection }) else {
            return nil
        }
        let items = engine.currentResponse().item ?? []
        var values: [String: Int] = [:]
        for item in items {
            guard let linkId = item.linkId.value?.string,
                let value = item.answer?.first?.integerAnswerValue()
            else {
                continue
            }
            values[linkId] = value
        }
        guard let systolic = values["systolic"], systolic > 0,
            let diastolic = values["diastolic"], diastolic > 0,
            let heartRate = values["heart-rate"], heartRate > 0
        else {
            return nil
        }
        return VitalSigns(systolicBP: systolic, diastolicBP: diastolic, heartRate: heartRate)
    }

    // MARK: - Symptom Score

    @MainActor
    private static func loadSymptomScore(from engines: [FHIRQuestionnaireEngine]) -> Double? {
        guard let engine = engines.first(where: { $0.section is KCCQ12Section }) else {
            return nil
        }
        let items = engine.currentResponse().item ?? []
        return KCCQ12ScoreCalculator.computeSymptomScore(from: items)
    }

    // MARK: - Condition Change

    @MainActor
    private static func loadConditionChange(
        from engines: [FHIRQuestionnaireEngine]
    ) -> PatientData.ConditionChange? {
        guard let engine = engines.first(where: { $0.section is Q17Section }) else {
            return nil
        }
        let items = engine.currentResponse().item ?? []
        guard let answer = items.first?.answer?.first,
            let value = answer.integerAnswerValue()
        else {
            return nil
        }
        return PatientData.ConditionChange.categorize(condition: value)
    }
}
