import Foundation

/// Where the detector origin currently shown by the aperture came from.
/// This is deliberately separate from `hasFittedOrigin`: a py4DSTEM file can
/// provide a trustworthy fitted *mean* without carrying the per-position maps
/// needed by analyses that require descan correction.
package enum OriginProvenance: Equatable, Sendable {
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

    package var displayName: String {
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

    package var readinessProvenance: CalibrationValueProvenance? {
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
package enum CalibrationValueProvenance: String, Equatable, Sendable {
    case importedFile = "Imported from file"
    case sessionSidecar = "Restored from session"
    case measuredInApp = "Measured in app"
    case manual = "Manual"
    case mixed = "Mixed sources"

    /// The short state word a readiness row shows (v2.5 step 4b).
    package var stateLabel: String {
        switch self {
        case .importedFile: "From file"
        case .sessionSidecar: "From session"
        case .measuredInApp: "Measured"
        case .manual: "Manual"
        case .mixed: "Mixed"
        }
    }
}

/// Provenance for fields that do not already carry `OriginProvenance`.
/// A nil entry means no trustworthy value is currently active.
package nonisolated struct CalibrationProvenance: Equatable, Sendable {
    package var probe: CalibrationValueProvenance?
    package var ellipse: CalibrationValueProvenance?
    package var rotation: CalibrationValueProvenance?
    package var qScale: CalibrationValueProvenance?
    package var rScale: CalibrationValueProvenance?

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(probe: CalibrationValueProvenance? = nil, ellipse: CalibrationValueProvenance? = nil, rotation: CalibrationValueProvenance? = nil, qScale: CalibrationValueProvenance? = nil, rScale: CalibrationValueProvenance? = nil) {
        self.probe = probe
        self.ellipse = ellipse
        self.rotation = rotation
        self.qScale = qScale
        self.rScale = rScale
    }
}

/// One normalization contract for the physical sampling units accepted by
/// readiness, DPC/iDPC, ACOM scale setup, and reconstruction preprocessing.
/// Pixel labels deliberately do not pass: a positive value such as
/// `1 pixels/pixel` is metadata, but it is not a physical calibration.
package nonisolated enum CalibrationUnitConversion {
    /// Canonical labels offered by the manual calibration controls. File
    /// imports may use any accepted spelling below; manual edits normalize to
    /// one of these labels so the value and its physical meaning are explicit.
    package static let editableRealUnits = ["Å", "nm", "pm"]
    package static let editableReciprocalUnits = ["Å⁻¹", "nm⁻¹", "mrad"]

    package static func normalized(_ unit: String?) -> String {
        (unit ?? "")
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "ångström", with: "angstrom")
    }

    package static func realAngstromPerPixel(value: Double, units: String?) -> Double? {
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

    package static func canonicalEditableRealUnit(_ units: String?) -> String? {
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

    package static func reciprocalInvAngstromPerPixel(
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

    package static func canonicalEditableReciprocalUnit(_ units: String?) -> String? {
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

    package static func isPhysicalReciprocalUnit(_ units: String?) -> Bool {
        if normalized(units) == "mrad" { return true }
        return reciprocalInvAngstromPerPixel(value: 1, units: units) != nil
    }

    package static func isPixelUnit(_ units: String?) -> Bool {
        switch normalized(units) {
        case "px", "pixel", "pixels", "1", "1/px", "1/pixel", "1/pixels":
            return true
        default:
            return false
        }
    }
}

package enum CalibrationReadinessKind: String, CaseIterable, Identifiable, Sendable {
    case originProbe = "Origin & probe"
    case ellipse = "Ellipse distortion"
    case rotation = "R–Q rotation"
    case qScale = "Q pixel scale"
    case rScale = "R pixel scale"

    package var id: String { rawValue }

    /// User-facing consequence of establishing this calibration field. Kept
    /// beside the readiness model so Prepare and export present the same
    /// scientific contract instead of maintaining two drifting explanations.
    package var unlockSummary: String {
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

package enum CalibrationReadinessStatus: Equatable, Sendable {
    case ready(CalibrationValueProvenance)
    case missing
    /// Measured, but not to a standard that supports quantitative work.
    ///
    /// Distinct from `.missing` because the two are not the same fact, and the
    /// row contradicted itself saying so: with a fit residual above the probe
    /// radius the Origin & probe row printed **"Missing"** directly above its
    /// own detail line reading *"Origin: Measured in app · Probe: 5.03 px ·
    /// Fit RMS 11.66 px (exceeds probe radius…)"*. Reported from the real app
    /// on 2026-08-06. The value exists; it is the *quality* that fails, and
    /// "Missing" sends the user to re-measure something they already have
    /// rather than to change how it is fitted.
    ///
    /// This is the #46 defect class — a label contradicting the data beside
    /// it — so it gets the same treatment: say the true thing.
    case unusable

    /// `.unusable` is **not** ready, exactly like `.missing`. Every gate, the
    /// `missingItems` list, and the task prerequisite checklist therefore
    /// behave as they did before this case existed: it changes the *word*,
    /// never the judgement.
    package var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    package var displayName: String {
        switch self {
        // One vocabulary on every surface (v2.5 step 4b): Not set / From file /
        // Measured / Manual / From session / Mixed, and Not quantitative for a
        // measurement that failed its own gate.
        case .ready(let provenance): return provenance.stateLabel
        case .missing: return "Not set"
        case .unusable: return "Not quantitative"
        }
    }
}

package struct CalibrationReadinessItem: Identifiable, Equatable, Sendable {
    package let kind: CalibrationReadinessKind
    package let status: CalibrationReadinessStatus
    package let detail: String

    package var id: CalibrationReadinessKind { kind }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(kind: CalibrationReadinessKind, status: CalibrationReadinessStatus, detail: String) {
        self.kind = kind
        self.status = status
        self.detail = detail
    }
}

package struct CalibrationReadinessReport: Equatable, Sendable {
    package let items: [CalibrationReadinessItem]

    package var missingItems: [CalibrationReadinessItem] {
        items.filter { !$0.status.isReady }
    }

    package var isReady: Bool { missingItems.isEmpty }

    package static func make(
        calibration: Calibration,
        provenance: CalibrationProvenance
    ) -> CalibrationReadinessReport {
        let originSource = calibration.originProvenance.readinessProvenance
        let validProbe = calibration.probeRadius.map {
            $0.isFinite && $0 > 0
        } ?? false
        let originResidual = calibration.judgedOriginResidual
        let originFitAcceptable = calibration.originFitIsSane
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
            : "Not set"
        var originDetail = "Origin: \(originSource?.stateLabel ?? "Not set") · Probe: \(probeDetail)"
        if let originResidual {
            originDetail += String(format: " · Fit RMS %.4g px", originResidual)
            // The excluded fraction reaches the reader who sees the NUMBER,
            // which is the reader who would otherwise over-trust it — the
            // owner's §6a decision, 2026-08-28. Shown whether the fit passed or
            // failed: "2.19 px over 73% of positions" is a different claim from
            // "2.19 px over all of them", and only one of them is being made.
            if let excluded = calibration.origin?.excludedFraction,
               excluded > Calibration.excludedFractionDisclosureFloor {
                originDetail += String(
                    format: " over %.0f%% of positions (%.0f%% excluded as outliers)",
                    Double(1 - excluded) * 100, Double(excluded) * 100
                )
            }
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
                // Three outcomes, not two. `.unusable` is reserved for the
                // case where the origin and probe are both *present* and it is
                // only the fit quality that fails — otherwise something really
                // is missing and the user does need to go measure it.
                status: originAndProbeReady
                    ? .ready(originProbeSource)
                    : (originSource != nil && validProbe ? .unusable : .missing),
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

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(items: [CalibrationReadinessItem]) {
        self.items = items
    }
}

/// Per-scan-position position of the unscattered beam, in detector pixels.
package nonisolated struct OriginMaps: Sendable {
    package let width: Int
    package let height: Int

    /// Raw per-pattern measurement, when available. py4DSTEM files can carry
    /// fitted qx0/qy0 arrays without the corresponding measured arrays.
    package let measuredX: [Float]?
    package let measuredY: [Float]?

    /// Smooth fit of the measurement. Analyses use the fitted origin when available.
    package var fittedX: [Float]
    package var fittedY: [Float]

    /// Fraction of scan positions the robust fit EXCLUDED, or nil when the maps
    /// did not come from one — imported py4DSTEM maps and file/session origins
    /// carry no trimming history, and inventing 0 for them would claim a
    /// robustness nobody performed. // v2 S13
    ///
    /// The release owner's decision, 2026-08-28: a trimmed calibration is
    /// ADMITTED and this number is carried *on the product*, because accuracy
    /// of the fitted origin outranks coverage of the input measurements and the
    /// fraction is disclosure rather than an apology
    /// (`docs/q-calibration-design.md` §6a).
    package var excludedFraction: Float?

    /// RMS(measured − fitted) over the positions the robust fit KEPT.
    ///
    /// **Not interchangeable with `rmsResidual`**, which is over ALL positions.
    /// Trimming removes the largest residuals by construction, so this number
    /// is guaranteed to be the smaller one and comparing *it* to a full-scan
    /// threshold would be circular. Measured on `Particle_1…bin8`: 2.19 px here
    /// against 18.47 px full-scan for the same trimmed fit (S12 §1.2). The
    /// gate reads this one deliberately — see `originFitIsSane`. // v2 S13
    package var robustResidual: Float?

    /// RMS of measured minus fitted origins, over EVERY scan position.
    package var rmsResidual: Float? {
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
    package var interleavedFitted: [Float] {
        var output = [Float](repeating: 0, count: fittedX.count * 2)
        for index in 0..<fittedX.count {
            output[2 * index] = fittedX[index]
            output[2 * index + 1] = fittedY[index]
        }
        return output
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(width: Int, height: Int, measuredX: [Float]?, measuredY: [Float]?, fittedX: [Float], fittedY: [Float], excludedFraction: Float? = nil, robustResidual: Float? = nil) {
        self.width = width
        self.height = height
        self.measuredX = measuredX
        self.measuredY = measuredY
        self.fittedX = fittedX
        self.fittedY = fittedY
        self.excludedFraction = excludedFraction
        self.robustResidual = robustResidual
    }
}

package nonisolated struct Calibration: Sendable {
    /// Provenance of the origin currently represented by the aperture center.
    package var originProvenance: OriginProvenance = .geometricDefault

    /// Radius of the central bright-field disk in detector pixels.
    package var probeRadius: Float?

    /// The beam centre a file or a restored session recorded as a mean, with no
    /// per-position maps beside it. **v2 S13.** Before this existed the value
    /// was written into `aperture.centerX/Y` and nowhere else, so it was lost
    /// the moment the user moved the aperture, and every analysis fell through
    /// to the detector's geometric middle while the inspector went on showing
    /// the file's origin (S11, 2026-08-28). Stored as two scalars rather than a
    /// tuple so `Calibration` stays `Equatable`-friendly for callers that need
    /// it; read it through `recordedMeanOrigin`.
    package var recordedOriginX: Float?
    package var recordedOriginY: Float?

    package nonisolated var recordedMeanOrigin: (x: Float, y: Float)? {
        guard let recordedOriginX, let recordedOriginY,
              recordedOriginX.isFinite, recordedOriginY.isFinite else { return nil }
        return (recordedOriginX, recordedOriginY)
    }

    /// Center and spread of the unscattered beam across the scan.
    package var origin: OriginMaps?

    package var qPixelSize: Double?
    package var qPixelUnits: String?

    /// The diffraction scale bar's calibration: the Q sampling and its unit
    /// only when BOTH are known, otherwise detector pixels. A missing unit is
    /// never guessed as "1/nm" (v2.5 step 3, negative control 3).
    package var diffractionScaleBar: (perPixel: Double, unitLabel: String) {
        if let q = qPixelSize, q > 0, let u = qPixelUnits, !u.isEmpty { return (q, u) }
        return (1, "px")
    }
    package var rPixelSize: Double?
    package var rPixelUnits: String?

    /// Relative rotation between scan and detector axes.
    package var rotationRad: Float?
    package var transposeQR: Bool?

    /// Elliptical distortion in py4DSTEM's native (qx=row, qy=column) frame.
    package var ellipseA: Double?
    package var ellipseB: Double?
    package var ellipseTheta: Double?

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
    /// **v2 S13 renamed this from `originFitIsQuantitative` and split the
    /// question in two.** The old single predicate answered "is the origin fit
    /// sane?" and was consulted for "may I measure a reciprocal scale in this
    /// frame?", which the 2026-08-06 adversarial review had already shown is
    /// the stricter question. This is the LOOSER half: it drives the readiness
    /// badge and anything that only needs a centred frame (Bragg map display,
    /// DPC, virtual detectors). The strict half is
    /// `originSupportsReciprocalMetrology`.
    ///
    /// **It reads the FULL-SCAN residual.** v2 S13 shipped it reading the
    /// robust (kept-set) residual instead, on S12's argument that a full-scan
    /// RMS describes contamination rather than displacement — and Gate B
    /// refuted the swap on the same day, by construction and by measurement:
    ///
    /// > 32×32 scan, true origin 100, probe radius 10.624, a 12×12 corner block
    /// > thrown +40 px. The trim removes 12.6%, the surviving fit is displaced
    /// > **15.03 px at the clean positions**, and `keptResidual` reads 9.94 —
    /// > **passing**. The full-scan RMS reads 15.64 and **blocks**.
    ///
    /// RMS over the set that *defined* the fit measures that set's internal
    /// consistency; it cannot see bias, and a partially-excluded clustered
    /// contamination is exactly a biased fit with a coherent remainder. S13's
    /// own E2 section says this about the bootstrap and then shipped the
    /// precision statistic as the gate.
    ///
    /// **The robust residual is still computed and still disclosed** — it is
    /// the honest description of the trimmed fit's quality on the positions it
    /// used — it is simply not what decides. Which statistic *should* gate is
    /// an open design question and neither of the two is right: the full-scan
    /// number is inflated by contamination the fit correctly ignored. See
    /// `docs/open-items.md`.
    ///
    /// A second reason the swap had to come out: `robustResidual` is dropped by
    /// `CalibrationReReference` and by every save/reopen path, so the verdict
    /// flipped PASS → BLOCK on a **pure detector crop**, where every residual is
    /// bit-identical.
    /// Below this the excluded fraction is not shown, because the trim's own
    /// false-positive rate on clean data is not zero. **Measured, not picked**
    /// (Gate B, 2026-08-28): a 3σ cut on Rayleigh-distributed radial residuals
    /// excludes 0.33%–1.08% of positions across σ = 0.1–2.0 px with no outliers
    /// planted at all. 2% sits above that whole range. The first version used
    /// 0.5%, which is *inside* it, so a perfectly clean scan was told "1%
    /// excluded as outliers".
    package static let excludedFractionDisclosureFloor: Float = 0.02

    package var originFitIsSane: Bool {
        guard let residual = origin?.rmsResidual, let probeRadius else { return true }
        return residual.isFinite && residual <= probeRadius
    }

    /// The residual `originFitIsSane` actually judged, so a caller quoting a
    /// number quotes the same one the verdict came from. Kept as a named
    /// property rather than inlined: it is the guarantee that the panel, the
    /// readiness row and the refusal cannot drift onto different numbers, which
    /// they had done before (`AppState` quoted `rmsResidual` while the panel
    /// quoted the robust one).
    package var judgedOriginResidual: Float? { origin?.rmsResidual }

    /// Whether a *reciprocal* measurement may be derived in this frame — the
    /// strict question, consulted by Q calibration only.
    ///
    /// Deliberately **not** a tighter threshold on the same number (#29 warns
    /// against exactly that, and on a contaminated scan the number being
    /// thresholded is itself contaminated, so no threshold on it is
    /// meaningful). It requires two things this type can answer, and the
    /// estimator supplies a third at run time
    /// (`KnownCrystalQCalibration`'s plausibility checks):
    ///
    /// 1. `originFitIsSane`;
    /// 2. the origin is a **measured beam centre** and not a stand-in. S11's
    ///    worst confirmed finding, 2026-08-28: `.fileMean`/`.sessionMean` left
    ///    `calibration.origin` nil, `meanOrigin` was therefore nil, and the
    ///    consumers substituted the detector's geometric middle — in Q
    ///    calibration, strain, ACOM and the Bragg map at once, stamped
    ///    `.measuredInApp`. Measured magnitude of that substitution:
    ///    **1.14 px on `sim_Au` and 7.07 px on `downsample_Si_SiGe_exp`**
    ///    (S13 E1). No estimator check can cover it — the 1.14 px case is below
    ///    the estimator's 2 px floor and the 7.07 px case is above the band
    ///    where its radius check acts — so this is closed structurally, here,
    ///    rather than watched for.
    package func originSupportsReciprocalMetrology(
        detectorQX: Int, detectorQY: Int, apertureCentre: (x: Float, y: Float)?
    ) -> Bool {
        guard originFitIsSane else { return false }
        return referenceOrigin(
            detectorQX: detectorQX, detectorQY: detectorQY, apertureCentre: apertureCentre
        ).kind.isMeasuredBeamCentre
    }

    // MARK: - Which origin does an analysis re-centre on? (v2 S13)

    /// Where the reference origin came from. Carried beside the value so a
    /// caller can refuse on the *kind* instead of re-deriving the fallback and
    /// getting a different answer, which is what S11 found four call sites
    /// doing three different ways.
    package nonisolated enum ReferenceOriginKind: String, Sendable, Equatable {
        /// Mean of the per-position fitted origin maps.
        case fittedMaps
        /// The beam centre a file or a restored session recorded, with no
        /// per-position maps beside it (py4DSTEM's `qx0_mean`/`qy0_mean` — the
        /// ordinary shape of a calibration bundle, not a corner case).
        case recordedMean
        /// The user's detector placement. A best-effort centre for display; it
        /// is NOT a statement about where the beam is, because an aperture can
        /// be moved off the beam deliberately.
        case apertureCentre
        /// Nothing is known: the detector's geometric middle.
        case geometricMiddle

        /// Whether this origin is a *measurement* of the beam centre. Only
        /// these two may carry a reciprocal measurement.
        package var isMeasuredBeamCentre: Bool { self == .fittedMaps || self == .recordedMean }
    }

    package nonisolated struct ReferenceOrigin: Sendable, Equatable {
        package var x: Float
        package var y: Float
        package var kind: ReferenceOriginKind
        /// `nonisolated` deliberately: this is pure value arithmetic and it is
        /// read inside `Task.detached` at the Q-calibration call site. Without
        /// it the app target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
        /// makes it main-actor-isolated and the access is a Swift 6 error.
        package nonisolated var point: (x: Float, y: Float) { (x, y) }

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(x: Float, y: Float, kind: ReferenceOriginKind) {
            self.x = x
            self.y = y
            self.kind = kind
        }
    }

    /// **The one derivation of "which origin do I re-centre on?"** — v2 S13,
    /// replacing the four S11 catalogued on 2026-08-28
    /// (`calibratedBraggVectors` fell through to the geometric middle;
    /// `computeCoMField` and `generateMeasuredProbeKernel` fell through to the
    /// aperture centre; `calibrateEllipse` used the aperture unconditionally).
    /// A new caller belongs here, not in a fifth hand-rolled `?? (qx/2, qy/2)`.
    ///
    /// Order: fitted maps → the recorded mean → the aperture the user placed →
    /// the geometric middle. `apertureCentre` is optional so a caller with no
    /// aperture (a harness, an export) gets the same order minus that step
    /// rather than a different function.
    package nonisolated func referenceOrigin(
        detectorQX: Int, detectorQY: Int, apertureCentre: (x: Float, y: Float)?
    ) -> ReferenceOrigin {
        if let mean = meanOrigin {
            return ReferenceOrigin(x: mean.x, y: mean.y, kind: .fittedMaps)
        }
        if let recorded = recordedMeanOrigin {
            return ReferenceOrigin(x: recorded.x, y: recorded.y, kind: .recordedMean)
        }
        if let apertureCentre {
            return ReferenceOrigin(x: apertureCentre.x, y: apertureCentre.y, kind: .apertureCentre)
        }
        return ReferenceOrigin(x: Float(detectorQX) / 2, y: Float(detectorQY) / 2,
                               kind: .geometricMiddle)
    }

    /// Why a quantitative measurement derived from this origin must be
    /// refused, with the app's own remedy — or `nil` when there is nothing to
    /// refuse. Lives beside `originFitIsSane` so the refusal a caller
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
    /// The judgement alone — the two numbers and what they mean — with no
    /// remedy attached. Surfaces append their OWN remedy, because remedies
    /// are surface-specific: "enter the scale manually" un-blocks a Q
    /// measurement (manual entry bypasses the estimator entirely) but cannot
    /// move this residual, so appending it to the iDPC refusal printed a
    /// remedy that provably does nothing there (Gate B, 2026-08-25). // v2 S7
    package var originFitJudgement: String? {
        guard !originFitIsSane, let residual = judgedOriginResidual else { return nil }
        let excluded = origin?.excludedFraction
        let scope = (excluded ?? 0) > Self.excludedFractionDisclosureFloor
            ? String(format: " over the %.0f%% of scan positions the robust fit kept",
                     Double(1 - (excluded ?? 0)) * 100)
            : ""
        return String(
            format: "Origin fit RMS %.4g px%@ exceeds the %.4g px probe radius — Bragg vectors are "
                + "re-centred on this origin, so a value measured from them would be wrong.",
            Double(residual), scope as NSString, Double(probeRadius ?? .nan)
        )
    }

    /// The judgement plus the remedy that can actually clear it.
    ///
    /// **v2 S13 rewrote the remedy, and the reason is measured.** It used to
    /// read *"Try another Origin fit (Constant / Plane / Parabola) and re-run
    /// Calibrate Origin, or enter the scale manually."* On **both** training
    /// datasets where that text is shown, all three fit functions miss the gate
    /// — `downsample_Si_SiGe_exp` 13.133 / 11.655 / 11.302 px against a 5.026 px
    /// gate, `Particle_1…bin8` 18.720 / 18.295 / 18.138 against 10.624 — a 3–14%
    /// span sitting 1.7–2.2× above the threshold. The sentence spent most of its
    /// words on the one remedy that provably cannot succeed and buried the one
    /// that works (S12 §1.1). Manual entry bypasses the estimator entirely and
    /// its field is rendered in both branches of the readiness row, which is why
    /// `AppState.swift` records that refusing here is never a dead end.
    ///
    /// It also now says WHICH failure this is, because the app can finally tell
    /// them apart: broad measurement failure (no tail to trim — trimming keeps
    /// ~100% and moves nothing) versus outlier contamination (a heavy tail the
    /// trim removed, and the residual is still too large).
    package var originFitRefusal: String? {
        guard let judgement = originFitJudgement else { return nil }
        // The diagnosis says only what was OBSERVED. The first version drew an
        // inference from an excluded fraction of zero — "the origin measurement
        // is failing across the whole scan rather than at a few positions" —
        // and Gate B refuted it two ways on 2026-08-28. Trimming also excludes
        // nothing when the failures are **spatially clustered** (a contiguous
        // quarter of the scan thrown 40 px: 100.0% kept, fit 20.6 px off) and
        // when contamination reaches the estimator's **50% breakdown point**
        // (0.0% excluded, fit 30.4 px off). In both cases the sentence was the
        // exact opposite of the truth, and it steered the user away from the
        // remedy that would have worked. It also fired for maps that carry no
        // trim history at all — imported py4DSTEM origins — because `?? 0`
        // coalesced "never trimmed" into "trimmed and excluded nothing".
        let diagnosis: String
        switch origin?.excludedFraction {
        case .some(let excluded) where excluded > Self.excludedFractionDisclosureFloor:
            diagnosis = " The robust fit excluded \(Int((excluded * 100).rounded()))% of positions"
                + " as outliers and the rest still do not agree."
        case .some:
            diagnosis = " Trimming outliers changed nothing. That can mean the measurement is"
                + " failing across the whole scan, or that the bad positions are clustered"
                + " together or are more than half of them, which this trim cannot separate —"
                + " look at the origin map before assuming which."
        case .none:
            diagnosis = ""
        }
        return judgement + diagnosis
            + " Enter the reciprocal pixel size manually to proceed — that bypasses this fit."
            + " Changing the Origin fit function (Constant / Plane / Parabola) is unlikely to"
            + " help: the three differ by only a few percent of a residual this far above the"
            + " probe radius."
    }

    package var hasFittedOrigin: Bool { origin != nil }
    package var hasRotation: Bool { rotationRad != nil }
    package nonisolated var hasEllipse: Bool {
        guard let a = ellipseA, let b = ellipseB, let theta = ellipseTheta else { return false }
        return a.isFinite && b.isFinite && theta.isFinite && abs(a) > .leastNonzeroMagnitude
    }

    /// Mean fitted origin, suitable as a default detector center.
    ///
    /// **The finiteness check is load-bearing, added by Gate B, 2026-08-28.**
    /// Without it a NaN fitted map — which a single NaN in `measuredX` produces,
    /// because `fit2D` accumulates it into the normal equations and every
    /// fitted value becomes NaN — returned `(nan, nan)` as kind `.fittedMaps`,
    /// which `isMeasuredBeamCentre` calls a measured beam centre. With no
    /// `measuredX/Y` beside it there is also no residual to judge, so
    /// `originFitIsSane` returns true vacuously and the whole gate chain
    /// admits it: a Q scale computed from a NaN origin, stamped
    /// `.measuredInApp`. `recordedMeanOrigin` had validated its scalars all
    /// along; this path did not, 250 lines apart in one file.
    package nonisolated var meanOrigin: (x: Float, y: Float)? {
        guard let origin, !origin.fittedX.isEmpty,
              origin.fittedY.count == origin.fittedX.count else { return nil }
        let count = Float(origin.fittedX.count)
        let x = origin.fittedX.reduce(0, +) / count
        let y = origin.fittedY.reduce(0, +) / count
        guard x.isFinite, y.isFinite else { return nil }
        return (x, y)
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
    package nonisolated func ellipseCorrectedOffset(dx: Float, dy: Float) -> (x: Float, y: Float) {
        guard let t = ellipseTransform() else { return (dx, dy) }
        let qx = t.t00 * Double(dy) + t.t01 * Double(dx)
        let qy = t.t01 * Double(dy) + t.t11 * Double(dx)
        return (Float(qy), Float(qx))
    }

    /// Exact inverse of `ellipseCorrectedOffset`: maps a calibrated detector
    /// offset back to the raw (distorted) detector frame. Used by fit-overlay
    /// rendering, which must place calibrated-space predictions onto the raw
    /// pattern. Identity when no ellipse is set, matching the forward path.
    package nonisolated func ellipseUncorrectedOffset(dx: Float, dy: Float) -> (x: Float, y: Float) {
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

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(originProvenance: OriginProvenance = .geometricDefault, probeRadius: Float? = nil, recordedOriginX: Float? = nil, recordedOriginY: Float? = nil, origin: OriginMaps? = nil, qPixelSize: Double? = nil, qPixelUnits: String? = nil, rPixelSize: Double? = nil, rPixelUnits: String? = nil, rotationRad: Float? = nil, transposeQR: Bool? = nil, ellipseA: Double? = nil, ellipseB: Double? = nil, ellipseTheta: Double? = nil) {
        self.originProvenance = originProvenance
        self.probeRadius = probeRadius
        self.recordedOriginX = recordedOriginX
        self.recordedOriginY = recordedOriginY
        self.origin = origin
        self.qPixelSize = qPixelSize
        self.qPixelUnits = qPixelUnits
        self.rPixelSize = rPixelSize
        self.rPixelUnits = rPixelUnits
        self.rotationRad = rotationRad
        self.transposeQR = transposeQR
        self.ellipseA = ellipseA
        self.ellipseB = ellipseB
        self.ellipseTheta = ellipseTheta
    }
}

extension PixelOriginMaps {
    /// Convert py4DSTEM origin arrays to the app frame at the activation
    /// boundary. Real-space array order is unchanged; detector components swap
    /// because py4DSTEM qx is the first/row axis (app y), while qy is app x.
    package nonisolated func appOriginMaps(width: Int, height: Int) -> OriginMaps? {
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
