//
//  PhaseContrastProduct.swift
//  Role: seam 1 (docs/archive/v4/appstate-seams-plan.md) — the one owner of the Parallax
//        and single-slice ptychography products and their run controls. Held
//        by AppState as `let phaseContrast = PhaseContrastProduct()`, no
//        forwarding properties; views read `phaseContrast.…`.
//
//  Moved verbatim out of AppState.swift on 2026-09-18 (the seams plan, seam
//  1): the six results, sixteen run controls and the selected depth plane
//  and product, with their two `didSet` observers, keep their pre-seam
//  names, types, default values and didSet bodies. Every property stays a
//  plain `package var` (not `private(set)`) rather than following
//  `StrainProduct`'s `private(set)` + publish-method encapsulation: the
//  09-18 placement seam (a0ffb2a) already widened these exact 11 properties
//  from `private(set)` to plain `var` so `App/AppState+PhaseContrast.swift`
//  could keep assigning them directly, and several OTHER call sites
//  (`App/AppState+Calibration.swift`, `Support/ResultExport.swift`) also
//  assign or clear them directly with ad hoc multi-property resets (e.g.
//  `parallaxPreprocess = nil; parallaxAlignment = nil`). Wrapping those in
//  reset/publish methods would change each call site's statement structure,
//  which the seam rule against logic changes (plan §"Rules for every seam"
//  #2 — the diff must be identical except for the owner prefix and access
//  keywords) does not allow for this seam. This seam therefore REVERSES the
//  11 widenings (they move off AppState.swift's inventory entirely) without
//  reintroducing them here; a later encapsulation pass can tighten this
//  class to `private(set)` + methods if it also rewrites those call sites.
//
//  What deliberately does NOT live here: `ptychography`
//  (`PtychographySettings`, its own owner since 2026-09-17 — reconstruction
//  run controls, not a parallax stage) and the shared display derivation
//  (`resultImage`/`resultColormap`/`displayed*`) — AppState re-derives those
//  through `showParallaxProduct`'s `publishProduct` call.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation

/// Moved verbatim from `App/AppState.swift` with the state that switches on
/// it: a Session-layer owner cannot reference a type defined in App/, and
/// `parallaxResultProduct` below needs this enum in scope.
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

    // Explicit so the default initializer is `package` (synthesized ones are internal). // seam 1
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
