# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

A [Vapor](https://vapor.codes/) (Swift) server that bridges **OpenAI's Realtime API** with **phone calls** to conduct voice-based FHIR questionnaire sessions for heart failure patients (ENGAGE-HF study). The AI collects answers to three sequential questionnaire sections and delivers personalized feedback at the end.

## Commands

**Build:**
```bash
swift build
```

**Run tests:**
```bash
swift test
```

**Run a single test:**
```bash
swift test --filter "AppTests/health"
# or by test name:
swift test --filter "AppTests/testSymptomScoreCalculation"
```

**Run locally (Xcode):** Set environment variables in the scheme editor, then build and run. The server listens on port 5000 by default in DEBUG mode.

**Run with Docker:**
```bash
docker compose build
docker compose up app
```

**SwiftLint** is only enabled when `SPEZI_DEVELOPMENT_SWIFTLINT` env var is set. To use it, open Xcode with:
```bash
open --env SPEZI_DEVELOPMENT_SWIFTLINT /Applications/Xcode.app
```

## Architecture

### Call Flow

1. OpenAI posts to `POST /incoming-call` (webhook, verified via Standard Webhooks HMAC-SHA256 if `OPENAI_WEBHOOK_SECRET` is set).
2. `routes.swift` decodes the event and extracts the caller's phone number from SIP headers.
3. A `CallHandler` actor is created — it calls the OpenAI Realtime API to **accept** the call and opens a **WebSocket** connection to OpenAI.
4. A `CallSession` actor handles WebSocket messages from OpenAI. It dispatches `response.function_call_arguments.done` events to the appropriate handler (`save_response`, `count_answered_questions`, `end_call`).
5. When a questionnaire section completes, the session updates the OpenAI session instructions (via `session.update`) to transition to the next section's system prompt.
6. After all sections complete, feedback is generated and injected as the final system prompt.

### Questionnaire System

- **`QuestionnaireSection`** (protocol) — defines a section: its FHIR resource name, storage directory URL, system prompt `instructions` string, and whether to share all questions at once (`sharesAllQuestions`).
- **`FHIRQuestionnaireEngine`** — loads a FHIR R4 `Questionnaire` JSON from the bundle, tracks answered questions in a `QuestionnaireResponse`, exposes `nextQuestionJSON(includeAllQuestions:)` for the AI, and persists responses via `QuestionnaireResponseStore`.
- **`CallFlowCoordinator`** — owns an ordered array of engines, manages `currentIndex`, builds system messages by substituting `{{SECTION_INDEX}}`, `{{SECTION_COUNT}}`, and `{{INITIAL_INSTRUCTION}}` placeholders into each section's `instructions` string.
- **`QuestionnaireResponseStore`** — handles disk I/O: loads FHIR questionnaire JSON from the bundle, loads/saves `QuestionnaireResponse` files (optionally AES-encrypted). In `DEBUG`, data is written to `Sources/App/Resources/MockData/`; in release, to `./Data/`.

### Feedback

- **`FeedbackProvider`** (protocol) — receives all engines after completion and returns a feedback string.
- **`EngageHFFeedbackProvider`** reads vital signs, KCCQ-12 symptom score, and condition change (Q17), then runs a decision tree (`FeedbackDecisionTreeBuilder`) to produce the final feedback message.

### Configured Sections (in order)

| # | Section | Resource | Directory |
|---|---------|----------|-----------|
| 1 | Vital Signs | `vitalSigns.json` | `vital_signs/` |
| 2 | KCCQ-12 Survey | `kccq12.json` (or `kccq12Short.json` in testing mode) | `kccq12_questionnairs/` |
| 3 | Q17 (condition change) | `q17.json` | `q17/` |

### Adding a New Questionnaire Section

1. Add a FHIR R4 questionnaire JSON to `Sources/App/Resources/`.
2. Add a directory constant to `constants.swift`.
3. Create a struct conforming to `QuestionnaireSection` (see `EngageHFSections.swift` for examples).
4. Inject it into the `sections` array in `CallHandler.init` (in `CallHandler.swift`).

## Key Environment Variables

| Variable | Required (prod) | Purpose |
|----------|-----------------|---------|
| `OPENAI_API_KEY` | Yes | OpenAI API authentication |
| `OPENAI_WEBHOOK_SECRET` | No | Verify incoming webhook signatures (`whsec_...` format) |
| `ENCRYPTION_KEY` | No | Base64-encoded 32-byte key for encrypting stored responses |
| `RECORDINGS_DECRYPTION_KEY` | No | Twilio private key for decrypting call recordings |
| `TWILIO_ACCOUNT_SID` | No | Twilio account SID |
| `TWILIO_API_KEY` | No | Twilio API key |
| `TWILIO_SECRET` | No | Twilio API secret |
| `INTERNAL_TESTING_MODE` | No | Enables repeated daily calls and uses the shorter KCCQ-12 |
| `PORT` | No | Server port (default: 5000) |

## Important Behaviors

- **MockData in DEBUG**: In `#if DEBUG` builds, responses are stored in `Sources/App/Resources/MockData/` (committed to repo for test fixtures). Tests rely on pre-populated mock data here — do not delete these files.
- **Twilio recording updates**: `updateCallRecordings()` in `CallHandler` is wrapped in `#if !DEBUG` — it only runs in production.
- **Anonymous callers**: If the SIP `From` header does not contain a valid E.164 phone number, a random UUID-based identifier is used (`"Unknown-<UUID>"`).
- **Session config**: `Sources/App/Resources/sessionConfig.json` controls the OpenAI session (voice, available functions, etc.). The `{{SYSTEM_PROMPT}}` placeholder is substituted at runtime via `Constants.loadSessionConfig(systemMessage:)`.
- **Swift 6 concurrency**: The project uses Swift 6.2 with `ExistentialAny` enabled. `FHIRQuestionnaireEngine` and `QuestionnaireResponseStore` are `@MainActor` classes. `CallHandler` and `CallSession` are actors.
