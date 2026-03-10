//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Spezi
import Vapor


/// A Spezi Module that holds all application-wide configuration, replacing individual storage keys.
final class AppConfigModule: Module, @unchecked Sendable {
    let openAIKey: String?
    let openAIWebhookSecret: String?
    let encryptionKey: String?
    let recordingsDecryptionKey: String?
    let twilioAccountSid: String?
    let twilioAPIKey: String?
    let twilioSecret: String?
    let featureFlags: FeatureFlags

    init(
        openAIKey: String?,
        openAIWebhookSecret: String?,
        encryptionKey: String?,
        recordingsDecryptionKey: String?,
        twilioAccountSid: String?,
        twilioAPIKey: String?,
        twilioSecret: String?,
        featureFlags: FeatureFlags
    ) {
        self.openAIKey = openAIKey
        self.openAIWebhookSecret = openAIWebhookSecret
        self.encryptionKey = encryptionKey
        self.recordingsDecryptionKey = recordingsDecryptionKey
        self.twilioAccountSid = twilioAccountSid
        self.twilioAPIKey = twilioAPIKey
        self.twilioSecret = twilioSecret
        self.featureFlags = featureFlags
    }

    /// Default initializer for testing — all optional values are nil, feature flags use defaults.
    convenience init() {
        self.init(
            openAIKey: nil,
            openAIWebhookSecret: nil,
            encryptionKey: nil,
            recordingsDecryptionKey: nil,
            twilioAccountSid: nil,
            twilioAPIKey: nil,
            twilioSecret: nil,
            featureFlags: FeatureFlags()
        )
    }
}
