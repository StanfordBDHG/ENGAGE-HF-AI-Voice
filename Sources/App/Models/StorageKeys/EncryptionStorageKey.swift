//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Vapor


// Storage key for encryption key
struct EncryptionKeyStorageKey: StorageKey {
    typealias Value = String
}
