//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


// swiftlint:disable:next type_body_length
enum FeedbackService {
    static func feedback() -> String {
        // todo: load required questionnaire responses (q1, q2, symptom score, q17) istead of this mock
        let systolicBP = 180
        let diastolicBP = 100
        let heartRate = 60
        let symptomScore = 82
        let conditionChange: PatientData.ConditionChange = .worse
        
        let patientData = PatientData(
            systolicBP: systolicBP,
            diastolicBP: diastolicBP,
            heartRate: heartRate,
            symptomScore: symptomScore,
            conditionChange: conditionChange
        )
        
        let patientDataMap: [String: String] = [
            "bp": patientData.bloodPressureCategory.rawValue,
            "heartRate": patientData.pulseCategory.rawValue,
            "symptomScore": patientData.symptomScoreCategory.rawValue,
            "conditionChange": conditionChange.rawValue
        ]
        
        let tree = buildTree(data: patientData)
        
        return tree.decide(data: patientDataMap) ?? ""
    }
    
    // swiftlint:disable:next function_body_length
    private static func buildTree(data: PatientData) -> DecisionNode<String> {
        let feedbackNode1111 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are lower than normal.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode1112 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are lower than normal.
            """
        )
        let feedbackNode1121 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are lower than normal.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn’t stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode1122 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are lower than normal.
            """
        )
        let feedbackNode1211 = DecisionNode(
            leafValue: """
            Your blood pressure is low and your pulse is normal.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode1212 = DecisionNode(
            leafValue: """
            Your blood pressure is low and your pulse is normal.
            """
        )
        let feedbackNode1221 = DecisionNode(
            leafValue: """
            Your blood pressure is low and your pulse is normal.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn’t stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode1222 = DecisionNode(
            leafValue: """
            Your blood pressure is low and your pulse is normal.
            """
        )
        let feedbackNode1311 = DecisionNode(
            leafValue: """
            Your pulse is higher than normal and your blood pressure is low.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode1312 = DecisionNode(
            leafValue: """
            Your pulse is higher than normal and your blood pressure is low.
            """
        )
        let feedbackNode1321 = DecisionNode(
            leafValue: """
            Your pulse is higher than normal and your blood pressure is low.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn’t stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode1322 = DecisionNode(
            leafValue: """
            Your pulse is higher than normal and your blood pressure is low.
            """
        )
        let feedbackNode2111 = DecisionNode(
            leafValue: """
            Your blood pressure is normal and pulse is low.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode2112 = DecisionNode(
            leafValue: """
            Your blood pressure is normal and pulse is low.
            """
        )
        let feedbackNode2121 = DecisionNode(
            leafValue: """
            Your blood pressure is normal and pulse is low.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn’t stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode2122 = DecisionNode(
            leafValue: """
            Your blood pressure is normal and pulse is low.
            """
        )
        let feedbackNode2211 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are normal.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode2212 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are normal.
            """
        )
        let feedbackNode2221 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are normal.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn’t stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode2222 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are normal.
            """
        )
        let feedbackNode2311 = DecisionNode(
            leafValue: """
            Your blood pressure is normal and pulse is high.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode2312 = DecisionNode(
            leafValue: """
            Your blood pressure is normal and pulse is high.
            """
        )
        let feedbackNode2321 = DecisionNode(
            leafValue: """
            Your blood pressure is normal and pulse is high.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn’t stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode2322 = DecisionNode(
            leafValue: """
            Your blood pressure is normal and pulse is high.
            """
        )
        let feedbackNode3111 = DecisionNode(
            leafValue: """
            Your blood pressure is high and pulse is low.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode3112 = DecisionNode(
            leafValue: """
            Your blood pressure is high and pulse is low.
            """
        )
        let feedbackNode3121 = DecisionNode(
            leafValue: """
            Your blood pressure is high and pulse is low.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn’t stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode3122 = DecisionNode(
            leafValue: """
            Your blood pressure is high and pulse is low.
            """
        )
        let feedbackNode3211 = DecisionNode(
            leafValue: """
            Your blood pressure is high and pulse is normal.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode3212 = DecisionNode(
            leafValue: """
            Your blood pressure is high and pulse is normal.
            """
        )
        let feedbackNode3221 = DecisionNode(
            leafValue: """
            Your blood pressure is high and pulse is normal.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn’t stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode3222 = DecisionNode(
            leafValue: """
            Your blood pressure is high and pulse is normal.
            """
        )
        let feedbackNode3311 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are high.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode3312 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are high.
            """
        )
        let feedbackNode3321 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are high.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn’t stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode3322 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are high.
            """
        )
        
        // Condition Change
        let feedbackNode111 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode111.addBranch(value: "worse", node: feedbackNode1111)
        feedbackNode111.addBranch(value: "same", node: feedbackNode1112)
        feedbackNode111.addBranch(value: "better", node: feedbackNode1112)
        let feedbackNode112 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode112.addBranch(value: "worse", node: feedbackNode1121)
        feedbackNode112.addBranch(value: "same", node: feedbackNode1122)
        feedbackNode112.addBranch(value: "better", node: feedbackNode1122)
        let feedbackNode121 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode121.addBranch(value: "worse", node: feedbackNode1211)
        feedbackNode121.addBranch(value: "same", node: feedbackNode1212)
        feedbackNode121.addBranch(value: "better", node: feedbackNode1212)
        let feedbackNode122 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode122.addBranch(value: "worse", node: feedbackNode1221)
        feedbackNode122.addBranch(value: "same", node: feedbackNode1222)
        feedbackNode122.addBranch(value: "better", node: feedbackNode1222)
        let feedbackNode131 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode131.addBranch(value: "worse", node: feedbackNode1311)
        feedbackNode131.addBranch(value: "same", node: feedbackNode1312)
        feedbackNode131.addBranch(value: "better", node: feedbackNode1312)
        let feedbackNode132 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode132.addBranch(value: "worse", node: feedbackNode1321)
        feedbackNode132.addBranch(value: "same", node: feedbackNode1322)
        feedbackNode132.addBranch(value: "better", node: feedbackNode1322)
        let feedbackNode211 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode211.addBranch(value: "worse", node: feedbackNode2111)
        feedbackNode211.addBranch(value: "same", node: feedbackNode2112)
        feedbackNode211.addBranch(value: "better", node: feedbackNode2112)
        let feedbackNode212 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode212.addBranch(value: "worse", node: feedbackNode2121)
        feedbackNode212.addBranch(value: "same", node: feedbackNode2122)
        feedbackNode212.addBranch(value: "better", node: feedbackNode2122)
        let feedbackNode221 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode221.addBranch(value: "worse", node: feedbackNode2211)
        feedbackNode221.addBranch(value: "same", node: feedbackNode2212)
        feedbackNode221.addBranch(value: "better", node: feedbackNode2212)
        let feedbackNode222 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode222.addBranch(value: "worse", node: feedbackNode2221)
        feedbackNode222.addBranch(value: "same", node: feedbackNode2222)
        feedbackNode222.addBranch(value: "better", node: feedbackNode2222)
        let feedbackNode231 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode231.addBranch(value: "worse", node: feedbackNode2311)
        feedbackNode231.addBranch(value: "same", node: feedbackNode2312)
        feedbackNode231.addBranch(value: "better", node: feedbackNode2312)
        let feedbackNode232 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode232.addBranch(value: "worse", node: feedbackNode2321)
        feedbackNode232.addBranch(value: "same", node: feedbackNode2322)
        feedbackNode232.addBranch(value: "better", node: feedbackNode2322)
        let feedbackNode311 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode311.addBranch(value: "worse", node: feedbackNode3111)
        feedbackNode311.addBranch(value: "same", node: feedbackNode3112)
        feedbackNode311.addBranch(value: "better", node: feedbackNode3112)
        let feedbackNode312 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode312.addBranch(value: "worse", node: feedbackNode3121)
        feedbackNode312.addBranch(value: "same", node: feedbackNode3122)
        feedbackNode312.addBranch(value: "better", node: feedbackNode3122)
        let feedbackNode321 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode321.addBranch(value: "worse", node: feedbackNode3211)
        feedbackNode321.addBranch(value: "same", node: feedbackNode3212)
        feedbackNode321.addBranch(value: "better", node: feedbackNode3212)
        let feedbackNode322 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode322.addBranch(value: "worse", node: feedbackNode3221)
        feedbackNode322.addBranch(value: "same", node: feedbackNode3222)
        feedbackNode322.addBranch(value: "better", node: feedbackNode3222)
        let feedbackNode331 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode331.addBranch(value: "worse", node: feedbackNode3311)
        feedbackNode331.addBranch(value: "same", node: feedbackNode3312)
        feedbackNode331.addBranch(value: "better", node: feedbackNode3312)
        let feedbackNode332 = DecisionNode<String>(attribute: "conditionChange")
        feedbackNode332.addBranch(value: "worse", node: feedbackNode3321)
        feedbackNode332.addBranch(value: "same", node: feedbackNode3322)
        feedbackNode332.addBranch(value: "better", node: feedbackNode3322)
        
        // Symptom Score
        let feedbackNode11 = DecisionNode<String>(attribute: "symptomScore")
        feedbackNode11.addBranch(value: "severe", node: feedbackNode111)
        feedbackNode11.addBranch(value: "mild", node: feedbackNode112)
        let feedbackNode12 = DecisionNode<String>(attribute: "symptomScore")
        feedbackNode12.addBranch(value: "severe", node: feedbackNode121)
        feedbackNode12.addBranch(value: "mild", node: feedbackNode122)
        let feedbackNode13 = DecisionNode<String>(attribute: "symptomScore")
        feedbackNode13.addBranch(value: "severe", node: feedbackNode131)
        feedbackNode13.addBranch(value: "mild", node: feedbackNode132)
        let feedbackNode21 = DecisionNode<String>(attribute: "symptomScore")
        feedbackNode21.addBranch(value: "severe", node: feedbackNode211)
        feedbackNode21.addBranch(value: "mild", node: feedbackNode212)
        let feedbackNode22 = DecisionNode<String>(attribute: "symptomScore")
        feedbackNode22.addBranch(value: "severe", node: feedbackNode221)
        feedbackNode22.addBranch(value: "mild", node: feedbackNode222)
        let feedbackNode23 = DecisionNode<String>(attribute: "symptomScore")
        feedbackNode23.addBranch(value: "severe", node: feedbackNode231)
        feedbackNode23.addBranch(value: "mild", node: feedbackNode232)
        let feedbackNode31 = DecisionNode<String>(attribute: "symptomScore")
        feedbackNode31.addBranch(value: "severe", node: feedbackNode311)
        feedbackNode31.addBranch(value: "mild", node: feedbackNode312)
        let feedbackNode32 = DecisionNode<String>(attribute: "symptomScore")
        feedbackNode32.addBranch(value: "severe", node: feedbackNode321)
        feedbackNode32.addBranch(value: "mild", node: feedbackNode322)
        let feedbackNode33 = DecisionNode<String>(attribute: "symptomScore")
        feedbackNode33.addBranch(value: "severe", node: feedbackNode331)
        feedbackNode33.addBranch(value: "mild", node: feedbackNode332)
        
        
        // Heart Rate
        let feedbackNode1 = DecisionNode<String>(attribute: "heartRate")
        feedbackNode1.addBranch(value: "low", node: feedbackNode11)
        feedbackNode1.addBranch(value: "normal", node: feedbackNode12)
        feedbackNode1.addBranch(value: "high", node: feedbackNode13)
        let feedbackNode2 = DecisionNode<String>(attribute: "heartRate")
        feedbackNode2.addBranch(value: "low", node: feedbackNode21)
        feedbackNode2.addBranch(value: "normal", node: feedbackNode22)
        feedbackNode2.addBranch(value: "high", node: feedbackNode23)
        let feedbackNode3 = DecisionNode<String>(attribute: "heartRate")
        feedbackNode3.addBranch(value: "low", node: feedbackNode31)
        feedbackNode3.addBranch(value: "normal", node: feedbackNode32)
        feedbackNode3.addBranch(value: "high", node: feedbackNode33)
        
        // BP
        let rootNode = DecisionNode<String>(attribute: "bp")
        rootNode.addBranch(value: "low", node: feedbackNode1)
        rootNode.addBranch(value: "normal", node: feedbackNode2)
        rootNode.addBranch(value: "high", node: feedbackNode3)
        
        return rootNode
    }
}
