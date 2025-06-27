//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4
import Vapor


/// Service for managing Q17 questionnaire
@MainActor
class Q17Service: BaseQuestionnaireService, Sendable {
    init(phoneNumber: String, logger: Logger, featureFlags: FeatureFlags, encryptionKey: String? = nil) {
        super.init(
            questionnaireName: "q17",
            directoryPath: Constants.q17DirectoryPath,
            phoneNumber: phoneNumber,
            logger: logger,
            featureFlags: featureFlags,
            encryptionKey: encryptionKey
        )
    }
}
