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
    
    private static let vitalSignsDirectoryPath: String = {
        "\(dataDirectory)/vital_signs/"
    }()
    
    private static func hashPhoneNumber (_ phoneNumber: String) -> String {
        // swiftlint:disable:next force_unwrapping
        let data = phoneNumber.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }
    
    private static func vitalSignsFilePath(phoneNumber: String) -> String {
        "\(vitalSignsDirectoryPath)\(hashPhoneNumber(phoneNumber)).json"
    }
    
    /// Creats the file to save vital signs
    /// - Parameters:
    ///   - phoneNumber: The caller's phone number
    ///   - logger: The logger to use for logging
    static func setupVitalSignsFile(phoneNumber: String, logger: Logger) {
        logger.info("Attempting to create vital signs file at: \(vitalSignsFilePath(phoneNumber: phoneNumber))")
        do {
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                atPath: vitalSignsDirectoryPath,
                withIntermediateDirectories: true
            )
            
            let filePath = vitalSignsFilePath(phoneNumber: phoneNumber)
            
            // Check if file already exists
            if FileManager.default.fileExists(atPath: filePath) {
                logger.info("Vital signs file already exists for this participant")
                return
            }
            
            // Create initial vital signs array with phone number
            let initialVitalSigns = [VitalSigns(phoneNumber: phoneNumber)]
            let encoder = JSONEncoder()
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
            logger.info("Attempting to save blood pressure to: \(vitalSignsFilePath(phoneNumber: phoneNumber))")
            
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
            logger.info("Attempting to save heart rate to: \(vitalSignsFilePath(phoneNumber: phoneNumber))")
            
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
            logger.info("Attempting to save weight to: \(vitalSignsFilePath(phoneNumber: phoneNumber))")
            
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
        
        guard fileManager.fileExists(atPath: vitalSignsFilePath(phoneNumber: phoneNumber)) else {
            return []
        }
        
        let data = try Data(contentsOf: URL(fileURLWithPath: vitalSignsFilePath(phoneNumber: phoneNumber)))
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([VitalSigns].self, from: data)
    }
    
    private static func saveVitalSigns(_ vitalSigns: [VitalSigns], phoneNumber: String, logger: Logger) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let jsonData = try encoder.encode(vitalSigns)
        
        try jsonData.write(to: URL(fileURLWithPath: vitalSignsFilePath(phoneNumber: phoneNumber)))
        
        logger.info("Vital signs saved successfully to \(vitalSignsFilePath(phoneNumber: phoneNumber))")
        return true
    }
}
