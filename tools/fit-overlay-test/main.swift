// Fit-overlay geometry: the scientific contract that overlay marks drawn on
// the RAW diffraction pattern land where the fitted model actually predicts.
// Covers the inverse ellipse transform, per-position origin re-anchoring,
// the strain local-lattice overlay, the matched-ACOM-template overlay
// (including the in-plane-angle composition), and ellipse polyline axes.

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func approx(_ a: Float, _ b: Float, _ tolerance: Float) -> Bool {
    abs(a - b) <= tolerance
}

// MARK: - 1. Ellipse inverse is the exact inverse of the forward transform

var ellipseCal = Calibration()
ellipseCal.ellipseA = 1.0
ellipseCal.ellipseB = 0.85
ellipseCal.ellipseTheta = 0.37

let offsets: [(Float, Float)] = [
    (12.5, 0), (0, -8.25), (7.75, 7.75), (-15.5, 3.125), (0.001, -0.002), (-120, 90)
]
for (dx, dy) in offsets {
    let corrected = ellipseCal.ellipseCorrectedOffset(dx: dx, dy: dy)
    let restored = ellipseCal.ellipseUncorrectedOffset(dx: corrected.x, dy: corrected.y)
    guard approx(restored.x, dx, 2e-3), approx(restored.y, dy, 2e-3) else {
        fail("ellipse round-trip (\(dx), \(dy)) → \(restored)")
    }
    // And the other direction: uncorrect then correct.
    let distorted = ellipseCal.ellipseUncorrectedOffset(dx: dx, dy: dy)
    let recovered = ellipseCal.ellipseCorrectedOffset(dx: distorted.x, dy: distorted.y)
    guard approx(recovered.x, dx, 2e-3), approx(recovered.y, dy, 2e-3) else {
        fail("ellipse inverse-first round-trip (\(dx), \(dy)) → \(recovered)")
    }
}
let identityCal = Calibration()
let identity = identityCal.ellipseUncorrectedOffset(dx: 3.25, dy: -1.5)
guard identity.x == 3.25, identity.y == -1.5 else {
    fail("uncorrected offset without an ellipse must be identity")
}
print("PASS: ellipse inverse round-trips and identity fallback")

// MARK: - 2. Ellipse polyline axes respect the py4DSTEM → app axis swap

// theta = 0: the major axis a lies along py4DSTEM qx, which is app y.
let axisAligned = FitOverlays.ellipsePolyline(
    centerX: 10, centerY: 20, a: 5, b: 3, theta: 0
)
guard !axisAligned.isEmpty else { fail("empty axis-aligned ellipse polyline") }
let xExtent = axisAligned.map(\.x).max()! - 10
let yExtent = axisAligned.map(\.y).max()! - 20
guard approx(xExtent, 3, 0.01), approx(yExtent, 5, 0.01) else {
    fail("theta=0 extents x \(xExtent) (want b=3), y \(yExtent) (want a=5)")
}
let rotated = FitOverlays.ellipsePolyline(
    centerX: 10, centerY: 20, a: 5, b: 3, theta: .pi / 2
)
let xExtentRotated = rotated.map(\.x).max()! - 10
let yExtentRotated = rotated.map(\.y).max()! - 20
guard approx(xExtentRotated, 5, 0.01), approx(yExtentRotated, 3, 0.01) else {
    fail("theta=π/2 extents x \(xExtentRotated) (want 5), y \(yExtentRotated) (want 3)")
}
print("PASS: ellipse polyline axis conventions")

// MARK: - 3. localOrigin mirrors BraggVectors.calibrated's map-usability rule

var mapsCal = Calibration()
mapsCal.origin = OriginMaps(
    width: 2, height: 2, measuredX: nil, measuredY: nil,
    fittedX: [10, 11, 12, 13], fittedY: [20, 21, 22, 23]
)
let mapped = FitOverlays.localOrigin(
    calibration: mapsCal, referenceOrigin: (x: 64, y: 64),
    scanIndex: 3, scanWidth: 2, scanHeight: 2
)
guard mapped.x == 13, mapped.y == 23 else { fail("per-position origin lookup \(mapped)") }
let mismatched = FitOverlays.localOrigin(
    calibration: mapsCal, referenceOrigin: (x: 64, y: 64),
    scanIndex: 0, scanWidth: 3, scanHeight: 2
)
guard mismatched.x == 64, mismatched.y == 64 else {
    fail("mismatched origin maps must fall back to the reference origin")
}
print("PASS: local origin map-usability mirror")

