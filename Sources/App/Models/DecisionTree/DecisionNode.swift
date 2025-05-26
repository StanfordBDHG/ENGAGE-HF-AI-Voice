//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Decision node that can be used to build a decision tree
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
        if let result = leafValue {
            return result
        }
        
        guard let attribute = attribute else {
            return nil
        }
        
        guard let attributeValue = data[attribute] else {
            return branches["default"]?.decide(data: data)
        }
        
        if let nextNode = branches[attributeValue] {
            return nextNode.decide(data: data)
        } else if let defaultNode = branches["default"] {
            return defaultNode.decide(data: data)
        } else {
            print("No branch for value \(attributeValue) of attribute \(attribute)")
            return nil
        }
    }
    
    func addBranch(value: String, node: DecisionNode<T>) {
        branches[value] = node
    }
}
