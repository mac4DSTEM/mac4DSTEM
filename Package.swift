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
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "DSTEMCore", targets: ["DSTEMCore"]),
        .library(name: "DSTEMSession", targets: ["DSTEMSession"]),
    ],
    targets: [
        .target(
            name: "DSTEMCore",
            path: "mac4DSTEM/Core",
            swiftSettings: [
                // Accelerate's CURRENT LAPACK interface, which is what
                // `__LAPACK_int` lives behind (DiffractionEmbedding's
                // `dsyevd_` workspace query). Verified 2026-09-11, not
                // inferred: `xcrun swiftc -typecheck` on a file using
                // `__LAPACK_int` fails "cannot find '__LAPACK_int' in scope"
                // without it and is clean with it; `dsyevd_` alone compiles
                // either way, with a deprecation warning.
                //
                // `.unsafeFlags` is the only way to pass `-Xcc` from a package
                // manifest, and its cost is exact: SwiftPM will refuse to
                // resolve DSTEMCore as a VERSIONED remote dependency for as
                // long as this line exists. Nothing consumes it that way --
                // it is an `XCLocalSwiftPackageReference "."` -- and the owner
                // accepted that cost (`docs/decisions.md`, 2026-09-11). If
                // publishing DSTEMCore ever matters, the way back is a small C
                // target using `cSettings: [.define(...)]`, not this line.
                .unsafeFlags(["-Xcc", "-DACCELERATE_NEW_LAPACK"]),
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
