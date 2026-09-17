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
import DSTEMSession
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

/// The permutation null on the R–Q rotation fit (2026-09-14/15). Gate D record:
/// `docs/open-items.md`, "R–Q rotation reports Measured from a field that is
/// pure shot noise". The app told the owner it had measured −67.5° on a cube
/// built with the axes aligned; the field it fitted was Poisson noise.
final class RotationSignificanceTests: XCTestCase {

    /// A field with a genuine rotation must still be measured. Mutation this
    /// names: a null that is too strict, or `carriesRotation` inverted — either
    /// one would refuse every real dataset, which is worse than the defect.
    func testARealRotationIsStillMeasured() throws {
        let planted = 30.0 * Double.pi / 180
        let field = Self.phaseObjectField(width: 40, height: 40, rotatedBy: planted)
        let result = try XCTUnwrap(RotationCalibration.solve(com: field, width: 40, height: 40))
        XCTAssertTrue(result.carriesRotation,
                      "a planted 30° rotation on a phase-object field was refused: "
                      + "depth \(result.depth), shuffled max \(result.shuffledDepths.max() ?? 0)")
        XCTAssertNil(result.refusalMessage)
        // and it is the right angle, up to the method's own 180° ambiguity
        let deg = Double(result.rotationRad) * 180 / .pi
        let error = min(abs(deg + 30), abs(deg + 30 - 180), abs(deg + 30 + 180))
        XCTAssertLessThan(error, 2.0, "recovered \(deg)°, expected −30° (mod 180)")
    }

    /// Mutation this names: deleting the null, or comparing against the mean of
    /// the shuffles rather than all of them. Either restores the defect.
    func testAFieldOfPureNoiseIsRefused() throws {
        let field = Self.noiseField(width: 40, height: 40)
        let result = try XCTUnwrap(RotationCalibration.solve(com: field, width: 40, height: 40))
        XCTAssertFalse(result.carriesRotation,
                       "a field of pure noise was reported as a rotation: depth "
                       + "\(result.depth), shuffled max \(result.shuffledDepths.max() ?? 0)")
        let refusal = try XCTUnwrap(result.refusalMessage)
        XCTAssertTrue(refusal.contains("surrogates with the same spectrum"),
                      "the refusal must name the null it lost to — the surrogate, not the "
                      + "shuffle the 2026-09-15 drive still read on screen: \(refusal)")
        // Gate B, 2026-09-15: the sentence used to claim "the rotation is left
        // as Not set", which the code never establishes — it declines to write
        // and never clears. A refusal that misdescribes the state it leaves is
        // worse than none, so the wording is pinned here.
        XCTAssertTrue(refusal.contains("not updated"),
                      "the refusal must not claim to have cleared anything: \(refusal)")
        XCTAssertFalse(refusal.contains("Not set"),
                       "the refusal claims a state the code does not establish")
    }

    /// THE FAILURE GATE B FOUND, pinned (2026-09-15 night). A rotation-free
    /// field with spatial structure — white noise smoothed by a 7 × 7 box,
    /// longer than probe overlap produces — was certified 65 % of the time by
    /// the shuffle null (`tools/rotation-null-probe`, box 7). The
    /// phase-randomised surrogate null keeps the field's correlation length,
    /// so structure alone no longer beats it. Six fixed seeds, each a
    /// deterministic refusal under the new null (seed 16 was certified — the
    /// 1-in-16 lottery the entry records — and was swapped for 17; the rate
    /// claim lives in the probe, this pins six fields). Under the old null the
    /// same six seeds were scanned and four of them certified, so restoring
    /// the shuffle turns this red.
    func testAStructuredRotationFreeFieldIsRefused() throws {
        for seed in [11, 12, 13, 14, 15, 17] as [UInt64] {
            let field = Self.smoothedNoiseField(width: 40, height: 40, radius: 3, seed: seed)
            let result = try XCTUnwrap(RotationCalibration.solve(com: field, width: 40, height: 40))
            XCTAssertFalse(result.carriesRotation,
                           "seed \(seed): a rotation-free field with a 7-px correlation length "
                           + "was certified: depth \(result.depth), null max "
                           + "\(result.shuffledDepths.max() ?? 0)")
        }
    }

    /// The surrogate must be a REAL field: Gate B (2026-09-15 night) dropped
    /// the Hermitian pairing so each bin got an independent phase, and every
    /// pinned test stayed green because the noiseless planted rotation's
    /// depth dwarfs even a garbage null — while the probe's noisy planted
    /// rotation fell from 60 of 60 certified to 16. Three seeds at sd 0.03:
    /// under that mutation the chance that all three certify is about 2 %.
    func testANoisyPlantedRotationIsStillCertified() throws {
        for seed in [3, 4, 5] as [UInt64] {
            let field = Self.noisyPhaseObjectField(width: 40, height: 40, rotatedBy: 30 * .pi / 180,
                                                   noiseSd: 0.03, seed: seed)
            let result = try XCTUnwrap(RotationCalibration.solve(com: field, width: 40, height: 40))
            XCTAssertTrue(result.carriesRotation,
                          "seed \(seed): a planted 30° under sd 0.03 was refused: depth "
                          + "\(result.depth), null max \(result.shuffledDepths.max() ?? 0)")
        }
    }

