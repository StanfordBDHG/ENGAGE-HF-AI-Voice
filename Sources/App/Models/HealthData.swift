//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation

/// Model for storing health data measurements
struct HealthData: Codable {
    var bloodPressure: String?
    var heartRate: String?
    var weight: String?
    var timestamp: Date
    
    init(bloodPressure: String? = nil, heartRate: String? = nil, weight: String? = nil) {
        self.bloodPressure = bloodPressure
        self.heartRate = heartRate
        self.weight = weight
        self.timestamp = Date()
    }
} 