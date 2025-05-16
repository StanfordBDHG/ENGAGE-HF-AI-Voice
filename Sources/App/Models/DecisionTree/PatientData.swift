//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

struct PatientData {
    enum BloodPressureCategory: String {
        case low
        case normal
        case high
        
        static func categorize(systolic: Int, diastolic: Int) -> BloodPressureCategory {
            if systolic < 100 || diastolic < 60 {
                return .low
            } else if systolic > 130 || diastolic > 80 {
                return .high
            } else {
                return .normal
            }
        }
    }
    
    enum HeartRateCategory: String {
        case low
        case normal
        case high
        
        static func categorize(heartRate: Int) -> HeartRateCategory {
            if heartRate < 50 {
                return .low
            } else if heartRate > 100 {
                return .high
            } else {
                return .normal
            }
        }
    }
    
    enum SymptomScoreCategory: String {
        case severe
        case mild
        
        static func categorize(score: Int) -> SymptomScoreCategory {
            score <= 80 ? .severe : .mild
        }
    }
    
    enum ConditionChange: String {
        case worse
        case same
        case better
    }
    
    struct Feedback {
        let vitals: String
        let survey: String
    }
    
    let systolicBP: Int
    let diastolicBP: Int
    let heartRate: Int
    let symptomScore: Int
    let conditionChange: ConditionChange
    
    var bloodPressureCategory: BloodPressureCategory {
        BloodPressureCategory.categorize(systolic: systolicBP, diastolic: diastolicBP)
    }
    
    var pulseCategory: HeartRateCategory {
        HeartRateCategory.categorize(heartRate: heartRate)
    }
    
    var symptomScoreCategory: SymptomScoreCategory {
        SymptomScoreCategory.categorize(score: symptomScore)
    }
}
