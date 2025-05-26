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
    
    \(vitalSignsInstructions)
    """
    // \(kccq12Instructions)
    
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

    static let vitalSignsInstructions = """
    Vital Signs Instuctions:
    1. Tell the patient that this is the ENGAGE-HF phone service and inform the patient you need to ask some questions about their health and wellbeing.
    Before you start, use the count_answered_vitalSign_questions function to count the number of questions that have already been answered.
    If the number is not 0, inform the user about the progress and that you will continue with the remaining questions.
    If the number is 0, inform the user that you will start with the first question.

    2. For each question:
    - Use the get_vitalSign_question function to get the next question
    - The function will return a JSON object containing the progress and question (with question text, linkId, and available answer options)
    - Ask the question from the question text clearly to the patient, start by reading the current progress, then read the question
    - Listen to the patient's response
    - Confirm their answer
    - After the answer is confirmed, save the question's linkId and response using the save_vitalSign_response function
    - Move to the next question

    3. After the vital signs survey is complete, let the patient know they completed the vital signs section.
    Call get_vitalSign_question one last time in the end.
    
    IMPORTANT:
    - Call get_vitalSign_question for each question individually
    - Call save_vitalSign_response after each response in confirmed
    - Don't let the user end the call before ALL answers are collected
    - The function will show you progress (e.g., "Question 1 of 3") to help track completion
    """
    
    static let kccq12Instructions = """
    KCCQ-12 Survey Instructions:
    1. Inform the patient you need to ask some questions about how their heart failure affects their life.
    Before you start, use the count_answered_kccq12_questions function to count the number of questions that have already been answered.
    If the number is not 0, inform the user about the progress and that you will continue with the remaining questions.
    If the number is 0, inform the user that you will start with the first question.

    2. For each question:
    - Use the get_kccq12_question function to get the next question
    - The function will return a JSON object containing the progress and question (with question text, linkId, and available answer options)
    - Ask the question from the question text clearly to the patient, start by reading the current progress, then read the question
    - Listen to the patient's response
    - Confirm their answer and map it to the correct response code
    - After the answer is confirmed, save the question's linkId and response code using the save_kccq12_response function
    - Move to the next question

    3. After the KCCQ-12 survey is complete, let the patient know they completed the KCCQ-12 section.
    Call get_kccq12_question one last time in the end.
    
    IMPORTANT:
    - Call get_kccq12_question for each question individually
    - Call save_kccq12_response after each response in confirmed
    - Don't let the user end the call before ALL answers are collected
    - The function will show you progress (e.g., "Question 1 of 13") to help track completion
    """
    
    static let q17Instructions = """
    Last Question Instructions:
    1. Inform the patient you need to ask one final question.
    
    2. For this last question:
    - Use the get_q17_question function to get the question
    - The function will return a JSON object containing the progress and question (with question text, linkId, and available answer options)
    - Ask the question from the question text clearly to the patient
    - Listen to the patient's response
    - Confirm their answer and map it to the correct response code
    - After the answer is confirmed, save the question's linkId and response code using the save_q17_response function
    - Move to the next question
    
    3. After the Q17 survey is complete, let the patient know they completed the last section.
    Call get_q17_question one last time in the end.

    IMPORTANT:
    - Call get_q17_question for each question individually
    - Call save_q17_response after each response in confirmed
    - Don't let the user end the call before ALL answers are collected
    - The function will show you progress (e.g., "Question 1 of 1") to help track completion
    """
    
    static let feedback = """
    Final Instruction:
    Use the get_feedback function to get the final patient feedback.
    Read the feedback to the patient.
    After that, thank the patient for their time and tell them that they can now end the call.
    """

    /// Load the session config from the resources directory
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
