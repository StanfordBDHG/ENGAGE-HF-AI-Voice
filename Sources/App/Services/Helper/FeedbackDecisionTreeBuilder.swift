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
    // swiftlint:disable:next function_body_length
    static func buildTree(data: PatientData) -> DecisionNode<String> {
        let feedbackNode111 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are lower than normal.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode112 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are lower than normal.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn't stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode121 = DecisionNode(
            leafValue: """
            Your blood pressure is low and your pulse is normal.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode122 = DecisionNode(
            leafValue: """
            Your blood pressure is low and your pulse is normal.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn't stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode131 = DecisionNode(
            leafValue: """
            Your pulse is higher than normal and your blood pressure is low.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode132 = DecisionNode(
            leafValue: """
            Your pulse is higher than normal and your blood pressure is low.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn't stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode211 = DecisionNode(
            leafValue: """
            Your blood pressure is normal and pulse is low.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode212 = DecisionNode(
            leafValue: """
            Your blood pressure is normal and pulse is low.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn't stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode221 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are normal.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode222 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are normal.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn't stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode231 = DecisionNode(
            leafValue: """
            Your blood pressure is normal and pulse is high.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode232 = DecisionNode(
            leafValue: """
            Your blood pressure is normal and pulse is high.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn't stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode311 = DecisionNode(
            leafValue: """
            Your blood pressure is high and pulse is low.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode312 = DecisionNode(
            leafValue: """
            Your blood pressure is high and pulse is low.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn't stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode321 = DecisionNode(
            leafValue: """
            Your blood pressure is high and pulse is normal.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode322 = DecisionNode(
            leafValue: """
            Your blood pressure is high and pulse is normal.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn't stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode331 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are high.
            Your symptom score is \(data.symptomScore), which means you have a lot of symptoms from your heart failure that make it hard to do everyday activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        let feedbackNode332 = DecisionNode(
            leafValue: """
            Your blood pressure and pulse are high.
            Your symptom score is \(data.symptomScore), which means your heart failure doesn't stop you much from doing your normal daily activities.
            You feel \(data.conditionChange) compared to 3 months ago.
            """
        )
        
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
