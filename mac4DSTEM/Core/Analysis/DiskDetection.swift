//
//  DiskDetection.swift
//  Role: Bragg disk detection — the workhorse of 4DSTEM crystallography.
//        Port of py4DSTEM's find_Bragg_disks pipeline per pattern:
//
//   (1) hybrid cross-correlation with the probe kernel:
//         m  = FFT(pattern) · conj(FFT(kernel))
//         cc = |m|^p · exp(i·arg m)  =  m · |m|^(p−1)     (p = corrPower)
//         CC = max(Re(IFFT(cc)), 0)
//   (2) maxima of CC (optionally Gaussian-smoothed by sigmaCC), via strict
//       8-neighbor comparison (get_maxima_2D)
//   (3) the filter cascade: absolute / relative intensity, edge boundary,
//       min spacing (keep-brighter), max count
//   (4) subpixel refinement: parabolic ('poly'), or DFT-upsampled matrix-
//       multiply correlation ('multicorr', Guizar-Sicairos et al.) on the
//       UNsmoothed complex correlation — needed for strain-grade precision.
//
//  Coordinates: peaks are (x = detector column, y = row), app convention.
//  py4DSTEM's (qx, qy) has x as the row axis — translated here, nowhere else.
//
//  Steps (1)-(4) are CuboKit's (CuboBragg 0.6.0, Float32 `BraggPrecision.single`);
//  `DiskDetector` below maps the app's controls onto it. The full-scan pass is the kit's (`BraggDisks.detectAll`, CuboKit 0.7.0: bounded scan-row tiles, every core on a tile's patterns; `TiledDiskDetection.swift`). multicorr is
//  ~10× slower than poly per pattern — poly is the interactive default,
//  multicorr the strain-analysis choice.
//

import Foundation
import CuboBragg
import CuboVirtual

// MARK: - Types

/// One detected Bragg reflection, in detector pixels (x = column, y = row).
package nonisolated struct BraggPeak: Sendable {
    package var x: Float
    package var y: Float
    package var intensity: Float

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(x: Float, y: Float, intensity: Float) {
        self.x = x
        self.y = y
        self.intensity = intensity
    }
}

package nonisolated enum SubpixelMode: String, CaseIterable, Identifiable, Sendable {
    case pixel     = "Pixel"
    case poly      = "Parabolic"
    case multicorr = "Fourier (multicorr)"
    package var id: String { rawValue }

    package var provenanceID: String {
        switch self {
        case .pixel: "pixel"
        case .poly: "poly"
        case .multicorr: "multicorr"
        }
    }
}

/// Which stage proposes a scan position's peaks (v3-plan §3a). `.learned` is a
/// CANDIDATE stage only — a heatmap peak-pick, on the Neural Engine — never a
/// measurement on its own: `DiskDetector.refine` (the classical detector's own
/// snap-to-maximum, parabola, edge rule, spacing and cap) is what turns either
/// class's candidates into accepted `BraggPeak`s. `.classical` finds its own
/// candidates by exhaustive correlation-maxima search and refines those.
package nonisolated enum DetectorClass: String, Sendable, CaseIterable, Identifiable {
    case classical = "Classical"
    case learned = "Neural net"
    package var id: String { rawValue }

    package var provenanceID: String {
        switch self {
        case .classical: "classical"
        case .learned: "learned"
        }
    }
}

/// Stable parameter identifiers shared by the numerical detector, UI, tests,
/// and persisted provenance. UI labels are deliberately defined here so a
/// control cannot drift away from the quantity consumed by the core.
package nonisolated enum DiskDetectionParameterID: String, CaseIterable, Sendable {
    case correlationPower = "corr_power"
    case patternSigma = "sigma_dp_px"
    case correlationSigma = "sigma_cc_px"
    case subpixel = "subpixel"
    case upsampleFactor = "upsample_factor"
    case minimumAbsoluteIntensity = "min_absolute_intensity"
    case minimumRelativeIntensity = "min_relative_intensity"
    case relativeReferencePeak = "relative_to_peak"
    case relativeReferenceMinimumRadius = "relative_reference_minimum_radius_px"
    case minimumPeakSpacing = "min_peak_spacing_px"
    case edgeBoundary = "edge_boundary_px"
    case maximumPeaks = "max_num_peaks"

    package var title: String {
        switch self {
        case .correlationPower: "Correlation power"
        case .patternSigma: "Pattern smoothing σ"
        case .correlationSigma: "Correlation smoothing σ"
        case .subpixel: "Subpixel localization"
        case .upsampleFactor: "Fourier upsampling"
        case .minimumAbsoluteIntensity: "Minimum absolute"
        case .minimumRelativeIntensity: "Minimum relative"
        case .relativeReferencePeak: "Reference peak"
        case .relativeReferenceMinimumRadius: "Reference outside"
        case .minimumPeakSpacing: "Minimum spacing"
        case .edgeBoundary: "Edge exclusion"
        case .maximumPeaks: "Maximum peaks"
        }
    }

    package var explanation: String {
        switch self {
        case .correlationPower:
            "Hybrid-correlation exponent: 1 is cross-correlation, 0 is phase-correlation, and intermediate values mix both."
        case .patternSigma:
            "Gaussian σ in detector pixels applied to each diffraction pattern before correlation. Excessive smoothing can merge nearby features."
        case .correlationSigma:
            "Gaussian σ in detector pixels applied to the correlation map before maxima selection. Zero disables this smoothing."
        case .subpixel:
            "Pixel is fastest; Parabolic is the interactive default; Fourier multicorr uses matrix-DFT refinement for strain-grade localization."
        case .upsampleFactor:
            "Matrix-DFT upsampling used only by Fourier multicorr. Higher values refine the sampling at increased cost."
        case .minimumAbsoluteIntensity:
            "Minimum correlation-peak intensity on the absolute correlation scale. Zero disables this data- and kernel-dependent filter."
        case .minimumRelativeIntensity:
            "Minimum peak intensity as a fraction of the selected ranked reference peak. Zero disables the filter."
        case .relativeReferencePeak:
            "Intensity rank used by the relative filter. The UI calls the brightest candidate #1; the py4DSTEM-compatible stored parameter uses zero-based index 0."
        case .relativeReferenceMinimumRadius:
            "The relative filter's reference is the brightest candidate at least this many pixels from the brightest one, so a saturated direct beam does not set the scale wherever it sits. A flat plateau has maxima all over it: set at least its diameter. 0 keeps py4DSTEM's rule: the brightest candidate anywhere."
        case .minimumPeakSpacing:
            "Minimum center-to-center separation in detector pixels. When candidates are closer, the brighter one is retained."
        case .edgeBoundary:
            "Reject maxima whose centers lie within this many detector pixels of an edge. At least one pixel is needed for neighborhood testing."
        case .maximumPeaks:
            "Maximum number of accepted correlation maxima returned for each diffraction pattern."
        }
    }

    /// Recommended editor bounds. Dynamic detector-size and peak-rank bounds
    /// are supplied by `DiskDetectionContext` and `DiskDetectionParams`.
    package var editorRange: ClosedRange<Double>? {
        switch self {
        case .correlationPower: 0...1
        case .patternSigma, .correlationSigma: 0...10
        case .upsampleFactor: 4...64
        case .minimumRelativeIntensity: 0...1
        case .maximumPeaks: 1...500
        case .minimumAbsoluteIntensity, .subpixel, .relativeReferencePeak,
             .minimumPeakSpacing, .edgeBoundary, .relativeReferenceMinimumRadius: nil
        }
    }

    package var editorStep: Double? {
        switch self {
        case .correlationPower: 0.05
        case .patternSigma, .correlationSigma: 0.1
        case .upsampleFactor: 4
        case .minimumRelativeIntensity: 0.001
        case .maximumPeaks, .relativeReferencePeak, .minimumPeakSpacing,
             .edgeBoundary, .relativeReferenceMinimumRadius: 1
        case .minimumAbsoluteIntensity, .subpixel: nil
        }
    }
}

