<!--
                  
This source file is part of the ENGAGE-HF-AI-Voice open source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
             
-->

# ENGAGE HF AI-Voice

[![Build and Test](https://github.com/StanfordBDHG/SwiftPackageTemplate/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/StanfordBDHG/SwiftPackageTemplate/actions/workflows/build-and-test.yml)
[![codecov](https://codecov.io/gh/StanfordBDHG/SwiftPackageTemplate/branch/main/graph/badge.svg?token=X7BQYSUKOH)](https://codecov.io/gh/StanfordBDHG/SwiftPackageTemplate)
[![DOI](https://zenodo.org/badge/573230182.svg)](https://zenodo.org/badge/latestdoi/573230182)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FStanfordBDHG%2FSwiftPackageTemplate%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/StanfordBDHG/SwiftPackageTemplate)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FStanfordBDHG%2FSwiftPackageTemplate%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/StanfordBDHG/SwiftPackageTemplate)

**Engage HF AI-Voice** is a [Vapor](https://vapor.codes/) server that integrates Twilio with OpenAI’s real-time API (ChatGPT-4o) to enable voice-based conversations for healthcare data collection.

### Key Features

- **Twilio + OpenAI Integration**  
  Receives and streams audio to and from Twilio, relaying it in real-time to OpenAI's API.

- **Conversational AI on FHIR Questionnaires**  
  Configures ChatGPT-4o to conduct voice conversations based on a FHIR Questionnaire (e.g., `kccq12.json`) and records user responses in FHIR format on disk.

- **Customizable AI Behavior**  
  Includes function calling and system prompts to tailor the conversation flow and data handling.

---

## Configuration

You can customize the server in several ways:

- **Custom FHIR Questionnaire**  
  Replace the default FHIR R4 questionnaire (`Sources/App/Resources/kccq12.json`) with your own to change the conversation content.

- **System Message (AI Behavior)**  
  Edit the `systemMessage` constant in  
  `Sources/App/constants.swift`  
  This message sets the behavior of the AI and is passed to OpenAI during session initialization.

- **Session Configuration (Voice, Functions, etc.)**  
  Modify `sessionConfig.json` in  
  `Sources/App/Resources/`  
  This file controls OpenAI-specific parameters such as:
  - Which voice model to use
  - The available function calls (e.g., saving responses)
  - Other ChatGPT session settings

---

## Setup
You can either run the server in Xcode or using Docker.

### Xcode

To run the server locally using Xcode:

1. Add your OpenAI API key as an environment variable:
   - Open the **Scheme Editor** (`Product > Scheme > Edit Scheme…`)
   - Select the **Run** section and go to the **Arguments** tab.
   - Add a new environment variable:  
     ```
     OPENAI_API_KEY=your_key_here
     ```

2. Build and run the server in Xcode.
3. Start [ngrok](https://ngrok.com/) to expose the local server:
   ```bash
    ngrok http http://127.0.0.1:5000
    ```
4. In your Twilio Console, update the "A call comes in" webhook URL to match the forwarding address from ngrok, appending `/incoming-call`.
Example: `https://your-ngrok-url.ngrok-free.app/incoming-call`
5. Call your Twilio number and talk to the AI.

### Docker

To run the server using Docker:

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```
2. Open the **.env** file and insert your OpenAI API Key.
3. Build and start the server:
   ```bash
   docker compose build
   docker compose up app
   ```
4. Start [ngrok](https://ngrok.com/) to expose the local server:
   ```bash
    ngrok http http://127.0.0.1:8080
    ```
5. In your Twilio Console, update the "A call comes in" webhook URL to match the forwarding address from ngrok, appending `/incoming-call`.
Example: `https://your-ngrok-url.ngrok-free.app/incoming-call`
6. Call your Twilio number and talk to the AI.
---

## License
This project is licensed under the MIT License. See [Licenses](https://github.com/StanfordBDHG/ENGAGE-HF-AI-Voice/tree/main/LICENSES) for more information.

---

## Contributors
This project is developed as part of the Stanford Byers Center for Biodesign at Stanford University.
See [CONTRIBUTORS.md](https://github.com/StanfordBDHG/ENGAGE-HF-AI-Voice/tree/main/CONTRIBUTORS.md) for a full list of all ENGAGE-HF-AI-Voice contributors.

![Stanford Byers Center for Biodesign Logo](https://raw.githubusercontent.com/StanfordBDHG/.github/main/assets/biodesign-footer-light.png#gh-light-mode-only)
![Stanford Byers Center for Biodesign Logo](https://raw.githubusercontent.com/StanfordBDHG/.github/main/assets/biodesign-footer-dark.png#gh-dark-mode-only)
