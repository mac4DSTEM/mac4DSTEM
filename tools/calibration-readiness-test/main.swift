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