    /// The null must not move between runs. A refusal that flickers is worse
    /// than none, because the user cannot tell which answer to believe.
    func testTheNullIsDeterministic() throws {
        let field = Self.noiseField(width: 32, height: 32)
        let first = try XCTUnwrap(RotationCalibration.solve(com: field, width: 32, height: 32))
        let second = try XCTUnwrap(RotationCalibration.solve(com: field, width: 32, height: 32))
        XCTAssertEqual(first.shuffledDepths, second.shuffledDepths,
                       "the permutation null is not reproducible")
        XCTAssertEqual(first.carriesRotation, second.carriesRotation)
    }

    /// The three mutations Gate B left alive on 2026-09-15, pinned here.
    /// None is about the science; each is about a claim the code makes that
    /// nothing checked.
    func testTheNullReportsFifteenShufflesOfTheWinningCurve() throws {
        let field = Self.noiseField(width: 40, height: 40)
        let result = try XCTUnwrap(RotationCalibration.solve(com: field, width: 40, height: 40))

        // (1) `shuffleCount` 15 → 6 was green. Fifteen is a 1-in-16 design
        // rate; six is 1-in-7, more than double the false-certification rate,
        // and nothing noticed.
        XCTAssertEqual(result.shuffledDepths.count, 15,
                       "the null's size is what sets its false-certification rate")

        // (2) `depth` is the WINNING curve's, not the losing one's — taking the
        // loser was green, and the comment arguing for the winner was the only
        // thing saying so. Recomputed here from the curves the result carries.
        func depth(_ c: [Float]) -> Float {
            guard let lo = c.min(), let hi = c.max() else { return .nan }
            let mean = c.reduce(0, +) / Float(c.count)
            return mean != 0 ? (hi - lo) / abs(mean) : .nan
        }
        let winning = result.transpose ? result.objectiveCurveTransposed : result.objectiveCurve
        let losing = result.transpose ? result.objectiveCurve : result.objectiveCurveTransposed
        XCTAssertEqual(result.depth, depth(winning), accuracy: 1e-6,
                       "depth was not measured on the curve the answer came from")
        // and the two must differ, or the assertion above is vacuous
        XCTAssertNotEqual(depth(winning), depth(losing), accuracy: 1e-9)
    }

    /// THE MUTATION THIS CLOSES, and it is the one that mattered: Gate B
    /// deleted the guard from `AppState.calibrateRotation` and the entire
    /// suite stayed green, because every test lived in Core and none
    /// constructed a session. The line deciding whether a refused rotation
    /// reaches strain, ACOM and DPC was the line nothing covered.
    func testARefusedFitWritesNothingAndAKeptOneWrites() {
        let session = CalibrationSession()

        // A fit the field does not support: nothing may be written.
        let refused = Self.result(depth: .nan, shuffled: [])
        let message = session.applyRotation(refused)
        XCTAssertNotNil(message, "a refused fit was accepted")
        XCTAssertNil(session.calibration.rotationRad)
        XCTAssertNil(session.calibration.transposeQR)
        XCTAssertNil(session.provenance.rotation)

        // One it does: angle, transpose and provenance all land together.
        let kept = Self.result(depth: 1.0, shuffled: [0.1, 0.2])
        XCTAssertNil(session.applyRotation(kept), "a good fit was refused")
        XCTAssertEqual(session.calibration.rotationRad, kept.rotationRad)
        XCTAssertEqual(session.calibration.transposeQR, kept.transpose)
        XCTAssertEqual(session.provenance.rotation, .measuredInApp)
    }

    /// `applyEllipseFit`/`refuseEllipseFit`: the ellipse's version of the two
    /// tests above, at the same boundary and for the same reason (Gate B,
    /// 2026-09-15) — the "fit anyway" decision lives in `CalibrationSession`
    /// precisely so a test can reach it without an `AppState`.
    func testAFullCoverageEllipseFitIsMeasuredInApp() {
        let session = CalibrationSession()
        let fit = Self.ellipseFit(sparseCoverage: false, occupiedAngularBins: 34)
        session.applyEllipseFit(fit)

        XCTAssertEqual(session.calibration.ellipseA, fit.a)
        XCTAssertEqual(session.calibration.ellipseB, fit.b)
        XCTAssertEqual(session.calibration.ellipseTheta, fit.theta)
        XCTAssertEqual(session.provenance.ellipse, .measuredInApp)
        let item = session.readiness.items.first { $0.kind == .ellipse }
        XCTAssertEqual(item?.status, .ready(.measuredInApp))
        XCTAssertNil(session.ellipseFitAnywayOffer)
    }