/// Compares the provenance a `BraggVectors` carries (`DiskDetectionParams.
/// provenance`, the sidecar's `mac4dstem_detection_provenance`) with the
/// parameters of a recorded `disk_detection` replay step
/// (`DiskDetectionParams.replayParameters` + the detector-class keys). The two
/// vocabularies name six keys differently (`sigma_dp_px` / `sigma_dp`, …), so
/// this table is the one place that says which is which. Used to decide
/// whether peaks restored from a sidecar are the peaks the recorded step made
/// (../_archive/mac4DSTEM/docs/registrations/bragg-restore-registration-2026-09-28.md).
package nonisolated enum DiskDetectionRecordMatch {
    /// (provenance key, step key). Every pair is REQUIRED: a step or a
    /// provenance that lacks one cannot be verified, and unverified peaks are
    /// not adopted.
    package static let requiredKeys: [(provenance: String, step: String)] = [
        (DiskDetectionParameterID.correlationPower.rawValue, "corr_power"),
        (DiskDetectionParameterID.patternSigma.rawValue, "sigma_dp"),
        (DiskDetectionParameterID.correlationSigma.rawValue, "sigma_cc"),
        (DiskDetectionParameterID.subpixel.rawValue, "subpixel"),
        (DiskDetectionParameterID.upsampleFactor.rawValue, "upsample_factor"),
        (DiskDetectionParameterID.minimumAbsoluteIntensity.rawValue, "min_absolute_intensity"),
        (DiskDetectionParameterID.minimumRelativeIntensity.rawValue, "min_relative_intensity"),
        (DiskDetectionParameterID.relativeReferencePeak.rawValue, "relative_to_peak"),
        (DiskDetectionParameterID.relativeReferenceMinimumRadius.rawValue,
         "relative_reference_minimum_radius_px"),
        (DiskDetectionParameterID.minimumPeakSpacing.rawValue, "min_peak_spacing"),
        (DiskDetectionParameterID.edgeBoundary.rawValue, "edge_boundary"),
        (DiskDetectionParameterID.maximumPeaks.rawValue, "max_peaks"),
        ("kernel_source", "kernel_source"),
        ("kernel_mode", "kernel_mode"),
    ]
    /// Same name on both sides, compared only when the step carries it (a
    /// classical step written before the detector class was recorded does not).
    package static let optionalKeys = ["detector_class", "learned_threshold", "learned_model_sha256"]

    /// The provenance restated in the recorded step's vocabulary, so it can be
    /// compared with `DiskDetectionParams.replayParameters` /
    /// `ProductWorkflow.stalenessVerdict`. A required key the provenance lacks
    /// maps to "" — which differs from any recorded value — so an unverifiable
    /// provenance reads as changed, never as matching.
    package static func stepSignature(fromProvenance provenance: [String: String]) -> [String: String] {
        var signature = [String: String]()
        for pair in requiredKeys { signature[pair.step] = provenance[pair.provenance] ?? "" }
        for key in optionalKeys { if let value = provenance[key] { signature[key] = value } }
        return signature
    }

    /// The detection controls a recorded step was run with: the
    /// `DiskDetectionParams` the Bragg-disks inspector edits, plus the detector
    /// class and (learned only) pick threshold the Detector picker edits.
    package struct Controls: Equatable, Sendable {
        package var params: DiskDetectionParams
        package var detectorClass: DetectorClass
        /// Nil for a classical step, or a learned one that recorded none.
        package var learnedThreshold: Float?

        package init(params: DiskDetectionParams, detectorClass: DetectorClass, learnedThreshold: Float?) {
            self.params = params
            self.detectorClass = detectorClass
            self.learnedThreshold = learnedThreshold
        }
    }

    /// The reverse of `DiskDetectionParams.replayParameters` (+ the detector
    /// class keys): the controls a recorded `disk_detection` step was run with,
    /// so peaks restored from a sidecar can seed the inspector with the
    /// settings they were detected with instead of detector defaults.
    /// Unlike `ReplayPlan.parse` this is not a replay: a step whose kernel was
    /// measured still names the controls its peaks were detected with, so the
    /// kernel keys are not judged here (there is no control for them — the
    /// kernel is built, not set). Nil when any control value is missing or
    /// malformed, so a partial seed never happens. `String(Float)` round-trips
    /// exactly, so the seeded controls restate the recorded step key for key.
    package static func controls(fromStepParameters p: [String: String]) -> Controls? {
        func float(_ key: String) -> Float? {
            guard let text = p[key], let value = Float(text), value.isFinite else { return nil }
            return value
        }
        func int(_ key: String) -> Int? { p[key].flatMap { Int($0) } }
        guard let corrPower = float("corr_power"), let sigmaDP = float("sigma_dp"),
              let sigmaCC = float("sigma_cc"),
              let subpixel = SubpixelMode.allCases.first(where: { $0.provenanceID == p["subpixel"] }),
              let upsample = int("upsample_factor"),
              let minAbsolute = float("min_absolute_intensity"),
              let minRelative = float("min_relative_intensity"),
              let relativeTo = int("relative_to_peak"),
              let radius = float("relative_reference_minimum_radius_px"), radius >= 0,
              let spacing = float("min_peak_spacing"), let edge = int("edge_boundary"),
              let maxPeaks = int("max_peaks") else { return nil }
        var params = DiskDetectionParams()
        params.corrPower = corrPower
        params.sigmaDP = sigmaDP
        params.sigmaCC = sigmaCC
        params.subpixel = subpixel
        params.upsampleFactor = upsample
        params.minAbsoluteIntensity = minAbsolute
        params.minRelativeIntensity = minRelative
        params.relativeToPeak = relativeTo
        params.relativeReferenceMinimumRadiusPx = radius
        params.minPeakSpacing = spacing
        params.edgeBoundary = edge
        params.maxNumPeaks = maxPeaks
        // Absent means classical, as in `ReplayPlan.parse`.
        switch p["detector_class"] {
        case nil, DetectorClass.classical.provenanceID?:
            return Controls(params: params, detectorClass: .classical, learnedThreshold: nil)
        case DetectorClass.learned.provenanceID?:
            return Controls(params: params, detectorClass: .learned, learnedThreshold: float("learned_threshold"))
        default:
            return nil
        }
    }

    /// The step keys whose values differ from the provenance's, sorted; empty
    /// means the provenance is the recorded step's. An empty provenance
    /// mismatches every required key.
    package static func mismatches(
        provenance: [String: String], stepParameters: [String: String]
    ) -> [String] {
        let signature = stepSignature(fromProvenance: provenance)
        var differing = [String]()
        for pair in requiredKeys {
            let recorded = stepParameters[pair.step]
            if recorded == nil || signature[pair.step] != recorded { differing.append(pair.step) }
        }
        for key in optionalKeys {
            if let recorded = stepParameters[key], signature[key] != recorded { differing.append(key) }
        }
        return differing.sorted()
    }
}

