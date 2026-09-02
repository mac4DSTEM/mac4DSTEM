import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// Backlog #17b. The display orientation is presentation-only, but it is
/// applied to the exported publication figure, so getting its *direction*
/// wrong would silently ship mirrored or back-to-front figures. These pin the
/// mapping in pixel indices, which is the one place it can be checked exactly.
@MainActor
final class ResultOrientationTests: XCTestCase {

    /// A 3×2 image whose every pixel is uniquely identifiable by its red
    /// channel, so a transform cannot pass by symmetry.
    ///
    ///     value = y * 10 + x        (x → columns, y → rows)
    ///     ┌────┬────┬────┐
    ///     │  0 │  1 │  2 │   row 0
    ///     ├────┼────┼────┤
    ///     │ 10 │ 11 │ 12 │   row 1
    ///     └────┴────┴────┘
    private let width = 3
    private let height = 2

    private var source: [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = UInt8(y * 10 + x)
                bytes[i + 3] = 255
            }
        }
        return bytes
    }

    private func grid(
        _ result: (bytes: [UInt8], width: Int, height: Int)
    ) -> [[UInt8]] {
        (0..<result.height).map { y in
            (0..<result.width).map { x in result.bytes[(y * result.width + x) * 4] }
        }
    }

    private func oriented(
        _ orientation: RealSpaceDisplayOrientation, mirrored: Bool = false
    ) -> (bytes: [UInt8], width: Int, height: Int) {
        AppState.orientedRGBA(
            source, width: width, height: height,
            orientation: orientation, mirrored: mirrored
        )
    }

    func testIdentityIsAByteForByteNoOp() {
        let result = oriented(.identity)
        XCTAssertEqual(result.width, width)
        XCTAssertEqual(result.height, height)
        XCTAssertEqual(result.bytes, source)
    }

    /// SwiftUI's `rotationEffect` turns clockwise for a positive angle, so the
    /// top-left pixel must end up top-RIGHT after a quarter turn.
    func testQuarterTurnRotatesClockwise() {
        let result = oriented(.quarterTurn)
        XCTAssertEqual(result.width, height, "a quarter turn swaps the dimensions")
        XCTAssertEqual(result.height, width)
        XCTAssertEqual(grid(result), [
            [10, 0],
            [11, 1],
            [12, 2],
        ])
    }

    func testHalfTurnReversesBothAxesAndKeepsTheShape() {
        let result = oriented(.halfTurn)
        XCTAssertEqual(result.width, width)
        XCTAssertEqual(result.height, height)
        XCTAssertEqual(grid(result), [
            [12, 11, 10],
            [2, 1, 0],
        ])
    }

    func testThreeQuarterTurnIsTheInverseOfAQuarterTurn() {
        let result = oriented(.threeQuarterTurn)
        XCTAssertEqual(result.width, height)
        XCTAssertEqual(result.height, width)
        XCTAssertEqual(grid(result), [
            [2, 12],
            [1, 11],
            [0, 10],
        ])

        // Composing the two must return the original exactly.
        let back = AppState.orientedRGBA(
            result.bytes, width: result.width, height: result.height,
            orientation: .quarterTurn, mirrored: false
        )
        XCTAssertEqual(back.width, width)
        XCTAssertEqual(back.height, height)
        XCTAssertEqual(back.bytes, source)
    }

    func testFourQuarterTurnsReturnTheOriginal() {
        var current = (bytes: source, width: width, height: height)
        for _ in 0..<4 {
            current = AppState.orientedRGBA(
                current.bytes, width: current.width, height: current.height,
                orientation: .quarterTurn, mirrored: false
            )
        }
        XCTAssertEqual(current.width, width)
        XCTAssertEqual(current.height, height)
        XCTAssertEqual(current.bytes, source)
    }

    /// The mirror is composed AFTER the rotation, in display space — the same
    /// order the viewer uses (`.rotationEffect` then `.scaleEffect(x: -1)`).
    func testMirrorIsAppliedInDisplaySpaceAfterTheRotation() {
        XCTAssertEqual(grid(oriented(.identity, mirrored: true)), [
            [2, 1, 0],
            [12, 11, 10],
        ])

        // Rotate first (columns become [10,0],[11,1],[12,2]), then flip the
        // displayed horizontal.
        XCTAssertEqual(grid(oriented(.quarterTurn, mirrored: true)), [
            [0, 10],
            [1, 11],
            [2, 12],
        ])
    }

    func testAlphaAndColourChannelsTravelWithTheirPixel() {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        // One fully-specified pixel at (2, 0) — the top-right corner.
        let i = (0 * width + 2) * 4
        bytes[i] = 200; bytes[i + 1] = 150; bytes[i + 2] = 100; bytes[i + 3] = 50

        let result = AppState.orientedRGBA(
            bytes, width: width, height: height,
            orientation: .quarterTurn, mirrored: false
        )
        // Clockwise: top-right becomes bottom-right of a 2×3 output.
        let j = (2 * result.width + 1) * 4
        XCTAssertEqual(Array(result.bytes[j..<(j + 4)]), [200, 150, 100, 50])
    }

    func testDegenerateInputIsReturnedUntouchedRatherThanCrashing() {
        for (w, h) in [(0, 0), (3, 0), (0, 2)] {
            let result = AppState.orientedRGBA(
                [], width: w, height: h, orientation: .quarterTurn, mirrored: true
            )
            XCTAssertEqual(result.width, w)
            XCTAssertEqual(result.height, h)
            XCTAssertTrue(result.bytes.isEmpty)
        }

        // A buffer shorter than its declared size must not be indexed past.
        let short = [UInt8](repeating: 7, count: 4)
        let result = AppState.orientedRGBA(
            short, width: width, height: height,
            orientation: .halfTurn, mirrored: false
        )
        XCTAssertEqual(result.bytes, short, "an inconsistent buffer is passed through")
    }

    func testSwapsAxesIsTrueForExactlyTheQuarterTurns() {
        XCTAssertFalse(RealSpaceDisplayOrientation.identity.swapsAxes)
        XCTAssertTrue(RealSpaceDisplayOrientation.quarterTurn.swapsAxes)
        XCTAssertFalse(RealSpaceDisplayOrientation.halfTurn.swapsAxes)
        XCTAssertTrue(RealSpaceDisplayOrientation.threeQuarterTurn.swapsAxes)

        for orientation in RealSpaceDisplayOrientation.allCases {
            XCTAssertEqual(orientation.degrees, Double(orientation.rawValue) * 90)
        }
    }

    /// The orientation must never leak onto a diffraction pattern: the app has
    /// a measured R–Q rotation, and a display rotation of the CBED would be
    /// indistinguishable from it.
    func testOrientationIsIgnoredForNonScanProducts() {
        let state = AppState()
        state.realSpaceDisplayOrientation = .quarterTurn
        state.realSpaceDisplayMirrored = true

        state.resultImage = FloatImage(width: 2, height: 2, pixels: [0, 1, 2, 3])
        XCTAssertEqual(state.displayedProduct?.domain, .scan, "test precondition")
        XCTAssertEqual(state.effectiveRealSpaceDisplayOrientation, .quarterTurn)
        XCTAssertTrue(state.effectiveRealSpaceDisplayMirrored)
        XCTAssertFalse(state.realSpaceDisplayIsDefault)

        state.resultImage = nil
        XCTAssertNotEqual(state.displayedProduct?.domain, .scan)
        XCTAssertEqual(
            state.effectiveRealSpaceDisplayOrientation, .identity,
            "a non-scan product must never be reoriented"
        )
        XCTAssertFalse(state.effectiveRealSpaceDisplayMirrored)
        XCTAssertTrue(state.realSpaceDisplayIsDefault)
    }

    /// Whatever the orientation, the export provenance must state it — an
    /// applied-but-unrecorded rotation is the one unacceptable outcome.
    func testProvenanceAlwaysStatesTheOrientation() {
        let state = AppState()
        state.resultImage = FloatImage(width: 2, height: 2, pixels: [0, 1, 2, 3])

        XCTAssertEqual(state.realSpaceDisplayProvenance["display_rotation_deg"], "0")
        XCTAssertEqual(state.realSpaceDisplayProvenance["display_flip"], "none")

        state.realSpaceDisplayOrientation = .threeQuarterTurn
        state.realSpaceDisplayMirrored = true
        XCTAssertEqual(state.realSpaceDisplayProvenance["display_rotation_deg"], "270")
        XCTAssertEqual(state.realSpaceDisplayProvenance["display_flip"], "horizontal")
    }
}