// MARK: - 4. Strain overlay lands on the constructed raw lattice

// Physical model: a true lattice in calibrated space, measured on a detector
// with per-position beam drift and elliptical distortion. The overlay must
// map fitted calibrated-space predictions back onto those raw positions.
let scanW = 4, scanH = 3, positionCount = scanW * scanH
let strainRef = (x: Float(64), y: Float(64))

var strainCal = Calibration()
strainCal.ellipseA = 1.0
strainCal.ellipseB = 0.9
strainCal.ellipseTheta = 0.5
strainCal.origin = OriginMaps(
    width: scanW, height: scanH, measuredX: nil, measuredY: nil,
    fittedX: (0..<positionCount).map { 64 + 0.4 * Float($0 % scanW) },
    fittedY: (0..<positionCount).map { 63.5 - 0.25 * Float($0) }
)

let hkList: [(Float, Float)] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1)]
func localLattice(for index: Int) -> (g1: (Float, Float), g2: (Float, Float)) {
    index == 5 ? ((10.6, 0), (0, 10)) : ((10, 0), (0, 10))
}
func rawLatticePoint(index: Int, h: Float, k: Float) -> (x: Float, y: Float) {
    let lattice = localLattice(for: index)
    let offset = (x: h * lattice.g1.0 + k * lattice.g2.0,
                  y: h * lattice.g1.1 + k * lattice.g2.1)
    let origin = (x: strainCal.origin!.fittedX[index], y: strainCal.origin!.fittedY[index])
    let raw = strainCal.ellipseUncorrectedOffset(dx: offset.x, dy: offset.y)
    return (origin.x + raw.x, origin.y + raw.y)
}

let strainPeaks = (0..<positionCount).map { index -> [BraggPeak] in
    var peaks = hkList.map { h, k -> BraggPeak in
        let point = rawLatticePoint(index: index, h: h, k: k)
        return BraggPeak(x: point.x, y: point.y, intensity: 100)
    }
    if index == 11 { peaks = Array(peaks.prefix(3)) }   // too few → masked
    return peaks
}
let strainVectors = BraggVectors(scanWidth: scanW, scanHeight: scanH, peaks: strainPeaks)
let calibratedStrain = strainVectors.calibrated(with: strainCal, referenceOrigin: strainRef)
guard let strainMap = StrainMapping.compute(
    bragg: calibratedStrain, originX: strainRef.x, originY: strainRef.y
) else { fail("strain solver rejected the synthetic lattice") }
guard strainMap.mask[5], !strainMap.mask[11] else {
    fail("expected position 5 fitted and position 11 masked")
}

guard let overlay = FitOverlays.strainOverlay(
    map: strainMap, scanIndex: 5,
    calibration: strainCal, referenceOrigin: strainRef,
    patternWidth: 128, patternHeight: 128, maxOrder: 1
) else { fail("no strain overlay for a fitted position") }
guard overlay.predicted.count == 8, overlay.localG1 != nil else {
    fail("strain overlay should predict the 8 first-order lattice points")
}
guard let residual = overlay.localResidualPixels, residual < 0.05 else {
    fail("exact synthetic lattice should have ≈0 local residual")
}
// Every prediction must land on the constructed raw lattice of position 5.
let idealRaw: [(x: Float, y: Float)] = {
    var points: [(Float, Float)] = []
    for h in [Float(-1), 0, 1] {
        for k in [Float(-1), 0, 1] where h != 0 || k != 0 {
            points.append(rawLatticePoint(index: 5, h: h, k: k))
        }
    }
    return points
}()
for marker in overlay.predicted {
    let distance = idealRaw.map { hypot($0.x - marker.x, $0.y - marker.y) }.min()!
    guard distance < 0.05 else {
        fail("strain prediction (\(marker.x), \(marker.y)) misses raw lattice by \(distance) px")
    }
}
// The overlay origin must be the per-position beam, not the collapsed reference.
guard approx(overlay.originX, strainCal.origin!.fittedX[5], 1e-4),
      approx(overlay.originY, strainCal.origin!.fittedY[5], 1e-4) else {
    fail("strain overlay origin should re-anchor on the per-position origin")
}
guard let maskedOverlay = FitOverlays.strainOverlay(
    map: strainMap, scanIndex: 11,
    calibration: strainCal, referenceOrigin: strainRef,
    patternWidth: 128, patternHeight: 128, maxOrder: 1
), maskedOverlay.predicted.isEmpty, maskedOverlay.localG1 == nil,
   maskedOverlay.localResidualPixels == nil else {
    fail("masked position must yield reference vectors only")
}
print("PASS: strain overlay maps local fit back onto the raw pattern")

