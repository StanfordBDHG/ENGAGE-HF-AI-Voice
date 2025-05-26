//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Patient struct that holds the relevant data used by the decision tree
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
        
        static func categorize(score: Double) -> SymptomScoreCategory {
            score <= 80 ? .severe : .mild
        }
    }
    
    enum ConditionChange: String {
        case worse
        case same
        case better
        
        static func categorize(condition: Int) -> ConditionChange {
            switch condition {
            case 1:
                return .worse
            case 2:
                return .worse
            case 3:
                return .same
            case 4:
                return .better
            default:
                return .better
            }
        }
    }
    
    struct Feedback {
        let vitals: String
        let survey: String
    }
    
    let systolicBP: Int
    let diastolicBP: Int
    let heartRate: Int
    let symptomScore: Double
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
