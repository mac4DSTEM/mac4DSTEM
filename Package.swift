// swift-tools-version: 6.2
// DSTEMCore — Core/ compiled as a standalone module (v2.5 step 2, 2026-09-02).
//
// The Xcode app target still compiles these same sources directly through its
// synchronized folder group; this package exists so that `swift build` fails
// the moment Core/ reaches upward into App/, UI/ or Support/, and so Core can
// be built and tested from the shell without Xcode's DerivedData footprint.
// Settings mirror the app target (Swift 5 mode, MainActor default isolation,
// approachable concurrency, MemberImportVisibility). `tools/run-tests.sh core`
// runs it; CI runs it on every push.
import PackageDescription

let package = Package(
    name: "mac4DSTEM",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DSTEMCore", targets: ["DSTEMCore"]),
        .library(name: "DSTEMSession", targets: ["DSTEMSession"]),
    ],
    targets: [
        .target(
            name: "DSTEMCore",
            path: "mac4DSTEM/Core",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("InferSendableFromCaptures"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // Session layer (v2.5 step 2c): calibration state, products, recipes and
        // replay, sidecar location, recovery, residency — no SwiftUI, no AppState.
        .target(
            name: "DSTEMSession",
            dependencies: ["DSTEMCore"],
            path: "mac4DSTEM/Session",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("InferSendableFromCaptures"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ]
)
