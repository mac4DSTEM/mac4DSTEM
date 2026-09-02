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
//  The full-scan pass reads bounded scan-row tiles, then parallelizes each
//  tile with one detector (and its FFT scratch) per worker. multicorr is
//  ~10× slower than poly per pattern — poly is the interactive default,
//  multicorr the strain-analysis choice.
//

import Foundation
import Accelerate
import Metal

// MARK: - Types

/// One detected Bragg reflection, in detector pixels (x = column, y = row).
package nonisolated struct BraggPeak: Sendable {
    package var x: Float
    package var y: Float
    package var intensity: Float

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(x: Float, y: Float, intensity: Float) {
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
             .minimumPeakSpacing, .edgeBoundary: nil
        }
    }

    package var editorStep: Double? {
        switch self {
        case .correlationPower: 0.05
        case .patternSigma, .correlationSigma: 0.1
        case .upsampleFactor: 4
        case .minimumRelativeIntensity: 0.001
        case .maximumPeaks, .relativeReferencePeak, .minimumPeakSpacing,
             .edgeBoundary: 1
        case .minimumAbsoluteIntensity, .subpixel: nil
        }
    }
}

package nonisolated struct DiskDetectionContext: Sendable, Equatable {
    package let qy: Int
    package let qx: Int
    package let probeRadius: Float?

    package var detectorMinimum: Int { min(qx, qy) }
    package var maximumEdgeBoundary: Int { max(1, (detectorMinimum - 1) / 2) }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(qy: Int, qx: Int, probeRadius: Float?) {
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
    package init(field: DiskDetectionParameterID, severity: DiskDetectionValidationSeverity, message: String) {
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

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(localMaximumCount: Int, afterAbsoluteThresholdCount: Int, afterRelativeThresholdCount: Int, afterSpacingCount: Int, acceptedCount: Int, wasCountLimited: Bool, relativeReferenceIntensity: Float?, relativeReferenceWasAvailable: Bool, correlationMaximum: Float) {
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
    package init(peaks: [BraggPeak], diagnostics: DiskDetectionPatternDiagnostics) {
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

    package init(vectors: BraggVectors, maximumPeaks: Int) {
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
        if zeroPeakPositionCount * 2 > positionCount {
            result.append("More than half of scan positions contain no accepted peaks; inspect the kernel and intensity thresholds.")
        }
        if atMaximumPositionCount * 10 > positionCount {
            result.append("More than 10% of scan positions reached the maximum-peak limit; raise the limit and rerun to check for truncation.")
        }
        if medianPeakCount <= 1 {
            result.append("The median pattern contains at most one accepted peak; spacing or thresholds may be too restrictive for lattice analysis.")
        }
        return result
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
    package var minRelativeIntensity: Float = 0.005
    package var relativeToPeak: Int = 0
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
    /// training set with `tools/bragg-spacing-probe/` (40 patterns each,
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
            DiskDetectionParameterID.correlationPower.rawValue: String(corrPower),
            DiskDetectionParameterID.patternSigma.rawValue: String(sigmaDP),
            DiskDetectionParameterID.correlationSigma.rawValue: String(sigmaCC),
            DiskDetectionParameterID.subpixel.rawValue: subpixel.provenanceID,
            DiskDetectionParameterID.upsampleFactor.rawValue: String(upsampleFactor),
            DiskDetectionParameterID.minimumAbsoluteIntensity.rawValue: String(minAbsoluteIntensity),
            DiskDetectionParameterID.minimumRelativeIntensity.rawValue: String(minRelativeIntensity),
            DiskDetectionParameterID.relativeReferencePeak.rawValue: String(relativeToPeak),
            DiskDetectionParameterID.minimumPeakSpacing.rawValue: String(minPeakSpacing),
            DiskDetectionParameterID.edgeBoundary.rawValue: String(edgeBoundary),
            DiskDetectionParameterID.maximumPeaks.rawValue: String(maxNumPeaks),
            "kernel_source": kernel.source.provenanceID,
            "kernel_probe_radius_px": String(kernel.probeRadius),
            "kernel_trench_inner_px": String(kernel.trenchRadii.inner),
            "kernel_trench_outer_px": String(kernel.trenchRadii.outer),
            "detector_qy": String(qy),
            "detector_qx": String(qx),
        ]
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(corrPower: Float = 1, sigmaDP: Float = 0, sigmaCC: Float = 2, subpixel: SubpixelMode = .poly, upsampleFactor: Int = 16, minAbsoluteIntensity: Float = 0, minRelativeIntensity: Float = 0.005, relativeToPeak: Int = 0, minPeakSpacing: Float = 60, edgeBoundary: Int = 20, maxNumPeaks: Int = 70) {
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

    package init(
        scanWidth: Int, scanHeight: Int, peaks: [[BraggPeak]],
        detectionProvenance: [String: String] = [:]
    ) {
        self.scanWidth = scanWidth
        self.scanHeight = scanHeight
        self.peaks = peaks
        self.detectionProvenance = detectionProvenance
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

/// Per-worker detector: owns the FFT plan and scratch buffers, so one
/// instance must not be used from two threads at once. Create one per
/// concurrent worker (they share the kernel, which is immutable).
package nonisolated final class DiskDetector {

    private let kernel: ProbeKernel
    private let fft: FFT2D
    private let px: Int, py: Int          // exact detector/FFT dims
    private let qx: Int, qy: Int          // detector dims

    // Scratch (native detector grid)
    private var re: [Float]
    private var im: [Float]
    private var ccRe: [Float]             // complex correlation, kept for multicorr
    private var ccIm: [Float]
    private var cc: [Float]               // real correlation
    private var smooth: [Float]
    private var blurTemp: [Float]
    private var blurPadded: [Float] = []
    private var blurTaps: [Float] = []
    private var cachedBlurSigma: Float = -.greatestFiniteMagnitude

    package init?(kernel: ProbeKernel) {
        guard let fft = FFT2D(nx: kernel.px, ny: kernel.py) else { return nil }
        self.kernel = kernel
        self.fft = fft
        self.px = kernel.px; self.py = kernel.py
        self.qx = kernel.qx; self.qy = kernel.qy
        let n = px * py
        re = [Float](repeating: 0, count: n)
        im = [Float](repeating: 0, count: n)
        ccRe = [Float](repeating: 0, count: n)
        ccIm = [Float](repeating: 0, count: n)
        cc = [Float](repeating: 0, count: n)
        smooth = [Float](repeating: 0, count: n)
        blurTemp = [Float](repeating: 0, count: n)
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
        crossCorrelate(
            pattern: pattern,
            corrPower: params.corrPower,
            sigmaDP: params.sigmaDP,
            retainComplexCorrelation: params.subpixel == .multicorr
        )

        // Smooth (or copy) the real CC for maxima finding.
        if params.sigmaCC > 0 {
            gaussianBlur(src: cc, dst: &smooth, sigma: params.sigmaCC)
        } else {
            smooth = cc
        }

        var result = findMaxima(in: smooth, params: params)

        if params.subpixel != .pixel {
            polyRefine(&result.peaks, in: smooth)
        }
        if params.subpixel == .multicorr {
            multicorrRefine(&result.peaks, upsampleFactor: params.upsampleFactor)
        }
        return DiskDetectionPatternResult(
            peaks: result.peaks,
            diagnostics: result.diagnostics
        )
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

    // MARK: Stage 1 — hybrid cross correlation

    private func crossCorrelate(
        pattern: UnsafePointer<Float>,
        corrPower: Float,
        sigmaDP: Float,
        retainComplexCorrelation: Bool
    ) {
        // Copy the pattern onto the native circular-correlation grid, then
        // optionally apply py4DSTEM's pre-correlation diffraction smoothing.
        let n = px * py
        for i in 0..<n { re[i] = 0; im[i] = 0 }
        for y in 0..<qy {
            re.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.advanced(by: y * px)
                    .update(from: pattern + y * qx, count: qx)
            }
        }
        if sigmaDP > 0 {
            gaussianBlur(src: re, dst: &smooth, sigma: sigmaDP)
            re = smooth
        }
        fft.transform(re: &re, im: &im, forward: true)

        // m = FFT(pattern) · conj(FFT(kernel));  hybrid: m · |m|^(p−1)
        let kRe = kernel.ftRe, kIm = kernel.ftIm
        for i in 0..<n {
            let pr = re[i], pi = im[i]
            var mr = pr * kRe[i] - pi * kIm[i]
            var mi = pr * kIm[i] + pi * kRe[i]
            if corrPower != 1 {
                let mag = (mr * mr + mi * mi).squareRoot()
                let f = mag > 0 ? pow(mag, corrPower - 1) : 0
                mr *= f; mi *= f
            }
            re[i] = mr; im[i] = mi
            if retainComplexCorrelation { ccRe[i] = mr; ccIm[i] = mi }
        }

        // CC = max(Re(IFFT(cc)), 0), computed in place on re/im. ccRe/ccIm
        // are only populated when the caller needs the complex correlation
        // retained (multicorrRefine is the sole consumer).
        fft.transform(re: &re, im: &im, forward: false)
        vDSP_vthres(re, 1, [0], &cc, 1, vDSP_Length(n))
    }

    // MARK: Stage 2+3 — maxima + filter cascade (get_maxima_2D port)

    private func findMaxima(
        in ar: [Float], params p: DiskDetectionParams
    ) -> (peaks: [BraggPeak], diagnostics: DiskDetectionPatternDiagnostics) {
        // Local maxima by strict/loose 8-neighbor comparison, restricted to
        // the detector region minus the edge boundary.
        let eb = max(1, p.edgeBoundary)
        var found: [BraggPeak] = []
        guard qy - eb > eb, qx - eb > eb else {
            return (
                [],
                DiskDetectionPatternDiagnostics(
                    localMaximumCount: 0, afterAbsoluteThresholdCount: 0,
                    afterRelativeThresholdCount: 0, afterSpacingCount: 0,
                    acceptedCount: 0, wasCountLimited: false,
                    relativeReferenceIntensity: nil,
                    relativeReferenceWasAvailable: p.minRelativeIntensity == 0,
                    correlationMaximum: ar.max() ?? 0
                )
            )
        }
        for y in eb..<(qy - eb) {
            for x in eb..<(qx - eb) {
                let i = y * px + x
                let v = ar[i]
                // Ties break toward the earlier (lower-index) pixel, matching
                // py4DSTEM's mixed >=/> roll comparison.
                if v >= ar[i + 1], v > ar[i - 1],
                   v >= ar[i + px], v > ar[i - px],
                   v >= ar[i + px + 1], v > ar[i + px - 1],
                   v >= ar[i - px + 1], v > ar[i - px - 1] {
                    found.append(BraggPeak(x: Float(x), y: Float(y), intensity: v))
                }
            }
        }
        found.sort { $0.intensity > $1.intensity }
        let localMaximumCount = found.count

        // Intensity thresholds.
        if p.minAbsoluteIntensity > 0 {
            found.removeAll { $0.intensity < p.minAbsoluteIntensity }
        }
        let afterAbsoluteThresholdCount = found.count
        var relativeReferenceIntensity: Float?
        var relativeReferenceWasAvailable = p.minRelativeIntensity == 0
        if p.minRelativeIntensity > 0, found.count > p.relativeToPeak {
            let ref = found[p.relativeToPeak].intensity
            relativeReferenceIntensity = ref
            relativeReferenceWasAvailable = true
            found.removeAll { $0.intensity / ref < p.minRelativeIntensity }
        }
        let afterRelativeThresholdCount = found.count

        // Min spacing: walk brightest-first, drop anything too close to a
        // kept peak.
        if p.minPeakSpacing > 0 {
            let d2 = p.minPeakSpacing * p.minPeakSpacing
            var kept: [BraggPeak] = []
            outer: for cand in found {
                for k in kept {
                    let dx = cand.x - k.x, dy = cand.y - k.y
                    if dx * dx + dy * dy < d2 { continue outer }
                }
                kept.append(cand)
            }
            found = kept
        }
        let afterSpacingCount = found.count

        let wasCountLimited = found.count > p.maxNumPeaks
        if found.count > p.maxNumPeaks {
            found.removeLast(found.count - p.maxNumPeaks)
        }
        return (
            found,
            DiskDetectionPatternDiagnostics(
                localMaximumCount: localMaximumCount,
                afterAbsoluteThresholdCount: afterAbsoluteThresholdCount,
                afterRelativeThresholdCount: afterRelativeThresholdCount,
                afterSpacingCount: afterSpacingCount,
                acceptedCount: found.count,
                wasCountLimited: wasCountLimited,
                relativeReferenceIntensity: relativeReferenceIntensity,
                relativeReferenceWasAvailable: relativeReferenceWasAvailable,
                correlationMaximum: ar.max() ?? 0
            )
        )
    }

    // MARK: Stage 4a — parabolic subpixel

    private func polyRefine(_ peaks: inout [BraggPeak], in ar: [Float]) {
        for i in 0..<peaks.count {
            let x = Int(peaks[i].x), y = Int(peaks[i].y)
            let c = y * px + x
            let ix0 = ar[c], ix1 = ar[c + 1], ix1_ = ar[c - 1]
            let iy1 = ar[c + px], iy1_ = ar[c - px]
            let dx = (ix1 - ix1_) / (4 * ix0 - 2 * ix1 - 2 * ix1_)
            let dy = (iy1 - iy1_) / (4 * ix0 - 2 * iy1 - 2 * iy1_)
            if dx.isFinite { peaks[i].x += dx }
            if dy.isFinite { peaks[i].y += dy }

            // py4DSTEM updates the reported peak intensity after polynomial
            // refinement using bilinear interpolation of the same correlation
            // image. Keeping the integer-pixel value biases refined peaks high.
            let refinedX = peaks[i].x
            let refinedY = peaks[i].y
            let x0 = Int(refinedX.rounded(.down))
            let x1 = Int(refinedX.rounded(.up))
            let y0 = Int(refinedY.rounded(.down))
            let y1 = Int(refinedY.rounded(.up))
            let fx = refinedX - Float(x0)
            let fy = refinedY - Float(y0)
            peaks[i].intensity =
                (1 - fx) * (1 - fy) * ar[y0 * px + x0]
                + fx * (1 - fy) * ar[y0 * px + x1]
                + (1 - fx) * fy * ar[y1 * px + x0]
                + fx * fy * ar[y1 * px + x1]
        }
    }

    // MARK: Stage 4b — multicorr (DFT-upsampled) subpixel

    /// Refine each peak on the unsmoothed complex correlation via the
    /// matrix-multiply DFT of Guizar-Sicairos et al. (upsampled_correlation).
    private func multicorrRefine(_ peaks: inout [BraggPeak], upsampleFactor: Int) {
        guard upsampleFactor > 2 else { return }
        for i in 0..<peaks.count {
            let refined = MatrixDFTCorrelation.refine(
                correlationRe: ccRe, correlationIm: ccIm,
                width: px, height: py,
                initial: CorrelationPeak(row: peaks[i].y, column: peaks[i].x),
                upsampleFactor: upsampleFactor
            )
            peaks[i].x = refined.column
            peaks[i].y = refined.row
        }
    }

    // MARK: Gaussian smoothing (separable, truncated at 4σ)

    private func gaussianBlur(src: [Float], dst: inout [Float], sigma: Float) {
        let radius = max(1, Int((4 * sigma).rounded()))
        if sigma != cachedBlurSigma {
            blurTaps = [Float](repeating: 0, count: 2 * radius + 1)
            var sum: Float = 0
            for i in -radius...radius {
                let value = exp(-Float(i * i) / (2 * sigma * sigma))
                blurTaps[i + radius] = value
                sum += value
            }
            for index in blurTaps.indices { blurTaps[index] /= sum }
            blurPadded = [Float](
                repeating: 0, count: max(px, py) + 2 * radius
            )
            cachedBlurSigma = sigma
        }

        // vDSP performs the same separable convolution as the prior scalar
        // loops. Explicit padding retains scipy.ndimage's half-sample reflect
        // boundary instead of substituting Accelerate's edge extension.
        // scipy.ndimage.gaussian_filter defaults to half-sample symmetric
        // `reflect`: -1 -> 0, -2 -> 1, n -> n-1.
        func reflected(_ raw: Int, count: Int) -> Int {
            var value = raw
            while value < 0 || value >= count {
                value = value < 0 ? -value - 1 : 2 * count - value - 1
            }
            return value
        }

        for y in 0..<py {
            let row = y * px
            for paddedIndex in 0..<(px + 2 * radius) {
                let x = reflected(paddedIndex - radius, count: px)
                blurPadded[paddedIndex] = src[row + x]
            }
            blurPadded.withUnsafeBufferPointer { input in
                blurTaps.withUnsafeBufferPointer { filter in
                    blurTemp.withUnsafeMutableBufferPointer { output in
                        vDSP_conv(
                            input.baseAddress!, 1,
                            filter.baseAddress!, 1,
                            output.baseAddress!.advanced(by: row), 1,
                            vDSP_Length(px), vDSP_Length(filter.count)
                        )
                    }
                }
            }
        }

        for x in 0..<px {
            for paddedIndex in 0..<(py + 2 * radius) {
                let y = reflected(paddedIndex - radius, count: py)
                blurPadded[paddedIndex] = blurTemp[y * px + x]
            }
            blurPadded.withUnsafeBufferPointer { input in
                blurTaps.withUnsafeBufferPointer { filter in
                    dst.withUnsafeMutableBufferPointer { output in
                        vDSP_conv(
                            input.baseAddress!, 1,
                            filter.baseAddress!, 1,
                            output.baseAddress!.advanced(by: x), vDSP_Stride(px),
                            vDSP_Length(py), vDSP_Length(filter.count)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Full-scan detection

package enum DiskDetection {

    /// Detect disks at every scan position, parallelized over scan rows.
    /// `cube` is the resident float32 cube [ry][rx][qy][qx]; progress is
    /// reported in [0, 1] from worker threads.
    package nonisolated static func detectAll(cube: MTLBuffer,
                          descriptor d: DatasetDescriptor,
                          kernel: ProbeKernel,
                          params: DiskDetectionParams,
                          cancellation: AnalysisCancellationToken? = nil,
                          progress: (@Sendable (Double) -> Void)? = nil) -> BraggVectors? {
        guard cancellation?.isCancelled != true else { return nil }
        let context = DiskDetectionContext(
            qy: d.qy, qx: d.qx, probeRadius: kernel.probeRadius
        )
        guard !params.validationIssues(in: context).contains(where: {
            $0.severity == .error
        }) else { return nil }
        let base = cube.contents().bindMemory(to: Float.self,
                                              capacity: d.ry * d.rx * d.qy * d.qx)
        let patPix = d.qy * d.qx
        let rowPix = d.rx * patPix

        // One result slot per scan position; rows are disjoint, so workers
        // never touch the same slot. The buffer is captured via a wrapper to
        // sidestep Sendable checking on the raw pointer (read-only access).
        struct Slots: @unchecked Sendable {
            package let ptr: UnsafeMutablePointer<[BraggPeak]>
            package let cubeBase: UnsafePointer<Float>
        }
        var results = [[BraggPeak]](repeating: [], count: d.ry * d.rx)
        let rowsDone = NSLock()
        var doneCount = 0
        // Progress counts PATTERNS, not scan rows (FFT session ride-along,
        // 2026-09-01): a tile of a few rows on a wide scan used to move the bar
        // in ~8 % steps. One lock take per pattern costs nothing next to a
        // correlation. The CALLBACK is rate-limited to one per 0.1 % of the
        // scan (at most ~1,000 per run), because the app's progress closure
        // hops to the main actor per call and a tick per pattern at ~3,000
        // patterns/s would flood exactly the runloop P1 just freed.
        let patternCount = d.ry * d.rx
        var lastBucket = -1

        let ok = results.withUnsafeMutableBufferPointer { buf -> Bool in
            let slots = Slots(ptr: buf.baseAddress!, cubeBase: base)
            // One detector (FFT plan + padded scratch) per WORKER, rows strided
            // across workers — not one per row, which churned multi-MB
            // allocations on large scans. `failed` is guarded by the lock.
            var failed = false
            let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, d.ry))
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                guard cancellation?.isCancelled != true else { return }
                guard let det = DiskDetector(kernel: kernel) else {
                    rowsDone.lock(); failed = true; rowsDone.unlock(); return
                }
                for ry in stride(from: w, to: d.ry, by: workers) {
                    if cancellation?.isCancelled == true { break }
                    for rx in 0..<d.rx {
                        if cancellation?.isCancelled == true { break }
                        let pat = slots.cubeBase + ry * rowPix + rx * patPix
                        slots.ptr[ry * d.rx + rx] = det.detect(pattern: pat, params: params)
                        if let progress {
                            rowsDone.lock()
                            doneCount += 1
                            let bucket = doneCount * 1000 / patternCount
                            let tick = bucket != lastBucket
                            if tick { lastBucket = bucket }
                            let f = Double(doneCount) / Double(patternCount)
                            rowsDone.unlock()
                            if tick { progress(f) }
                        }
                    }
                    if cancellation?.isCancelled == true { break }
                }
            }
            rowsDone.lock(); let bad = failed; rowsDone.unlock()
            return !bad && cancellation?.isCancelled != true
        }
        guard ok else { return nil }
        return BraggVectors(
            scanWidth: d.rx, scanHeight: d.ry, peaks: results,
            detectionProvenance: params.provenance(
                kernel: kernel, qy: d.qy, qx: d.qx
            )
        )
    }
}
