//
//  tools/load-spec-calibration — stage L3, step 2 (docs/load-pipeline-plan.md).
//
//  THE CLAIM: a re-referenced origin lands on the SAME PHYSICAL FEATURE as an
//  origin measured directly on the cropped data.
//
//  This is the test the plan asks for by name, and it is deliberately not a
//  self-consistency check. `CalibrationReReferenceTests` already pins the
//  arithmetic — "subtract the crop offset" — without a dataset. Arithmetic that
//  is internally consistent and points at the wrong pixel is exactly this
//  repository's recorded failure mode, twice. So here the app MEASURES the beam
//  on the full frame, MEASURES it again on the cropped frame through the real
//  reader crop, and asserts that re-referencing the first gives the second.
//  Nothing in that chain is allowed to be arithmetic this stage wrote:
//  `MetalEngine.measureOrigins` is the arbiter, and it does not know a crop
//  exists.
//
//  Also asserted: a value that CANNOT be re-referenced — the beam outside the
//  diffraction crop — is invalidated with a named reason rather than carried,
//  and the app falls back to the geometric default instead of pointing at a
//  detector pixel it no longer holds.
//
//  WHY "MEASURE IT AGAIN ON THE CROP" IS NOT THE WHOLE ARBITER, and this is the
//  finding that shaped the harness. `measureOrigin` is FRAME-DEPENDENT by
//  construction: its coarse step takes an argmax over blocks of side
//  `bin = round(probeRadius)` tiled from pixel (0, 0), so a crop offset that is
//  not a multiple of `bin` slides that block grid under the disk and moves the
//  coarse centre, and with it the windowed centre of mass. Measured here
//  2026-08-18 on this fixture (bin = 4): a crop at offset (8, 4) — both
//  multiples of 4 — reproduces the full-frame origin EXACTLY, while (6, 4)
//  differs by 0.68 px and (8, 5) by 1.13 px. That is the estimator moving, not
//  the re-reference. py4DSTEM's own coarse step, `argmax(gaussian_filter(dp,
//  sigma=r))`, is translation-equivariant and would not do this; the binned-block
//  substitution is the DELIBERATE DEVIATION recorded in OriginMeasure.metal.
//
//  So the claim is checked two ways, neither of which is the arithmetic under
//  test:
//    1. On a bin-ALIGNED crop the two measurements must agree to 1e-3 px. No
//       confound there, so this is a genuine end-to-end equality.
//    2. On ANY crop the re-referenced origin must agree with the disk position
//       MEASURED IN THE CROPPED PIXELS by this file, using a window anchored on
//       the fixture's analytically known disk centre — a number no code under
//       test has ever seen. A control re-runs the comparison with the
//       un-re-referenced origin, which must miss by roughly the crop offset,
//       otherwise assertion 2 would be proving nothing.
//
//  WHAT ASSERTION 2 IS REALLY FOR, since a translation compared against a
//  translated expectation would be arithmetic proving itself: it checks that the
//  READER's crop and the CALIBRATION's shift use the SAME coordinate convention.
//  If the reader cropped with y and x swapped while the calibration shifted
//  correctly — or the reverse — every unit test in
//  `CalibrationReReferenceTests` would still pass and this one would not.
//
//  Tolerance: 1.0 px, and it is loose on purpose. `measureOrigin` performs a
//  SINGLE centre-of-mass refinement from its coarse block centre rather than
//  iterating, so its output is systematically ~0.6 px from the converged centre
//  on this fixture — a property of the estimator that predates this stage. The
//  defect being guarded against displaces the origin by the crop offset (4-8 px
//  here), so the separation is large: the control asserts a miss of more than
//  3 px.
//

import Foundation

// `Aperture` now lives in Core/Analysis/VirtualDetector.swift (2026-09-02);
// the local mirror this file carried is gone.

