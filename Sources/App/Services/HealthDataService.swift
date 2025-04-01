//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor

/// Service for managing health data storage
struct HealthDataService {
    private static let dataDirectory: String = {
        let fileManager = FileManager.default
        let currentDirectoryPath = fileManager.currentDirectoryPath
        return "\(currentDirectoryPath)/Data"
    }()
    
    private static let healthDataFilePath: String = {
        return "\(dataDirectory)/health_data.json"
    }()
    
    /// Save blood pressure measurement to the health data file
    /// - Parameters:
    ///   - bloodPressure: The blood pressure value to save
    ///   - logger: The logger to use for logging
    /// - Returns: A boolean indicating whether the save was successful
    static func saveBloodPressure(bloodPressureSystolic: Int, bloodPressureDiastolic: Int, logger: Logger) -> Bool {
        do {
            logger.info("Attempting to save blood pressure to: \(healthDataFilePath)")
            
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                atPath: dataDirectory,
                withIntermediateDirectories: true
            )
            
            var healthData = try loadHealthData() ?? []
            
            // Check if we have an entry for today
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            if let index = healthData.firstIndex(where: { calendar.isDate($0.timestamp, inSameDayAs: today) }) {
                // Update existing entry for today
                healthData[index].bloodPressureSystolic = bloodPressureSystolic
                healthData[index].bloodPressureDiastolic = bloodPressureDiastolic
                logger.info("Updated existing entry for today")
            } else {
                // Create new entry for today
                healthData.append(HealthData(bloodPressureSystolic: bloodPressureSystolic, bloodPressureDiastolic: bloodPressureDiastolic))
                logger.info("Created new entry for today")
            }
            
            let result = try saveHealthData(healthData, logger: logger)
            logger.info("Save result: \(result)")
            return result
        } catch {
            logger.error("Failed to save blood pressure: \(error)")
            return false
        }
    }
    
    /// Save heart rate measurement to the health data file
    /// - Parameters:
    ///   - heartRate: The heart rate value to save
    ///   - logger: The logger to use for logging
    /// - Returns: A boolean indicating whether the save was successful
    static func saveHeartRate(_ heartRate: Int, logger: Logger) -> Bool {
        do {
            logger.info("Attempting to save heart rate to: \(healthDataFilePath)")
            
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                atPath: dataDirectory,
                withIntermediateDirectories: true
            )
            
            var healthData = try loadHealthData() ?? []
            
            // Check if we have an entry for today
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            if let index = healthData.firstIndex(where: { calendar.isDate($0.timestamp, inSameDayAs: today) }) {
                // Update existing entry for today
                healthData[index].heartRate = heartRate
            } else {
                // Create new entry for today
                healthData.append(HealthData(heartRate: heartRate))
            }
            
            return try saveHealthData(healthData, logger: logger)
        } catch {
            logger.error("Failed to save heart rate: \(error)")
            return false
        }
    }

    static func saveWeight(_ weight: Double, logger: Logger) -> Bool {
        do {
            logger.info("Attempting to save weight to: \(healthDataFilePath)")
            
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                atPath: dataDirectory,
                withIntermediateDirectories: true
            )
            
            var healthData = try loadHealthData() ?? []
            
            // Check if we have an entry for today
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            if let index = healthData.firstIndex(where: { calendar.isDate($0.timestamp, inSameDayAs: today) }) {
                // Update existing entry for today
                healthData[index].weight = weight
            } else {
                // Create new entry for today
                healthData.append(HealthData(weight: weight))
            }
            
            return try saveHealthData(healthData, logger: logger)
        } catch {
            logger.error("Failed to save weight: \(error)")
            return false
        }
    }

    private static func loadHealthData() throws -> [HealthData]? {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: healthDataFilePath) else {
            return []
        }
        
        let data = try Data(contentsOf: URL(fileURLWithPath: healthDataFilePath))
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HealthData].self, from: data)
    }
    
    private static func saveHealthData(_ healthData: [HealthData], logger: Logger) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let jsonData = try encoder.encode(healthData)
        
        try jsonData.write(to: URL(fileURLWithPath: healthDataFilePath))
        
        logger.info("Health data saved successfully to \(healthDataFilePath)")
        return true
    }
} 