// MARK: - 5. ACOM template overlay lands on the constructed pattern

guard let plan = OrientationPlan.generate(
    crystal: .gold, kMax: 1.2, zoneAxisCount: 96
) else { fail("orientation plan generation") }
guard plan.templateSpots.count == plan.count else {
    fail("plan must retain spots for every template")
}

let templateIndex = 17
let scale = 0.01
// Bin-exact rotation so azimuthal quantization cannot blur the check.
let inPlane = Float(2 * Double.pi * 11 / Double(plan.geometry.nAzimuthal))

func acomCase(
    name: String, calibration: Calibration, reference: (x: Float, y: Float)
) {
    let spots = plan.templateSpots[templateIndex]
    let localOrigin = FitOverlays.localOrigin(
        calibration: calibration, referenceOrigin: reference,
        scanIndex: 0, scanWidth: 1, scanHeight: 1
    )
    let rawPeaks = spots.map { spot -> BraggPeak in
        let radius = Float(Double(spot.r) / scale)
        let azimuth = spot.azim + inPlane
        let raw = calibration.ellipseUncorrectedOffset(
            dx: radius * cos(azimuth), dy: radius * sin(azimuth)
        )
        // templateSpots carry the plan's already-compressed weight. A detected
        // Bragg peak carries a physical intensity, which the matcher then
        // compresses itself — so undo the plan's power here, or the fixture
        // applies it twice and flattens the pattern the match is judged on.
        let intensity = plan.intensityPower == 1
            ? spot.weight
            : pow(spot.weight, Float(1 / plan.intensityPower))
        return BraggPeak(x: localOrigin.x + raw.x, y: localOrigin.y + raw.y,
                         intensity: intensity)
    }
    let vectors = BraggVectors(scanWidth: 1, scanHeight: 1, peaks: [rawPeaks])
    let calibrated = vectors.calibrated(with: calibration, referenceOrigin: reference)
    guard let matcher = OrientationMatcher(plan: plan) else { fail("matcher init") }
    let result = matcher.match(
        peaks: calibrated.peaks[0],
        originX: reference.x, originY: reference.y,
        invAngstromPerPixel: scale
    )
    guard result.templateIndex >= 0 else { fail("\(name): matching failed") }
    guard let overlay = FitOverlays.acomTemplateOverlay(
        result: result, plan: plan, invAngstromPerPixel: scale,
        calibration: calibration, referenceOrigin: reference,
        scanIndex: 0, scanWidth: 1, scanHeight: 1,
        patternWidth: 256, patternHeight: 256
    ) else { fail("\(name): no template overlay") }

    // Strong predicted spots must land on the constructed pattern. This is
    // the sign/convention contract for azimuth + in-plane composition and
    // the inverse calibration mapping.
    var checked = 0
    for marker in overlay.predicted where marker.weight >= 0.3 {
        let distance = rawPeaks.map { hypot($0.x - marker.x, $0.y - marker.y) }.min()!
        guard distance < 0.75 else {
            fail("\(name): template spot (\(marker.x), \(marker.y)) off by \(distance) px")
        }
        checked += 1
    }
    guard checked >= 3 else { fail("\(name): too few strong spots checked (\(checked))") }
    print("PASS: \(name) (template \(result.templateIndex), \(checked) strong spots)")
}

acomCase(name: "acom overlay, identity calibration",
         calibration: Calibration(), reference: (x: 128, y: 128))

var acomCal = Calibration()
acomCal.ellipseA = 1.0
acomCal.ellipseB = 0.9
acomCal.ellipseTheta = 0.5
acomCal.origin = OriginMaps(
    width: 1, height: 1, measuredX: nil, measuredY: nil,
    fittedX: [130.5], fittedY: [126.25]
)
acomCase(name: "acom overlay, ellipse + origin maps",
         calibration: acomCal, reference: (x: 128, y: 128))

print("fit-overlay-test: all passed")
