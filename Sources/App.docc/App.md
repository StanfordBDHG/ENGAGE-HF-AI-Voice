# ``ENGAGE-HF-AI-Voice``

<!--

This source file is part of the ENGAGE-HF-AI-Voice open source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
       
-->

A Vapor server integrating Twilio with OpenAI to enable AI-powered voice conversations for healthcare data collection.

## Overview

ENGAGE-HF-AI-Voice connects Twilio's telephony services with OpenAI's real-time API to conduct voice-based FHIR questionnaires. The system:

- Streams audio between Twilio and OpenAI in real-time
- Conducts structured healthcare conversations based on FHIR questionnaires
- Records patient responses in FHIR-compatible format
