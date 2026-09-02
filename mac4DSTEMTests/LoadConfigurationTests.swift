//
//  LoadConfigurationTests.swift
//  Stage L5: the rectangle -> LoadSpecification mapping the plan asks to unit
//  test, "including inverted drags and out-of-bounds clamping".
//
//  The mapping is where a configurator can be wrong in a way that looks like a
//  UI glitch and is a data defect: the wrong region loads, and every number
//  computed from it is correct about the wrong place.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class LoadConfigurationTests: XCTestCase {

    // 60 x 40 scan on a 128 x 96 detector. Non-square in both spaces, and the
    // scan is taller than it is wide while the detector is wider than it is
    // tall — so a y/x swap cannot survive anywhere.
    private let source = DatasetDescriptor(
        filePath: "/tmp/source.h5", datasetPath: "/data",
        shape: [60, 40, 128, 96], dtypeDescription: "uint16", chunkShape: nil
    )

    private func configuration() -> LoadConfiguration {
        LoadConfiguration(source: source)
    }

    // MARK: - The stride, which is the trap

    func testARealSpaceDragIsScaledByThePreviewStride() throws {
        // The preview is on the SAMPLED grid: stride 6 down, 4 across. Preview
        // pixels y 2...4, x 1...2 therefore cover source scan rows 12..<30 and
        // columns 4..<12.
        let crop = try XCTUnwrap(LoadConfiguration.scanCrop(
            from: DragRectangle(startX: 1, startY: 2, endX: 2, endY: 4),
            strideY: 6, strideX: 4, source: source
        ))
        XCTAssertEqual(crop.yOffset, 12)
        XCTAssertEqual(crop.height, 18, "rows 12..<30 — three preview pixels of 6")
        XCTAssertEqual(crop.xOffset, 4)
        XCTAssertEqual(crop.width, 8, "columns 4..<12 — two preview pixels of 4")
    }

    func testTheLastSampledPixelContributesItsWholeFootprint() throws {
        // A single preview pixel at stride 6 is six scan rows, not one. Taking
        // `end * stride` instead of `(end + 1) * stride` would drop five.
        let crop = try XCTUnwrap(LoadConfiguration.scanCrop(
            from: DragRectangle(startX: 0, startY: 3, endX: 0, endY: 3),
            strideY: 6, strideX: 6, source: source
        ))
        XCTAssertEqual(crop.yOffset, 18)
        XCTAssertEqual(crop.height, 6)
        XCTAssertEqual(crop.width, 6)
    }

    func testAStrideOfOneIsTheIdentity() throws {
        let crop = try XCTUnwrap(LoadConfiguration.scanCrop(
            from: DragRectangle(startX: 5, startY: 7, endX: 9, endY: 11),
            strideY: 1, strideX: 1, source: source
        ))
        XCTAssertEqual(crop.yOffset, 7)
        XCTAssertEqual(crop.height, 5)
        XCTAssertEqual(crop.xOffset, 5)
        XCTAssertEqual(crop.width, 5)
    }

    func testTheDiffractionPreviewIsNotScaled() throws {
        // meanDP/maxDP are full detector resolution, so this must be 1:1 — the
        // asymmetry with the real-space preview is deliberate and load-bearing.
        let crop = try XCTUnwrap(LoadConfiguration.detectorCrop(
            from: DragRectangle(startX: 10, startY: 20, endX: 29, endY: 39),
            source: source
        ))
        XCTAssertEqual(crop.xOffset, 10)
        XCTAssertEqual(crop.yOffset, 20)
        XCTAssertEqual(crop.width, 20)
        XCTAssertEqual(crop.height, 20)
    }

    // MARK: - Inverted drags

    func testDraggingUpAndLeftGivesTheSameCropAsDownAndRight() throws {
        let downRight = try XCTUnwrap(LoadConfiguration.detectorCrop(
            from: DragRectangle(startX: 10, startY: 20, endX: 29, endY: 39),
            source: source
        ))
        let upLeft = try XCTUnwrap(LoadConfiguration.detectorCrop(
            from: DragRectangle(startX: 29, startY: 39, endX: 10, endY: 20),
            source: source
        ))
        XCTAssertEqual(downRight, upLeft)

        // And the two mixed diagonals.
        let mixedA = try XCTUnwrap(LoadConfiguration.detectorCrop(
            from: DragRectangle(startX: 10, startY: 39, endX: 29, endY: 20),
            source: source
        ))
        let mixedB = try XCTUnwrap(LoadConfiguration.detectorCrop(
            from: DragRectangle(startX: 29, startY: 20, endX: 10, endY: 39),
            source: source
        ))
        XCTAssertEqual(downRight, mixedA)
        XCTAssertEqual(downRight, mixedB)
    }

    // MARK: - Out of bounds

    func testADragPastTheEdgeClampsToTheEdgeRatherThanFailing() throws {
        let crop = try XCTUnwrap(LoadConfiguration.detectorCrop(
            from: DragRectangle(startX: -50, startY: 60, endX: 500, endY: 500),
            source: source
        ))
        XCTAssertEqual(crop.xOffset, 0)
        XCTAssertEqual(crop.width, 96, "clamped to the detector width")
        XCTAssertEqual(crop.yOffset, 60)
        XCTAssertEqual(crop.height, 68, "rows 60..<128")
    }

    func testADragEntirelyOutsideTheImageStillYieldsAnEdgePixel() throws {
        // Dragging off the image is a gesture, not an error. What it must never
        // do is produce an empty or inverted crop.
        let crop = try XCTUnwrap(LoadConfiguration.detectorCrop(
            from: DragRectangle(startX: 500, startY: 500, endX: 600, endY: 600),
            source: source
        ))
        XCTAssertGreaterThan(crop.height, 0)
        XCTAssertGreaterThan(crop.width, 0)
        XCTAssertTrue(crop.fits(height: source.qy, width: source.qx))
    }

    func testANonFiniteDragIsRefusedRatherThanClamped() {
        XCTAssertNil(LoadConfiguration.detectorCrop(
            from: DragRectangle(startX: 0, startY: 0, endX: .nan, endY: 10),
            source: source
        ))
        XCTAssertNil(LoadConfiguration.detectorCrop(
            from: DragRectangle(startX: 0, startY: 0, endX: .infinity, endY: 10),
            source: source
        ))
    }

    func testAFiniteButAbsurdCoordinateIsRefusedRatherThanTrapping() {
        // `isFinite` does not cover this: 1e300 is perfectly finite, and
        // `Int(1e300.rounded(.down))` TRAPS rather than saturating. A gesture
        // layer that hands over a runaway coordinate should get a refusal, not
        // a crash. Controls confirmed the two guards are individually redundant
        // for NaN and infinity but that only the magnitude bound catches this.
        XCTAssertNil(LoadConfiguration.detectorCrop(
            from: DragRectangle(startX: 0, startY: 0, endX: 1e300, endY: 10),
            source: source
        ))
        XCTAssertNil(LoadConfiguration.scanCrop(
            from: DragRectangle(startX: -1e300, startY: 0, endX: 5, endY: 10),
            strideY: 3, strideX: 3, source: source
        ))
    }

    func testSelectingEverythingIsNotACropAtAll() {
        // Full extent must come back as nil, not as an AxisCrop covering
        // everything — otherwise `isFullExtent` is false, the view stops being
        // identical to the source, and "remove the specification to promote to
        // the full dataset" quietly stops working.
        XCTAssertNil(LoadConfiguration.detectorCrop(
            from: DragRectangle(startX: 0, startY: 0, endX: 95, endY: 127),
            source: source
        ))
        XCTAssertNil(LoadConfiguration.scanCrop(
            from: DragRectangle(startX: 0, startY: 0, endX: 39, endY: 59),
            strideY: 1, strideX: 1, source: source
        ))
    }

    // MARK: - Everything the configurator offers must be loadable

    func testEveryDragProducesASpecificationTheLoaderAccepts() throws {
        // The configurator must not be able to offer something `LoadView`
        // refuses. Swept over drags that are inverted, out of bounds, empty and
        // degenerate, at every offered bin factor.
        let drags = [
            DragRectangle(startX: 0, startY: 0, endX: 0, endY: 0),
            DragRectangle(startX: 95, startY: 127, endX: 0, endY: 0),
            DragRectangle(startX: -10, startY: -10, endX: 200, endY: 200),
            DragRectangle(startX: 30, startY: 40, endX: 31, endY: 41),
            DragRectangle(startX: 94, startY: 126, endX: 95, endY: 127),
        ]
        for drag in drags {
            for bin in [1, 2, 4, 8] {
                var configuration = self.configuration()
                configuration.detectorCrop = LoadConfiguration.detectorCrop(
                    from: drag, source: source
                )
                configuration.scanCrop = LoadConfiguration.scanCrop(
                    from: drag, strideY: 3, strideX: 2, source: source
                )
                configuration.detectorBin = bin
                let view = configuration.view
                if let crop = configuration.detectorCrop,
                   min(crop.height, crop.width) < bin {
                    // Legitimately unloadable: binning would leave no pixels.
                    XCTAssertNil(view, "bin \(bin) on \(crop.height)x\(crop.width)")
                } else {
                    XCTAssertNotNil(view, "bin \(bin), drag \(drag)")
                }
            }
        }
    }

    // MARK: - What it would cost

    func testTheCostIsFloat32BytesOfTheLoadedViewNotOfTheFile() throws {
        var configuration = self.configuration()
        // 60 x 40 x 128 x 96 float32 = 117,964,800 bytes, whatever uint16 says.
        XCTAssertEqual(configuration.fullExtentByteCount, 60 * 40 * 128 * 96 * 4)
        XCTAssertEqual(configuration.byteCount, configuration.fullExtentByteCount)
        XCTAssertEqual(configuration.fractionOfFullExtent, 1)

        configuration.detectorBin = 4
        // The detector divides exactly, so this is one sixteenth.
        XCTAssertEqual(configuration.byteCount, 60 * 40 * 32 * 24 * 4)
        XCTAssertEqual(try XCTUnwrap(configuration.fractionOfFullExtent), 1.0 / 16,
                       accuracy: 1e-12)
    }

    func testACropAndABinCompoundInTheCost() throws {
        var configuration = self.configuration()
        configuration.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 30, width: 40)
        configuration.detectorBin = 2
        // Half the scan rows, a quarter of the detector pixels.
        XCTAssertEqual(try XCTUnwrap(configuration.fractionOfFullExtent), 1.0 / 8,
                       accuracy: 1e-12)
    }

    func testTheEdgeRemainderIsReflectedInTheCost() throws {
        // A 127-row detector crop binned by 8 keeps 120 rows, not 127.
        var configuration = self.configuration()
        configuration.detectorCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 127, width: 96)
        configuration.detectorBin = 8
        XCTAssertEqual(configuration.byteCount, 60 * 40 * 15 * 12 * 4)
    }

    func testResidencyAnswersNotDecidedWhileTheThresholdIsUnmeasured() {
        // `measuredWorkingSetFraction` is deliberately nil, so the honest answer
        // is nil — not `false`, which would read as "it does not fit".
        XCTAssertNil(ResidencyAdmission.measuredWorkingSetFraction,
                     "if this becomes non-nil, this test and the UI copy both need revisiting")
        XCTAssertNil(configuration().fitsResident(
            workingSetSize: 8_000_000_000, maximumBufferLength: 4_000_000_000
        ))
    }
}
