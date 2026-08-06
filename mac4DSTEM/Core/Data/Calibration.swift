import Foundation

/// Where the detector origin currently shown by the aperture came from.
/// This is deliberately separate from `hasFittedOrigin`: a py4DSTEM file can
/// provide a trustworthy fitted *mean* without carrying the per-position maps
/// needed by analyses that require descan correction.
enum OriginProvenance: Equatable, Sendable {
    /// Detector geometry only; no calibration has supplied an origin.
    case geometricDefault
    /// py4DSTEM qx0_mean/qy0_mean metadata, converted to the app's axis frame.
    case fileMean
    /// Full fitted per-position qx0/qy0 maps loaded from a py4DSTEM file.
    case fileMaps
    /// Origin mean restored from the mac4DSTEM session companion.
    case sessionMean
    /// Full origin maps restored from the mac4DSTEM session companion.
    case sessionMaps
    /// Mean of the per-position origin map fitted in this app.
    case fitted
    /// The user moved the aperture center after loading or calibration.
    case manual

    var displayName: String {
        switch self {
        case .geometricDefault: return "Geometric default (unfitted)"
        case .fileMean:         return "From file (qx0/qy0 mean)"
        case .fileMaps:         return "From file (fitted origin maps)"
        case .sessionMean:      return "From session sidecar (origin mean)"
        case .sessionMaps:      return "From session sidecar (origin maps)"
        case .fitted:           return "Fitted by calibration"
        case .manual:           return "Manual aperture center"
        }
    }

    var readinessProvenance: CalibrationValueProvenance? {
        switch self {
        case .geometricDefault: return nil
        case .fileMean, .fileMaps: return .importedFile
        case .sessionMean, .sessionMaps: return .sessionSidecar
        case .fitted: return .measuredInApp
        case .manual: return .manual
        }
    }
}

/// Source of a calibration value shown by the preprocessing readiness guide.
/// This is tracked separately from the value itself so imported/session values
/// are never presented as measurements performed by this app.
enum CalibrationValueProvenance: String, Equatable, Sendable {
    case importedFile = "Imported from file"
    case sessionSidecar = "Restored from session"
    case measuredInApp = "Measured in app"
    case manual = "Manual"
    case mixed = "Mixed sources"
}

/// Provenance for fields that do not already carry `OriginProvenance`.
/// A nil entry means no trustworthy value is currently active.
struct CalibrationProvenance: Equatable, Sendable {
    var probe: CalibrationValueProvenance?
    var ellipse: CalibrationValueProvenance?
    var rotation: CalibrationValueProvenance?
    var qScale: CalibrationValueProvenance?
    var rScale: CalibrationValueProvenance?
}

/// One normalization contract for the physical sampling units accepted by
/// readiness, DPC/iDPC, ACOM scale setup, and reconstruction preprocessing.
/// Pixel labels deliberately do not pass: a positive value such as
/// `1 pixels/pixel` is metadata, but it is not a physical calibration.
nonisolated enum CalibrationUnitConversion {
    /// Canonical labels offered by the manual calibration controls. File
    /// imports may use any accepted spelling below; manual edits normalize to
    /// one of these labels so the value and its physical meaning are explicit.
    static let editableRealUnits = ["Å", "nm", "pm"]
    static let editableReciprocalUnits = ["Å⁻¹", "nm⁻¹", "mrad"]

    static func normalized(_ unit: String?) -> String {
        (unit ?? "")
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "ångström", with: "angstrom")
    }

    static func realAngstromPerPixel(value: Double, units: String?) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        switch normalized(units) {
        case "a", "å", "angstrom", "ang":
            return value
        case "nm", "nanometer", "nanometers", "nanometre", "nanometres":
            return value * 10
        case "pm", "picometer", "picometers", "picometre", "picometres":
            return value * 0.01
        default:
            return nil
        }
    }

    static func canonicalEditableRealUnit(_ units: String?) -> String? {
        switch normalized(units) {
        case "a", "å", "angstrom", "ang":
            return "Å"
        case "nm", "nanometer", "nanometers", "nanometre", "nanometres":
            return "nm"
        case "pm", "picometer", "picometers", "picometre", "picometres":
            return "pm"
        default:
            return nil
        }
    }

    static func reciprocalInvAngstromPerPixel(
        value: Double, units: String?, wavelengthAngstrom: Double? = nil
    ) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        switch normalized(units) {
        case "1/a", "1/å", "a^-1", "å^-1", "a⁻¹", "å⁻¹",
             "angstrom^-1", "angstrom⁻¹", "1/angstrom", "ang^-1", "ang⁻¹":
            return value
        case "1/nm", "nm^-1", "nm⁻¹", "1/nanometer", "1/nanometre",
             "nanometer^-1", "nanometer⁻¹", "nanometre^-1", "nanometre⁻¹":
            return value * 0.1
        case "mrad":
            guard let wavelengthAngstrom,
                  wavelengthAngstrom.isFinite, wavelengthAngstrom > 0 else { return nil }
            return value / (1_000 * wavelengthAngstrom)
        default:
            return nil
        }
    }

    static func canonicalEditableReciprocalUnit(_ units: String?) -> String? {
        switch normalized(units) {
        case "1/a", "1/å", "a^-1", "å^-1", "a⁻¹", "å⁻¹",
             "angstrom^-1", "angstrom⁻¹", "1/angstrom", "ang^-1", "ang⁻¹":
            return "Å⁻¹"
        case "1/nm", "nm^-1", "nm⁻¹", "1/nanometer", "1/nanometre",
             "nanometer^-1", "nanometer⁻¹", "nanometre^-1", "nanometre⁻¹":
            return "nm⁻¹"
        case "mrad":
            return "mrad"
        default:
            return nil
        }
    }

    static func isPhysicalReciprocalUnit(_ units: String?) -> Bool {
        if normalized(units) == "mrad" { return true }
        return reciprocalInvAngstromPerPixel(value: 1, units: units) != nil
    }

    static func isPixelUnit(_ units: String?) -> Bool {
        switch normalized(units) {
        case "px", "pixel", "pixels", "1", "1/px", "1/pixel", "1/pixels":
            return true
        default:
            return false
        }
    }
}

