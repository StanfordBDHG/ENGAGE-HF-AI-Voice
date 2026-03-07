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
    private static let severeSymptomDescription =
        "you have a lot of symptoms from your heart failure that make it hard to do everyday activities"
    private static let mildSymptomDescription =
        "your heart failure doesn't stop you much from doing your normal daily activities"

    private static func leafNode(
        vitalsDescription: String,
        data: PatientData,
        symptomDescription: String
    ) -> DecisionNode<String> {
        DecisionNode(
            leafValue: """
                \(vitalsDescription)
                Your symptom score is \(data.symptomScore), which means \(symptomDescription).
                You feel \(data.conditionChange) compared to 3 months ago.
                """
        )
    }

    private static func symptomBranch(
        vitalsDescription: String,
        data: PatientData
    ) -> DecisionNode<String> {
        let node = DecisionNode<String>(attribute: "symptomScore")
        node.addBranch(
            value: "severe",
            node: leafNode(
                vitalsDescription: vitalsDescription,
                data: data,
                symptomDescription: severeSymptomDescription
            )
        )
        node.addBranch(
            value: "mild",
            node: leafNode(
                vitalsDescription: vitalsDescription,
                data: data,
                symptomDescription: mildSymptomDescription
            )
        )
        return node
    }

    private static func heartRateBranch(
        lowDescription: String,
        normalDescription: String,
        highDescription: String,
        data: PatientData
    ) -> DecisionNode<String> {
        let node = DecisionNode<String>(attribute: "heartRate")
        node.addBranch(
            value: "low",
            node: symptomBranch(vitalsDescription: lowDescription, data: data)
        )
        node.addBranch(
            value: "normal",
            node: symptomBranch(vitalsDescription: normalDescription, data: data)
        )
        node.addBranch(
            value: "high",
            node: symptomBranch(vitalsDescription: highDescription, data: data)
        )
        return node
    }

    static func buildTree(data: PatientData) -> DecisionNode<String> {
        let lowBPNode = heartRateBranch(
            lowDescription: "Your blood pressure and pulse are lower than normal.",
            normalDescription: "Your blood pressure is low and your pulse is normal.",
            highDescription: "Your pulse is higher than normal and your blood pressure is low.",
            data: data
        )
        let normalBPNode = heartRateBranch(
            lowDescription: "Your blood pressure is normal and pulse is low.",
            normalDescription: "Your blood pressure and pulse are normal.",
            highDescription: "Your blood pressure is normal and pulse is high.",
            data: data
        )
        let highBPNode = heartRateBranch(
            lowDescription: "Your blood pressure is high and pulse is low.",
            normalDescription: "Your blood pressure is high and pulse is normal.",
            highDescription: "Your blood pressure and pulse are high.",
            data: data
        )

        let rootNode = DecisionNode<String>(attribute: "bp")
        rootNode.addBranch(value: "low", node: lowBPNode)
        rootNode.addBranch(value: "normal", node: normalBPNode)
        rootNode.addBranch(value: "high", node: highBPNode)

        return rootNode
    }
}
