//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation

/// Helper class for building the feedback decision tree
@MainActor
enum FeedbackDecisionTreeBuilder {
    private static func leafNode(vitalsDescription: String, data: PatientData, symptomDescription: String) -> DecisionNode<String> {
        DecisionNode(
            leafValue: """
            \(vitalsDescription)
            Your symptom score is \(data.symptomScore), which means \(symptomDescription).
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
    }
    
    private static let severeSymptomDescription = "you have a lot of symptoms from your heart failure that make it hard to do everyday activities"
    private static let mildSymptomDescription = "your heart failure doesn't stop you much from doing your normal daily activities"
    
    private static func symptomBranch(vitalsDescription: String, data: PatientData) -> DecisionNode<String> {
        let node = DecisionNode<String>(attribute: "symptomScore")
        node.addBranch(value: "severe", node: leafNode(vitalsDescription: vitalsDescription, data: data, symptomDescription: severeSymptomDescription))
        node.addBranch(value: "mild", node: leafNode(vitalsDescription: vitalsDescription, data: data, symptomDescription: mildSymptomDescription))
        return node
    }
    
    static func buildTree(data: PatientData) -> DecisionNode<String> {
        // Heart Rate branches for low BP
        let feedbackNode1 = DecisionNode<String>(attribute: "heartRate")
        feedbackNode1.addBranch(value: "low", node: symptomBranch(vitalsDescription: "Your blood pressure and pulse are lower than normal.", data: data))
        feedbackNode1.addBranch(value: "normal", node: symptomBranch(vitalsDescription: "Your blood pressure is low and your pulse is normal.", data: data))
        feedbackNode1.addBranch(value: "high", node: symptomBranch(vitalsDescription: "Your pulse is higher than normal and your blood pressure is low.", data: data))
        
        // Heart Rate branches for normal BP
        let feedbackNode2 = DecisionNode<String>(attribute: "heartRate")
        feedbackNode2.addBranch(value: "low", node: symptomBranch(vitalsDescription: "Your blood pressure is normal and pulse is low.", data: data))
        feedbackNode2.addBranch(value: "normal", node: symptomBranch(vitalsDescription: "Your blood pressure and pulse are normal.", data: data))
        feedbackNode2.addBranch(value: "high", node: symptomBranch(vitalsDescription: "Your blood pressure is normal and pulse is high.", data: data))
        
        // Heart Rate branches for high BP
        let feedbackNode3 = DecisionNode<String>(attribute: "heartRate")
        feedbackNode3.addBranch(value: "low", node: symptomBranch(vitalsDescription: "Your blood pressure is high and pulse is low.", data: data))
        feedbackNode3.addBranch(value: "normal", node: symptomBranch(vitalsDescription: "Your blood pressure is high and pulse is normal.", data: data))
        feedbackNode3.addBranch(value: "high", node: symptomBranch(vitalsDescription: "Your blood pressure and pulse are high.", data: data))
        
        // BP root
        let rootNode = DecisionNode<String>(attribute: "bp")
        rootNode.addBranch(value: "low", node: feedbackNode1)
        rootNode.addBranch(value: "normal", node: feedbackNode2)
        rootNode.addBranch(value: "high", node: feedbackNode3)
        
        return rootNode
    }
}