package nonisolated struct DiskDetectionContext: Sendable, Equatable {
    package let qy: Int
    package let qx: Int
    package let probeRadius: Float?

    package var detectorMinimum: Int { min(qx, qy) }
    package var maximumEdgeBoundary: Int { max(1, (detectorMinimum - 1) / 2) }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(qy: Int, qx: Int, probeRadius: Float?) {
        self.qy = qy
        self.qx = qx
        self.probeRadius = probeRadius
    }
}

package nonisolated enum DiskDetectionValidationSeverity: Sendable, Equatable {
    case warning
    case error
}

package nonisolated struct DiskDetectionValidationIssue: Sendable, Equatable {
    package let field: DiskDetectionParameterID
    package let severity: DiskDetectionValidationSeverity
    package let message: String

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(field: DiskDetectionParameterID, severity: DiskDetectionValidationSeverity, message: String) {
        self.field = field
        self.severity = severity
        self.message = message
    }
}

/// Per-pattern selection funnel. These diagnostics explain a zero- or
/// low-peak preview without changing the py4DSTEM-compatible filter order.
package nonisolated struct DiskDetectionPatternDiagnostics: Sendable, Equatable {
    package let localMaximumCount: Int
    package let afterAbsoluteThresholdCount: Int
    package let afterRelativeThresholdCount: Int
    package let afterSpacingCount: Int
    package let acceptedCount: Int
    package let wasCountLimited: Bool
    package let relativeReferenceIntensity: Float?
    package let relativeReferenceWasAvailable: Bool
    package let correlationMaximum: Float
    /// Non-finite detector pixels replaced before correlation (D019) — so a
    /// pattern emptied by bad pixels is not mistaken for vacuum.
    package var nonFinitePixelCount = 0
    /// Set when the kit refused the pattern (`CuboBraggError`, for instance a refinement that was not finite): the empty peak list
    /// and zero funnel then mean "the detector failed here", not "nothing was found" (the D019 failure, an emptied pattern
    /// mistaken for vacuum).
    package var detectionFailure: String? = nil

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(localMaximumCount: Int, afterAbsoluteThresholdCount: Int, afterRelativeThresholdCount: Int, afterSpacingCount: Int, acceptedCount: Int, wasCountLimited: Bool, relativeReferenceIntensity: Float?, relativeReferenceWasAvailable: Bool, correlationMaximum: Float) {
        self.localMaximumCount = localMaximumCount
        self.afterAbsoluteThresholdCount = afterAbsoluteThresholdCount
        self.afterRelativeThresholdCount = afterRelativeThresholdCount
        self.afterSpacingCount = afterSpacingCount
        self.acceptedCount = acceptedCount
        self.wasCountLimited = wasCountLimited
        self.relativeReferenceIntensity = relativeReferenceIntensity
        self.relativeReferenceWasAvailable = relativeReferenceWasAvailable
        self.correlationMaximum = correlationMaximum
    }
}

package nonisolated struct DiskDetectionPatternResult: Sendable {
    package let peaks: [BraggPeak]
    package let diagnostics: DiskDetectionPatternDiagnostics

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(peaks: [BraggPeak], diagnostics: DiskDetectionPatternDiagnostics) {
        self.peaks = peaks
        self.diagnostics = diagnostics
    }
}

package nonisolated struct DiskDetectionScanSummary: Sendable, Equatable {
    package let positionCount: Int
    package let totalPeakCount: Int
    package let minimumPeakCount: Int
    package let medianPeakCount: Double
    package let maximumPeakCount: Int
    package let zeroPeakPositionCount: Int
    /// Positions whose returned count equals the configured ceiling. The
    /// aggregate vectors cannot distinguish an exact count from truncation;
    /// per-pattern diagnostics use `wasCountLimited` when that distinction is
    /// available.
    package let atMaximumPositionCount: Int
    /// The thresholds the run used, so a warning can name the one that is
    /// most likely holding peaks back instead of saying "thresholds".
    package let parameters: DiskDetectionParams?
    /// Positions where the detector failed (counted inside `zeroPeakPositionCount`, but not vacuum).
    package let failedPositionCount: Int

    package init(vectors: BraggVectors, maximumPeaks: Int, parameters: DiskDetectionParams? = nil) {
        self.parameters = parameters
        failedPositionCount = vectors.failedPatternCount
        let counts = vectors.peaks.map(\.count).sorted()
        positionCount = counts.count
        totalPeakCount = counts.reduce(0, +)
        minimumPeakCount = counts.first ?? 0
        maximumPeakCount = counts.last ?? 0
        zeroPeakPositionCount = counts.filter { $0 == 0 }.count
        atMaximumPositionCount = counts.filter { $0 >= maximumPeaks }.count
        if counts.isEmpty {
            medianPeakCount = 0
        } else if counts.count.isMultiple(of: 2) {
            medianPeakCount = Double(counts[counts.count / 2 - 1] + counts[counts.count / 2]) / 2
        } else {
            medianPeakCount = Double(counts[counts.count / 2])
        }
    }

    package var warnings: [String] {
        guard positionCount > 0 else { return ["No scan positions were evaluated."] }
        var result: [String] = []
        if failedPositionCount > 0 {
            result.append("Detection failed at \(failedPositionCount) of \(positionCount) scan positions (a peak refinement was not finite); those positions are empty because the detector failed, not because they hold no disks.")
        }
        if zeroPeakPositionCount * 2 > positionCount {
            result.append("More than half of scan positions contain no accepted peaks; inspect the kernel and intensity thresholds.")
        }
        if atMaximumPositionCount * 10 > positionCount {
            result.append("More than 10% of scan positions reached the maximum-peak limit; raise the limit and rerun to check for truncation.")
        }
        if medianPeakCount <= 1 {
            result.append(onePeakWarning)
        }
        return result
    }

    /// One accepted peak per pattern is what a too-strict relative threshold
    /// looks like: with `relativeToPeak` 0 every maximum is held to a fraction
    /// of the BRIGHTEST correlation peak, which is the central beam whenever
    /// it is in the pattern, and a specimen whose disks are weaker than that
    /// fraction keeps only the beam (WS₂: disks at ~0.2 % of the beam against
    /// the shipped 0.5 %, open item 2026-09-05). The text names the threshold
    /// and the reference so the reader reaches for the right knob; it does not
    /// claim to know which filter removed the peaks — the per-pattern funnel
    /// in the Bragg panel does that.
    private var onePeakWarning: String {
        let lead = "The median pattern contains at most one accepted peak."
        guard let p = parameters, p.minRelativeIntensity > 0 else {
            return lead + " Min peak spacing or the edge boundary may be too restrictive for lattice analysis."
        }
        let percent = String(format: "%.3g %%", Double(p.minRelativeIntensity) * 100)
        let reference: String
        if p.relativeToPeak == 0 {
            reference = "the brightest peak — the central beam when it is in the pattern — so every disk weaker than that fraction of the beam is rejected. Lower Min relative intensity, or set Relative to peak to 1 to measure against the brightest disk instead"
        } else {
            reference = "the \(ordinal(p.relativeToPeak + 1))-brightest peak; disks weaker than that fraction of it are rejected. Lower Min relative intensity"
        }
        return lead + " Min relative intensity \(percent) is measured against \(reference). Min peak spacing (\(String(format: "%.0f", p.minPeakSpacing)) px) and the edge boundary can also remove peaks."
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 2: return "second"
        case 3: return "third"
        default: return "\(n)th"
        }
    }
}