    func testASparseEllipseFitIsMarkedFitAnywayAndReady() {
        let session = CalibrationSession()
        let fit = Self.ellipseFit(sparseCoverage: true, occupiedAngularBins: 20)
        session.applyEllipseFit(fit)

        XCTAssertEqual(session.provenance.ellipse, .fitAnyway)
        XCTAssertEqual(session.provenance.ellipse?.stateLabel, "Fit anyway")
        let item = session.readiness.items.first { $0.kind == .ellipse }
        XCTAssertEqual(item?.status, .ready(.fitAnyway))
        XCTAssertEqual(item?.status.isReady, true)
        XCTAssertEqual(item?.status.displayName, "Fit anyway")
        XCTAssertEqual(session.lastEllipseFit, fit)
        XCTAssertNil(session.ellipseFitAnywayOffer)
    }

    /// The offer exists ONLY in the band a retry could rescue: below the
    /// sparse floor `fit1D` refuses outright regardless of `acceptSparseCoverage`,
    /// and at/above the degeneracy bound the original call would not have been
    /// refused for coverage in the first place — belt and braces on that last
    /// one, since it should be unreachable from the fitter itself.
    func testACoverageRefusalOffersFitAnywayOnlyBetweenTheFloorAndTheBound() {
        let session = CalibrationSession()

        session.refuseEllipseFit(EllipseCalibration.FitError.insufficientAngularCoverage(12))
        XCTAssertEqual(session.ellipseFitAnywayOffer, 12)
        XCTAssertFalse(session.calibration.hasEllipse)
        XCTAssertNil(session.provenance.ellipse)

        session.refuseEllipseFit(EllipseCalibration.FitError.insufficientAngularCoverage(29))
        XCTAssertEqual(session.ellipseFitAnywayOffer, 29)

        session.refuseEllipseFit(EllipseCalibration.FitError.insufficientAngularCoverage(8))
        XCTAssertNil(session.ellipseFitAnywayOffer)

        session.refuseEllipseFit(EllipseCalibration.FitError.insufficientAngularCoverage(30))
        XCTAssertNil(session.ellipseFitAnywayOffer)

        session.refuseEllipseFit(EllipseCalibration.FitError.moreThanOneRing(minRadius: 36.6, maxRadius: 58.2))
        XCTAssertNil(session.ellipseFitAnywayOffer)

        session.refuseEllipseFit(EllipseCalibration.FitError.invalidEllipse)
        XCTAssertNil(session.ellipseFitAnywayOffer)

        // Moving the annulus retires the offer: the caption named the old one.
        session.refuseEllipseFit(EllipseCalibration.FitError.insufficientAngularCoverage(18))
        XCTAssertEqual(session.ellipseFitAnywayOffer, 18)
        session.ellipseFitOuterRadius += 5
        XCTAssertNil(session.ellipseFitAnywayOffer, "a changed annulus kept a stale offer")
    }

    func testARefusalLeavesAnEarlierEllipseStandingAndASuccessClearsTheOffer() {
        let session = CalibrationSession()
        let full = Self.ellipseFit(sparseCoverage: false, occupiedAngularBins: 34)
        session.applyEllipseFit(full)

        session.refuseEllipseFit(EllipseCalibration.FitError.insufficientAngularCoverage(12))
        XCTAssertEqual(session.calibration.ellipseA, full.a,
                       "the refusal cleared an ellipse it only meant to decline")
        XCTAssertEqual(session.provenance.ellipse, .measuredInApp)
        XCTAssertEqual(session.ellipseFitAnywayOffer, 12)

        let sparse = Self.ellipseFit(sparseCoverage: true, occupiedAngularBins: 20)
        session.applyEllipseFit(sparse)
        XCTAssertNil(session.ellipseFitAnywayOffer)
        XCTAssertEqual(session.provenance.ellipse, .fitAnyway)

        session.clear()
        XCTAssertNil(session.ellipseFitAnywayOffer)
        XCTAssertNil(session.lastEllipseFit)
        XCTAssertFalse(session.calibration.hasEllipse)
    }

    private static func ellipseFit(sparseCoverage: Bool, occupiedAngularBins: Int) -> EllipseCalibrationFit {
        EllipseCalibrationFit(
            centerQX: 12, centerQY: 11, a: 43.68, b: 39.72, theta: 0.4,
            normalizedResidual: 0.08, conicResidual: 0.08,
            sampleCount: 900, occupiedAngularBins: occupiedAngularBins,
            model: .conic, profile: nil, profileFallbackReason: nil,
            sparseCoverage: sparseCoverage
        )
    }

