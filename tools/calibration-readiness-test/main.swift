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
