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
    /// The directory where health data is stored
    private static let dataDirectory: String = {
        let fileManager = FileManager.default
        let currentDirectoryPath = fileManager.currentDirectoryPath
        return "\(currentDirectoryPath)/Data"
    }()
    
    /// The file path for the health data JSON file
    private static let healthDataFilePath: String = {
        return "\(dataDirectory)/health_data.json"
    }()
    
    /// Save blood pressure measurement to the health data file
    /// - Parameters:
    ///   - bloodPressure: The blood pressure value to save
    ///   - logger: The logger to use for logging
    /// - Returns: A boolean indicating whether the save was successful
    static func saveBloodPressure(_ bloodPressure: String, logger: Logger) -> Bool {
        do {
            logger.info("Attempting to save blood pressure to: \(healthDataFilePath)")
            logger.info("Current directory: \(FileManager.default.currentDirectoryPath)")
            
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                atPath: dataDirectory,
                withIntermediateDirectories: true
            )
            
            logger.info("Directory created/verified: \(dataDirectory)")
            
            // Load existing data or create new data
            var healthData = try loadHealthData() ?? []
            
            // Check if we have an entry for today
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            if let index = healthData.firstIndex(where: { calendar.isDate($0.timestamp, inSameDayAs: today) }) {
                // Update existing entry for today
                healthData[index].bloodPressure = bloodPressure
                logger.info("Updated existing entry for today")
            } else {
                // Create new entry for today
                healthData.append(HealthData(bloodPressure: bloodPressure))
                logger.info("Created new entry for today")
            }
            
            // Save the updated data
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
    static func saveHeartRate(_ heartRate: String, logger: Logger) -> Bool {
        do {
            logger.info("Attempting to save heart rate to: \(healthDataFilePath)")
            
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                atPath: dataDirectory,
                withIntermediateDirectories: true
            )
            
            // Load existing data or create new data
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
            
            // Save the updated data
            return try saveHealthData(healthData, logger: logger)
        } catch {
            logger.error("Failed to save heart rate: \(error)")
            return false
        }
    }
    
    /// Load health data from the JSON file
    /// - Returns: An array of HealthData objects, or nil if the file doesn't exist
    private static func loadHealthData() throws -> [HealthData]? {
        let fileManager = FileManager.default
        
        // Check if the file exists
        guard fileManager.fileExists(atPath: healthDataFilePath) else {
            return []
        }
        
        // Read the file data
        let data = try Data(contentsOf: URL(fileURLWithPath: healthDataFilePath))
        
        // Decode the JSON data
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HealthData].self, from: data)
    }
    
    /// Save health data to the JSON file
    /// - Parameters:
    ///   - healthData: The health data to save
    ///   - logger: The logger to use for logging
    /// - Returns: A boolean indicating whether the save was successful
    private static func saveHealthData(_ healthData: [HealthData], logger: Logger) throws -> Bool {
        // Encode the health data as JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let jsonData = try encoder.encode(healthData)
        
        // Write the JSON data to the file
        try jsonData.write(to: URL(fileURLWithPath: healthDataFilePath))
        
        logger.info("Health data saved successfully to \(healthDataFilePath)")
        return true
    }
    
    /// Check if the health data file exists and print its contents for debugging
    /// - Parameter logger: The logger to use for logging
    static func debugHealthDataFile(logger: Logger) {
        let fileManager = FileManager.default
        
        logger.info("Checking health data file at: \(healthDataFilePath)")
        
        if fileManager.fileExists(atPath: healthDataFilePath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: healthDataFilePath))
                if let jsonString = String(data: data, encoding: .utf8) {
                    logger.info("Health data file contents: \(jsonString)")
                } else {
                    logger.error("Failed to convert file data to string")
                }
            } catch {
                logger.error("Failed to read health data file: \(error)")
            }
        } else {
            logger.error("Health data file does not exist")
            
            // Check if the directory exists
            if fileManager.fileExists(atPath: dataDirectory) {
                logger.info("Data directory exists: \(dataDirectory)")
                
                // List files in the directory
                do {
                    let files = try fileManager.contentsOfDirectory(atPath: dataDirectory)
                    logger.info("Files in data directory: \(files)")
                } catch {
                    logger.error("Failed to list files in data directory: \(error)")
                }
            } else {
                logger.error("Data directory does not exist: \(dataDirectory)")
            }
        }
    }
} 