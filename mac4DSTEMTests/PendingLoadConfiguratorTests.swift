//
//  PendingLoadConfiguratorTests.swift
//  Pins the pure halves of v2 S4's configurator additions on `PendingLoad`:
//  the brightest-position pick behind the single-DP default, the beam-proxy
//  evidence rule, and the configure-time direct-beam refusal.
//
//  Why the refusal exists here at all: `CalibrationReReference.apply` refuses
//  a beam-excluding crop well, but only when there is an existing calibration
//  to re-reference — on a first open nothing fires and the load succeeds
//  silently (release owner, 2026-08-19). This gate is the only one on that
//  path, which is why it refuses rather than warns.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class PendingLoadConfiguratorTests: XCTestCase {

    // MARK: - brightestPosition (the single-DP default pick)

    func testBrightestPositionFindsTheLargestPixelInImageCoordinates() {
        // 4 wide × 3 tall, brightest at x=1, y=2 (index 9).
        var pixels = [Float](repeating: 0, count: 12)
        pixels[9] = 7
        let position = PendingLoad.brightestPosition(of: pixels, width: 4, height: 3)
        XCTAssertEqual(position?.x, 1)
        XCTAssertEqual(position?.y, 2)
    }

    func testBrightestPositionIgnoresNonFinitePixels() {
        // An infinity or NaN from a dead detector column must not win the
        // argmax — the pick would land the single-DP pane on garbage.
        var pixels: [Float] = [1, 2, 3, 4]
        pixels[0] = .infinity
        pixels[1] = .nan
        let position = PendingLoad.brightestPosition(of: pixels, width: 4, height: 1)
        XCTAssertEqual(position?.x, 3)
        XCTAssertEqual(position?.y, 0)
    }

    func testBrightestPositionRefusesAMismatchedPixelCount() {
        XCTAssertNil(PendingLoad.brightestPosition(of: [1, 2, 3], width: 2, height: 2))
        XCTAssertNil(PendingLoad.brightestPosition(of: [], width: 0, height: 0))
    }

    // MARK: - beamProxyPosition (the refusal's evidence)

    private func meanPattern(beamX: Int, beamY: Int, qx: Int = 8, qy: Int = 8) -> DiffractionPattern {
        var pixels = [Float](repeating: 0.1, count: qx * qy)
        pixels[beamY * qx + beamX] = 100
        return DiffractionPattern(qy: qy, qx: qx, pixels: pixels)
    }

    func testTheBeamProxyIsTheMeanPatternsBrightestPixel() {
        let beam = PendingLoad.beamProxyPosition(of: meanPattern(beamX: 3, beamY: 2))
        XCTAssertEqual(beam?.x, 3)
        XCTAssertEqual(beam?.y, 2)
    }

    func testAFlatMeanPatternCarriesNoBeamEvidence() {
        // Vacuum / flat-field data: "the brightest pixel" of a constant image
        // is a tie-breaking artifact at index 0, not a beam — treating it as
        // one would refuse every crop that misses the top-left corner.
        let flat = DiffractionPattern(qy: 4, qx: 4,
                                      pixels: [Float](repeating: 3.5, count: 16))
        XCTAssertNil(PendingLoad.beamProxyPosition(of: flat))
    }

    func testNonFinitePixelsCannotBeTheBeam() {
        var pixels = [Float](repeating: 0.1, count: 16)
        pixels[0] = .infinity
        pixels[10] = 50
        let beam = PendingLoad.beamProxyPosition(
            of: DiffractionPattern(qy: 4, qx: 4, pixels: pixels)
        )
        XCTAssertEqual(beam?.x, 2)
        XCTAssertEqual(beam?.y, 2)
    }

    // MARK: - directBeamRefusal

    func testACropContainingTheBeamIsNotRefused() {
        let crop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        XCTAssertNil(PendingLoad.directBeamRefusal(beam: (x: 3, y: 2),
                                                   readDetectorCrop: crop))
    }

    func testACropExcludingTheBeamIsRefusedAndTheMessageNamesTheEvidence() throws {
        // Crop covers columns 4–7; the beam sits at column 3 — the exact
        // configuration the 2026-08-19 screenshots were taken in.
        let crop = AxisCrop(yOffset: 0, xOffset: 4, height: 8, width: 4)
        let refusal = PendingLoad.directBeamRefusal(beam: (x: 3, y: 2),
                                                    readDetectorCrop: crop)
        let message = try XCTUnwrap(refusal)
        // Precision explains the rejection: the message must name where the
        // beam evidence is and what is actually read, or the user cannot
        // argue with it (docs/v2-release.md §4).
        XCTAssertTrue(message.contains("column 3"), message)
        XCTAssertTrue(message.contains("row 2"), message)
        XCTAssertTrue(message.contains("direct beam"), message)
    }

    func testTheBeamOnTheCropBoundaryCountsAsInside() {
        // Offset 3, width 1: the crop is exactly the beam's column. An
        // off-by-one here refuses the tightest legitimate crop.
        let crop = AxisCrop(yOffset: 2, xOffset: 3, height: 1, width: 1)
        XCTAssertNil(PendingLoad.directBeamRefusal(beam: (x: 3, y: 2),
                                                   readDetectorCrop: crop))
    }

    func testNoCropMeansNoRefusal() {
        XCTAssertNil(PendingLoad.directBeamRefusal(beam: (x: 3, y: 2),
                                                   readDetectorCrop: nil))
    }

    func testNoBeamEvidenceMeansNoRefusal() {
        // No evidence, no refusal: refusing on absence would block every
        // dataset the preview builder cannot sample, and every flat one.
        let crop = AxisCrop(yOffset: 0, xOffset: 4, height: 8, width: 4)
        XCTAssertNil(PendingLoad.directBeamRefusal(beam: nil,
                                                   readDetectorCrop: crop))
    }

    // MARK: - The gate consults what is READ, not what was requested

    func testABeamInTheBinTrimmedRemainderIsRefused() throws {
        // Detector crop of height 10 under bin 8 reads only 8 rows — the last
        // 2 are the edge remainder, trimmed before any pixel is converted
        // (`LoadView.readDetectorCrop`). A beam in those rows is inside the
        // REQUESTED crop and outside the READ one; the gate must consult the
        // read rectangle, or it silently permits the exact beam-excluded load
        // it exists to stop.
        let source = DatasetDescriptor(
            filePath: "/tmp/fixture.h5", datasetPath: "/data",
            shape: [4, 4, 64, 64], dtypeDescription: "float32", chunkShape: nil
        )
        var specification = LoadSpecification.fullExtent
        specification.detectorCrop = AxisCrop(yOffset: 0, xOffset: 0,
                                              height: 10, width: 64)
        specification.detectorBin = 8
        let view = try LoadView(source: source, specification: specification)
        let readCrop = try XCTUnwrap(view.readDetectorCrop)
        XCTAssertEqual(readCrop.height, 8, "bin 8 must trim 10 rows to 8")

        // Beam at requested row 9: inside the request, outside the read.
        XCTAssertNotNil(
            PendingLoad.directBeamRefusal(beam: (x: 5, y: 9),
                                          readDetectorCrop: readCrop),
            "A beam in the trimmed remainder is never read — the gate must refuse"
        )
        // Against the REQUESTED crop the same beam looks fine — this is the
        // defect the read-crop rule prevents.
        XCTAssertNil(
            PendingLoad.directBeamRefusal(beam: (x: 5, y: 9),
                                          readDetectorCrop: specification.detectorCrop)
        )
    }

    func testABinAloneWithAnEdgeTrimStillGuardsTheBeam() throws {
        // No crop at all, bin 4 on a 66-pixel axis: readDetectorCrop is
        // non-nil (64 of 66 pixels) and a beam in the trimmed 2 columns must
        // still be refused — the nil-crop early-out of the first
        // implementation missed this case entirely.
        let source = DatasetDescriptor(
            filePath: "/tmp/fixture.h5", datasetPath: "/data",
            shape: [4, 4, 66, 66], dtypeDescription: "float32", chunkShape: nil
        )
        var specification = LoadSpecification.fullExtent
        specification.detectorBin = 4
        let view = try LoadView(source: source, specification: specification)
        let readCrop = try XCTUnwrap(
            view.readDetectorCrop,
            "bin > 1 must produce a read rectangle even without a crop"
        )
        XCTAssertNotNil(
            PendingLoad.directBeamRefusal(beam: (x: 65, y: 30),
                                          readDetectorCrop: readCrop)
        )
        XCTAssertNil(
            PendingLoad.directBeamRefusal(beam: (x: 30, y: 30),
                                          readDetectorCrop: readCrop)
        )
    }
}
