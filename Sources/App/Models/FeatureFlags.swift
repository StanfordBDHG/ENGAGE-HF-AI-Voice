//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Vapor

/// Feature flags for controlling application behavior
/// These can be overridden by environment variables
struct FeatureFlags {
    /// Enable internal testing mode
    /// Environment variable: INTERNAL_TESTING_MODE
    /// Default: false
    let internalTestingMode: Bool
    
    /// Initialize feature flags from environment variables
    init() {
        self.internalTestingMode = Environment.get("INTERNAL_TESTING_MODE")?.lowercased() == "true"
    }
    
    /// Initialize feature flags with custom values (useful for testing)
    init(internalTestingMode: Bool = false) {
        self.internalTestingMode = internalTestingMode
    }
}

/// Extension to make feature flags easily accessible from Application
extension Application {
    var featureFlags: FeatureFlags {
        get {
            storage[FeatureFlagsStorageKey.self] ?? FeatureFlags()
        }
        set {
            storage[FeatureFlagsStorageKey.self] = newValue
        }
    }
}

/// Extension to make feature flags easily accessible from Request
extension Request {
    var featureFlags: FeatureFlags {
        application.featureFlags
    }
}
