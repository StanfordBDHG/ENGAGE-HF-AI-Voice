//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation

struct VitalSigns: Codable {
    var bloodPressureSystolic: Int?
    var bloodPressureDiastolic: Int?
    var heartRate: Int?
    var weight: Double?
    var timestamp: Date
    var phoneNumber: String?
    
    init(
        bloodPressureSystolic: Int? = nil,
        bloodPressureDiastolic: Int? = nil,
        heartRate: Int? = nil,
        weight: Double? = nil,
        phoneNumber: String? = nil
    ) {
        self.bloodPressureSystolic = bloodPressureSystolic
        self.bloodPressureDiastolic = bloodPressureDiastolic
        self.heartRate = heartRate
        self.weight = weight
        self.timestamp = Date()
        self.phoneNumber = phoneNumber
    }
}
