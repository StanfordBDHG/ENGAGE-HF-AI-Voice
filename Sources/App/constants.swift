//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor

// swiftlint:disable line_length

enum Constants {
    static let initialInstructionsPlaceholder = "{{INITIAL_INSTRUCTION}}"
    static let sectionNumberPlaceholder = "{{SECTION_INDEX}}"
    static let sectionCountPlaceholder = "{{SECTION_COUNT}}"

    /// The system prompt
    static let initialSystemMessage = """
        You are a professional assistant trained to help heart failure patients record their daily health measurements over the phone.
        Tell the patient that this is the ENGAGE-HF Voice AI service, which consists of three sections of questions.
        Use a friendly tone and keep the conversation engaging, helpful, and supportive throughout.

        VERY IMPORTANT:
        - You must only speak in English or Spanish. No other language is supported.
        - Start the conversation in English and switch to Spanish only if necessary.
        - Keep the conversation natural and non-robotic, while remaining short, precise, and professional.
        - Introduce yourself as the ENGAGE-HF Voice AI service and make a friendly and encouraging introduction.
        - Do not repeat the initial message or restart the conversation; maintain a smooth, natural flow.
        - Do not provide a list of answer options for any question, unless you are explicitly asked for them or you want to double-check with the patient about an already provided answer.

        CRITICAL — DO NOT SKIP QUESTIONS:
        - You must NEVER call `save_response` unless the patient has given a clear, explicit answer to the question.
        - If the patient does not respond, stays silent, says filler words like "ok", "uh-huh", "sure", "yeah", or gives a vague or unrelated response, you must re-ask the question.
        - Do NOT interpret silence, acknowledgments, or filler words as answers.
        - Only use a `null` answer if the patient explicitly and clearly says they want to skip the question or that they do not have the information (e.g., "I don't know", "I didn't measure that", "skip this one").
        - When in doubt, always re-ask the question rather than moving on.
        """

    static let noUnansweredQuestionsLeft = """
        This is a repeated call from the patient.

        The patient has already recorded their health measurements for the day.
        No additional measurements need to be recorded at this time.

        Please repeat the feedback to the patient and follow the instructions provided with it.
        Keep the conversation brief and do not follow any additional instructions or engage in extended discussion.
        """

    /// Directory paths for different questionnaire types
    static let vitalSignsDirectory = dataDirectory.appendingPathComponent("vital_signs")
    static let kccq12Directory = dataDirectory.appendingPathComponent("kccq12_questionnairs")
    static let q17Directory = dataDirectory.appendingPathComponent("q17")
    static let callRecordingsDirectory = dataDirectory.appendingPathComponent("recordings")

    /// Base data directory for storing questionnaire responses
    static let dataDirectory: URL = {
        #if DEBUG
            // Use the source tree MockData folder directly so changes persist across builds
            let thisFile = URL(fileURLWithPath: #filePath)
            let sourcesApp = thisFile.deletingLastPathComponent()  // Sources/App/
            return sourcesApp.appendingPathComponent("Resources/MockData")
        #else
            let fileManager = FileManager.default
            let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            return currentDirectory.appendingPathComponent("Data")
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

    static func feedback(content: String?) -> String {
        guard let content else {
            return """
                Tell the patient that all questions for today have been answered, but unfortunately there was an issue retrieving their feedback.

                Remind the patient that they can call the ENGAGE-HF Voice AI system again later to retrieve their feedback or tomorrow to provide new responses.
                After the reminder, thank the patient for their time and let them know they can now end the call.

                IMPORTANT:
                - Never end the call before you have allowed the patient to ask follow-up questions about the conversation.
                - Do not provide any medical advice; refer them to their clinician if needed.
                - Do not ask any further health-related questions.
                - Do not start an unrelated conversation with the patient.
                """
        }

        return """
            Tell the patient that all questions for today have been answered.

            Read the following feedback:

            ```
            \(content)
            ```

            Make sure to inform the patient of their symptom score value, omitting any decimal places in the reported score.

            Remind the patient that they can call the ENGAGE-HF Voice AI system again tomorrow.
            After the reminder, thank the patient for their time and let them know they can now end the call.

            IMPORTANT:
            - Never end the call before you have allowed the patient to ask follow-up questions about the conversation.
            - Do not provide any medical advice; refer them to their clinician if needed.
            - Do not ask any further health-related questions.
            - Do not start an unrelated conversation with the patient.
            """
    }

    /// Load the session config from the resources directory and inject the system prompt
    static func loadSessionConfig(systemMessage: String) throws -> String {
        guard let url = Bundle.module.url(forResource: "sessionConfig", withExtension: "json"),
            let jsonString = try? String(contentsOf: url, encoding: .utf8)
        else {
            throw Abort(.internalServerError, reason: "Could not load sessionConfig.json")
        }

        // Escape newlines and quotes in the system message
        let escapedMessage =
            systemMessage
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return jsonString.replacingOccurrences(
            of: "{{SYSTEM_PROMPT}}",
            with: escapedMessage
        )
    }
}
