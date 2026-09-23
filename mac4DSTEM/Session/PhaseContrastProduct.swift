//
//  PhaseContrastProduct.swift
//  Role: the one owner of the Parallax and single-slice ptychography
//        products and their run controls. Held by AppState as
//        `let phaseContrast = PhaseContrastProduct()`, no forwarding
//        properties; views read `phaseContrast.…`.
//        (docs/archive/v4/appstate-seams-plan.md, seam 1)
//
//  Every property stays a plain `package var` (not `private(set)`), unlike
//  `StrainProduct`'s `private(set)` + publish-method encapsulation:
//  `App/AppState+PhaseContrast.swift` and other call sites
//  (`App/AppState+Calibration.swift`, `Support/ResultExport.swift`) assign
//  or clear these directly with ad hoc multi-property resets (e.g.
//  `parallaxPreprocess = nil; parallaxAlignment = nil`). Wrapping them in
//  reset/publish methods would change every one of those call sites — a
//  later encapsulation pass can tighten this class if it rewrites the call
//  sites too.
//
//  What deliberately does NOT live here: `ptychography`
//  (`PtychographySettings`, its own owner — reconstruction run controls, not
//  a parallax stage) and the shared display derivation
//  (`resultImage`/`resultColormap`/`displayed*`) — AppState re-derives those
//  through `showParallaxProduct`'s `publishProduct` call.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation

/// Declared here, not in App/: a Session-layer owner cannot reference a
/// type defined in App/, and `parallaxResultProduct` below needs this enum
/// in scope.
package enum ParallaxResultProduct: String, CaseIterable, Identifiable, Sendable {
    case preprocess = "Preprocessed BF"
    case alignment = "Aligned BF"
    case subpixel = "Subpixel BF"
    case correctedPhase = "Corrected phase"
    case depth = "Depth plane"
    case iterativePhase = "Ptychography phase"
    case iterativeAmplitude = "Ptychography amplitude"
    case iterativeProbePhase = "Probe phase"
    case iterativeProbeAmplitude = "Probe amplitude"

    package var id: String { rawValue }
}

@Observable
@MainActor
package final class PhaseContrastProduct {

    // Explicit so the default initializer is `package` (synthesized ones are internal).
    package nonisolated init() {}

    // MARK: - Six retained results

    package var parallaxPreprocess: ParallaxPreprocessResult?
    package var parallaxAberrationFit: ParallaxAberrationFitResult?
    package var parallaxCorrection: ParallaxAberrationCorrectionResult?
    package var parallaxSubpixel: ParallaxSubpixelResult?
    package var parallaxDepth: ParallaxDepthResult?
    package var singleslicePtychography: SingleslicePtychographyResult?

    // MARK: - Sixteen run controls, plus the selected depth plane and product

    package var parallaxKDEUpsampleFactor: Double = 0
    package var parallaxKDESigmaPixels: Double = 0.125
    package var parallaxKDELowpass = false
    package var parallaxKDELanczosOrder = 0
    package var parallaxPositionCorrectionIterations = 0
    package var parallaxPositionCorrectionCheckerboard = false
    package var parallaxDepthStartAngstrom: Double = -256
    package var parallaxDepthEndAngstrom: Double = 256
    package var parallaxDepthPlaneCount = 33
    package var parallaxDepthUseFullFit = true
    package var parallaxDepthInformationLimit: Double = 0
    package var parallaxDepthInformationPower: Double = 1
    package var parallaxDepthSelectedIndex = 0
    package var parallaxResultProduct: ParallaxResultProduct = .preprocess
    package var parallaxQLowpassInvAngstrom: Double = 0
    package var parallaxQHighpassInvAngstrom: Double = 0

    // MARK: - The two cascading didSets

    /// A higher-order re-fit invalidates the phase correction and depth
    /// sections computed from the PRIOR fit.
    package var parallaxHigherOrderFit: ParallaxHigherOrderAberrationFitResult? {
        didSet {
            parallaxCorrection = nil
            parallaxDepth = nil
        }
    }

    /// A new (or reset) alignment invalidates every later stage: the
    /// aberration fit, the higher-order fit (which cascades further, above),
    /// the KDE subpixel reconstruction and the depth sections.
    package var parallaxAlignment: ParallaxAlignmentResult? {
        didSet {
            parallaxAberrationFit = nil
            parallaxHigherOrderFit = nil
            parallaxSubpixel = nil
            parallaxDepth = nil
        }
    }
}
