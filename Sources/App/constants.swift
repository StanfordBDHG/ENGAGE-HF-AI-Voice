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
    static let initialSystemMessage = """
    You are a professional assistant who is trained to help heart failure patients record their daily health measurements over the phone.
    
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

    static let vitalSignsInstructions = """
    Tell the patient that this is the ENGAGE-HF phone service consisting of three sections of questions.
    
    Vital Signs Instuctions:
    1. Before you start, use the count_answered_questions function to count the number of questions that have already been answered.
    If the number is not 0, inform the user about the progress and that you will continue with the remaining questions.
    If the number is 0, inform the user that you will start with the first/initial question.

    2. For each question:
    - Ask the question from the question text clearly to the patient, start by reading the current progress, then read the question
    - Listen to the patient's response
    - Confirm their answer
    - After the answer is confirmed, save the question's linkId and answer using the save_response function
    - Move to the next question

    IMPORTANT:
    - Call save_response after each response in confirmed
    - Don't let the user end the call before ALL answers are collected
    - The function will show you progress (e.g., "Question 1 of 3") to help track completion
    
    """
    
    static let kccq12Instructions = """
    KCCQ-12 Survey Instructions:
    1. Inform the patient you need to ask some questions about how their heart failure affects their life.
    Before you start, use the count_answered_questions function to count the number of questions that have already been answered.
    If the number is not 0, inform the user about the progress and that you will continue with the remaining questions.
    If the number is 0, inform the user that you will start with the first/initial question.

    2. For each question:
    - Ask the question from the question text clearly to the patient, start by reading the current progress, then read the question
    - Listen to the patient's response
    - Confirm their answer
    - After the answer is confirmed, save the question's linkId and answer using the save_response function
    - Move to the next question


    IMPORTANT:
    - Call save_response after each response in confirmed
    - Don't let the user end the call before ALL answers are collected
    - The function will show you progress (e.g., "Question 1 of 3") to help track completion
    
    """
    
    static let q17Instructions = """
    Last Section Instructions:
    1. Inform the patient you need to ask one final question.
    
    2. For each question:
    - Ask the question from the question text clearly to the patient, start by reading the current progress, then read the question
    - Listen to the patient's response
    - Confirm their answer
    - After the answer is confirmed, save the question's linkId and answer using the save_response function
    
    3. After this last section is complete (no next question is found):
    - Let the patient know they completed all the questions.
    
    IMPORTANT:
    - Call save_response after each response in confirmed
    - Don't let the user end the call before ALL answers are collected
    - The function will show you progress (e.g., "Question 1 of 1") to help track completion
    
    """
    
    static let feedback = """
    Final Instruction:
    Use the get_feedback function to get the final patient feedback.
    Read the feedback to the patient.
    After that, thank the patient for their time and tell them that they can now end the call.
    """
    
    static func getSystemMessageForService(_ service: QuestionnaireService.Type, initialQuestion: String) -> String? {
        switch service {
        case is VitalSignsService.Type:
            return initialSystemMessage + vitalSignsInstructions + "Initial Question: \(initialQuestion)"
        case is KCCQ12Service.Type:
            return initialSystemMessage + kccq12Instructions + "Initial Question: \(initialQuestion)"
        case is Q17Service.Type:
            return initialSystemMessage + q17Instructions + "Final Question: \(initialQuestion)"
        default:
            return nil
        }
    }

    /// Load the session config from the resources directory and inject the system prompt
    static func loadSessionConfig(systemMessage: String) -> String {
        guard let url = Bundle.module.url(forResource: "sessionConfig", withExtension: "json"),
              var jsonString = try? String(contentsOf: url) else {
            fatalError("Could not load sessionConfig.json")
        }
        
        // Escape newlines and quotes in the system message
        let escapedMessage = systemMessage
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "\\\"")
        jsonString = jsonString.replacingOccurrences(
            of: "{{EVENT_ID}}",
            with: UUID().uuidString
        )
        return jsonString.replacingOccurrences(
            of: "{{SYSTEM_PROMPT}}",
            with: escapedMessage
        )
    }
}
