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


/// Service for managing vital signs questionnaire
@MainActor
class VitalSignsService: BaseQuestionnaireService, Sendable {
    init(phoneNumber: String, logger: Logger, featureFlags: FeatureFlags, encryptionKey: String? = nil) {
        super.init(
            questionnaireName: "vitalSigns",
            directoryPath: Constants.vitalSignsDirectoryPath,
            phoneNumber: phoneNumber,
            logger: logger,
            sharesAllQuestionsIfNeeded: true,
            featureFlags: featureFlags,
            encryptionKey: encryptionKey
        )
    }
}
