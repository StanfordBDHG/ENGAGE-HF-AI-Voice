//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor


/// Service for managing vital signs storage
enum VitalSignsService {
    private static let dataDirectory: String = {
        let fileManager = FileManager.default
        let currentDirectoryPath = fileManager.currentDirectoryPath
        return "\(currentDirectoryPath)/Data"
    }()
    
    private static let vitalSignsFilePath: String = {
        "\(dataDirectory)/health_data.json"
    }()
    
    /// Save blood pressure measurement to the vital signs file
    /// - Parameters:
    ///   - bloodPressure: The blood pressure value to save
    ///   - logger: The logger to use for logging
    /// - Returns: A boolean indicating whether the save was successful
    static func saveBloodPressure(bloodPressureSystolic: Int, bloodPressureDiastolic: Int, logger: Logger) -> Bool {
        do {
            logger.info("Attempting to save blood pressure to: \(vitalSignsFilePath)")
            
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                atPath: dataDirectory,
                withIntermediateDirectories: true
            )
            
            var vitalSigns = try loadVitalSigns()
            
            // Check if we have an entry for today
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            if let index = vitalSigns.firstIndex(where: { calendar.isDate($0.timestamp, inSameDayAs: today) }) {
                // Update existing entry for today
                vitalSigns[index].bloodPressureSystolic = bloodPressureSystolic
                vitalSigns[index].bloodPressureDiastolic = bloodPressureDiastolic
                logger.info("Updated existing entry for today")
            } else {
                // Create new entry for today
                vitalSigns.append(VitalSigns(bloodPressureSystolic: bloodPressureSystolic, bloodPressureDiastolic: bloodPressureDiastolic))
                logger.info("Created new entry for today")
            }
            
            let result = try saveVitalSigns(vitalSigns, logger: logger)
            logger.info("Save result: \(result)")
            return result
        } catch {
            logger.error("Failed to save blood pressure: \(error)")
            return false
        }
    }
    
    /// Save heart rate measurement to the vital signs file
    /// - Parameters:
    ///   - heartRate: The heart rate value to save
    ///   - logger: The logger to use for logging
    /// - Returns: A boolean indicating whether the save was successful
    static func saveHeartRate(_ heartRate: Int, logger: Logger) -> Bool {
        do {
            logger.info("Attempting to save heart rate to: \(vitalSignsFilePath)")
            
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                atPath: dataDirectory,
                withIntermediateDirectories: true
            )
            
            var vitalSigns = try loadVitalSigns()
            
            // Check if we have an entry for today
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            if let index = vitalSigns.firstIndex(where: { calendar.isDate($0.timestamp, inSameDayAs: today) }) {
                // Update existing entry for today
                vitalSigns[index].heartRate = heartRate
            } else {
                // Create new entry for today
                vitalSigns.append(VitalSigns(heartRate: heartRate))
            }
            
            return try saveVitalSigns(vitalSigns, logger: logger)
        } catch {
            logger.error("Failed to save heart rate: \(error)")
            return false
        }
    }

    /// Save weight measurement to the vital signs file
    /// - Parameters:
    ///   - weight: The weight value to save
    ///   - logger: The logger to use for logging
    /// - Returns: A boolean indicating whether the save was successful
    static func saveWeight(_ weight: Double, logger: Logger) -> Bool {
        do {
            logger.info("Attempting to save weight to: \(vitalSignsFilePath)")
            
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                atPath: dataDirectory,
                withIntermediateDirectories: true
            )
            
            var vitalSigns = try loadVitalSigns()
            
            // Check if we have an entry for today
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            if let index = vitalSigns.firstIndex(where: { calendar.isDate($0.timestamp, inSameDayAs: today) }) {
                // Update existing entry for today
                vitalSigns[index].weight = weight
            } else {
                // Create new entry for today
                vitalSigns.append(VitalSigns(weight: weight))
            }
            
            return try saveVitalSigns(vitalSigns, logger: logger)
        } catch {
            logger.error("Failed to save weight: \(error)")
            return false
        }
    }

    private static func loadVitalSigns() throws -> [VitalSigns] {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: vitalSignsFilePath) else {
            return []
        }
        
        let data = try Data(contentsOf: URL(fileURLWithPath: vitalSignsFilePath))
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([VitalSigns].self, from: data)
    }
    
    private static func saveVitalSigns(_ vitalSigns: [VitalSigns], logger: Logger) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let jsonData = try encoder.encode(vitalSigns)
        
        try jsonData.write(to: URL(fileURLWithPath: vitalSignsFilePath))
        
        logger.info("Vital signs saved successfully to \(vitalSignsFilePath)")
        return true
    }
}
