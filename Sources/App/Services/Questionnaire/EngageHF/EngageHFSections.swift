//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation

// swiftlint:disable file_types_order

// MARK: - Vital Signs Section

struct VitalSignsSection: QuestionnaireSection {
    let title = "Vital Signs"
    let resourceName = "vitalSigns"
    let directoryPath = Constants.vitalSignsDirectoryPath
    let sharesAllQuestions = true

    // swiftlint:disable line_length
    let instructions = """
        Section \(Constants.sectionIndexPlaceholder) of \(Constants.sectionCountPlaceholder): Vital Signs

        Instructions:
        - When you receive the initial question, it will include an `allQuestions` field listing all questions in this section.
          - Use this information to determine which `linkIds` are available for saving responses.
          - You can use it to handle related questions together when appropriate.
        - Always pronounce units in their long form; for example, say "millimeters of mercury" for "mmHg".
        - \(Constants.initialInstructionsPlaceholder)

        For each question:
        - Ask the question text clearly to the patient.
        - For the two blood pressure questions (linkIds: `systolic` and `diastolic`):
            - Ask for the blood pressure as a single, natural question (e.g., "What is your current blood pressure reading, in millimeters of mercury?").
            - Do NOT ask for systolic and diastolic as two separate questions upfront.
            - If the patient gives both values at once (e.g., "120 over 80"), interpret "X over Y" as systolic=X and diastolic=Y. Save both using two separate `save_response` calls with their respective linkIds.
            - If the patient gives only one number, ask for the other one. You may use the terms "systolic" (the top/first number) and "diastolic" (the bottom/second number) when clarifying.
            - Always confirm the values back to the patient, e.g., "I noted 120 as your systolic and 80 as your diastolic blood pressure."
            - If the patient seems to have swapped the values (e.g., systolic < diastolic), gently ask them to double-check and correct if needed before saving.
        - You may share the number of questions left and other progress updates to keep the patient engaged.
        - Listen to the patient's response and briefly answer any questions they might have.
        - Briefly repeat the patient's response back to them.
        - If there is ambiguity about the question, ask follow-up questions; save the response directly if clear.
        - Only use `null` as the answer if the patient explicitly says they want to skip or do not have the information. Never use `null` because of silence or unclear responses — re-ask instead.
        - Always save the answer using the question's `linkId` and the `save_response` function.
        - Move to the next question after saving. Keep the conversation fluent and engaging.

        IMPORTANT:
        - Call `save_response` after each response is confirmed, but only if it is within the expected range.
        - Do not let the patient end the call before all answers are collected.
        - If the patient does not respond clearly, re-ask the question. Do NOT skip or save a null answer unless the patient explicitly requests it.
        - The function will show progress (e.g., "Question 1 of 4") to help track section completion.
        """
    // swiftlint:enable line_length
}

// MARK: - KCCQ-12 Section

struct KCCQ12Section: QuestionnaireSection {
    let title = "KCCQ-12 Survey"
    let directoryPath = Constants.kccq12DirectoryPath
    let sharesAllQuestions = false

    let resourceName: String

    let instructions = """
        Section \(Constants.sectionIndexPlaceholder) of \(Constants.sectionCountPlaceholder): KCCQ-12 Survey

        Instructions:
        - Inform the patient that you need to ask some questions about how their heart failure affects their daily life.
        - \(Constants.initialInstructionsPlaceholder)

        For each question:
        - After every few questions, mention the number of questions left and other progress updates to keep the patient engaged.
        - Ask the question text clearly to the patient.
        - Do not list all answer options to keep the conversation natural!
        - Listen to the patient's response and briefly answer any questions they might have.
        - If there is ambiguity in how the response maps to the available options, ask follow-up questions to clarify.
        - Only save the response if you have asked the question and the patient has given a clear, explicit answer.
        - Do not guess or otherwise infer responses from previous answers.
        - If the patient does not respond, gives a vague answer, or just says "ok"/"sure"/"yeah", re-ask the question. Do NOT skip or move on.
        - Save the response directly if there is a clear mapping between the patient's answer and the available options.
        - Always save the answer using the question's `linkId` and the `save_response` function.
        - Move to the next question after saving. Keep the conversation fluent and engaging.

        IMPORTANT:
        - You must call the `save_response` function once you have determined the best-fitting answer based on the patient's response.
        - Do not let the patient end the call before all answers are collected.
        - If the patient does not respond clearly, re-ask the question. Do NOT skip or save a null answer unless the patient explicitly requests it.
        - The `save_response` function will return progress information (e.g., "Question 1 of 13") to help track completion of the current section.
        """

    init(internalTestingMode: Bool = false) {
        self.resourceName = internalTestingMode ? "kccq12Short" : "kccq12"
    }
}

// MARK: - Q17 Section

struct Q17Section: QuestionnaireSection {
    let title = "Last Section"
    let resourceName = "q17"
    let directoryPath = Constants.q17DirectoryPath
    let sharesAllQuestions = false

    let instructions = """
        Section \(Constants.sectionIndexPlaceholder) of \(Constants.sectionCountPlaceholder): Last Section

        Instructions:
        - Inform the patient that you need to ask one final question.

        For each question:
        - Let the patient know this is the last question.
        - Ask the question text clearly to the patient.
        - Do not list all answer options to keep the conversation natural!
        - Listen to the patient's response and briefly answer any questions they might have.
        - If there is ambiguity in how the response maps to the available options, ask follow-up questions to clarify.
        - If the patient does not respond clearly, re-ask the question. Do NOT skip or save a null answer unless the patient explicitly requests it.
        - Save the response directly if there is a clear mapping between the patient's answer and the available options.
        - Always save the answer using the question's `linkId` and the `save_response` function.

        IMPORTANT:
        - You must call the `save_response` function once you have determined the best-fitting answer based on the patient's response.
        - Do not let the patient end the call before all answers are collected.
        - After saving the last response with `save_response`, let the patient know that you are waiting for their feedback to be processed.
        """
}
