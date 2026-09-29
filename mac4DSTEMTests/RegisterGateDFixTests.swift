//
//  RegisterGateDFixTests.swift
//  Session queue S7–S9 (2026-09-30): three items of the 2026-09-09 register
//  (`docs/archive/2026-09-09-review/triage-2026-09-29.md`), each diagnosed by
//  one agent with a byte copy of the code, refuted by another, then fixed.
//  Record: `docs/archive/v4/register-D019-D023-D025-gateD-2026-09-30.md`.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// D025: the real-space circle mask sat on the pixel CORNER (R 5 at (30, 30):
/// 88 pixels, centroid (30.5, 30.5)) while the drawn ring is centred on the
/// pixel — half a pixel off in both axes.
final class RegionCircleMaskCentreTests: XCTestCase {
    func testTheCircleMaskIsCentredOnTheSelectedPixel() {
        let mask = VirtualDetector.makeMask(
            shape: DetectorShape.realSpaceRegion(shape: .circle, radius: 5, scanX: 30, scanY: 30),
            qy: 64, qx: 64)
        var count = 0, sx = 0.0, sy = 0.0
        for y in 0..<64 { for x in 0..<64 where mask[y * 64 + x] != 0 { count += 1; sx += Double(x); sy += Double(y) } }
        XCTAssertEqual(count, 97, "a disc centred on a pixel holds an odd count")
        XCTAssertEqual(sx / Double(count), 30, accuracy: 1e-9)
        XCTAssertEqual(sy / Double(count), 30, accuracy: 1e-9)
        for y in 0..<64 { for x in 1..<60 {
            XCTAssertEqual(mask[y * 64 + x], mask[y * 64 + (60 - x)], "mirror-symmetric about x = 30")
            XCTAssertEqual(mask[x * 64 + y], mask[(60 - x) * 64 + y], "mirror-symmetric about y = 30")
        } }
    }
}

/// D023: an empty (or central-beam-only) position added the 3.4e38 sentinel
/// to the median nearest-peak radius, so from half the scan empty the median
/// exploded and no basis was found.
final class StrainEmptyPositionMedianTests: XCTestCase {
    private func lattice(origin: Float = 32) -> [BraggPeak] {
        var peaks = [BraggPeak(x: origin, y: origin, intensity: 10)]
        for h in -2...2 { for k in -2...2 where !(h == 0 && k == 0) {
            peaks.append(BraggPeak(x: origin + Float(h) * 20 + Float(k) * 3,
                                   y: origin + Float(k) * 18, intensity: 1))
        } }
        return peaks
    }

    private func basis(empty: Int, of total: Int, centralOnly: Bool) -> (g1: (x: Float, y: Float), g2: (x: Float, y: Float))? {
        let filler: [BraggPeak] = centralOnly ? [BraggPeak(x: 32, y: 32, intensity: 10)] : []
        let peaks = (0..<total).map { $0 < empty ? filler : lattice() }
        return StrainMapping.chooseLatticeVectors(
            bragg: BraggVectors(scanWidth: 20, scanHeight: total / 20, peaks: peaks), x0: 32, y0: 32)
    }

    func testHalfTheScanEmptyStillFindsTheBasis() throws {
        for centralOnly in [false, true] { for empty in [200, 240] {
            let found = try XCTUnwrap(basis(empty: empty, of: 400, centralOnly: centralOnly),
                                      "centralOnly \(centralOnly), \(empty)/400 empty: must not hide the lattice")
            let lengths = [found.g1, found.g2].map { hypot($0.x, $0.y) }.sorted()
            XCTAssertEqual(lengths[0], hypot(3, 18), accuracy: 0.5)
            XCTAssertEqual(lengths[1], 20, accuracy: 0.5)
        } }
    }

    func testAMinorityOfEmptyPositionsWasAndStaysFine() {
        XCTAssertNotNil(basis(empty: 199, of: 400, centralOnly: false), "control: green before and after the fix")
    }
}

/// D019: one NaN or ±Inf detector pixel turned the whole correlation map to
/// zero and the pattern lost every peak, reading like vacuum.
final class DiskDetectionNonFinitePixelTests: XCTestCase {
    private let size = 64

    private func pattern() -> [Float] {
        var pixels = [Float](repeating: 1, count: size * size)
        for (cx, cy, amp) in [(32, 32, 1000), (44, 32, 200), (32, 20, 150), (20, 44, 100)] as [(Int, Int, Float)] {
            for y in 0..<size { for x in 0..<size {
                let d = hypot(Float(x - cx), Float(y - cy))
                if d <= 3 { pixels[y * size + x] += amp }
            } }
        }
        return pixels
    }

    private func detect(_ pixels: [Float]) throws -> [BraggPeak] {
        var probe = [Float](repeating: 0, count: size * size)
        for y in 0..<size { for x in 0..<size where hypot(Float(x - 32), Float(y - 32)) <= 3 { probe[y * size + x] = 1 } }
        let kernel = try XCTUnwrap(ProbeKernel.flat(
            pattern: DiffractionPattern(qy: size, qx: size, pixels: probe), originX: 32, originY: 32, radius: 4))
        let detector = try XCTUnwrap(DiskDetector(kernel: kernel))
        var params = DiskDetectionParams()
        params.minPeakSpacing = 4
        params.edgeBoundary = 2
        params.subpixel = .poly
        return pixels.withUnsafeBufferPointer { detector.detect(pattern: $0.baseAddress!, params: params) }
    }

    /// Far from the disks and inside one (the refuter's case: a zero fill
    /// inside a disk biased the subpixel position).
    func testOneNonFinitePixelChangesNoPeak() throws {
        let clean = try detect(pattern())
        XCTAssertGreaterThanOrEqual(clean.count, 4, "the fixture must find its disks at all")
        for index in [5 * size + 5, 32 * size + 43] {
            for poison in [Float.nan, .infinity, -.infinity] {
                var pixels = pattern()
                pixels[index] = poison
                let poisoned = try detect(pixels)
                XCTAssertEqual(poisoned.count, clean.count, "\(poison) at \(index): every peak must survive one bad pixel")
                for (a, b) in zip(clean.sorted { $0.intensity > $1.intensity }, poisoned.sorted { $0.intensity > $1.intensity }) {
                    XCTAssertEqual(a.x, b.x, accuracy: 0.01)
                    XCTAssertEqual(a.y, b.y, accuracy: 0.01)
                }
            }
        }
    }

    /// The fill is the neighbour median (0 with none), counted — including at
    /// index 0, which the refuter found poisoned every learned-detector input.
    func testTheFillIsTheNeighbourMedianAndIsCounted() {
        var image: [Float] = [.nan, 2, 9,
                              4, 6, 1,
                              7, 8, .infinity]
        let count = image.withUnsafeMutableBufferPointer {
            DiskDetector.fillNonFinite($0.baseAddress!, width: 3, height: 3, rowStride: 3)
        }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(image[0], 4, "median of 2, 4, 6")
        XCTAssertEqual(image[8], 6, "median of 6, 1, 8")
    }
}
