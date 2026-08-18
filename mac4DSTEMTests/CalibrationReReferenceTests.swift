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
}
