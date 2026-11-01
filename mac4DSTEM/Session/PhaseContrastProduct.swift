//
//  PhaseContrastProduct.swift
//  Role: the one owner of the Parallax and single-slice ptychography
//        products and their run controls. Held by AppState as
//        `let phaseContrast = PhaseContrastProduct()`, no forwarding
//        properties; views read `phaseContrast.…`.
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
import struct CuboParallax.ParallaxAberrationFitResult
import struct CuboParallax.ParallaxHigherOrderAberrationFitResult
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
    /// The defocus and fitted aberrations the retained reconstruction's probe STARTED from (lane R1), read from the result itself
    /// (`SingleslicePtychographyResult.probeAberrations`, copied from the input `prepare` built) - there is no second copy to drift.
    package var singleslicePtychographyProbe: PtychographyProbeAberrations? { singleslicePtychography?.probeAberrations }

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

    // MARK: - What the held KDE and depth products ran with

    /// The controls the held `parallaxSubpixel` / `parallaxDepth` ran with, for
    /// the replay record (`ParallaxReplayPlan`). The results carry their
    /// resolved values, not the controls (the heuristic upsample factor, the
    /// depth list rather than its start, end and count). Read only while the
    /// matching result is held: a site that clears the result leaves these
    /// behind, and the record builder never reads them then.
    package var parallaxSubpixelControls: ReplayStepPlan.ParallaxReplayPlan.Subpixel?
    package var parallaxDepthControls: ReplayStepPlan.ParallaxReplayPlan.Depth?

    /// The KDE controls as the fields hold them now.
    package var parallaxSubpixelSettings: ReplayStepPlan.ParallaxReplayPlan.Subpixel {
        .init(upsampleFactor: parallaxKDEUpsampleFactor, kdeSigmaPixels: parallaxKDESigmaPixels,
              lowpass: parallaxKDELowpass, lanczosOrder: parallaxKDELanczosOrder,
              positionCorrectionIterations: parallaxPositionCorrectionIterations,
              positionCorrectionCheckerboard: parallaxPositionCorrectionCheckerboard)
    }

    /// The phase-correction filters as the fields hold them now.
    package var parallaxCorrectionSettings: ReplayStepPlan.ParallaxReplayPlan.Correction {
        .init(qLowpassInvAngstrom: parallaxQLowpassInvAngstrom, qHighpassInvAngstrom: parallaxQHighpassInvAngstrom)
    }

    /// The depth controls as the fields hold them now.
    package var parallaxDepthSettings: ReplayStepPlan.ParallaxReplayPlan.Depth {
        .init(startAngstrom: parallaxDepthStartAngstrom, endAngstrom: parallaxDepthEndAngstrom,
              planeCount: parallaxDepthPlaneCount, useFullFit: parallaxDepthUseFullFit,
              informationLimitInvAngstrom: parallaxDepthInformationLimit,
              informationPower: parallaxDepthInformationPower)
    }

    /// Put a recorded run's controls back (the replay executor); a stage the
    /// run did not reach keeps its fields.
    package func apply(_ plan: ReplayStepPlan.ParallaxReplayPlan) {
        if let s = plan.subpixel {
            parallaxKDEUpsampleFactor = s.upsampleFactor
            parallaxKDESigmaPixels = s.kdeSigmaPixels
            parallaxKDELowpass = s.lowpass
            parallaxKDELanczosOrder = s.lanczosOrder
            parallaxPositionCorrectionIterations = s.positionCorrectionIterations
            parallaxPositionCorrectionCheckerboard = s.positionCorrectionCheckerboard
        }
        if let c = plan.correction {
            parallaxQLowpassInvAngstrom = c.qLowpassInvAngstrom
            parallaxQHighpassInvAngstrom = c.qHighpassInvAngstrom
        }
        if let d = plan.depth {
            parallaxDepthStartAngstrom = d.startAngstrom
            parallaxDepthEndAngstrom = d.endAngstrom
            parallaxDepthPlaneCount = d.planeCount
            parallaxDepthUseFullFit = d.useFullFit
            parallaxDepthInformationLimit = d.informationLimitInvAngstrom
            parallaxDepthInformationPower = d.informationPower
        }
    }

    /// The step the held products make (`ParallaxReplayPlan`), nil with no
    /// preprocess. Correction's filters are read from its result, which
    /// carries them as run (nil for 0).
    package var parallaxReplayPlan: ReplayStepPlan.ParallaxReplayPlan? {
        guard let preprocess = parallaxPreprocess else { return nil }
        return .init(
            calibration: .init(preprocess.calibration),
            alignmentLevels: parallaxAlignment?.completedBins.count ?? 0,
            alignmentComplete: parallaxAlignment?.isComplete ?? false,
            alignmentStop: parallaxAlignment.flatMap { .init(completedBins: $0.completedBins) },
            fitsAberrations: parallaxHigherOrderFit != nil,
            subpixel: parallaxSubpixel == nil ? nil : parallaxSubpixelControls,
            correction: parallaxCorrection.map {
                .init(qLowpassInvAngstrom: $0.qLowpassInvAngstrom ?? 0, qHighpassInvAngstrom: $0.qHighpassInvAngstrom ?? 0)
            },
            depth: parallaxDepth == nil ? nil : parallaxDepthControls)
    }

    /// The staleness signature over the controls of each later stage whose
    /// product is held, read from the fields.
    package var parallaxCurrentSignature: [String: String] {
        ReplayStepPlan.ParallaxReplayPlan.currentSignature(
            subpixel: parallaxSubpixel == nil ? nil : parallaxSubpixelSettings,
            correction: parallaxCorrection == nil ? nil : parallaxCorrectionSettings,
            depth: parallaxDepth == nil ? nil : parallaxDepthSettings)
    }

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