/// Detection parameters, mirroring find_Bragg_disks. Defaults follow
/// py4DSTEM where scale-free; AppState adapts the pixel-scaled ones
/// (minPeakSpacing, edgeBoundary) to the detector size on dataset load.
package nonisolated struct DiskDetectionParams: Equatable, Sendable {
    package static let algorithmID = "py4dstem_find_bragg_disks_native_v1"

    package var corrPower: Float = 1              // 1 = cross, 0 = phase correlation
    package var sigmaDP: Float = 0                // gaussian smoothing before correlation
    package var sigmaCC: Float = 2                // gaussian smoothing of CC before maxima
    package var subpixel: SubpixelMode = .poly
    package var upsampleFactor: Int = 16
    package var minAbsoluteIntensity: Float = 0
    // DEVIATION (ADR 041, Gate D 2026-09-28,
    // ../_archive/mac4DSTEM/docs/archive/v4/default-floor-gateD-2026-09-28.md): py4DSTEM's
    // find_Bragg_disks defaults to 0.005 (diskdetection.py:34). The app's
    // default is 0.15 %: at 0.5 % the weak θ′/T1 reflections phase mapping
    // needs are cut — on Thronsen dataset A, 11.42 % per-position error and
    // θ′ face-on lost vs 1.31 % at 0.15 %. Parity checks pass 0.005 explicitly.
    package var minRelativeIntensity: Float = 0.0015
    package var relativeToPeak: Int = 0
    /// The reference the relative threshold is measured against is the
    /// brightest maximum at least this far from the brightest one, in
    /// detector pixels — from the direct beam wherever descan put it, not
    /// from the array centre; 0 keeps py4DSTEM's rule (the brightest
    /// anywhere, which is the direct beam). A saturated plateau is a field
    /// of tied maxima and "the brightest" is one point on it, so the radius
    /// should cover the plateau's diameter, the bound on how far apart two
    /// of its maxima can be (measured 2026-09-15 on a 12-px plateau: 6.5 px). MEASURED (Thronsen step 3, 2026-09-15):
    /// their preprocessed patterns carry a saturated direct-beam plateau, so
    /// "0.5 % of the maximum" was 0.5 % of a plateau and the T1 reflections
    /// at 1–5 % of it were kept only at 0.2 %; against the brightest Bragg
    /// peak instead, the same fraction means the same thing on every pattern.
    package var relativeReferenceMinimumRadiusPx: Float = 0
    package var minPeakSpacing: Float = 60
    package var edgeBoundary: Int = 20
    package var maxNumPeaks: Int = 70

    /// py4DSTEM's literal spacing/edge defaults target roughly 512-pixel
    /// patterns. Preserve its scale-free defaults while keeping the spatial
    /// filters useful on smaller detectors.
    ///
    /// `probeRadius` is the fitted probe radius in detector pixels, when it is
    /// known. Pass it whenever it is available — it is what makes
    /// `minPeakSpacing` physically meaningful.
    ///
    /// DEVIATION from py4DSTEM: py4DSTEM's `minPeakSpacing` default is 60 px,
    /// and rescaling that by detector size (`qMin / 8`, which reproduces ~60 on
    /// a 512 px detector) is wrong in principle and measurably wrong in
    /// practice. Bragg spacing is set by camera length, accelerating voltage
    /// and d-spacing — it does not scale with the detector. Measured on the
    /// training set with `../_archive/mac4DSTEM/tools/bragg-spacing-probe/` (40 patterns each,
    /// peaks detected under each rule):
    ///
    /// | dataset | probe r | true nearest-neighbour | qMin/8 | 1.0·r |
    /// |---|---|---|---|---|
    /// | downsample_Si_SiGe_exp | 5.03 px | 14.9 px | 16 px → 487 peaks | 5 px → 989 |
    /// | Particle_1…bin8 | 10.6 px | 12.7 px | 16 px → 455 | 11 px → 769 |
    /// | sim_Au_data_all_binned | 6.1 px | 21.4 px | 16 px → 547 | 6 px → 547 |
    ///
    /// On the first two the detector-scaled gate lands *above* the lattice —
    /// 96.9% and 94.4% of genuine peaks have a neighbour closer than it — so it
    /// suppresses the shortest g-vectors, which are exactly the ones that
    /// define the strain basis. Si_SiGe's yield halved to a median 12
    /// peaks/pattern and the basis fit became unsolvable ("No well-conditioned
    /// lattice explains at least half of the detected peak population"). On
    /// sim_Au, whose lattice is coarser than the gate, the rule changes
    /// nothing — its parity records are unaffected.
    ///
    /// The probe radius is the right scale because this filter exists to stop
    /// one disk producing two maxima, not to enforce a lattice period. 1.0·r
    /// was chosen over 1.5·r and 2.0·r, which both regress Particle_1 back to
    /// ~455 peaks (its disks overlap — they sit closer together than one probe
    /// diameter), and over 0.75·r, which admits ~8% more peaks on Particle_1
    /// that cannot be distinguished from duplicate maxima.
    ///
    /// Without a probe radius the old detector-scaled value is retained: it is
    /// only a transient placeholder, since detection needs a probe kernel and
    /// therefore a radius before it can run at all.
    package static func detectorAdapted(
        qy: Int, qx: Int, probeRadius: Float? = nil
    ) -> DiskDetectionParams {
        var params = DiskDetectionParams()
        let qMin = Float(min(qx, qy))
        let detectorScaled = max(4, (qMin / 8).rounded())
        if let probeRadius, probeRadius.isFinite, probeRadius > 0 {
            // Clamped so this can only ever *loosen* the gate, never tighten
            // it. All four training datasets have r < qMin/8, so the clamp is
            // inactive on every dataset the rule was measured against — but a
            // large convergence semi-angle puts r above it, and there the
            // unclamped rule would suppress more than the value it replaced.
            // A 300 kV, 25 mrad probe on a 128 px detector reaches r ≈ 60 px,
            // which is below the `detectorMinimum / 2` validation warning and
            // would therefore have silently returned ~1 peak per pattern.
            // Only the loosening direction is evidenced, so only that is taken.
            params.minPeakSpacing = min(max(4, probeRadius.rounded()), detectorScaled)
        } else {
            params.minPeakSpacing = detectorScaled
        }
        params.edgeBoundary = max(2, Int(qMin / 24))
        return params
    }

    package func validationIssues(in context: DiskDetectionContext) -> [DiskDetectionValidationIssue] {
        var issues: [DiskDetectionValidationIssue] = []
        func error(_ field: DiskDetectionParameterID, _ message: String) {
            issues.append(.init(field: field, severity: .error, message: message))
        }
        func warning(_ field: DiskDetectionParameterID, _ message: String) {
            issues.append(.init(field: field, severity: .warning, message: message))
        }

        if !corrPower.isFinite || !(0...1).contains(corrPower) {
            error(.correlationPower, "Correlation power must be finite and between 0 and 1.")
        }
        if !sigmaDP.isFinite || sigmaDP < 0 {
            error(.patternSigma, "Pattern smoothing σ must be finite and non-negative.")
        }
        if !sigmaCC.isFinite || sigmaCC < 0 {
            error(.correlationSigma, "Correlation smoothing σ must be finite and non-negative.")
        }
        if subpixel == .multicorr && upsampleFactor <= 2 {
            error(.upsampleFactor, "Fourier multicorr requires an upsampling factor greater than 2.")
        }
        if !minAbsoluteIntensity.isFinite || minAbsoluteIntensity < 0 {
            error(.minimumAbsoluteIntensity, "Minimum absolute intensity must be finite and non-negative.")
        }
        if !minRelativeIntensity.isFinite || !(0...1).contains(minRelativeIntensity) {
            error(.minimumRelativeIntensity, "Minimum relative intensity must be a fraction between 0 and 1.")
        }
        if maxNumPeaks < 1 {
            error(.maximumPeaks, "Maximum peaks must be at least 1.")
        }
        if relativeToPeak < 0 || relativeToPeak >= maxNumPeaks {
            error(.relativeReferencePeak, "The relative reference rank must be smaller than the maximum peak count.")
        }
        if !minPeakSpacing.isFinite || minPeakSpacing < 0 {
            error(.minimumPeakSpacing, "Minimum spacing must be finite and non-negative.")
        }
        if context.qx < 3 || context.qy < 3 {
            error(.edgeBoundary, "Disk detection requires detector dimensions of at least 3 × 3 pixels.")
        } else if edgeBoundary < 1 || edgeBoundary > context.maximumEdgeBoundary {
            error(.edgeBoundary, "Edge exclusion must be between 1 and \(context.maximumEdgeBoundary) pixels for this detector.")
        }
        if minPeakSpacing >= Float(context.detectorMinimum) / 2 {
            warning(.minimumPeakSpacing, "This spacing is at least half the detector width and will usually retain only one peak.")
        }
        if let radius = context.probeRadius, radius.isFinite, radius > 0 {
            if sigmaDP > radius {
                warning(.patternSigma, "Pattern smoothing exceeds the measured probe radius and may erase disk separation.")
            }
            if sigmaCC > radius {
                warning(.correlationSigma, "Correlation smoothing exceeds the measured probe radius and may merge maxima.")
            }
        }
        return issues
    }

    package func provenance(kernel: ProbeKernel, qy: Int, qx: Int) -> [String: String] {
        [
            "detection_algorithm": Self.algorithmID,
            // The learned path overwrites this with its own class (C7 session 2).
            "detector_class": DetectorClass.classical.provenanceID,
            DiskDetectionParameterID.correlationPower.rawValue: String(corrPower),
            DiskDetectionParameterID.patternSigma.rawValue: String(sigmaDP),
            DiskDetectionParameterID.correlationSigma.rawValue: String(sigmaCC),
            DiskDetectionParameterID.subpixel.rawValue: subpixel.provenanceID,
            DiskDetectionParameterID.upsampleFactor.rawValue: String(upsampleFactor),
            DiskDetectionParameterID.minimumAbsoluteIntensity.rawValue: String(minAbsoluteIntensity),
            DiskDetectionParameterID.minimumRelativeIntensity.rawValue: String(minRelativeIntensity),
            DiskDetectionParameterID.relativeReferencePeak.rawValue: String(relativeToPeak),
            DiskDetectionParameterID.relativeReferenceMinimumRadius.rawValue: String(relativeReferenceMinimumRadiusPx),
            DiskDetectionParameterID.minimumPeakSpacing.rawValue: String(minPeakSpacing),
            DiskDetectionParameterID.edgeBoundary.rawValue: String(edgeBoundary),
            DiskDetectionParameterID.maximumPeaks.rawValue: String(maxNumPeaks),
            "kernel_source": kernel.source.provenanceID,
            "kernel_mode": kernel.mode.provenanceID,
            "kernel_probe_radius_px": String(kernel.probeRadius),
            "kernel_trench_inner_px": String(kernel.trenchRadii.inner),
            "kernel_trench_outer_px": String(kernel.trenchRadii.outer),
            "detector_qy": String(qy),
            "detector_qx": String(qx),
        ]
    }

    /// The recipe step's parameters for a classical `disk_detection` run —
    /// exactly the keys `ReplayPlan` reads back (`ReplayPlanTests` pins the
    /// set). Moved out of `AppState.runDiskDetection` in C7 session 3; the
    /// learned class appends its own keys (`LearnedDetectionSession`).
    package func replayParameters(kernel: ProbeKernel) -> [String: String] {
        [
            "corr_power": String(corrPower),
            "sigma_dp": String(sigmaDP),
            "sigma_cc": String(sigmaCC),
            "subpixel": subpixel.provenanceID,
            "upsample_factor": String(upsampleFactor),
            "min_absolute_intensity": String(minAbsoluteIntensity),
            "min_relative_intensity": String(minRelativeIntensity),
            "relative_to_peak": String(relativeToPeak),
            "relative_reference_minimum_radius_px": String(relativeReferenceMinimumRadiusPx),
            "min_peak_spacing": String(minPeakSpacing),
            "edge_boundary": String(edgeBoundary),
            "max_peaks": String(maxNumPeaks),
            // The kernel class is a detection parameter even though this
            // struct does not carry it: the thresholds above were tuned
            // against ITS correlation response, and a replay that regenerated
            // a different class of kernel would silently move every peak
            // (Gate A finding C3, 2026-08-25). Vocabulary shared with result
            // provenance ("synthetic" / "measured_roi").
            "kernel_source": kernel.source.provenanceID,
            "kernel_mode": kernel.mode.provenanceID,
            "kernel_probe_path": kernel.probePath ?? "",
        ]
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(corrPower: Float = 1, sigmaDP: Float = 0, sigmaCC: Float = 2, subpixel: SubpixelMode = .poly, upsampleFactor: Int = 16, minAbsoluteIntensity: Float = 0, minRelativeIntensity: Float = 0.0015, relativeToPeak: Int = 0, minPeakSpacing: Float = 60, edgeBoundary: Int = 20, maxNumPeaks: Int = 70) {
        self.corrPower = corrPower
        self.sigmaDP = sigmaDP
        self.sigmaCC = sigmaCC
        self.subpixel = subpixel
        self.upsampleFactor = upsampleFactor
        self.minAbsoluteIntensity = minAbsoluteIntensity
        self.minRelativeIntensity = minRelativeIntensity
        self.relativeToPeak = relativeToPeak
        self.minPeakSpacing = minPeakSpacing
        self.edgeBoundary = edgeBoundary
        self.maxNumPeaks = maxNumPeaks
    }
}

/// Detected peaks for every scan position, row-major [ry][rx].
package nonisolated struct BraggVectors: Sendable {
    package let scanWidth: Int
    package let scanHeight: Int
    package let peaks: [[BraggPeak]]              // count == scanWidth * scanHeight
    package let detectionProvenance: [String: String]
    /// Scan positions whose detection the kit refused (their entry in `peaks` is empty because the detector failed, not because the
    /// pattern holds no disks). Zero for vectors that were loaded or built elsewhere.
    package let failedPatternCount: Int

    package init(
        scanWidth: Int, scanHeight: Int, peaks: [[BraggPeak]],
        detectionProvenance: [String: String] = [:],
        failedPatternCount: Int = 0
    ) {
        self.scanWidth = scanWidth
        self.scanHeight = scanHeight
        self.peaks = peaks
        self.detectionProvenance = detectionProvenance
        self.failedPatternCount = failedPatternCount
    }

    package var totalPeakCount: Int { peaks.reduce(0) { $0 + $1.count } }

    /// Vectors for calibrated scientific analysis. Raw detector coordinates
    /// remain stored for overlays and py4DSTEM `_v_uncal` export. Per-position
    /// origins are first collapsed onto `referenceOrigin`, then py4DSTEM's
    /// ellipse matrix is applied in its native qx/qy axis convention.
    package nonisolated func calibrated(
        with calibration: Calibration,
        referenceOrigin: (x: Float, y: Float),
        positions: [Int]? = nil
    ) -> BraggVectors {
        let origins = calibration.origin
        let canUseMaps = origins?.width == scanWidth
            && origins?.height == scanHeight
            && origins?.fittedX.count == peaks.count
            && origins?.fittedY.count == peaks.count
        guard canUseMaps || calibration.hasEllipse else { return self }

        var transformed = peaks
        let selectedPositions = positions ?? Array(transformed.indices)
        for scan in selectedPositions where transformed.indices.contains(scan) {
            let localX = canUseMaps ? origins!.fittedX[scan] : referenceOrigin.x
            let localY = canUseMaps ? origins!.fittedY[scan] : referenceOrigin.y
            for peak in transformed[scan].indices {
                let raw = transformed[scan][peak]
                let offset = calibration.ellipseCorrectedOffset(
                    dx: raw.x - localX, dy: raw.y - localY
                )
                transformed[scan][peak].x = referenceOrigin.x + offset.x
                transformed[scan][peak].y = referenceOrigin.y + offset.y
            }
        }
        return BraggVectors(
            scanWidth: scanWidth, scanHeight: scanHeight, peaks: transformed,
            detectionProvenance: detectionProvenance
        )
    }

    /// Bragg vector map: intensity-weighted 2D histogram of all peak
    /// positions in detector space (bilinear deposition, py4DSTEM's
    /// add_to_2D_array_from_floats).
    package func map(qy: Int, qx: Int) -> FloatImage {
        var out = [Float](repeating: 0, count: qy * qx)
        for positionPeaks in peaks {
            for p in positionPeaks {
                let x0 = Int(p.x.rounded(.down)), y0 = Int(p.y.rounded(.down))
                let fx = p.x - Float(x0), fy = p.y - Float(y0)
                for (xi, yi, w) in [(x0, y0, (1 - fx) * (1 - fy)),
                                    (x0 + 1, y0, fx * (1 - fy)),
                                    (x0, y0 + 1, (1 - fx) * fy),
                                    (x0 + 1, y0 + 1, fx * fy)] {
                    if xi >= 0, xi < qx, yi >= 0, yi < qy {
                        out[yi * qx + xi] += w * p.intensity
                    }
                }
            }
        }
        return FloatImage(width: qx, height: qy, pixels: out)
    }
}

// MARK: - DiskDetector

/// The app's detector: a facade over CuboKit's `CuboBragg.BraggDetector` (CuboKit 0.6.0), which owns the correlation,
/// the maxima, the filter cascade and both subpixel refinements. This type keeps the app's vocabulary (`DiskDetectionParams`,
/// x = column, Float peaks, `DiskDetectionPatternDiagnostics`) and the learned detector's two entries (`correlation`,
/// `refine`). The kit's detector is `Sendable` and keeps one scratch per concurrent caller, so one `DiskDetector` may serve
/// several threads; the full-scan pass is the kit's own and does not use this facade.
///
/// Precision: Float32 (`BraggPrecision.single`, as the former in-app detector computed) on a detector size vDSP's DFT
/// supports and at `corrPower` of 0.5 or more; otherwise the kit's Double path. Phase correlation (`corrPower` near 0) is
/// not held in Float32 (CuboKit `docs/bragg.md`, moves a peak by up to 11 px), and an unsupported size is refused by
/// `.single`. DEVIATION from the former detector: it ran Float32 everywhere; Double is more exact where it is used.
///
/// The kit refuses a peak whose parabola or matrix DFT is not finite (`CuboBraggError.nonFiniteRefinement`); the former
/// detector kept the integer position and the kit has no option to. Such a pattern yields no peaks and a zero funnel, and says
/// why: `DiskDetectionPatternDiagnostics.detectionFailure` is set, a full scan counts these in `BraggVectors.failedPatternCount`
/// and `DiskDetectionScanSummary` warns, so a failed pattern is never read as vacuum.
package nonisolated final class DiskDetector {

    private let detector: BraggDetector
    private let qx: Int, qy: Int          // detector dims

    /// The kit's kernel image for the app's probe kernel; nil when the kernel is not on the detector's own grid (the kit's
    /// detector needs it) or is refused. The full-scan pass and the facade both build it here.
    package static func kitKernel(_ kernel: ProbeKernel) -> CuboVirtual.DetectorImage? {
        guard kernel.px == kernel.qx, kernel.py == kernel.qy else { return nil }
        return try? CuboVirtual.DetectorImage(
            detectorRows: kernel.qy, detectorColumns: kernel.qx,
            values: kernel.kernel.map(Double.init), path: .cpu)
    }

    package init?(kernel: ProbeKernel) {
        guard let image = Self.kitKernel(kernel), let detector = try? BraggDetector(kernel: image) else { return nil }
        self.detector = detector
        self.qx = kernel.qx; self.qy = kernel.qy
    }

    /// The kit's options for these controls: the app's variants on (neighbour-median fill, multicorr peaks left in
    /// correlation order), every field from `params`. The same options serve the single-pattern facade below and the
    /// full-scan pass (`DiskDetection.detectAll(data:)`, `BraggDisks.detectAll`).
    package static func kitOptions(_ params: DiskDetectionParams, qy: Int, qx: Int) -> BraggDiskOptions {
        var o = BraggDiskOptions.mac4DSTEM
        o.correlationPower = Double(params.corrPower)
        o.patternSigma = Double(params.sigmaDP)
        o.correlationSigma = Double(params.sigmaCC)
        switch params.subpixel {
        case .pixel: o.subpixel = .pixel
        case .poly: o.subpixel = .parabolic
        // DEVIATION: the kit refuses an upsample factor of 2 or less for multicorr (py4DSTEM would produce NaN or an error there);
        // the former in-app detector skipped the refinement, so this facade runs the parabolic refinement instead, silently, and
        // the peaks are the 'Parabolic' ones. The parameter validation (`validationIssues`) refuses this combination before a scan
        // or a preview starts; only a direct caller reaches it. Pinned by DiskDetectorKitTests.
        case .multicorr: o.subpixel = params.upsampleFactor > 2 ? .multicorr : .parabolic
        }
        o.upsampleFactor = params.upsampleFactor
        o.minimumAbsoluteIntensity = Double(params.minAbsoluteIntensity)
        o.minimumRelativeIntensity = Double(params.minRelativeIntensity)
        o.relativeToPeak = params.relativeToPeak
        o.relativeReferenceMinimumRadius = Double(params.relativeReferenceMinimumRadiusPx)
        o.minimumPeakSpacing = Double(params.minPeakSpacing)
        o.edgeBoundary = params.edgeBoundary
        o.maximumPeaks = params.maxNumPeaks
        o.precision = BraggDetector.supportsSinglePrecision(detectorRows: qy, detectorColumns: qx) && params.corrPower >= 0.5
            ? .single : .double
        return o
    }

    private func options(_ params: DiskDetectionParams) -> BraggDiskOptions {
        Self.kitOptions(params, qy: qy, qx: qx)
    }

    // MARK: Detection (one pattern)

    /// Detect Bragg disks in one [qy * qx] pattern.
    package func detect(pattern: UnsafePointer<Float>, params: DiskDetectionParams) -> [BraggPeak] {
        detectWithDiagnostics(pattern: pattern, params: params).peaks
    }

    /// Detect one pattern and retain the complete acceptance funnel for UI
    /// diagnostics. The numerical path is identical to `detect`.
    package func detectWithDiagnostics(
        pattern: UnsafePointer<Float>, params: DiskDetectionParams
    ) -> DiskDetectionPatternResult {
        let buffer = UnsafeBufferPointer(start: pattern, count: qy * qx)
        let peaks: [CuboBragg.BraggPeak], funnel: BraggFunnel
        do {
            (peaks, funnel) = try detector.detectWithFunnel(buffer, options: options(params))
        } catch {
            var failed = DiskDetectionPatternDiagnostics(
                localMaximumCount: 0, afterAbsoluteThresholdCount: 0, afterRelativeThresholdCount: 0,
                afterSpacingCount: 0, acceptedCount: 0, wasCountLimited: false, relativeReferenceIntensity: nil,
                relativeReferenceWasAvailable: params.minRelativeIntensity == 0, correlationMaximum: 0)
            failed.detectionFailure = error.localizedDescription
            return DiskDetectionPatternResult(peaks: [], diagnostics: failed)
        }
        var diagnostics = DiskDetectionPatternDiagnostics(
            localMaximumCount: funnel.localMaximumCount,
            afterAbsoluteThresholdCount: funnel.afterAbsoluteCutCount,
            afterRelativeThresholdCount: funnel.afterRelativeCutCount,
            afterSpacingCount: funnel.afterSpacingCount,
            acceptedCount: funnel.acceptedCount,
            wasCountLimited: funnel.wasCountLimited,
            relativeReferenceIntensity: funnel.relativeReferenceIntensity.map { Float($0) },
            relativeReferenceWasAvailable: funnel.relativeReferenceWasAvailable,
            correlationMaximum: Float(funnel.correlationMaximum))
        diagnostics.nonFinitePixelCount = funnel.nonFinitePixelCount
        return DiskDetectionPatternResult(
            peaks: peaks.map { BraggPeak(x: Float($0.column), y: Float($0.row), intensity: Float($0.intensity)) },
            diagnostics: diagnostics)
    }

    /// Convenience for [Float] input (live single-pattern path).
    package func detect(pattern: [Float], params: DiskDetectionParams) -> [BraggPeak] {
        precondition(pattern.count == qy * qx)
        return pattern.withUnsafeBufferPointer { detect(pattern: $0.baseAddress!, params: params) }
    }

    package func detectWithDiagnostics(
        pattern: [Float], params: DiskDetectionParams
    ) -> DiskDetectionPatternResult {
        precondition(pattern.count == qy * qx)
        return pattern.withUnsafeBufferPointer {
            detectWithDiagnostics(pattern: $0.baseAddress!, params: params)
        }
    }

    // MARK: Learned candidates (v3-plan §3a step 4, 2026-09-07)

    /// The edge-rule margin of each side of a frame, in pixels (`refine`).
    package struct EdgeMargins: Sendable {
        package let left: Int, right: Int, top: Int, bottom: Int
        package init(left: Int, right: Int, top: Int, bottom: Int) { self.left = left; self.right = right; self.top = top; self.bottom = bottom }
    }

    /// A disk-centre proposal from the learned detector: a pixel and the net's score.
    package struct Candidate: Sendable {
        package let x: Int, y: Int, score: Float
        package init(x: Int, y: Int, score: Float) { self.x = x; self.y = y; self.score = score }
    }

    /// Stage 1 alone, on the [qy * qx] detector grid: the real cross-correlation
    /// (`max(Re(IFFT), 0)`, the learned detector's third input channel — it must
    /// equal `simulate.cross_correlation`) and its sigmaCC-smoothed copy (the
    /// surface the classical maxima are found and refined on).
    package func correlation(
        pattern: UnsafePointer<Float>, params: DiskDetectionParams
    ) -> (raw: [Float], smoothed: [Float]) {
        // The parameters are validated before any caller gets here, so the kit cannot refuse; if it ever does, the surfaces are
        // zero (an empty input channel), which `correlationChecked` reports instead.
        (try? correlationChecked(pattern: pattern, params: params))
            ?? ([Float](repeating: 0, count: qy * qx), [Float](repeating: 0, count: qy * qx))
    }

    /// `correlation`, but a kit error (an invalid option, a smoothing failure) is thrown, not turned into zero surfaces.
    package func correlationChecked(
        pattern: UnsafePointer<Float>, params: DiskDetectionParams
    ) throws -> (raw: [Float], smoothed: [Float]) {
        let o = options(params)
        let values = UnsafeBufferPointer(start: pattern, count: qy * qx).map(Double.init)
        let image = try CuboVirtual.DetectorImage(detectorRows: qy, detectorColumns: qx, values: values, path: .cpu)
        let raw = try detector.correlate(image, options: o).real
        let smoothed = o.correlationSigma > 0
            ? try CuboVirtual.GaussianFilter(sigma: o.correlationSigma).apply(raw, rows: qy, columns: qx, edge: .reflect)
            : raw
        return (raw.map { Float($0) }, smoothed.map { Float($0) })
    }

    /// Refine learned candidates the way the classical maxima are refined, on the
    /// [qy * qx] smoothed correlation from `correlation(pattern:params:)`: snap each
    /// candidate to the correlation's maximum within ±2 px (the net's peak is not the
    /// correlation's) and REQUIRE that pixel to be an 8-neighbour local maximum — a
    /// candidate the correlation does not confirm is rejected (Gate B 2026-09-07: without
    /// this, py4DSTEM's parabola evaluated on a flank fabricated positions up to 28 px off,
    /// and the Python reference agreed because it shared the defect); then the same
    /// parabolic sub-pixel step and bilinear intensity as the classical path (`polyRefine`),
    /// the edge boundary on the refined position, non-maximum suppression at
    /// `minPeakSpacing` by NET score, and the `maxNumPeaks` cap. No correlation-relative
    /// intensity cut: that is the cut that drops the faint disks the net is for. Mirrors
    /// `evaluate.refine` + `evaluate.accept` in ../_archive/mac4DSTEM/tools/disk-detector/evaluate.py (the Python reference the
    /// Swift fixture test compares against; Python has no cap).
    ///
    /// DEVIATION from py4DSTEM `get_maxima_2D` (preprocess/utils.py), on purpose — the
    /// candidates come from the net, not from an exhaustive maxima search: (1) the maxima
    /// are the net's picks snapped to the correlation, not every correlation maximum;
    /// (2) the order is snap → parabola → edge rule → spacing → cap, where py4DSTEM applies
    /// the edge rule and the spacing on the integer maxima before the parabola; (3) the
    /// edge rule tests the REFINED position, py4DSTEM the integer pixel; (4) the spacing
    /// suppression ranks by the net's score, py4DSTEM by correlation intensity. Shared with
    /// py4DSTEM: the parabola is only evaluated at a local maximum (so |shift| ≤ 0.5 px),
    /// the `<` spacing test, the cap keeps the highest-ranked.
    ///
    /// `edgeMargins` (D004, 2026-09-29): the edge rule per side, for a window of a larger detector, whose
    /// sides on the detector's own edge keep `edgeBoundary` and whose sides on a neighbouring window take the
    /// margin `LearnedDiskDetector.edgeMargins` computes. `nil` (every caller but the windowed learned scan) is
    /// `edgeBoundary` on all four sides, the rule this function always had.
    package func refine(
        candidates: [Candidate], smoothedCorrelation ar: [Float], params: DiskDetectionParams,
        edgeMargins: EdgeMargins? = nil
    ) -> [BraggPeak] {
        precondition(ar.count == qy * qx)
        let eb = Float(params.edgeBoundary)
        let mLeft = edgeMargins.map { Float($0.left) } ?? eb, mRight = edgeMargins.map { Float($0.right) } ?? eb
        let mTop = edgeMargins.map { Float($0.top) } ?? eb, mBottom = edgeMargins.map { Float($0.bottom) } ?? eb
        var accepted: [(peak: BraggPeak, score: Float)] = []
        accepted.reserveCapacity(candidates.count)
        for cand in candidates {
            // snap: the maximum of the 5x5 window, clipped one pixel inside the grid
            let rs = max(cand.y - 2, 1), re = min(cand.y + 3, qy - 1)
            let cs = max(cand.x - 2, 1), ce = min(cand.x + 3, qx - 1)
            guard rs < re, cs < ce else { continue }
            var by = rs, bx = cs, best = -Float.greatestFiniteMagnitude
            for y in rs..<re { for x in cs..<ce where ar[y * qx + x] > best { best = ar[y * qx + x]; by = y; bx = x } }
            // py4DSTEM's precondition: the parabola is evaluated only AT a local maximum
            let c = by * qx + bx
            var isMaximum = true
            for dy in -1...1 where isMaximum {
                for dx in -1...1 where !(dx == 0 && dy == 0) {
                    if ar[c + dy * qx + dx] > best { isMaximum = false; break }
                }
            }
            guard isMaximum else { continue }
            let ix0 = ar[c], ix1 = ar[c + 1], ix1_ = ar[c - 1], iy1 = ar[c + qx], iy1_ = ar[c - qx]
            let dx = (ix1 - ix1_) / (4 * ix0 - 2 * ix1 - 2 * ix1_)
            let dy = (iy1 - iy1_) / (4 * ix0 - 2 * iy1 - 2 * iy1_)
            let x = Float(bx) + (dx.isFinite ? dx : 0), y = Float(by) + (dy.isFinite ? dy : 0)
            guard x >= mLeft, x < Float(qx) - mRight, y >= mTop, y < Float(qy) - mBottom else { continue }
            // bilinear intensity at the refined position (as polyRefine reports it)
            let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
            let x1 = min(x0 + 1, qx - 1), y1 = min(y0 + 1, qy - 1)
            let fx = x - Float(x0), fy = y - Float(y0)
            let intensity = (1 - fx) * (1 - fy) * ar[y0 * qx + x0] + fx * (1 - fy) * ar[y0 * qx + x1]
                + (1 - fx) * fy * ar[y1 * qx + x0] + fx * fy * ar[y1 * qx + x1]
            accepted.append((BraggPeak(x: x, y: y, intensity: intensity), cand.score))
        }
        accepted.sort { $0.score > $1.score }
        var kept: [(peak: BraggPeak, score: Float)] = []
        outer: for a in accepted {
            for k in kept {
                let dx = a.peak.x - k.peak.x, dy = a.peak.y - k.peak.y
                if (dx * dx + dy * dy).squareRoot() < params.minPeakSpacing { continue outer }
            }
            kept.append(a)
            if kept.count >= params.maxNumPeaks { break }
        }
        return kept.map(\.peak)
    }

}
