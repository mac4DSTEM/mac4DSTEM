// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-only
// DSTEMCore — Core/ compiled as a standalone module (v2.5 step 2, 2026-09-02).
//
// The Xcode app target links these two products (`packageProductDependencies`);
// the package is also what makes `swift build` fail the moment Core/ reaches
// upward into App/, UI/ or Support/, and lets Core build and test from the
// shell without Xcode's DerivedData footprint.
// Settings mirror the app target (Swift 5 mode, MainActor default isolation,
// approachable concurrency, MemberImportVisibility). `tools/run-tests.sh core`
// runs it; CI runs it on every push.
import PackageDescription

/// The settings every target here shares.
let commonSwiftSettings: [SwiftSetting] = [
    // Optimised in Debug too (2026-09-30): the owner runs the Debug build, and a package's Debug is -Onone — the
    // Friedel origin pass ran its FFTs at a crawl there while the app module beside it was -O. `.unsafeFlags` keeps
    // DSTEMCore from resolving as a versioned remote dependency; nothing consumes it that way (it is an
    // `XCLocalSwiftPackageReference "."`).
    .unsafeFlags(["-O"], .when(configuration: .debug)),
    .swiftLanguageMode(.v5),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "mac4DSTEM",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DSTEMCore", targets: ["DSTEMCore"]),
        .library(name: "DSTEMSession", targets: ["DSTEMSession"]),
        .library(name: "DSTEMTraining", targets: ["DSTEMTraining"]),
        // The Quick Look rendering and preview card, shared by the two extensions and the unit tests (QuickLook/Shared).
        .library(name: "DSTEMQuickLook", targets: ["DSTEMQuickLook"]),
    ],
    // Standalone EDX (fit, quantification, the spectrum image) lives in SpectroKit since S4 (ADR 064); the file readers
    // (DM4, Velox EMD) and the one HDF5 lock are FormatoKit's since SpectroKit 0.4.0 (2026-10-15). The two move
    // TOGETHER and never apart: a process that linked an older SpectroKit's HDF5Serial beside FormatoKit's would have
    // two locks around one libhdf5 that is not thread-safe. SpectroKit 0.7.0 takes FormatoKit 0.4.0..<0.6.0;
    // since 0.4.0 FormatoKit ships libhdf5 as three dynamic-framework XCFrameworks (FormatoLibHDF5, FormatoLibSZ, FormatoLibAEC) that Xcode
    // embeds in Contents/Frameworks and signs with the app's identity. Version ranges up to the next major; the two Package.resolved files
    // (this package's and the Xcode workspace's) hold the versions built, and a package update moves them.
    dependencies: [
        .package(url: "https://github.com/mac4DSTEM/SpectroKit", from: "0.13.1"),
        .package(url: "https://github.com/mac4DSTEM/FormatoKit", from: "0.12.1"),
        // The crystallography (cells, CIF, structure factors, the ring and ellipse fit) is DiffractoKit's and the 4D core
        // (virtual imaging, mean and max, centre of mass, origins) CuboKit's since 2026-10-15.
        .package(url: "https://github.com/mac4DSTEM/DiffractoKit", from: "0.11.0"),
        .package(url: "https://github.com/mac4DSTEM/CuboKit", from: "0.10.0"),
        // The exact-length 2D FFT (FFT2D) is ImagoKit's ImagoCore since 2026-10-15 (GPL-3.0 from 0.1.1; the app's copy was its origin,
        // the same arithmetic) and FFT1D (ACOM) is ImagoFFT's since 0.1.1. Only DSTEMCore uses it.
        .package(url: "https://github.com/mac4DSTEM/ImagoKit", from: "0.9.1"),
        // The window shell, controls and Metal image view both apps share (suite task 8). DSTEMCore takes ShellMetal only, for MetalEngine and ColormapKind.
        .package(url: "https://github.com/mac4DSTEM/MacEMUI", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "DSTEMCore",
            dependencies: [.product(name: "SpectroCore", package: "SpectroKit"),
                           .product(name: "SpectroEDX", package: "SpectroKit"),
                           .product(name: "FormatoCore", package: "FormatoKit"),
                           .product(name: "FormatoDM", package: "FormatoKit"),
                           .product(name: "FormatoEMD", package: "FormatoKit"),
                           .product(name: "FormatoHDF5", package: "FormatoKit"),
                           .product(name: "FormatoEMPAD", package: "FormatoKit"),
                           .product(name: "FormatoMIB", package: "FormatoKit"),
                           .product(name: "Formato", package: "FormatoKit"),
                           .product(name: "FormatoMSA", package: "FormatoKit"),
                           .product(name: "DiffractoCore", package: "DiffractoKit"),
                           .product(name: "DiffractoScattering", package: "DiffractoKit"),
                           .product(name: "DiffractoGeometry", package: "DiffractoKit"),
                           .product(name: "DiffractoOrientation", package: "DiffractoKit"),
                           .product(name: "CuboCore", package: "CuboKit"),
                           .product(name: "CuboVirtual", package: "CuboKit"),
                           .product(name: "CuboPhase", package: "CuboKit"),
                           .product(name: "CuboParallax", package: "CuboKit"),
                           .product(name: "CuboPtycho", package: "CuboKit"),
                           .product(name: "CuboStrain", package: "CuboKit"),
                           .product(name: "CuboBragg", package: "CuboKit"),
                           .product(name: "CuboEmbedding", package: "CuboKit"),
                           .product(name: "ImagoCore", package: "ImagoKit"),
                           .product(name: "ImagoFFT", package: "ImagoKit"),
                           .product(name: "ImagoFilters", package: "ImagoKit"),   // the EDS room's map filter (macTEM's EDXMapFilter)
                           .product(name: "ShellMetal", package: "MacEMUI"),
                           .product(name: "ShellEDXModel", package: "MacEMUI")],
            path: "mac4DSTEM/Core",
            // No `-DACCELERATE_NEW_LAPACK` any more: the LAPACK call it served (DiffractionEmbedding's `dsyevd_`) is CuboKit's.
            swiftSettings: commonSwiftSettings
        ),
        // Session layer (v2.5 step 2c): calibration state, products, recipes and
        // replay, sidecar location, recovery, residency — no SwiftUI, no AppState.
        .target(
            name: "DSTEMSession",
            dependencies: ["DSTEMCore", .product(name: "SpectroCore", package: "SpectroKit"),
                           .product(name: "SpectroEDX", package: "SpectroKit"),
                           .product(name: "FormatoCore", package: "FormatoKit"),
                           .product(name: "FormatoDM", package: "FormatoKit"),
                           .product(name: "FormatoEMD", package: "FormatoKit"),
                           .product(name: "FormatoHDF5", package: "FormatoKit"),
                           .product(name: "DiffractoCore", package: "DiffractoKit"),
                           .product(name: "DiffractoScattering", package: "DiffractoKit"),
                           .product(name: "DiffractoGeometry", package: "DiffractoKit"),
                           .product(name: "DiffractoOrientation", package: "DiffractoKit"),
                           .product(name: "CuboCore", package: "CuboKit"),
                           .product(name: "CuboVirtual", package: "CuboKit"),
                           .product(name: "CuboPhase", package: "CuboKit"),
                           .product(name: "CuboParallax", package: "CuboKit"),
                           .product(name: "ImagoCore", package: "ImagoKit"),
                           .product(name: "ShellMetal", package: "MacEMUI"),
                           .product(name: "ShellEDXModel", package: "MacEMUI"),
                           .product(name: "ShellLayout", package: "MacEMUI")],
            path: "mac4DSTEM/Session",
            swiftSettings: commonSwiftSettings
        ),
        // The Quick Look thumbnail pixels and the preview card (CoreGraphics and SwiftUI over FormatoKit's `Peek`): linked by the
        // QuickLookThumbnail and QuickLookPreview extensions and by the app, whose hosted unit tests read it.
        .target(
            name: "DSTEMQuickLook",
            dependencies: [.product(name: "FormatoPeek", package: "FormatoKit")],
            path: "QuickLook/Shared",
            swiftSettings: commonSwiftSettings
        ),
        // On-device fine-tuning of the learned disk detector (Phase C4a, ADR 048): the held-out split, the
        // detection scorer, the MPSGraph trainer, the model-package writer and the trained-model store. System
        // frameworks only (Metal, MetalPerformanceShadersGraph, CoreML, CryptoKit, Foundation): no package
        // dependency beyond DSTEMCore and CuboBragg. The app target links it (the detector training sheet).
        .target(
            name: "DSTEMTraining",
            dependencies: ["DSTEMCore", .product(name: "CuboBragg", package: "CuboKit")],
            path: "mac4DSTEM/Training",
            swiftSettings: commonSwiftSettings
        ),
    ]
)
