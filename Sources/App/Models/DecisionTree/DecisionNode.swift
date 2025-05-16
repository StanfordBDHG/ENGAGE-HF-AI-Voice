//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


class DecisionNode<T> {
    let attribute: String?
    private var branches: [String: DecisionNode<T>]
    private var leafValue: T?
    
    init(attribute: String? = nil, branches: [String: DecisionNode<T>] = [:], leafValue: T? = nil) {
        self.attribute = attribute
        self.branches = branches
        self.leafValue = leafValue
    }
    
    func decide(data: [String: String]) -> T? {
        // If this is a leaf node, return the decision
        if let result = leafValue {
            return result
        }
        
        guard let attribute = attribute else {
            return nil
        }
        
        // Get the value of the attribute for this data point
        guard let attributeValue = data[attribute] else {
            // Try default branch if attribute is missing
            return branches["default"]?.decide(data: data)
        }
        
        // Follow the appropriate branch
        if let nextNode = branches[attributeValue] {
            return nextNode.decide(data: data)
        } else if let defaultNode = branches["default"] {
            return defaultNode.decide(data: data)
        } else {
            print("No branch for value \(attributeValue) of attribute \(attribute)")
            return nil
        }
    }
    
    // Add a branch to the node
    func addBranch(value: String, node: DecisionNode<T>) {
        branches[value] = node
    }
}
