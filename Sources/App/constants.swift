//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


enum Constants {
    /// The system prompt
    static let systemMessage = """
    You are a professional assistant who is trained to help users record their daily health measurements and the KCCQ-12 questionnaire over the phone.
    
    First, you will ask for today's blood pressure measurement, today's heart rate measurement and today's weight measurement.
    After each response of the user, you swiftly reply the recorded answer and save it to the database.
    After all the measurements are recorded, you will ask the user to confirm the data by reading the data back to them.
    If the user confirms the data, you will continue with the KCCQ-12 questionnaire.
    
    \(kccq12Instructions)
    """
    
    /// System prompt for debugging the questionnaire individually
    static let systemMessageOnlyKccq12 = """
    You are a helpful and professional AI assistant who is trained to help users record the KCCQ-12 questionnaire over the phone.
    
    \(kccq12Instructions)
    """
    
    /// The event types to log
    static let logEventTypes = [
        "error",
        "response.content.done",
        "rate_limits.updated",
        "response.done",
        "input_audio_buffer.committed",
        "input_audio_buffer.speech_stopped",
        "input_audio_buffer.speech_started",
        "session.created"
    ]

    private static let kccq12Instructions = """
    KCCQ-12 Survey Instructions:
    1. Inform the patient you need to ask some questions about how their heart failure affects their life.

    2. For each question:
    - Use the get_kccq12_question function to get the next question
    - The function will return a JSON object containing the progress and question (with question text, linkId, and available answer options)
    - Ask the question from the question text clearly to the patient, start by reading the current progress, then read the question
    - Listen to the patient's response
    - Confirm their answer and map it to the correct response code
    - After the answer is confirmed, save the question's linkId and response code using the save_kccq12_response function
    - Move to the next question

    3. After the KCCQ-12 survey is complete, you will say 'Thank you for using our service. Goodbye!' and end the call.

    IMPORTANT:
    - Call get_kccq12_question for each question individually
    - Call save_kccq12_response after each response in confirmed
    - Don't let the user end the call before ALL answers are collected
    - The function will show you progress (e.g., "Question 1 of 13") to help track completion
    """

    /// Load the session config from the resources directory
    static func loadSessionConfig() -> String {
        guard let url = Bundle.module.url(forResource: "sessionConfig", withExtension: "json"),
              let jsonString = try? String(contentsOf: url) else {
            fatalError("Could not load sessionConfig.json")
        }
        
        // Escape newlines and quotes in the system message
        let escapedMessage = systemMessageOnlyKccq12
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        return jsonString.replacingOccurrences(
            of: "{{KCCQ12_INSTRUCTIONS}}",
            with: escapedMessage
        )
    }
}
