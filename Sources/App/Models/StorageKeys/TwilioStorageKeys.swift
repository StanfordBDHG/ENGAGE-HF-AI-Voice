//
//  TwilioStorageKeys.swift
//  ENGAGE-HF-AI-Voice
//
//  Created by Paul Kraft on 05.10.2025.
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
