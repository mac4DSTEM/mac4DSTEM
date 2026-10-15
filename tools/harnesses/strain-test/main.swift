import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

let origin = (x: Float(50), y: Float(50))
func latticePeaks(g1: (Float, Float), g2: (Float, Float)) -> [BraggPeak] {
    let hk: [(Float, Float)] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1)]
    return hk.map { h, k in
        BraggPeak(
            x: origin.x + h * g1.0 + k * g2.0,
            y: origin.y + h * g1.1 + k * g2.1,
            intensity: 1
        )
    }
}

let reference = latticePeaks(g1: (10, 0), g2: (0, 10))
let strained = latticePeaks(g1: (9, 0), g2: (0, 11))
let vectors = BraggVectors(
    scanWidth: 4, scanHeight: 1,
    peaks: [reference, reference, strained, strained]
)

guard let whole = StrainMapping.compute(
    bragg: vectors, originX: origin.x, originY: origin.y
) else { fail("whole-scan reference failed") }
guard whole.referencePositionCount == 4,
      abs(whole.exx[2] - (1 - 9 / 9.5)) < 1e-5,
      abs(whole.eyy[2] - (1 - 11 / 10.5)) < 1e-5 else {
    fail("whole-scan reference values differ")
}
print("PASS: whole-scan component-median reference")

guard let selected = StrainMapping.compute(
    bragg: vectors, originX: origin.x, originY: origin.y,
    referenceMask: [true, true, false, false]
) else { fail("selected reference failed") }
guard selected.referencePositionCount == 2,
      abs(selected.exx[0]) < 1e-6, abs(selected.eyy[0]) < 1e-6,
      abs(selected.exx[2] - 0.1) < 1e-6,
      abs(selected.eyy[2] + 0.1) < 1e-6 else {
    fail("selected reference strain values differ")
}
print("PASS: selected unstrained reference region")

guard let manual = StrainMapping.compute(
    bragg: vectors, originX: origin.x, originY: origin.y,
    referenceMask: [true, true, false, false],
    initialBasis: (g1: (x: 10, y: 0), g2: (x: 0, y: 10))
) else { fail("manual reciprocal basis failed") }
guard abs(manual.exx[2] - 0.1) < 1e-6,
      abs(manual.eyy[2] + 0.1) < 1e-6 else {
    fail("manual reciprocal basis changed the expected strain")
}
guard StrainMapping.compute(
    bragg: vectors, originX: origin.x, originY: origin.y,
    initialBasis: (g1: (x: 10, y: 0), g2: (x: 20, y: 0))
) == nil else { fail("collinear manual reciprocal basis should fail") }
print("PASS: manual reciprocal basis and collinearity validation")

guard StrainMapping.compute(
    bragg: vectors, originX: origin.x, originY: origin.y,
    referenceMask: [false, false, false, false]
) == nil else { fail("empty reference region should fail") }
print("PASS: empty reference rejected")

// Non-square scan with missing positions, short/high-intensity false peaks,
// off-lattice outliers, real strain, and one distorted reference position.
let robustWidth = 5, robustHeight = 3
var robustPeaks: [[BraggPeak]] = []
let missing: Set<Int> = [7, 13]
for index in 0..<(robustWidth * robustHeight) {
    let row = index / robustWidth
    let localG1: (Float, Float)
    let localG2: (Float, Float)
    if index == 4 {
        localG1 = (10.6, 0); localG2 = (0, 9.4)
    } else if row == 0 {
        localG1 = (10, 0); localG2 = (0, 10)
    } else {
        localG1 = (9.5, 0); localG2 = (0, 10.5)
    }
    var peaks = latticePeaks(g1: localG1, g2: localG2)
    if missing.contains(index) { peaks = Array(peaks.prefix(3)) }
    if index == 0 || index == 6 {
        peaks.append(BraggPeak(
            x: origin.x + 2.4, y: origin.y + 0.1, intensity: 1_000
        ))
    }
    peaks.append(BraggPeak(
        x: origin.x + 24 + Float(index) * 0.37,
        y: origin.y - 17 + Float(index) * 0.23,
        intensity: 500
    ))
    robustPeaks.append(peaks)
}
let robustVectors = BraggVectors(
    scanWidth: robustWidth, scanHeight: robustHeight, peaks: robustPeaks
)
let robustReference = (0..<(robustWidth * robustHeight)).map { $0 < robustWidth }
guard let robust = StrainMapping.compute(
    bragg: robustVectors, originX: origin.x, originY: origin.y,
    referenceMask: robustReference
) else { fail("consensus strain fit rejected a supported lattice") }
guard robust.width == robustWidth, robust.height == robustHeight,
      robust.referencePositionCount == 4,
      robust.diagnostics.referenceCandidateCount == 5,
      robust.diagnostics.referenceRejectedCount == 1,
      robust.diagnostics.automaticBasis,
      robust.diagnostics.basisSupportFraction > 0.75,
      robust.diagnostics.basisConditionNumber < 3,
      robust.mask.filter({ $0 }).count == robustWidth * robustHeight - missing.count,
      !robust.mask[7], !robust.mask[13],
      abs(robust.exx[5] - 0.05) < 2e-4,
      abs(robust.eyy[5] + 0.05) < 2e-4 else {
    fail("consensus/outlier/missing-position diagnostics or strain differ")
}
print("PASS: non-square consensus basis, local outliers, and robust reference")

