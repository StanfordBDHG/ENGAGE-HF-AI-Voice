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
    /// Creats the file to save vital signs
    /// - Parameters:
    ///   - phoneNumber: The caller's phone number
    ///   - logger: The logger to use for logging
    static func setupVitalSignsFile(phoneNumber: String, logger: Logger) {
        logger.info("Attempting to create vital signs file at: \(FileService.vitalSignsFilePath(phoneNumber: phoneNumber))")
        do {
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                atPath: FileService.vitalSignsDirectoryPath,
                withIntermediateDirectories: true
            )
            
            let filePath = FileService.vitalSignsFilePath(phoneNumber: phoneNumber)
            
            // Check if file already exists
            if FileManager.default.fileExists(atPath: filePath) {
                logger.info("Vital signs file already exists for this participant")
                return
            }
            
            // Create initial vital signs array with phone number
            let initialVitalSigns = [VitalSigns(phoneNumber: phoneNumber)]
            let encoder = JSONEncoder()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            encoder.dateEncodingStrategy = .formatted(formatter)
            encoder.outputFormatting = .prettyPrinted
            
            let data = try encoder.encode(initialVitalSigns)
            
            // Write to file
            try data.write(to: URL(fileURLWithPath: filePath))
            logger.info("Created new vital signs file for this participant")
            
            return
        } catch {
            logger.error("Failed to setup vital signs file: \(error)")
            return
        }
    }
    
    /// Save blood pressure measurement to the vital signs file
    /// - Parameters:
    ///   - bloodPressure: The blood pressure value to save
    ///   - logger: The logger to use for logging
    /// - Returns: A boolean indicating whether the save was successful
    static func saveBloodPressure(bloodPressureSystolic: Int, bloodPressureDiastolic: Int, phoneNumber: String, logger: Logger) -> Bool {
        do {
            logger.info("Attempting to save blood pressure to: \(FileService.vitalSignsFilePath(phoneNumber: phoneNumber))")
            
            var vitalSigns = try loadVitalSigns(phoneNumber: phoneNumber)
            
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
            
            let result = try saveVitalSigns(vitalSigns, phoneNumber: phoneNumber, logger: logger)
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
    static func saveHeartRate(_ heartRate: Int, phoneNumber: String, logger: Logger) -> Bool {
        do {
            logger.info("Attempting to save heart rate to: \(FileService.vitalSignsFilePath(phoneNumber: phoneNumber))")
            
            var vitalSigns = try loadVitalSigns(phoneNumber: phoneNumber)
            
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
            
            return try saveVitalSigns(vitalSigns, phoneNumber: phoneNumber, logger: logger)
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
    static func saveWeight(_ weight: Double, phoneNumber: String, logger: Logger) -> Bool {
        do {
            logger.info("Attempting to save weight to: \(FileService.vitalSignsFilePath(phoneNumber: phoneNumber))")
            
            var vitalSigns = try loadVitalSigns(phoneNumber: phoneNumber)
            
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
            
            return try saveVitalSigns(vitalSigns, phoneNumber: phoneNumber, logger: logger)
        } catch {
            logger.error("Failed to save weight: \(error)")
            return false
        }
    }

    private static func loadVitalSigns(phoneNumber: String) throws -> [VitalSigns] {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: FileService.vitalSignsFilePath(phoneNumber: phoneNumber)) else {
            return []
        }
        
        let data = try Data(contentsOf: URL(fileURLWithPath: FileService.vitalSignsFilePath(phoneNumber: phoneNumber)))
        
        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        decoder.dateDecodingStrategy = .formatted(formatter)
        return try decoder.decode([VitalSigns].self, from: data)
    }
    
    private static func saveVitalSigns(_ vitalSigns: [VitalSigns], phoneNumber: String, logger: Logger) throws -> Bool {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        encoder.dateEncodingStrategy = .formatted(formatter)
        encoder.outputFormatting = .prettyPrinted
        
        let jsonData = try encoder.encode(vitalSigns)
        
        try jsonData.write(to: URL(fileURLWithPath: FileService.vitalSignsFilePath(phoneNumber: phoneNumber)))
        
        logger.info("Vital signs saved successfully to \(FileService.vitalSignsFilePath(phoneNumber: phoneNumber))")
        return true
    }
}