enum CalibrationReadinessKind: String, CaseIterable, Identifiable, Sendable {
    case originProbe = "Origin & probe"
    case ellipse = "Ellipse distortion"
    case rotation = "R–Q rotation"
    case qScale = "Q pixel scale"
    case rScale = "R pixel scale"

    var id: String { rawValue }

    /// User-facing consequence of establishing this calibration field. Kept
    /// beside the readiness model so Prepare and export present the same
    /// scientific contract instead of maintaining two drifting explanations.
    var unlockSummary: String {
        switch self {
        case .originProbe:
            return "Unlocks descan-corrected DPC, Bragg vectors, strain, and reconstruction."
        case .ellipse:
            return "Corrects detector distortion in Bragg, strain, and orientation coordinates."
        case .rotation:
            return "Unlocks scan-frame DPC/iDPC and calibrated reconstruction geometry."
        case .qScale:
            return "Unlocks reciprocal units, physical orientation matching, and quantitative phase."
        case .rScale:
            return "Unlocks real-space axes, scale bars, and quantitative reconstruction sampling."
        }
    }
}

enum CalibrationReadinessStatus: Equatable, Sendable {
    case ready(CalibrationValueProvenance)
    case missing

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .ready(let provenance): return provenance.rawValue
        case .missing: return "Missing"
        }
    }
}

struct CalibrationReadinessItem: Identifiable, Equatable, Sendable {
    let kind: CalibrationReadinessKind
    let status: CalibrationReadinessStatus
    let detail: String

    var id: CalibrationReadinessKind { kind }
}

struct CalibrationReadinessReport: Equatable, Sendable {
    let items: [CalibrationReadinessItem]

    var missingItems: [CalibrationReadinessItem] {
        items.filter { !$0.status.isReady }
    }

    var isReady: Bool { missingItems.isEmpty }