guard StrainMapping.compute(
    bragg: robustVectors, originX: origin.x, originY: origin.y,
    initialBasis: (g1: (x: 10, y: 0), g2: (x: 10, y: 0.5))
) == nil else { fail("ill-conditioned manual basis should be rejected") }
print("PASS: ill-conditioned manual basis rejected")

let incoherent = BraggVectors(
    scanWidth: 4, scanHeight: 3,
    peaks: (0..<12).map { position in
        (0..<6).map { peak in
            let angle = Float(position * 19 + peak * 7) * 0.371
            let radius = Float(5 + ((position * 11 + peak * 13) % 23))
            return BraggPeak(
                x: origin.x + radius * cos(angle),
                y: origin.y + radius * sin(angle), intensity: 1
            )
        }
    }
)
guard StrainMapping.compute(
    bragg: incoherent, originX: origin.x, originY: origin.y
) == nil else { fail("weak incoherent lattice consensus should be rejected") }
print("PASS: weak lattice consensus rejected")

let qRadii: [Float] = [10, 10.2, 9.8, 3, 20]
let qVectors = BraggVectors(
    scanWidth: qRadii.count, scanHeight: 1,
    peaks: qRadii.map { radius in
        [BraggPeak(x: origin.x + radius, y: origin.y, intensity: 1)]
    }
)
// nil for both new arguments, explicitly and not by default: this fixture is a
// synthetic single-shell ring with no probe, so the estimator's plausibility
// checks cannot run here and the estimate must say `.notSelfChecked` rather
// than quietly appear to have been checked. // v2 S13
guard let qEstimate = KnownCrystalQCalibration.estimate(
    bragg: qVectors, origin: origin, referenceRadiusInvAngstrom: 0.25,
    secondShellRadiusInvAngstrom: nil, probeRadiusPixels: nil
) else { fail("known-crystal Q calibration failed") }
guard case .notSelfChecked = qEstimate.shellCheck else {
    fail("a single synthetic shell must report NOT self-checked, never a pass")
}
// The estimator refuses nothing since Gate B cut its thresholds; what it
// must still do is report the single-shell state rather than imply a check.
guard abs(qEstimate.observedRadiusPixels - 10) < 1e-6,
      abs(qEstimate.invAngstromPerPixel - 0.025) < 1e-9,
      qEstimate.sampleCount == 5 else {
    fail("known-crystal median Q calibration differs")
}
print("PASS: robust known-crystal Q calibration")

guard let wavelength = DPC.electronWavelengthAngstrom(voltageKV: 200),
      let angularScale = DPC.milliradiansPerDetectorPixel(
        voltageKV: 200, invAngstromPerPixel: 0.01
      ) else { fail("physical DPC scale returned nil") }
guard abs(wavelength - 0.025079) < 1e-5,
      abs(angularScale - 0.25079) < 1e-4 else {
    fail("relativistic DPC angular scale differs: \(wavelength) Å, \(angularScale) mrad/px")
}
let physicalDPC = DPC.physicalMagnitudeImage(
    com: [3, 4], width: 1, height: 1, milliradiansPerPixel: angularScale
)
guard abs(physicalDPC.pixels[0] - 5 * angularScale) < 1e-6 else {
    fail("physical DPC magnitude scaling differs")
}
print("PASS: relativistic DPC mrad conversion")
print("strain-test: all passed")
