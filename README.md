<!--
                  
This source file is part of the ENGAGE-HF-AI-Voice open source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
             
-->

# ENGAGE HF AI-Voice

[![Main](https://github.com/StanfordBDHG/ENGAGE-HF-AI-Voice/actions/workflows/main.yml/badge.svg)](https://github.com/StanfordBDHG/ENGAGE-HF-AI-Voice/actions/workflows/main.yml)
[![codecov](https://codecov.io/gh/StanfordBDHG/ENGAGE-HF-AI-Voice/graph/badge.svg?token=UqiQBJqfZY)](https://codecov.io/gh/StanfordBDHG/ENGAGE-HF-AI-Voice)

**Engage HF AI-Voice** is a [Vapor](https://vapor.codes/) server that integrates Twilio with OpenAI's real-time API (ChatGPT-4o) to enable voice-based conversations for healthcare data collection.

### Key Features

- **Twilio + OpenAI Integration**  
  Receives and streams audio to and from Twilio, relaying it in real-time to OpenAI's API.

- **Conversational AI on FHIR Questionnaires**  
  Configures ChatGPT-4o to conduct voice conversations based on FHIR Questionnaires and records user responses in FHIR format on disk (encrypted on rest).

- **Customizable Conversation Flow**  
  Configure the voice assistant with multiple questionnaires, custom system prompts, and flexible session settings to tailor the conversation flow and data handling.

---

## Configuration

The ENGAGE-HF-AI-Voice assistant is configured by default with **3 questionnaires** that are processed sequentially:

1. **Vital Signs** - Collects blood pressure, heart rate, and weight (4 questions)
2. **KCCQ12** - Kansas City Cardiomyopathy Questionnaire (12 questions)
3. **Q17** - A final question on how the patient feels compared to three months ago (1 question)

### Customizing the Conversation Flow

To customize the conversation flow and questions, you can replace or modify these services:

#### **Adding a New Questionnaire Service**

1. **Create a new service class** that conforms to `BaseQuestionnaireService` and `Sendable`:
   ```swift
   @MainActor
   class YourCustomService: BaseQuestionnaireService, Sendable {
       init(phoneNumber: String, logger: Logger) {
           super.init(
               questionnaireName: "yourQuestionnaire",
               directoryPath: Constants.yourQuestionnaireDirectoryPath,
               phoneNumber: phoneNumber,
               logger: logger
           )
       }
   }
   ```

2. **Add your FHIR R4 questionnaire JSON file** to `Sources/App/Resources/` (e.g., `yourQuestionnaire.json`)

3. **Add the directory path** to `Sources/App/constants.swift`:
   ```swift
   static let yourQuestionnaireDirectoryPath = "\(dataDirectory)/yourQuestionnaire/"
   ```

4. **Add questionnaire instructions** to `Sources/App/constants.swift`
   Define instructions that guide the AI on how to conduct this questionnaire section:
   ```swift
   static let yourQuestionnaireInstructions = """
   Your Questionnaire Section Instructions:
   - Inform the patient about this section
   - Use count_answered_questions to track progress
   - Ask each question clearly and confirm responses
   - Save responses using save_response function
   - Ensure all questions are answered before proceeding
   """
   ```

5. **Update the `getSystemMessageForService` function** in `Sources/App/constants.swift` to include your service:
   ```swift
   static func getSystemMessageForService(_ service: QuestionnaireService, initialQuestion: String) -> String? {
       switch service {
       // ... other cases ...
       case is YourCustomService: // add a case for your service
           return initialSystemMessage + yourQuestionnaireInstructions + "Initial Question: \(initialQuestion)"
       default:
           return nil
       }
   }
   ```

6. **Inject your service** into the `ServiceState` in `Sources/App/routes.swift`:
   ```swift
   let serviceState = await ServiceState(services: [
       /// ... other services ...
       YourCustomService(phoneNumber: callerPhoneNumber, logger: req.logger)  // Add your service
       /// ... other services ...
   ])
   ```

#### **Modifying Existing Services**

- **Replace a service**: Simply replace the service in the array with your custom implementation
- **Reorder services**: Change the order in the array to change the conversation flow
- **Remove services**: Remove services from the array to skip them

### Other Configuration Options

- **AI Behavior and System Prompts**  
  System prompts and instructions for each questionnaire section are defined in `Sources/App/constants.swift`. These control how the AI assistant interacts with patients and can be customized as needed.

- **Session Configuration (Voice, Functions, etc.)**  
  OpenAI session parameters (voice model, function calls, etc.) are configured in `sessionConfig.json` located in `Sources/App/Resources/`.

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
2. Open the **.env** file and insert your OpenAI API Key and optionally a encryption key if you wish to encrypt the response files (you can generate one using ``openssl rand -base64 32``).

   **Optional**: For internal testing, you can also set `INTERNAL_TESTING_MODE=true` which allows to do the survey multiple times per day and serves a reduced KCCQ12 section with only three questions to allow faster testing.
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

### Deployment

To deploy the service in a production environment, follow these steps:

0. **Prerequisites**
   - Install Docker and Docker Compose.

1. **Prepare the Deployment Directory**
   - Create a new directory on your target machine (e.g., `engage-hf-ai-voice`).
   - Copy the following files into this directory (e.g., via `scp` or by creating the files locally and pasting the content):
     - `docker-compose.prod.yml`
     - `nginx.conf`

2. **Configure Environment Variables**
   - Create a `.env` file in the deployment directory.
   - Add the following environment variables:
     ```bash
     # Required
     OPENAI_API_KEY=<your-openai-api-key>
     
     # Optional - Encryption key for storing questionnaire responses (base64-encoded 32 bytes)
     # Generate with: openssl rand -base64 32
     ENCRYPTION_KEY=<your-base64-encryption-key>
     
     # Optional - Enable internal testing mode (allows multiple surveys per day, reduced KCCQ12)
     INTERNAL_TESTING_MODE=false
     
     # Optional - Server port (default: 5000 for Xcode, 8080 for Docker)
     PORT=8080
     ```

3. **Set Up SSL Certificates (Docker Secrets)**
   - Create the required SSL certificate directories:
     ```bash
     sudo mkdir -p ./certs
     sudo mkdir -p ./private
     ```
   - Add your SSL certificates:
     - Place your certificate file with full certificate chain (e.g., `certificate.pem`) in `./certs`.
     - Place your private key file (e.g., `private.key`) in `./private`.
   - Ensure proper permissions:
     ```bash
     sudo chmod 644 ./certs/certificate.pem
     sudo chmod 640 ./private/private.key
     ```
   - These files are mounted as Docker secrets in the nginx container. If needed, adjust the `secrets` block in `docker-compose.prod.yml`:
   ```yaml
   secrets:
     cert_chain:
       file: ./certs/certificate.pem
     priv_key:
       file: ./private/private.key
   ```

4. **Adjust the App Data Volume**
By default the app uses a named volume `app-data`; data stays inside Docker.  
If you want data on the host, mount a host directory instead.

- Define the absolute path to the folder you would like to mount for the application data in the `docker-compose.prod.yml` file:
  ```yaml
  services:
    app:
      volumes:
        - "/Users/exampleuser/yourfolder:/app/data"
  ```

  Then you can delete named volume at the bottom section of the docker compose file.

5. **Start the Service**
   - Navigate to your deployment directory.
   - Run the following command to start the service in detached mode:
     ```bash
     docker compose -f docker-compose.prod.yml up -d
     ```

6. **Verify the Deployment**
   - The service should now be running and accessible via your configured domain.
   - Test the health check endpoint:
     ```bash
     curl -I https://voiceai-engagehf.stanford.edu/health
     ```

### Decrypting Stored Files

To decrypt questionnaire response files for analysis:

1. **Install Python cryptography library**:
   ```bash
   pip3 install cryptography
   ```

2. **Run the decryption script** (make sure you're in the directory containing the `/vital_signs`, `/kccq12_questionnairs`, and `/q17` folders):
   ```bash
   chmod +x decrypt_files.sh # make it executable
   ./decrypt_files.sh <your-base64-encryption-key>
   ```

The script will decrypt all files from `./vital_signs/`, `./kccq12_questionnairs/`, and `./q17/` directories and save them to `./decrypted/`.

---

## License
This project is licensed under the MIT License. See [Licenses](https://github.com/StanfordBDHG/ENGAGE-HF-AI-Voice/tree/main/LICENSES) for more information.

---

## Contributors
This project is developed as part of the Stanford Byers Center for Biodesign at Stanford University.
See [CONTRIBUTORS.md](https://github.com/StanfordBDHG/ENGAGE-HF-AI-Voice/tree/main/CONTRIBUTORS.md) for a full list of all ENGAGE-HF-AI-Voice contributors.

![Stanford Byers Center for Biodesign Logo](https://raw.githubusercontent.com/StanfordBDHG/.github/main/assets/biodesign-footer-light.png#gh-light-mode-only)
![Stanford Byers Center for Biodesign Logo](https://raw.githubusercontent.com/StanfordBDHG/.github/main/assets/biodesign-footer-dark.png#gh-dark-mode-only)