    static func make(
        calibration: Calibration,
        provenance: CalibrationProvenance
    ) -> CalibrationReadinessReport {
        let originSource = calibration.originProvenance.readinessProvenance
        let validProbe = calibration.probeRadius.map {
            $0.isFinite && $0 > 0
        } ?? false
        let originResidual = calibration.origin?.rmsResidual
        let originFitAcceptable = calibration.originFitIsQuantitative
        let originAndProbeReady = originSource != nil && validProbe && originFitAcceptable
        let originProbeSource: CalibrationValueProvenance
        if let originSource, let probeSource = provenance.probe,
           originSource == probeSource {
            originProbeSource = originSource
        } else {
            originProbeSource = .mixed
        }
        let probeDetail = validProbe
            ? String(
                format: "%.3g px (%@)", calibration.probeRadius!,
                provenance.probe?.rawValue ?? "Unknown source"
            )
            : "Missing"
        var originDetail = "Origin: \(originSource?.rawValue ?? "Missing") · Probe: \(probeDetail)"
        if let originResidual {
            originDetail += String(format: " · Fit RMS %.4g px", originResidual)
            if !originFitAcceptable {
                originDetail += " (exceeds probe radius; recalibrate before quantitative use)"
            }
        }

        let validEllipse = calibration.hasEllipse
            && (calibration.ellipseA ?? 0) > 0
            && (calibration.ellipseB ?? 0) > 0
        let ellipseDetail: String
        if validEllipse, let a = calibration.ellipseA, let b = calibration.ellipseB,
           let theta = calibration.ellipseTheta {
            ellipseDetail = String(
                format: "a %.4g · b %.4g · θ %.1f°", a, b, theta * 180 / .pi
            )
        } else {
            ellipseDetail = "No detector-distortion correction"
        }

        let validRotation = calibration.rotationRad?.isFinite == true
        let rotationDetail: String
        if let rotation = calibration.rotationRad, rotation.isFinite {
            rotationDetail = String(
                format: "%.1f°%@", rotation * 180 / .pi,
                (calibration.transposeQR ?? false) ? " · transposed" : ""
            )
        } else {
            rotationDetail = "Scan and detector axes are not aligned"
        }

        let positiveQ = calibration.qPixelSize.map { $0.isFinite && $0 > 0 } ?? false
        let positiveR = calibration.rPixelSize.map { $0.isFinite && $0 > 0 } ?? false
        let validQ = positiveQ
            && CalibrationUnitConversion.isPhysicalReciprocalUnit(calibration.qPixelUnits)
        let validR = calibration.rPixelSize.flatMap {
            CalibrationUnitConversion.realAngstromPerPixel(
                value: $0, units: calibration.rPixelUnits
            )
        } != nil
        let qDetail: String
        if validQ, let size = calibration.qPixelSize, let units = calibration.qPixelUnits {
            qDetail = String(format: "%.6g %@/px", size, units)
        } else if positiveQ, let size = calibration.qPixelSize {
            let units = calibration.qPixelUnits ?? "no units"
            qDetail = CalibrationUnitConversion.isPixelUnit(calibration.qPixelUnits)
                ? String(format: "Reciprocal dimensions remain in pixels (%.6g %@/px)", size, units)
                : "Reciprocal scale lacks supported physical units (\(units))"
        } else {
            qDetail = "Reciprocal dimensions remain in pixels"
        }
        let rDetail: String
        if validR, let size = calibration.rPixelSize, let units = calibration.rPixelUnits {
            rDetail = String(format: "%.6g %@/px", size, units)
        } else if positiveR, let size = calibration.rPixelSize {
            let units = calibration.rPixelUnits ?? "no units"
            rDetail = CalibrationUnitConversion.isPixelUnit(calibration.rPixelUnits)
                ? String(format: "Real-space dimensions remain in pixels (%.6g %@/px)", size, units)
                : "Real-space scale lacks supported physical units (\(units))"
        } else {
            rDetail = "Real-space dimensions remain in pixels"
        }

        return CalibrationReadinessReport(items: [
            CalibrationReadinessItem(
                kind: .originProbe,
                status: originAndProbeReady ? .ready(originProbeSource) : .missing,
                detail: originDetail
            ),
            CalibrationReadinessItem(
                kind: .ellipse,
                status: readyStatus(validEllipse, provenance.ellipse),
                detail: ellipseDetail
            ),
            CalibrationReadinessItem(
                kind: .rotation,
                status: readyStatus(validRotation, provenance.rotation),
                detail: rotationDetail
            ),
            CalibrationReadinessItem(
                kind: .qScale,
                status: readyStatus(validQ, provenance.qScale),
                detail: qDetail
            ),
            CalibrationReadinessItem(
                kind: .rScale,
                status: readyStatus(validR, provenance.rScale),
                detail: rDetail
            )
        ])
    }

    private static func readyStatus(
        _ valid: Bool,
        _ provenance: CalibrationValueProvenance?
    ) -> CalibrationReadinessStatus {
        guard valid else { return .missing }
        return .ready(provenance ?? .manual)
    }
}

/// Per-scan-position position of the unscattered beam, in detector pixels.
struct OriginMaps: Sendable {
    let width: Int
    let height: Int

    /// Raw per-pattern measurement, when available. py4DSTEM files can carry
    /// fitted qx0/qy0 arrays without the corresponding measured arrays.
    let measuredX: [Float]?
    let measuredY: [Float]?

