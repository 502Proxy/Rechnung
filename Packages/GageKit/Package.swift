// swift-tools-version: 6.0
import PackageDescription

/// Strict concurrency checking is enabled for all modules. The package still
/// builds in Swift 5 language mode; switching to `.v6` is tracked in docs/adr/0005.
let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
]

let package = Package(
    name: "GageKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GageCore", targets: ["GageCore"]),
        .library(name: "GageSecurity", targets: ["GageSecurity"]),
        .library(name: "GagePersistence", targets: ["GagePersistence"]),
        .library(name: "GageIntegrations", targets: ["GageIntegrations"]),
        .library(name: "GageUI", targets: ["GageUI"]),
    ],
    targets: [
        // Domain and application logic. Depends on Foundation only.
        .target(name: "GageCore", swiftSettings: strictSettings),
        // Keychain, encryption, hashing, device-owner authentication.
        .target(name: "GageSecurity", dependencies: ["GageCore"], swiftSettings: strictSettings),
        // Encrypted local store and invoice archive.
        .target(name: "GagePersistence", dependencies: ["GageCore", "GageSecurity"], swiftSettings: strictSettings),
        // bunq API, Apple Calendar (EventKit), Apple Mail.
        .target(name: "GageIntegrations", dependencies: ["GageCore", "GageSecurity"], swiftSettings: strictSettings),
        // SwiftUI presentation layer.
        .target(
            name: "GageUI",
            dependencies: ["GageCore", "GageSecurity", "GagePersistence", "GageIntegrations"],
            swiftSettings: strictSettings
        ),

        .testTarget(name: "GageCoreTests", dependencies: ["GageCore"], swiftSettings: strictSettings),
        .testTarget(name: "GageSecurityTests", dependencies: ["GageSecurity"], swiftSettings: strictSettings),
        .testTarget(
            name: "GagePersistenceTests",
            dependencies: ["GagePersistence", "GageSecurity", "GageCore"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "GageIntegrationsTests",
            dependencies: ["GageIntegrations", "GageSecurity", "GageCore"],
            swiftSettings: strictSettings
        ),
    ],
    swiftLanguageModes: [.v5]
)
