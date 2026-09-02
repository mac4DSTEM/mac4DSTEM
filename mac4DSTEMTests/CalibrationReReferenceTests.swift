//
//  CalibrationReReferenceTests.swift
//  Stage L3 step 2/3/5: moving a calibration into a cropped view's frame, or
//  refusing to.
//
//  These are the geometry rules, tested without a dataset, an actor or a GPU —
//  which is the point of `CalibrationReReference` being pure. The end-to-end
//  claim ("the re-referenced origin lands on the same physical feature as an
//  origin measured on the cropped data") is a different test and lives in
//  tools/load-spec-calibration/, because it needs real patterns and the GPU.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class CalibrationReReferenceTests: XCTestCase {

    // A 4x3 scan on a 10x8 detector (qy = 10 rows, qx = 8 columns).
    // NON-SQUARE ON PURPOSE, in both spaces: a y/x swap is invisible on a square
    // extent, and swapping the axes is the mistake this whole file is about.
    private let source = DatasetDescriptor(
        filePath: "/tmp/source.h5", datasetPath: "/data",
        shape: [4, 3, 10, 8], dtypeDescription: "float32", chunkShape: nil
    )

    /// Origins that differ per scan position AND differ between x and y, so any
    /// mis-indexing changes a value rather than shuffling equal ones.
    private func maps(width: Int = 3, height: Int = 4) -> OriginMaps {
        var fittedX: [Float] = []
        var fittedY: [Float] = []
        for y in 0..<height {
            for x in 0..<width {
                fittedX.append(Float(4 + x))          // columns: 4, 5, 6
                fittedY.append(Float(5 + y) + 0.25)   // rows: 5.25 … 8.25
            }
        }
        return OriginMaps(
            width: width, height: height,
            measuredX: fittedX.map { $0 + 0.5 },
            measuredY: fittedY.map { $0 - 0.5 },
            fittedX: fittedX, fittedY: fittedY
        )
    }

    private func calibration() -> Calibration {
        var calibration = Calibration()
        calibration.origin = maps()
        calibration.originProvenance = .fileMaps
        calibration.probeRadius = 2.5
        calibration.ellipseA = 1.03
        calibration.ellipseB = 0.97
        calibration.ellipseTheta = 0.4
        calibration.qPixelSize = 0.021
        calibration.qPixelUnits = "Å⁻¹"
        calibration.rPixelSize = 0.5
        calibration.rPixelUnits = "nm"
        calibration.rotationRad = 0.1
        calibration.transposeQR = false
        return calibration
    }

    private func apply(
        _ specification: LoadSpecification,
        calibration: Calibration? = nil,
        apertureCenter: CalibrationReReference.DetectorPoint = .init(x: 5, y: 6)
    ) throws -> CalibrationReReference.Outcome {
        let view = try LoadView(source: source, specification: specification)
        return CalibrationReReference.apply(
            view, to: calibration ?? self.calibration(),
            provenance: CalibrationProvenance(), apertureCenter: apertureCenter
        )
    }

    // MARK: - The identity that the whole design rests on

    func testFullExtentChangesNothingAtAll() throws {
        let outcome = try apply(.fullExtent)
        XCTAssertTrue(outcome.isUnchanged)
        XCTAssertEqual(outcome.calibration.origin?.fittedX, maps().fittedX)
        XCTAssertEqual(outcome.calibration.origin?.fittedY, maps().fittedY)
        XCTAssertEqual(outcome.apertureCenter, .init(x: 5, y: 6))
        XCTAssertEqual(outcome.calibration.originProvenance, .fileMaps)
    }

    // MARK: - A detector crop is a translation

    func testDetectorCropSubtractsTheCropOffsetOnTheMatchingAxis() throws {
        // Offsets differ between the axes so a swap cannot pass: x by 2, y by 3.
        let outcome = try apply(LoadSpecification(
            detectorCrop: AxisCrop(yOffset: 3, xOffset: 2, height: 7, width: 6)
        ))
        let origin = try XCTUnwrap(outcome.calibration.origin)
        XCTAssertEqual(origin.fittedX, maps().fittedX.map { $0 - 2 })
        XCTAssertEqual(origin.fittedY, maps().fittedY.map { $0 - 3 })
        // The measured arrays move with the fitted ones — they are positions in
        // the same frame, and leaving them behind would corrupt rmsResidual.
        XCTAssertEqual(origin.measuredX, maps().measuredX?.map { $0 - 2 })
        XCTAssertEqual(origin.measuredY, maps().measuredY?.map { $0 - 3 })
        XCTAssertEqual(outcome.apertureCenter, .init(x: 3, y: 3))
        XCTAssertTrue(outcome.invalidated.isEmpty)
        XCTAssertEqual(outcome.calibration.originProvenance, .fileMaps,
                       "a translation loses no trust, so provenance is kept")
    }

    func testRmsResidualSurvivesTheTranslationUnchanged() throws {
        let before = try XCTUnwrap(calibration().origin?.rmsResidual)
        let outcome = try apply(LoadSpecification(
            detectorCrop: AxisCrop(yOffset: 3, xOffset: 2, height: 7, width: 6)
        ))
        let after = try XCTUnwrap(outcome.calibration.origin?.rmsResidual)
        XCTAssertEqual(before, after, accuracy: 1e-6,
                       "a rigid translation of both arrays cannot change their difference")
    }

    func testLengthsAnglesAndSamplingIntervalsAreCarriedUnchanged() throws {
        let outcome = try apply(LoadSpecification(
            scanCrop: AxisCrop(yOffset: 1, xOffset: 1, height: 2, width: 2),
            detectorCrop: AxisCrop(yOffset: 3, xOffset: 2, height: 7, width: 6)
        ))
        // A radius, an angle and a sampling interval are not positions.
        XCTAssertEqual(outcome.calibration.probeRadius, 2.5)
        XCTAssertEqual(outcome.calibration.ellipseA, 1.03)
        XCTAssertEqual(outcome.calibration.ellipseB, 0.97)
        XCTAssertEqual(outcome.calibration.ellipseTheta, 0.4)
        XCTAssertEqual(outcome.calibration.qPixelSize, 0.021)
        XCTAssertEqual(outcome.calibration.rPixelSize, 0.5)
        XCTAssertEqual(outcome.calibration.rotationRad, 0.1)
    }

    // MARK: - A scan crop is a selection

    func testScanCropTakesTheSubRectangleExactly() throws {
        // Keep scan rows 1..2, columns 1..2 of the 4x3 map.
        let outcome = try apply(LoadSpecification(
            scanCrop: AxisCrop(yOffset: 1, xOffset: 1, height: 2, width: 2)
        ))
        let origin = try XCTUnwrap(outcome.calibration.origin)
        XCTAssertEqual(origin.width, 2)
        XCTAssertEqual(origin.height, 2)
        // Columns 1,2 -> x of 5,6; rows 1,2 -> y of 6.25, 7.25.
        XCTAssertEqual(origin.fittedX, [5, 6, 5, 6])
        XCTAssertEqual(origin.fittedY, [6.25, 6.25, 7.25, 7.25])
    }

    func testScanCropMakesScanIndexedResultsAmbiguousAndSaysSo() throws {
        let outcome = try apply(LoadSpecification(
            scanCrop: AxisCrop(yOffset: 1, xOffset: 0, height: 3, width: 3)
        ))
        XCTAssertTrue(outcome.scanIndexedResultsAreAmbiguous)
        let reason = try XCTUnwrap(
            outcome.invalidated.first { $0.field == .scanIndexedResults }?.reason
        )
        XCTAssertTrue(reason.contains("different position"),
                      "the reason must say WHY, not just that something was cleared")
    }

    func testADetectorCropAloneLeavesScanIndexedResultsAlone() throws {
        let outcome = try apply(LoadSpecification(
            detectorCrop: AxisCrop(yOffset: 1, xOffset: 1, height: 8, width: 6)
        ))
        XCTAssertFalse(outcome.scanIndexedResultsAreAmbiguous,
                       "cropping the detector does not renumber a scan position")
    }

    func testAnOriginMapThatDoesNotDescribeThisScanIsInvalidatedNotCropped() throws {
        var calibration = self.calibration()
        calibration.origin = maps(width: 7, height: 7)   // not the 4x3 source scan
        let outcome = try apply(
            LoadSpecification(scanCrop: AxisCrop(yOffset: 1, xOffset: 1, height: 2, width: 2)),
            calibration: calibration
        )
        XCTAssertNil(outcome.calibration.origin)
        XCTAssertEqual(outcome.calibration.originProvenance, .geometricDefault)
        XCTAssertTrue(outcome.invalidated.contains { $0.field == .origin })
    }

    // MARK: - The refusals

    func testAnOriginOutsideTheDetectorCropIsInvalidatedRatherThanClamped() throws {
        // Origins sit at x 4…6, y 5.25…8.25. This crop starts at x 6, so the
        // x = 4 column lands at -2.
        let outcome = try apply(LoadSpecification(
            detectorCrop: AxisCrop(yOffset: 0, xOffset: 6, height: 10, width: 2)
        ))
        XCTAssertNil(outcome.calibration.origin,
                     "an unusable origin is dropped, never clamped into the crop")
        XCTAssertEqual(outcome.calibration.originProvenance, .geometricDefault)
        XCTAssertNil(outcome.apertureCenter)
        let reason = try XCTUnwrap(
            outcome.invalidated.first { $0.field == .origin }?.reason
        )
        XCTAssertTrue(reason.contains("direct beam"), "reason: \(reason)")
        XCTAssertTrue(reason.contains("Widen the crop"), "the reason states a remedy")
    }

    func testANonFiniteOriginCountsAsOutsideRatherThanPassingTheBoundsCheck() throws {
        var calibration = self.calibration()
        var origin = maps()
        origin.fittedX[3] = .nan
        calibration.origin = origin
        let outcome = try apply(
            LoadSpecification(detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 10, width: 8)),
            calibration: calibration
        )
        XCTAssertNil(outcome.calibration.origin,
                     "NaN is unorderable, so a naive bounds test would admit it")
        XCTAssertTrue(outcome.invalidated.contains { $0.field == .origin })
    }

    func testTheApertureCentreAloneIsReReferencedWhenTheFileCarriesNoMaps() throws {
        // A file with qx0/qy0 only: the aperture centre is the app's ONLY origin.
        var calibration = self.calibration()
        calibration.origin = nil
        calibration.originProvenance = .fileMean
        let outcome = try apply(
            LoadSpecification(detectorCrop: AxisCrop(yOffset: 3, xOffset: 2, height: 7, width: 6)),
            calibration: calibration, apertureCenter: .init(x: 5, y: 6)
        )
        XCTAssertEqual(outcome.apertureCenter, .init(x: 3, y: 3))
        XCTAssertTrue(outcome.invalidated.isEmpty)
    }

    // MARK: - Order

    func testAScanPositionBeingCroppedAwayCannotVetoTheDetectorCrop() throws {
        // Put a wild origin at scan (0, 0) — a position the scan crop removes.
        // If the detector crop were judged before the scan selection, this would
        // invalidate a calibration that is in fact perfectly good.
        var calibration = self.calibration()
        var origin = maps()
        origin.fittedX[0] = 500
        origin.fittedY[0] = 500
        calibration.origin = origin
        let outcome = try apply(
            LoadSpecification(
                scanCrop: AxisCrop(yOffset: 1, xOffset: 1, height: 2, width: 2),
                detectorCrop: AxisCrop(yOffset: 3, xOffset: 2, height: 7, width: 6)
            ),
            calibration: calibration
        )
        XCTAssertNotNil(outcome.calibration.origin,
                        "the excursion is outside the loaded scan; it gets no vote")
        XCTAssertFalse(outcome.invalidated.contains { $0.field == .origin })
    }

    // MARK: - Binning (L4)

    func testBinningMapsAPositionToTheCentreOfItsBinNotToBinTimesTheIndex() throws {
        // THE HALF-PIXEL. Binned pixel j sums source pixels j*b … j*b+b-1, so
        // its centre is at source coordinate j*b + (b-1)/2 — and the inverse of
        // that is (x + 0.5)/b - 0.5, NOT x/b. Asserted with exact arithmetic
        // because the difference is (b-1)/2b px: 0.25 at bin 2, rising to 0.4375
        // at bin 8. That is under half a binned pixel and biased in one
        // direction, so in real data it would read as a small systematic descan
        // error rather than as a bug — no estimator-based test would separate it.
        var specification = LoadSpecification()
        specification.detectorBin = 2
        let outcome = try apply(specification)
        let origin = try XCTUnwrap(outcome.calibration.origin)
        // Source x of 4, 5, 6 -> 1.75, 2.25, 2.75. Naive x/2 would give 2, 2.5, 3.
        XCTAssertEqual(origin.fittedX[0], 1.75)
        XCTAssertEqual(origin.fittedX[1], 2.25)
        XCTAssertEqual(origin.fittedX[2], 2.75)
        // Source y of 5.25 -> (5.25 + 0.5)/2 - 0.5 = 2.375.
        XCTAssertEqual(origin.fittedY[0], 2.375)
        // The centre of the detector must stay the centre of the binned one.
        XCTAssertEqual(CalibrationReReference.binnedCoordinate(4.5, bin: 2), 2.0)
        XCTAssertEqual(CalibrationReReference.binnedCoordinate(7.5, bin: 8), 0.5)
    }

    func testTheBinnedOriginConventionMatchesTheExportWriter() throws {
        // `BraggVectorEMDWriter.transformedCalibration` has applied
        // ($0 + 0.5)/bin - 0.5 on export since before this stage. Two
        // conventions for one operation in a single codebase is how they drift
        // apart, so this pins them together rather than trusting a comment.
        for bin in [2, 4, 8] {
            for value in [Float(0), 3.5, 7, 12.25, 63] {
                let reReference = CalibrationReReference.binnedCoordinate(value, bin: bin)
                let writer = Float((Double(value) + 0.5) / Double(bin) - 0.5)
                XCTAssertEqual(reReference, writer, accuracy: 1e-6,
                               "bin \(bin), value \(value)")
            }
        }
    }

    func testBinningDividesLengthsAndMultipliesTheSamplingInterval() throws {
        var specification = LoadSpecification()
        specification.detectorBin = 2
        let outcome = try apply(specification)
        // A radius in detector pixels: the pixels got twice as big.
        XCTAssertEqual(outcome.calibration.probeRadius, 1.25)
        // Semi-axes are lengths too.
        XCTAssertEqual(try XCTUnwrap(outcome.calibration.ellipseA), 1.03 / 2, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(outcome.calibration.ellipseB), 0.97 / 2, accuracy: 1e-12)
        // An angle is not a length.
        XCTAssertEqual(outcome.calibration.ellipseTheta, 0.4)
        // A sampling interval goes the OTHER way — this is py4DSTEM's own
        // rescale and the only one it performs.
        XCTAssertEqual(try XCTUnwrap(outcome.calibration.qPixelSize), 0.021 * 2, accuracy: 1e-12)
        // Real-space sampling is untouched by diffraction binning.
        XCTAssertEqual(outcome.calibration.rPixelSize, 0.5)
    }

    func testRescalingTheEllipseChangesNoComputedOffset() throws {
        // Both semi-axes scale together, and `ellipseTransform` uses only their
        // ratio, so this must change the stored numbers and nothing else. If it
        // ever changes a result, the rescale has become a different decision.
        var specification = LoadSpecification()
        specification.detectorBin = 4
        let outcome = try apply(specification)
        XCTAssertEqual(calibration().ellipseCorrectedOffset(dx: 3.5, dy: -2.25).x,
                       outcome.calibration.ellipseCorrectedOffset(dx: 3.5, dy: -2.25).x)
        XCTAssertEqual(calibration().ellipseCorrectedOffset(dx: 3.5, dy: -2.25).y,
                       outcome.calibration.ellipseCorrectedOffset(dx: 3.5, dy: -2.25).y)
    }

    func testBinningItselfNeverPushesAValidOriginOffTheDetector() throws {
        // Binning maps a position TOWARD the origin, so compression alone can
        // never move an on-detector position off it. Bin 2 divides the 10 x 8
        // detector exactly, so nothing is trimmed and every origin must survive.
        //
        // This is the property the bounds check must not get wrong: the first
        // version tested against [0, width) and rejected every origin here,
        // because `binnedCoordinate` sends source 0 to a NEGATIVE binned
        // coordinate. The detector physically covers [-0.5, width - 0.5).
        var specification = LoadSpecification()
        specification.detectorBin = 2
        let outcome = try apply(specification)
        XCTAssertNotNil(outcome.calibration.origin)
        XCTAssertTrue(outcome.invalidated.isEmpty)
    }

    func testTheEdgeRemainderCanInvalidateAnOriginAndThatIsCorrect() throws {
        // Bin 4 and 8 trim the 10-row detector to 8, dropping rows 8 and 9 —
        // and the fitted origin sits at y 5.25…8.25, so the last scan row's
        // beam is in the discarded strip. The origin is genuinely not on the
        // detector that was loaded, and invalidating it is right.
        //
        // Worth its own test because the CAUSE is easy to misattribute: it is
        // the edge-remainder trim, not the binning, and the two arrive together.
        // Reading this as "binning broke the calibration" would send someone
        // looking in the wrong place.
        for bin in [4, 8] {
            var specification = LoadSpecification()
            specification.detectorBin = bin
            let outcome = try apply(specification)
            XCTAssertNil(outcome.calibration.origin, "bin \(bin)")
            XCTAssertTrue(outcome.invalidated.contains { $0.field == .origin }, "bin \(bin)")
        }

        // The same origin on a detector the factor divides exactly survives —
        // which is what shows the trim is the cause.
        let divisible = DatasetDescriptor(
            filePath: "/tmp/source.h5", datasetPath: "/data",
            shape: [4, 3, 16, 8], dtypeDescription: "float32", chunkShape: nil
        )
        var specification = LoadSpecification()
        specification.detectorBin = 4
        let view = try LoadView(source: divisible, specification: specification)
        XCTAssertEqual(view.discardedDetectorRows, 0)
        let outcome = CalibrationReReference.apply(
            view, to: calibration(), provenance: CalibrationProvenance(),
            apertureCenter: .init(x: 5, y: 6)
        )
        XCTAssertNotNil(outcome.calibration.origin)
    }

    func testAPositionInTheFirstHalfOfPixelZeroIsOnTheDetector() throws {
        // The exact case the [0, width) test got wrong, asserted directly.
        var calibration = self.calibration()
        var origin = maps()
        origin.fittedX = origin.fittedX.map { _ in 0 }   // source pixel 0
        origin.fittedY = origin.fittedY.map { _ in 0 }
        calibration.origin = origin
        var specification = LoadSpecification()
        specification.detectorBin = 4
        let outcome = try apply(specification, calibration: calibration,
                                apertureCenter: .init(x: 0, y: 0))
        // (0 + 0.5)/4 - 0.5 = -0.375, which is inside pixel 0 of the binned
        // detector and must not invalidate anything.
        XCTAssertEqual(outcome.calibration.origin?.fittedX.first, -0.375)
        XCTAssertNotNil(outcome.apertureCenter)
        XCTAssertTrue(outcome.invalidated.isEmpty)
    }

    func testAnOriginOffTheBinnedDetectorIsStillInvalidated() throws {
        // The check must stay real after the frame change above: a crop that
        // excludes the beam still invalidates, in the binned frame.
        var specification = LoadSpecification()
        specification.detectorBin = 2
        specification.detectorCrop = AxisCrop(yOffset: 0, xOffset: 6, height: 10, width: 2)
        let outcome = try apply(specification)
        XCTAssertNil(outcome.calibration.origin)
        XCTAssertTrue(outcome.invalidated.contains { $0.field == .origin })
    }

    func testTheEdgeRemainderIsRecordedRatherThanSilentlyDropped() throws {
        // The 10 x 8 detector binned by 4 keeps 8 x 8: two rows go.
        var specification = LoadSpecification()
        specification.detectorBin = 4
        let view = try LoadView(source: source, specification: specification)
        XCTAssertEqual(view.discardedDetectorRows, 2)
        XCTAssertEqual(view.discardedDetectorColumns, 0)
        XCTAssertEqual(view.descriptor.shape, [4, 3, 2, 2])
        // And the trimmed extent is what a reader is told to read, so the
        // dropped rows are never fetched.
        XCTAssertEqual(view.readDetectorCrop?.height, 8)
        XCTAssertEqual(view.readDetectorCrop?.yOffset, 0,
                       "py4DSTEM drops the remainder from the END of the axis")
    }

    // MARK: - Step 5: minPeakSpacing must still follow automatically

    func testMinPeakSpacingFollowsTheViewWithoutSpecialHandling() throws {
        // A LARGER detector and a real probe radius, not the 10x8 fixture the
        // rest of this file uses. On 10x8 the derivation floors at 4 for both
        // the full extent and any crop, so the test would have compared 4 with 4
        // and passed no matter what the re-reference did to `probeRadius` — the
        // control at the bottom is what caught that.
        let bigSource = DatasetDescriptor(
            filePath: "/tmp/source.h5", datasetPath: "/data",
            shape: [4, 3, 128, 96], dtypeDescription: "float32", chunkShape: nil
        )
        var bigCalibration = calibration()
        bigCalibration.probeRadius = 9
        let specification = LoadSpecification(
            detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 64, width: 48)
        )
        let view = try LoadView(source: bigSource, specification: specification)
        let outcome = CalibrationReReference.apply(
            view, to: bigCalibration, provenance: CalibrationProvenance(),
            apertureCenter: .init(x: 5, y: 6)
        )

        // The derivation reads the detector extent and the probe radius. The
        // extent is the VIEW's because `AppState.descriptor` is the view's, and
        // the probe radius came through the re-reference unchanged — so the
        // value follows with no crop-specific code anywhere. Pinned because this
        // is exactly the kind of derived property that quietly stops being true.
        let derived = DiskDetectionParams.detectorAdapted(
            qy: view.descriptor.qy, qx: view.descriptor.qx,
            probeRadius: outcome.calibration.probeRadius
        )
        let expected = DiskDetectionParams.detectorAdapted(
            qy: 64, qx: 48, probeRadius: 9
        )
        XCTAssertEqual(derived.minPeakSpacing, expected.minPeakSpacing)
        XCTAssertEqual(derived.edgeBoundary, expected.edgeBoundary)
        XCTAssertNotEqual(
            derived.minPeakSpacing,
            DiskDetectionParams.detectorAdapted(qy: 128, qx: 96, probeRadius: 9).minPeakSpacing,
            "if the cropped and full-extent values agreed, this test would prove nothing"
        )
    }

    // MARK: - The recorded beam centre (P2 refuter residual, 2026-09-01)

    // `Calibration.recordedOriginX/Y` is re-referenced by the same crop-then-
    // bin rule as the aperture centre — and since P2 routed SESSION
    // calibration through this engine, that rule is load-bearing for every
    // sidecar reopened on a reduced view. It had no direct unit test; these
    // pin it with values the aperture path cannot mask (the recorded centre is
    // deliberately NOT the aperture centre, and x ≠ y everywhere).

    func testTheRecordedOriginSubtractsTheCropOffsetLikeTheAperture() throws {
        var calibration = calibration()
        calibration.recordedOriginX = 5.5
        calibration.recordedOriginY = 6
        let outcome = try apply(LoadSpecification(
            detectorCrop: AxisCrop(yOffset: 3, xOffset: 2, height: 6, width: 6)
        ), calibration: calibration)
        XCTAssertEqual(outcome.calibration.recordedOriginX, 3.5)
        XCTAssertEqual(outcome.calibration.recordedOriginY, 3)
        XCTAssertTrue(outcome.invalidated.isEmpty)
    }

    func testTheRecordedOriginBinsToTheBinCentreNotToValueOverBin() throws {
        // Crop (x 2, y 3) THEN bin 2: (5.5 − 2 + 0.5)/2 − 0.5 = 1.5 and
        // (6 − 3 + 0.5)/2 − 0.5 = 1.25. Naive division would give 1.75 / 1.5;
        // binning before cropping would give (2.5 − 1) = 1.5 in y — every
        // wrong order or convention lands on a different number.
        var calibration = calibration()
        calibration.recordedOriginX = 5.5
        calibration.recordedOriginY = 6
        var specification = LoadSpecification(
            detectorCrop: AxisCrop(yOffset: 3, xOffset: 2, height: 6, width: 6)
        )
        specification.detectorBin = 2
        let outcome = try apply(specification, calibration: calibration)
        XCTAssertEqual(outcome.calibration.recordedOriginX, 1.5)
        XCTAssertEqual(outcome.calibration.recordedOriginY, 1.25)
        // And it agrees with the shared convention the maps and the writer use.
        XCTAssertEqual(outcome.calibration.recordedOriginX,
                       CalibrationReReference.binnedCoordinate(5.5 - 2, bin: 2))
    }

    func testARecordedOriginOutsideTheCropIsDroppedAndNamedNotClamped() throws {
        // Recorded (1, 1) with the crop starting at x = 2: it lands at x = −1,
        // off the loaded detector. Refusal-honesty: nil plus a named reason,
        // never a clamp to the edge (the ui-08 corner-BF failure mode, R11).
        var calibration = calibration()
        calibration.recordedOriginX = 1
        calibration.recordedOriginY = 1
        // The fitted maps (x 4–6) survive this crop, so the origin field is
        // invalidated by the RECORDED value alone — the check is independent.
        let outcome = try apply(LoadSpecification(
            detectorCrop: AxisCrop(yOffset: 0, xOffset: 2, height: 10, width: 6)
        ), calibration: calibration)
        XCTAssertNil(outcome.calibration.recordedOriginX)
        XCTAssertNil(outcome.calibration.recordedOriginY)
        XCTAssertNotNil(outcome.calibration.origin, "the fitted maps were inside the crop")
        let reason = try XCTUnwrap(outcome.invalidated.first { $0.field == .origin })
        XCTAssertTrue(reason.reason.contains("recorded beam centre"), reason.reason)
    }

    func testAFullExtentViewLeavesTheRecordedOriginUntouched() throws {
        var calibration = calibration()
        calibration.recordedOriginX = 5.5
        calibration.recordedOriginY = 6
        let outcome = try apply(LoadSpecification(), calibration: calibration)
        XCTAssertEqual(outcome.calibration.recordedOriginX, 5.5)
        XCTAssertEqual(outcome.calibration.recordedOriginY, 6)
    }
}