    /// Smooth fit of the measurement. Analyses use the fitted origin when available.
    var fittedX: [Float]
    var fittedY: [Float]

    /// RMS of measured minus fitted origins.
    var rmsResidual: Float? {
        guard let measuredX, let measuredY,
              measuredX.count == fittedX.count,
              measuredY.count == fittedY.count,
              !measuredX.isEmpty else { return nil }
        let count = measuredX.count

        var accumulator: Float = 0
        for index in 0..<count {
            let dx = measuredX[index] - fittedX[index]
            let dy = measuredY[index] - fittedY[index]
            accumulator += dx * dx + dy * dy
        }
        return (accumulator / Float(count)).squareRoot()
    }

    /// Fitted origins interleaved as [x0, y0, x1, y1, ...].
    var interleavedFitted: [Float] {
        var output = [Float](repeating: 0, count: fittedX.count * 2)
        for index in 0..<fittedX.count {
            output[2 * index] = fittedX[index]
            output[2 * index + 1] = fittedY[index]
        }
        return output
    }
}

struct Calibration: Sendable {
    /// Provenance of the origin currently represented by the aperture center.
    var originProvenance: OriginProvenance = .geometricDefault

    /// Radius of the central bright-field disk in detector pixels.
    var probeRadius: Float?

    /// Center and spread of the unscattered beam across the scan.
    var origin: OriginMaps?

    var qPixelSize: Double?
    var qPixelUnits: String?
    var rPixelSize: Double?
    var rPixelUnits: String?

    /// Relative rotation between scan and detector axes.
    var rotationRad: Float?
    var transposeQR: Bool?

    /// Elliptical distortion in py4DSTEM's native (qx=row, qy=column) frame.
    var ellipseA: Double?
    var ellipseB: Double?
    var ellipseTheta: Double?

    /// Whether the fitted origin is trustworthy enough to derive a
    /// *quantitative* number from Bragg vectors re-centred on it.
    ///
    /// **This is the single owner of that decision** (backlog #46) — the
    /// Prepare readiness row, `AppState.calibrateQFromCrystal()`, and
    /// `tools/training-dataset-campaign` all read it. The badge the user sees,
    /// the calibration the app is willing to perform, and the parity records
    /// therefore cannot disagree; the defect was exactly that disagreement,
    /// with the Origin row saying *"exceeds probe radius; recalibrate before
    /// quantitative use"* while the Q row, derived from that same origin, said
    /// *"Measured in app"*. Any new caller belongs here too, not in a fourth
    /// hand-rolled `residual > probeRadius`.
    ///
    /// **Known limit.** This threshold answers "is the origin fit sane?", which
    /// adversarial review on 2026-08-06 showed is a *looser* question than "may
    /// I measure a reciprocal scale in this frame?".
    /// `KnownCrystalQCalibration.estimate` discards peaks inside
    /// `minimumRadiusPixels` (default 2, never overridden), so a residual above
    /// roughly 2 px already lets the direct beam masquerade as the innermost
    /// reflection — well below a typical probe radius. Everything in
    /// `(2 px, probeRadius]` still passes here. Tightening it belongs with the
    /// estimator, not with this predicate; see the open item.
    ///
    /// A fitted descan field whose RMS error is larger than the direct beam
    /// disk is not a quantitative origin calibration: `BraggVectors.calibrated`
    /// re-centres every pattern on the fitted origin, so a residual that size
    /// displaces the reference by an appreciable fraction of the lattice
    /// period. File/session maps without raw measured arrays carry no residual
    /// to judge and are not second-guessed here — they keep their explicit
    /// provenance-based readiness.
    var originFitIsQuantitative: Bool {
        guard let residual = origin?.rmsResidual, let probeRadius else { return true }
        return residual.isFinite && residual <= probeRadius
    }

