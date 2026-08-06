import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(
            domain: "calibration-readiness-test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

func completeCalibration(origin: OriginProvenance) -> Calibration {
    var calibration = Calibration()
    calibration.originProvenance = origin
    calibration.probeRadius = 7.5
    calibration.ellipseA = 19
    calibration.ellipseB = 17
    calibration.ellipseTheta = 0.2
    calibration.rotationRad = 0.3
    calibration.transposeQR = true
    calibration.qPixelSize = 0.04
    calibration.qPixelUnits = "Å⁻¹"
    calibration.rPixelSize = 1.2
    calibration.rPixelUnits = "nm"
    return calibration
}

func completeProvenance(_ source: CalibrationValueProvenance) -> CalibrationProvenance {
    CalibrationProvenance(
        probe: source, ellipse: source, rotation: source,
        qScale: source, rScale: source
    )
}

@main
struct Harness {
    static func main() throws {
        let empty = CalibrationReadinessReport.make(
            calibration: Calibration(), provenance: CalibrationProvenance()
        )
        try require(empty.missingItems.count == 5, "empty dataset must reset all readiness")
        try require(!empty.isReady, "empty dataset reported ready")
        print("PASS: empty dataset resets readiness")

        let imported = CalibrationReadinessReport.make(
            calibration: completeCalibration(origin: .fileMaps),
            provenance: completeProvenance(.importedFile)
        )
        try require(imported.isReady, "complete file calibration was not ready")
        try require(imported.items.allSatisfy {
            $0.status == .ready(.importedFile)
        }, "file provenance was not retained")
        print("PASS: imported calibration provenance")

        let session = CalibrationReadinessReport.make(
            calibration: completeCalibration(origin: .sessionMaps),
            provenance: completeProvenance(.sessionSidecar)
        )
        try require(session.isReady, "complete session calibration was not ready")
        try require(session.items.allSatisfy {
            $0.status == .ready(.sessionSidecar)
        }, "session provenance was not retained")
        print("PASS: session calibration provenance")

        var mixedProvenance = completeProvenance(.measuredInApp)
        mixedProvenance.probe = .sessionSidecar
        let mixed = CalibrationReadinessReport.make(
            calibration: completeCalibration(origin: .fitted),
            provenance: mixedProvenance
        )
        try require(
            mixed.items.first { $0.kind == .originProbe }?.status == .ready(.mixed),
            "mixed origin/probe source was hidden"
        )
        print("PASS: mixed source is explicit")

        var partial = completeCalibration(origin: .manual)
        partial.probeRadius = nil
        partial.ellipseB = 0
        partial.rotationRad = .nan
        partial.qPixelSize = 0
        partial.rPixelSize = nil
        let incomplete = CalibrationReadinessReport.make(
            calibration: partial, provenance: completeProvenance(.manual)
        )
        try require(incomplete.missingItems.count == 5,
                    "invalid or partial values must remain missing")
        try require(incomplete.items.first?.detail.contains("Origin: Manual") == true,
                    "partial origin/probe detail lost manual origin")
        print("PASS: partial and non-physical values stay missing")

        var pixelMetadata = completeCalibration(origin: .fileMaps)
        pixelMetadata.qPixelSize = 1
        pixelMetadata.qPixelUnits = "pixels"
        pixelMetadata.rPixelSize = 1
        pixelMetadata.rPixelUnits = "pixels"
        let pixelReport = CalibrationReadinessReport.make(
            calibration: pixelMetadata, provenance: completeProvenance(.importedFile)
        )
        try require(pixelReport.missingItems.map(\.kind) == [.qScale, .rScale],
                    "positive pixel metadata was mistaken for physical calibration")
        try require(pixelReport.missingItems.allSatisfy { $0.detail.contains("pixels") },
                    "pixel-unit readiness did not explain the prerequisite block")
        print("PASS: pixel metadata does not claim physical readiness")

        var unitless = completeCalibration(origin: .manual)
        unitless.qPixelUnits = nil
        unitless.rPixelUnits = nil
        let unitlessReport = CalibrationReadinessReport.make(
            calibration: unitless, provenance: completeProvenance(.manual)
        )
        try require(unitlessReport.missingItems.map(\.kind) == [.qScale, .rScale],
                    "missing units were silently guessed")
        print("PASS: missing physical units are never guessed")

        var poorOrigin = completeCalibration(origin: .fitted)
        poorOrigin.origin = OriginMaps(
            width: 2, height: 1,
            measuredX: [0, 20], measuredY: [0, 20],
            fittedX: [0, 0], fittedY: [0, 0]
        )
        let poorOriginReport = CalibrationReadinessReport.make(
            calibration: poorOrigin, provenance: completeProvenance(.measuredInApp)
        )
        try require(poorOriginReport.missingItems.map(\.kind) == [.originProbe],
                    "high-residual origin fit unlocked quantitative workflows")
        try require(poorOriginReport.missingItems[0].detail.contains("exceeds probe radius"),
                    "high-residual origin block lacks actionable detail")

        // The row must not call a measured origin "Missing". It did, directly
        // above its own detail line reading "Origin: Measured in app · … Fit
        // RMS 11.66 px (exceeds probe radius…)" — the #46 defect class,
        // reported from the real app on 2026-08-06.
        try require(poorOriginReport.missingItems[0].status == .unusable,
                    "a measured-but-unusable origin is reported as missing")
        try require(poorOriginReport.missingItems[0].status.displayName != "Missing",
                    "the readiness word contradicts the detail beside it")
        try require(!poorOriginReport.missingItems[0].status.isReady,
                    "`.unusable` must not be ready — it changes the word, not the judgement")

        // …and a genuinely absent origin must still say Missing, or the new
        // case has simply swallowed the old one.
        var absentOrigin = completeCalibration(origin: .fitted)
        absentOrigin.origin = nil
        absentOrigin.probeRadius = nil
        let absentReport = CalibrationReadinessReport.make(
            calibration: absentOrigin, provenance: completeProvenance(.measuredInApp)
        )
        let absentRow = absentReport.items.first { $0.kind == .originProbe }
        try require(absentRow?.status == .missing,
                    "an absent origin must still be reported as missing")

        poorOrigin.origin = OriginMaps(
            width: 2, height: 1,
            measuredX: [0, 1], measuredY: [0, 1],
            fittedX: [0, 0], fittedY: [0, 0]
        )
        let acceptableOriginReport = CalibrationReadinessReport.make(
            calibration: poorOrigin, provenance: completeProvenance(.measuredInApp)
        )
        try require(acceptableOriginReport.isReady,
                    "origin fit within the probe radius was rejected")
        print("PASS: origin residual gates quantitative readiness")

        // Backlog #46. The defect was that the Origin row said "exceeds probe
        // radius; recalibrate before quantitative use" while the Q row,
        // derived from that same origin, said "Measured in app". The two
        // surfaces now read one predicate, and this pins them together: for
        // every origin state, a refusal exists exactly when the readiness row
        // is blocked by the fit rather than by a missing value.
        func originStates() -> [(String, Calibration)] {
            var cases: [(String, Calibration)] = []
            var none = completeCalibration(origin: .fitted)
            none.origin = nil
            cases.append(("no fitted origin", none))

            var clean = completeCalibration(origin: .fitted)
            clean.probeRadius = 5
            clean.origin = OriginMaps(
                width: 2, height: 1, measuredX: [0, 1], measuredY: [0, 0],
                fittedX: [0, 0], fittedY: [0, 0]
            )
            cases.append(("residual under probe radius", clean))

            // downsample_Si_SiGe_exp to scale: RMS 11.66 px, probe 5.03 px.
            var siSiGe = completeCalibration(origin: .fitted)
            siSiGe.probeRadius = 5.03
            siSiGe.origin = OriginMaps(
                width: 2, height: 1,
                measuredX: [11.66, -11.66], measuredY: [0, 0],
                fittedX: [0, 0], fittedY: [0, 0]
            )
            cases.append(("Si_SiGe-scale residual", siSiGe))

            // Imported fitted maps carry no measured arrays, so there is no
            // residual to judge and nothing may be refused on that basis.
            var imported = completeCalibration(origin: .fileMaps)
            imported.origin = OriginMaps(
                width: 2, height: 1, measuredX: nil, measuredY: nil,
                fittedX: [0, 0], fittedY: [0, 0]
            )
            cases.append(("imported maps without measured arrays", imported))

            var nonFinite = completeCalibration(origin: .fitted)
            nonFinite.probeRadius = 5
            nonFinite.origin = OriginMaps(
                width: 2, height: 1,
                measuredX: [.nan, 0], measuredY: [0, 0],
                fittedX: [0, 0], fittedY: [0, 0]
            )
            cases.append(("non-finite residual", nonFinite))

            return cases
        }

        for (label, calibration) in originStates() {
            let report = CalibrationReadinessReport.make(
                calibration: calibration, provenance: completeProvenance(.measuredInApp)
            )
            let originRow = report.items.first { $0.kind == .originProbe }
            let blockedByFit = !calibration.originFitIsQuantitative
            try require(originRow?.status.isReady == !blockedByFit,
                        "\(label): readiness row and origin-fit predicate disagree")
            try require((calibration.originFitRefusal != nil) == blockedByFit,
                        "\(label): refusal and origin-fit predicate disagree")
            if blockedByFit {
                try require(originRow?.detail.contains("exceeds probe radius") == true,
                            "\(label): blocked row lost its actionable detail")
                // The remedy must name **Origin fit**. `OriginCalibration`
                // never consults the disk-detection probe kernel, so advising
                // "build a measured probe kernel" — which an earlier draft did
                // — sends the user to a control that cannot move this number.
                try require(calibration.originFitRefusal?.contains("Origin fit") == true,
                            "\(label): refusal did not name the control that changes the fit")
                try require(calibration.originFitRefusal?.lowercased()
                                .contains("probe kernel") != true,
                            "\(label): refusal advises a lever that cannot change the residual")
            }
        }
        try require(originStates().contains { !$0.1.originFitIsQuantitative },
                    "the origin-fit invariant was checked without a single failing case")
        print("PASS: origin-fit refusal and readiness row are one judgement")

        // The refusal must quote the two numbers it is judging, so a user (and
        // the QC log) can see *why* without hunting for another row.
        let siSiGeRefusal = originStates().first { $0.0 == "Si_SiGe-scale residual" }!
            .1.originFitRefusal
        try require(siSiGeRefusal?.contains("11.66") == true,
                    "refusal did not quote the fit residual: \(siSiGeRefusal ?? "nil")")
        try require(siSiGeRefusal?.contains("5.03") == true,
                    "refusal did not quote the probe radius: \(siSiGeRefusal ?? "nil")")
        print("PASS: origin-fit refusal quotes the residual it is judging")

        let manual = CalibrationReadinessReport.make(
            calibration: completeCalibration(origin: .manual),
            provenance: completeProvenance(.manual)
        )
        try require(manual.isReady, "manual calibration should be explicitly usable")
        try require(manual.items.allSatisfy { $0.status == .ready(.manual) },
                    "manual provenance was not retained")
        print("PASS: explicit manual calibration")

        print("calibration-readiness-test: all passed")
    }
}