var failures: [String] = []

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition { failures.append(message()) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

/// A synthetic cube with a bright disk whose centre MOVES with the scan
/// position, so the origin map is not a constant and a re-reference that
/// collapses it would be caught.
///
/// The disk sits well inside the detector, and its centre is placed on a
/// half-pixel so a rounding difference between the two measurement paths would
/// show up rather than cancelling.
actor DiskCubeSource: FourDDataSource {
    static let ry = 3, rx = 4, qy = 40, qx = 32
    static let descriptor = DatasetDescriptor(
        filePath: "/tmp/disk-cube", datasetPath: "/data",
        shape: [ry, rx, qy, qx], dtypeDescription: "float32", chunkShape: nil
    )
    static let probeRadius: Float = 4

    let cube: [Float]

    init() {
        var cube = [Float](repeating: 0, count: Self.ry * Self.rx * Self.qy * Self.qx)
        for sy in 0..<Self.ry {
            for sx in 0..<Self.rx {
                // Centre wanders with the scan position, as a real descan does.
                let cx = Double(14 + sx) + 0.5
                let cy = Double(18 + sy) + 0.5
                for y in 0..<Self.qy {
                    for x in 0..<Self.qx {
                        let dx = Double(x) - cx
                        let dy = Double(y) - cy
                        let radius = (dx * dx + dy * dy).squareRoot()
                        // Smooth edge, so the centre of mass is well defined.
                        let value = 100 / (1 + exp(3.0 * (radius - Double(Self.probeRadius))))
                        let index = ((sy * Self.rx + sx) * Self.qy + y) * Self.qx + x
                        cube[index] = Float(value)
                    }
                }
            }
        }
        self.cube = cube
    }

    /// The disk centre this fixture DREW, in source detector coordinates. The
    /// arbiter for assertion 2, and the one number in this harness that no code
    /// under test can influence.
    nonisolated static func trueCenter(scanY: Int, scanX: Int) -> (x: Float, y: Float) {
        (Float(14 + scanX) + 0.5, Float(18 + scanY) + 0.5)
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { Self.descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        view.pattern(fromFullCube: cube, ry: ry, rx: rx)
    }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        view.scanRow(fromFullCube: cube, ry: ry)
    }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        view.scanTile(fromFullCube: cube, yRange: yRange)
    }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

/// A windowed centre of mass around a SUPPLIED centre, computed here rather
/// than on the GPU.
///
/// This is the harness's own arbiter: it takes the actual pixels of the cropped
/// pattern and asks "is this position the centre of the intensity around it?".
/// Unlike `measureOrigin` it never searches for the disk, so it has no coarse
/// grid to be shifted by a crop — which is exactly why it can adjudicate a
/// question the kernel cannot.
func windowedCenterOfMass(
    pattern: [Float], qy: Int, qx: Int, centerX: Float, centerY: Float, radius: Float
) -> (x: Float, y: Float)? {
    let windowSquared = radius * radius
    var sumI: Float = 0, sumIX: Float = 0, sumIY: Float = 0
    for y in 0..<qy {
        let dy = Float(y) - centerY
        let dy2 = dy * dy
        if dy2 > windowSquared { continue }
        for x in 0..<qx {
            let dx = Float(x) - centerX
            if dx * dx + dy2 > windowSquared { continue }
            let intensity = max(pattern[y * qx + x], 0)
            sumI += intensity
            sumIX += intensity * Float(x)
            sumIY += intensity * Float(y)
        }
    }
    guard sumI > 0 else { return nil }
    return (sumIX / sumI, sumIY / sumI)
}

/// Measure the beam origin at every scan position of `view`, through the real
/// reader crop and the production Metal kernel.
func measuredOrigins(_ reader: DiskCubeSource, view: LoadView) async throws -> OriginMaps {
    let data = FourDArray(reader: reader, view: view)
    let interleaved = try await VirtualDetector.tiledMeasuredOrigins(
        data: data, descriptor: view.descriptor,
        probeRadius: DiskCubeSource.probeRadius, maximumTileRows: 1
    )
    var x = [Float](), y = [Float]()
    for index in stride(from: 0, to: interleaved.count, by: 2) {
        x.append(interleaved[index])
        y.append(interleaved[index + 1])
    }
    return OriginMaps(width: view.descriptor.rx, height: view.descriptor.ry,
                      measuredX: nil, measuredY: nil, fittedX: x, fittedY: y)
}

@main struct LoadSpecCalibrationHarness {
    static func main() async throws {
        let reader = DiskCubeSource()
        let source = DiskCubeSource.descriptor
        let fullView = LoadView(fullExtentOf: source)

        // Measured once on the whole file — this stands in for a calibration
        // fitted before anyone thought about cropping.
        let full = try await measuredOrigins(reader, view: fullView)

        var calibration = Calibration()
        calibration.origin = full
        calibration.originProvenance = .fitted
        calibration.probeRadius = DiskCubeSource.probeRadius
        let meanX = full.fittedX.reduce(0, +) / Float(full.fittedX.count)
        let meanY = full.fittedY.reduce(0, +) / Float(full.fittedY.count)

        // ---- 1. The same physical feature, under every kind of crop ---------
        // `binAligned` says whether the crop offset is a multiple of the coarse
        // block size, i.e. whether `measureOrigin` can be expected to reproduce
        // the full-frame answer exactly. See the header.
        let crops: [(name: String, specification: LoadSpecification, binAligned: Bool)] = [
            ("detector crop, bin-aligned", LoadSpecification(
                detectorCrop: AxisCrop(yOffset: 8, xOffset: 4, height: 28, width: 24)
            ), true),
            ("detector crop, unaligned", LoadSpecification(
                detectorCrop: AxisCrop(yOffset: 6, xOffset: 5, height: 28, width: 24)
            ), false),
            ("scan crop", LoadSpecification(
                scanCrop: AxisCrop(yOffset: 1, xOffset: 1, height: 2, width: 3)
            ), true),
            ("both, different offsets", LoadSpecification(
                scanCrop: AxisCrop(yOffset: 1, xOffset: 1, height: 2, width: 3),
                detectorCrop: AxisCrop(yOffset: 8, xOffset: 4, height: 28, width: 24)
            ), true),
        ]

        for (name, specification, binAligned) in crops {
            let view = try LoadView(source: source, specification: specification)

            // What the app SAYS the origin is, after moving the full-frame
            // calibration into this view.
            let outcome = CalibrationReReference.apply(
                view, to: calibration, provenance: CalibrationProvenance(),
                apertureCenter: .init(x: meanX, y: meanY)
            )
            guard let reReferenced = outcome.calibration.origin else {
                check(false, "\(name): the origin was invalidated when it should have moved")
                continue
            }
            check(outcome.invalidated.allSatisfy { $0.field == .scanIndexedResults },
                  "\(name): unexpected invalidation \(outcome.invalidated.map(\.field))")

            // ---- Check 1: on a bin-aligned crop, re-measuring must agree ----
            if binAligned {
                let measured = try await measuredOrigins(reader, view: view)
                check(reReferenced.fittedX.count == measured.fittedX.count,
                      "\(name): \(reReferenced.fittedX.count) re-referenced positions against \(measured.fittedX.count) measured")
                if reReferenced.fittedX.count == measured.fittedX.count {
                    var worst: Float = 0
                    for index in 0..<measured.fittedX.count {
                        worst = max(worst, abs(reReferenced.fittedX[index] - measured.fittedX[index]))
                        worst = max(worst, abs(reReferenced.fittedY[index] - measured.fittedY[index]))
                    }
                    check(worst <= 1e-3,
                          "\(name): re-referenced origin is \(worst) px from the origin measured on the cropped data")
                }
            }

            // ---- Check 2: agreement with the disk measured in the CROPPED
            // pixels, anchored on the fixture's analytic centre ----------------
            let window = DiskCubeSource.probeRadius * 1.2
            let (detectorY, detectorX) = specification.detectorOffset
            let (scanY0, scanX0) = specification.scanOffset
            var worstAgreement: Float = 0
            var worstStale: Float = 0
            for viewY in 0..<view.descriptor.ry {
                for viewX in 0..<view.descriptor.rx {
                    let index = viewY * view.descriptor.rx + viewX
                    let pattern = try await reader.readPattern(view, ry: viewY, rx: viewX)

                    // Where the disk IS in this cropped pattern, from the truth
                    // the fixture drew — never from the app.
                    let truth = DiskCubeSource.trueCenter(scanY: scanY0 + viewY,
                                                          scanX: scanX0 + viewX)
                    guard let measured = windowedCenterOfMass(
                        pattern: pattern, qy: view.descriptor.qy, qx: view.descriptor.qx,
                        centerX: truth.x - Float(detectorX), centerY: truth.y - Float(detectorY),
                        radius: window
                    ) else {
                        check(false, "\(name): the fixture's own disk is not in the cropped pattern at (\(viewY), \(viewX)) — the READER crop is wrong, before any calibration question")
                        continue
                    }

                    worstAgreement = max(worstAgreement, abs(measured.x - reReferenced.fittedX[index]))
                    worstAgreement = max(worstAgreement, abs(measured.y - reReferenced.fittedY[index]))

                    // THE CONTROL: the origin the app would have carried if it
                    // had skipped the re-reference — py4DSTEM's behaviour, and
                    // the defect this stage exists to prevent.
                    if specification.detectorCrop != nil {
                        let sourceIndex = (scanY0 + viewY) * source.rx + scanX0 + viewX
                        worstStale = max(worstStale, abs(measured.x - full.fittedX[sourceIndex]))
                        worstStale = max(worstStale, abs(measured.y - full.fittedY[sourceIndex]))
                    }
                }
            }
            check(worstAgreement <= 1.0,
                  "\(name): the re-referenced origin is \(worstAgreement) px from the disk measured in the cropped pixels")
            if specification.detectorCrop != nil {
                check(worstStale > 3,
                      "\(name): a STALE origin was only \(worstStale) px off, so the agreement check proves little")
            }
        }

        // ---- 2. A value that cannot be re-referenced is invalidated ---------
        // Crop to a corner the beam is not in. The origin must be dropped with a
        // named reason — never clamped to the nearest in-crop pixel, which would
        // put the beam at a position it is not at and look entirely plausible.
        do {
            let specification = LoadSpecification(
                detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 6, width: 6)
            )
            let view = try LoadView(source: source, specification: specification)
            let outcome = CalibrationReReference.apply(
                view, to: calibration, provenance: CalibrationProvenance(),
                apertureCenter: .init(x: meanX, y: meanY)
            )
            check(outcome.calibration.origin == nil,
                  "the beam is outside this crop, but the origin was carried anyway")
            check(outcome.apertureCenter == nil,
                  "the aperture centre was carried into a crop that does not contain the beam")
            check(outcome.calibration.originProvenance == .geometricDefault,
                  "an invalidated origin kept its provenance: \(outcome.calibration.originProvenance)")
            let reason = outcome.invalidated.first { $0.field == .origin }?.reason ?? ""
            check(reason.contains("direct beam") && reason.contains("Widen the crop"),
                  "the invalidation reason does not say what happened or what to do: \(reason)")
            // Nothing was clamped: a clamped origin would still be non-nil.
            check(outcome.calibration.probeRadius == DiskCubeSource.probeRadius,
                  "the probe radius is a length and must survive a translation")
        }

        // ---- 3. Full extent is the identity --------------------------------
        do {
            let outcome = CalibrationReReference.apply(
                fullView, to: calibration, provenance: CalibrationProvenance(),
                apertureCenter: .init(x: meanX, y: meanY)
            )
            check(outcome.calibration.origin?.fittedX == full.fittedX
                  && outcome.calibration.origin?.fittedY == full.fittedY,
                  "a full-extent view changed the origin")
            check(outcome.isUnchanged, "a full-extent view reported changes")
        }

        if failures.isEmpty {
            print("load-spec-calibration: all passed")
        } else {
            for message in failures { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)) }
            FileHandle.standardError.write(
                Data("load-spec-calibration: \(failures.count) failure(s)\n".utf8)
            )
            exit(1)
        }
    }
}