    /// Why a quantitative measurement derived from this origin must be
    /// refused, with the app's own remedy — or `nil` when there is nothing to
    /// refuse. Lives beside `originFitIsQuantitative` so the refusal a caller
    /// shows and the readiness badge Prepare renders are the same judgement
    /// quoting the same two numbers.
    ///
    /// The remedy names **Origin fit** deliberately. The residual is
    /// RMS(measured − fitted) from `OriginCalibration.tiledRun`, which measures
    /// per-position origins by masked centre-of-mass and then fits them with
    /// `OriginFitFunction`; it never consults the disk-detection probe kernel.
    /// So "build a measured probe kernel" — the obvious-sounding advice, and
    /// what an earlier draft of this string said — cannot move this number by
    /// a single pixel. Changing the fit function can.
    var originFitRefusal: String? {
        guard !originFitIsQuantitative else { return nil }
        return String(
            format: "Origin fit RMS %.4g px exceeds the %.4g px probe radius — Bragg vectors are "
                + "re-centred on this origin, so a value measured from them would be wrong. "
                + "Try another Origin fit (Constant / Plane / Parabola) and re-run Calibrate "
                + "Origin, or enter the scale manually.",
            Double(origin?.rmsResidual ?? .nan), Double(probeRadius ?? .nan)
        )
    }

    var hasFittedOrigin: Bool { origin != nil }
    var hasRotation: Bool { rotationRad != nil }
    nonisolated var hasEllipse: Bool {
        guard let a = ellipseA, let b = ellipseB, let theta = ellipseTheta else { return false }
        return a.isFinite && b.isFinite && theta.isFinite && abs(a) > .leastNonzeroMagnitude
    }

    /// Mean fitted origin, suitable as a default detector center.
    var meanOrigin: (x: Float, y: Float)? {
        guard let origin, !origin.fittedX.isEmpty else { return nil }
        let count = Float(origin.fittedX.count)
        return (origin.fittedX.reduce(0, +) / count, origin.fittedY.reduce(0, +) / count)
    }

    /// py4DSTEM `_transform` ellipse matrix in the native (qx=row, qy=column)
    /// frame — the single construction shared by the forward and inverse
    /// offset corrections so the two paths cannot drift.
    private nonisolated func ellipseTransform()
        -> (t00: Double, t01: Double, t11: Double)? {
        guard hasEllipse, let a = ellipseA, let b = ellipseB,
              let theta = ellipseTheta else { return nil }
        let e = b / a
        let sine = sin(theta - .pi / 2)
        let cosine = cos(theta - .pi / 2)
        return (
            t00: e * sine * sine + cosine * cosine,
            t01: sine * cosine * (1 - e),
            t11: sine * sine + e * cosine * cosine
        )
    }

    /// Apply py4DSTEM `BraggVectors.cal._transform(..., ellipse=True)` to a
    /// detector offset. The axis swap is explicit: py4DSTEM [qx,qy] is this
    /// app's [dy,dx], and theta stays in that native py4DSTEM frame.
    nonisolated func ellipseCorrectedOffset(dx: Float, dy: Float) -> (x: Float, y: Float) {
        guard let t = ellipseTransform() else { return (dx, dy) }
        let qx = t.t00 * Double(dy) + t.t01 * Double(dx)
        let qy = t.t01 * Double(dy) + t.t11 * Double(dx)
        return (Float(qy), Float(qx))
    }

    /// Exact inverse of `ellipseCorrectedOffset`: maps a calibrated detector
    /// offset back to the raw (distorted) detector frame. Used by fit-overlay
    /// rendering, which must place calibrated-space predictions onto the raw
    /// pattern. Identity when no ellipse is set, matching the forward path.
    nonisolated func ellipseUncorrectedOffset(dx: Float, dy: Float) -> (x: Float, y: Float) {
        guard let t = ellipseTransform() else { return (dx, dy) }
        let det = t.t00 * t.t11 - t.t01 * t.t01
        guard abs(det) > .leastNormalMagnitude else { return (dx, dy) }
        // Forward returned (x: qy, y: qx); undo the same axis bookkeeping.
        let qx = Double(dy)
        let qy = Double(dx)
        let rawDY = ( t.t11 * qx - t.t01 * qy) / det
        let rawDX = (-t.t01 * qx + t.t00 * qy) / det
        return (Float(rawDX), Float(rawDY))
    }
}

extension PixelOriginMaps {
    /// Convert py4DSTEM origin arrays to the app frame at the activation
    /// boundary. Real-space array order is unchanged; detector components swap
    /// because py4DSTEM qx is the first/row axis (app y), while qy is app x.
    nonisolated func appOriginMaps(width: Int, height: Int) -> OriginMaps? {
        guard shape == [height, width],
              fittedQX.count == width * height,
              fittedQY.count == width * height else { return nil }
        return OriginMaps(
            width: width, height: height,
            measuredX: measuredQY?.map(Float.init),
            measuredY: measuredQX?.map(Float.init),
            fittedX: fittedQY.map(Float.init),
            fittedY: fittedQX.map(Float.init)
        )
    }
}
