//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4
import Vapor


/// Service for generating feedback based on the patient's data (vitals, symptom score, condition change)
@MainActor
class FeedbackService {
    struct VitalSigns {
        let systolicBP: Int
        let diastolicBP: Int
        let heartRate: Int
    }
    
    private let phoneNumber: String
    private let logger: Logger
    private let vitalSignsService: VitalSignsService
    private let kccq12Service: KCCQ12Service
    private let q17Service: Q17Service
    
    init(
        phoneNumber: String,
        logger: Logger,
        vitalSignsService: VitalSignsService,
        kccq12Service: KCCQ12Service,
        q17Service: Q17Service
    ) {
        self.phoneNumber = phoneNumber
        self.logger = logger
        self.vitalSignsService = vitalSignsService
        self.kccq12Service = kccq12Service
        self.q17Service = q17Service
    }
    
    func feedback() async -> String? {
        let vitalSigns = await loadVitalSignsFromFile()
        let symptomScore = await loadSymptomScoreFromFile()
        let conditionChange = await loadConditionChangeFromFile()
        guard let vitalSigns, let symptomScore, let conditionChange else {
            return nil
        }
        let patientData = PatientData(
            systolicBP: vitalSigns.systolicBP,
            diastolicBP: vitalSigns.diastolicBP,
            heartRate: vitalSigns.heartRate,
            symptomScore: symptomScore,
            conditionChange: conditionChange
        )
        let patientDataMap: [String: String] = [
            "bp": patientData.bloodPressureCategory.rawValue,
            "heartRate": patientData.pulseCategory.rawValue,
            "symptomScore": patientData.symptomScoreCategory.rawValue,
            "conditionChange": conditionChange.rawValue
        ]
        let tree = FeedbackDecisionTreeBuilder.buildTree(data: patientData)
        return tree.decide(data: patientDataMap)
    }
    
    private func getAnswerValue(_ item: QuestionnaireResponseItemAnswer) -> Int? {
        guard let value = item.value else {
            return nil
        }
        switch value {
        case .integer(let integerValue):
            return Int(integerValue.value?.integer ?? 0)
        case .string(let stringValue):
            return Int(stringValue.value?.string ?? "")
        default:
            return nil
        }
    }
    
    private func loadVitalSignsFromFile() async -> VitalSigns? {
        let questionnaireResponse = vitalSignsService.storage.loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
        var vitalSigns: [String: Int] = [:]
        for item in questionnaireResponse.item ?? [] {
            guard let linkId = item.linkId.value?.string,
                  let answer = item.answer?.first,
                  let value = getAnswerValue(answer) else {
                continue
            }
            
            vitalSigns[linkId] = value
        }
        guard let systolicBP = vitalSigns["systolic"],
              let diastolicBP = vitalSigns["diastolic"],
              let heartRate = vitalSigns["heart-rate"],
              systolicBP > 0, diastolicBP > 0, heartRate > 0 else {
            return nil
        }
        return VitalSigns(systolicBP: systolicBP, diastolicBP: diastolicBP, heartRate: heartRate)
    }
    
    private func loadSymptomScoreFromFile() async -> Double? {
        await kccq12Service.computeSymptomScore()
    }
    
    private func loadConditionChangeFromFile() async -> PatientData.ConditionChange? {
        let questionnaireResponse = q17Service.storage.loadQuestionnaireResponse(phoneNumber: phoneNumber, logger: logger)
        let conditionChange = questionnaireResponse.item?.first?.answer?.first
        if let conditionChange = conditionChange {
            if let value = getAnswerValue(conditionChange) {
                return PatientData.ConditionChange.categorize(condition: value)
            }
        }
        return nil
    }
}
