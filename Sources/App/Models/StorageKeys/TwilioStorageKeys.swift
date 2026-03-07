//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Vapor

// swiftlint:disable file_types_order

struct TwilioAccountSidStorageKey: StorageKey {
    typealias Value = String
}

struct TwilioAPIKeyStorageKey: StorageKey {
    typealias Value = String
}

struct TwilioSecretStorageKey: StorageKey {
    typealias Value = String
}
