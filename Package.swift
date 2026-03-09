// swift-tools-version:6.2

//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
// 
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
// 
// SPDX-License-Identifier: MIT
//

import class Foundation.ProcessInfo
import PackageDescription


let package = Package(
    name: "ENGAGE-HF-AI-Voice",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/FHIRModels.git", .upToNextMajor(from: "0.6.0")),
        .package(url: "https://github.com/toon-format/toon-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/StanfordSpezi/SpeziVapor.git", from: "0.1.0"),
        .package(url: "https://github.com/StanfordSpezi/SpeziLLM.git", from: "0.13.6")
    ] + swiftLintPackage(),
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CryptoExtras", package: "swift-crypto"),
                .product(name: "ModelsR4", package: "FHIRModels"),
                .product(name: "ToonFormat", package: "toon-swift"),
                .product(name: "SpeziVapor", package: "SpeziVapor"),
                .product(name: "SpeziLLMOpenAIRealtime", package: "SpeziLLM")
            ],
            resources: [
                .process("Resources/vitalSigns.json"),
                .process("Resources/kccq12.json"),
                .process("Resources/kccq12Short.json"),
                .process("Resources/q17.json"),
                .copy("Resources/MockData")
            ],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")],
            plugins: [] + swiftLintPlugin()
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "SpeziVaporTesting", package: "SpeziVapor")
            ],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")],
            plugins: [] + swiftLintPlugin()
        )
    ]
)


func swiftLintPlugin() -> [Target.PluginUsage] {
    // Fully quit Xcode and open again with `open --env SPEZI_DEVELOPMENT_SWIFTLINT /Applications/Xcode.app`
    if ProcessInfo.processInfo.environment["SPEZI_DEVELOPMENT_SWIFTLINT"] != nil {
        [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")]
    } else {
        []
    }
}

func swiftLintPackage() -> [PackageDescription.Package.Dependency] {
    if ProcessInfo.processInfo.environment["SPEZI_DEVELOPMENT_SWIFTLINT"] != nil {
        [.package(url: "https://github.com/realm/SwiftLint.git", from: "0.55.1")]
    } else {
        []
    }
}
