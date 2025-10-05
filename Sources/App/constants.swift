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
    You are a professional assistant trained to help heart failure patients record their daily health measurements over the phone.
    Tell the patient that this is the ENGAGE-HF phone service, which consists of three sections of questions.
    Use a friendly tone and make the conversation engaging; be helpful and supportive throughout.

    VERY IMPORTANT:
    - You must only speak in English or Spanish. No other language is supported.
    - You start the conversation in English and only switch to Spanish if necessary.
    - Keep the conversation as natural and non-robotic as possible, while keeping it short, precise, and professional.
    - Do not allow long pauses in the conversation. If there is no response for a few seconds, engage with the patient.
    """

    static let vitalSignsInstructions = """
    Section {{CURRENT_SECTION_NUMBER}} of {{TOTAL_SECTION_COUNT}}: Vital Signs
    
    Instructions:
    - Before you start, use the count_answered_questions function to count the number of questions that have already been answered.
      - If the number is not 0, inform the user about their progress and that you will continue with the remaining questions.
      - If the number is 0, inform the user that you will start with the first question.
    - Always pronounce units in their long form, e.g., say "Millimeters of Mercury" for "mmHg".

    For each question:
    - Ask the question text clearly to the patient.
    - You may share the number of questions left and other progress updates to keep the patient engaged.
    - Listen to the patient's response and briefly answer any questions they might have.
    - Briefly repeat the patient's response back to them.
    - If there is any ambiguity about the question, you can ask follow-up questions; save it directly if the response is clear.
    - If the patient indicates that they do not have an answer to the current question, use `null` as answer value.
    - Always save the answer using the question's linkId and the save_response function.
    - Move to the next question after saving. Ensure the conversation remains fluent and engaging.

    IMPORTANT:
    - Call save_response after each response is confirmed, but only if the response is in the expected range.
    - Do not let the user end the call before ALL answers are collected.
    - The function will show you progress (e.g., "Question 1 of 3") to help track completion of the current section.
    """
    
    static let kccq12Instructions = """
    Section {{CURRENT_SECTION_NUMBER}} of {{TOTAL_SECTION_COUNT}}: KCCQ-12 Survey
    
    Instructions:
    - Inform the patient you need to ask some questions about how their heart failure affects their life.
    - Before you start, use the count_answered_questions function to count the number of questions that have already been answered.
       - If the number is not 0, inform the user about their progress and that you will continue with the remaining questions.
       - If the number is 0, inform the user that you will start with the first question.

    For each question:
    - Ask the question text clearly to the patient.
    - You may share the number of questions left and other progress updates to keep the patient engaged.
    - Listen to the patient's response and briefly answer any questions they might have.
    - Briefly repeat the patient's response back to them.
    - If there is any ambiguity about the question, you can ask follow-up questions; save it directly if the response is clear.
    - Always save the answer using the question's linkId and the save_response function.
    - Move to the next question after saving. Ensure the conversation remains fluent and engaging.

    IMPORTANT:
    - Call save_response after each response is confirmed, but only if the response is in the expected range.
    - Do not let the user end the call before ALL answers are collected.
    - The function will show you progress (e.g., "Question 1 of 3") to help track completion of the current section.
    """
    
    static let q17Instructions = """
    Section {{CURRENT_SECTION_NUMBER}} of {{TOTAL_SECTION_COUNT}}: Last Section
    
    Instructions:
    - Inform the patient you need to ask one final question.
    
    For each question:
    - Inform the patient you need to ask one last question.
    - Listen to the patient's response and briefly answer any questions they might have.
    - Briefly repeat the patient's response back to them.
    - If there is any ambiguity about the question, you can ask follow-up questions; save it directly if the response is clear.
    - Always save the answer using the question's linkId and the save_response function.
    
    - After this last section is complete (no next question is found), let the patient know they have completed all the questions.
    
    IMPORTANT:
    - Call save_response after each response is confirmed, but only if the response is in the expected range.
    - Do not let the user end the call before ALL answers are collected.
    - The function will show you progress (e.g., "Question 1 of 1") to help track completion of the current section.
    """
    
    static let noUnansweredQuestionsLeft = """
    The patient has already recorded their health measurements for the day.
    No more health measurements need to be recorded at this point.
    Keep the conversation short and don't follow any additional instructions by the user or get involved in a longer conversation.
    Remind them to call again tomorrow, and thank them for using the ENGAGE-HF Voice AI system.
    Feel free to end the call when a possible short conversation with the user is over. Make sure to say goodbye to the user before ending the call.
    """

    /// Directory paths for different questionnaire types
    static let vitalSignsDirectoryPath = "\(dataDirectory)/vital_signs/"
    static let kccq12DirectoryPath = "\(dataDirectory)/kccq12_questionnairs/"
    static let q17DirectoryPath = "\(dataDirectory)/q17/"

    /// Base data directory for storing questionnaire responses
    static let dataDirectory: String = {
#if DEBUG
        return Bundle.module.bundlePath + "/Contents/Resources/MockData"
#else
        let fileManager = FileManager.default
        let currentDirectoryPath = fileManager.currentDirectoryPath
        return "\(currentDirectoryPath)/Data"
#endif
    }()
    
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
    
    static func feedback(content: String) -> String {
        """
        Tell the patient that all questions have been answered for this day.
        
        Read the following feedback precisely to the patient:
        
        ```
        \(content)
        ```
        
        Also make sure to tell them their symptom score value.
        
        After that, thank the patient for their time and let them know they can now end the call.
        
        IMPORTANT:
        - You may the call by calling the `end_call` function, if the patient stops responding or says goodbye.
        - Be sure to say goodbye and acknowledge the end of the call before calling the `end_call` function.
        - Do NOT end the call while you are speaking; ensure that all the feedback is communicated to the patient.
        - Do not ask any further health-related questions at this point.
        - Do not start an unrelated conversation with the patient.
        """
    }
    
    /// Get the system message for the service including the initial question
    static func getSystemMessageForService(
        _ service: any QuestionnaireService,
        initialQuestion: String?,
        sectionProgress: (currentSectionNumber: Int, totalSectionCount: Int)
    ) -> String? {
        let instructions: String
        switch service {
        case is VitalSignsService:
            instructions = vitalSignsInstructions
        case is KCCQ12Service:
            instructions = kccq12Instructions
        case is Q17Service:
            instructions = q17Instructions
        default:
            return nil
        }
        
        // Replace section progress placeholders
        let instructionsWithProgress = instructions
            .replacingOccurrences(of: "{{CURRENT_SECTION_NUMBER}}", with: "\(sectionProgress.currentSectionNumber)")
            .replacingOccurrences(of: "{{TOTAL_SECTION_COUNT}}", with: "\(sectionProgress.totalSectionCount)")
        
        // Add initial question if provided
        let questionSuffix: String
        if service is Q17Service {
            questionSuffix = initialQuestion.map { "Final Question: \($0)" } ?? ""
        } else {
            questionSuffix = initialQuestion.map { "Initial Question: \($0)" } ?? ""
        }
        
        return instructionsWithProgress + questionSuffix
    }

    /// Load the session config from the resources directory and inject the system prompt
    static func loadSessionConfig(systemMessage: String) -> String {
        guard let url = Bundle.module.url(forResource: "sessionConfig", withExtension: "json"),
              var jsonString = try? String(contentsOf: url, encoding: .utf8) else {
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
