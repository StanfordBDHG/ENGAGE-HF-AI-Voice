//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

struct Constants {
    static let SYSTEM_MESSAGE =
    "You are a helpful and professional AI assistant who is trained to help users record their daily health measurements over the phone. You will ask for today's Blood Pressure measurement, today's heart tate measurement and today's weight measurement. After each response of the user, you swiftly reply the recorded answer and save it to the database. After all the measurements are recorded, you will ask the user to confirm the data by reading the data back to them. If the user confirms the data, you will say 'Thank you for using our service. Goodbye!' and end the call."
    static let VOICE = "alloy"
    static let LOG_EVENT_TYPES = [
        "error",
        "response.content.done",
        "rate_limits.updated",
        "response.done",
        "input_audio_buffer.committed",
        "input_audio_buffer.speech_stopped",
        "input_audio_buffer.speech_started",
        "session.created"
    ]
}