    /// And the behaviour the refusal sentence had to be corrected to describe:
    /// a refusal declines to write, it does NOT clear. An earlier value stands,
    /// which is why the message says "not updated" rather than "Not set".
    func testARefusalLeavesAnEarlierRotationStanding() {
        let session = CalibrationSession()
        XCTAssertNil(session.applyRotation(Self.result(depth: 1.0, shuffled: [0.1])))
        let kept = session.calibration.rotationRad

        let message = session.applyRotation(Self.result(depth: .nan, shuffled: []))
        XCTAssertNotNil(message)
        XCTAssertEqual(session.calibration.rotationRad, kept,
                       "the refusal cleared a rotation it only meant to decline")
        XCTAssertEqual(session.provenance.rotation, .measuredInApp,
                       "the refusal changed the provenance of a value it did not touch")
        XCTAssertTrue(try XCTUnwrap(message).contains("not updated"),
                      "the sentence must describe what actually happened")
    }

    private static func result(depth: Float,
                               shuffled: [Float]) -> RotationCalibration.Result {
        RotationCalibration.Result(
            rotationRad: 0.5236, transpose: true, objective: 0.01,
            anglesDeg: [0], objectiveCurve: [0.01], objectiveCurveTransposed: [0.02],
            depth: depth, shuffledDepths: shuffled)
    }

    // MARK: Fixtures

    /// The gradient of a smooth scalar potential, rotated — what the method is
    /// built for. Interleaved (x, y) per scan position, as `solve` expects.
    private static func phaseObjectField(width: Int, height: Int,
                                         rotatedBy theta: Double) -> [Float] {
        var out = [Float](repeating: 0, count: width * height * 2)
        let c = cos(theta), s = sin(theta)
        for y in 0..<height {
            for x in 0..<width {
                // ∂/∂x and ∂/∂y of sin(x/6)·cos(y/5), analytically.
                let gx = cos(Double(x) / 6) * cos(Double(y) / 5) / 6
                let gy = -sin(Double(x) / 6) * sin(Double(y) / 5) / 5
                let i = (y * width + x) * 2
                out[i] = Float(c * gx - s * gy)
                out[i + 1] = Float(s * gx + c * gy)
            }
        }
        return out
    }

    /// The phase-object gradient field with white noise of `noiseSd` on both
    /// channels, seeded.
    private static func noisyPhaseObjectField(width: Int, height: Int, rotatedBy theta: Double,
                                              noiseSd: Double, seed: UInt64) -> [Float] {
        var state: UInt64 = 0xB16B00B5DEADBEEF &+ seed &* 0x9E3779B97F4A7C15
        func next() -> Double {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            return Double((state &* 2685821657736338717) >> 11) / Double(UInt64(1) << 53)
        }
        func gauss() -> Double { sqrt(-2 * log(max(1e-12, next()))) * cos(2 * .pi * next()) }
        var out = phaseObjectField(width: width, height: height, rotatedBy: theta)
        for i in out.indices { out[i] += Float(gauss() * noiseSd) }
        return out
    }

    /// White noise (sd ≈ 0.010 px) smoothed by a (2·radius + 1)² box, each
    /// channel independently: spatial structure with no rotation in it.
    private static func smoothedNoiseField(width: Int, height: Int, radius: Int, seed: UInt64) -> [Float] {
        var state: UInt64 = 0xC0FFEE0000000000 &+ seed &* 0x9E3779B97F4A7C15
        func next() -> Float {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            let u = Double((state &* 2685821657736338717) >> 11) / Double(UInt64(1) << 53)
            return Float((u - 0.5) * 0.035)
        }
        let white = (0..<(width * height * 2)).map { _ in next() }
        var out = [Float](repeating: 0, count: white.count)
        for y in 0..<height {
            for x in 0..<width {
                var sx: Float = 0, sy: Float = 0, count: Float = 0
                for dy in -radius...radius where y + dy >= 0 && y + dy < height {
                    for dx in -radius...radius where x + dx >= 0 && x + dx < width {
                        let i = ((y + dy) * width + (x + dx)) * 2
                        sx += white[i]; sy += white[i + 1]; count += 1
                    }
                }
                out[(y * width + x) * 2] = sx / count
                out[(y * width + x) * 2 + 1] = sy / count
            }
        }
        return out
    }

    /// Deterministic white noise at the scale the demo cube actually showed
    /// (sd ≈ 0.010 detector pixels), with no spatial structure at all.
    private static func noiseField(width: Int, height: Int) -> [Float] {
        var state: UInt64 = 0xDEADBEEF12345678
        func next() -> Float {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            let u = Double((state &* 2685821657736338717) >> 11) / Double(UInt64(1) << 53)
            return Float((u - 0.5) * 0.02)
        }
        return (0..<(width * height * 2)).map { _ in next() }
    }
}
