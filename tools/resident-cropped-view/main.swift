//
//  Gate B fixture, adopted 2026-08-28: does the S18 resident fast path survive a
//  CROPPED + BINNED view, where `descriptor.rx` is NOT the source scan width and
//  a resident "scan row" is not a whole source scan row?
//
//  WHY IT IS A SEPARATE HARNESS, and this is the whole point of it:
//  `tools/virtual-detector-residency` builds every array at full extent, where
//  `descriptor.rx == source.rx`, so it cannot see this class at all. Mutate
//  `FourDArray`'s pattern slice from `descriptor.rx` to `view.source.rx` — the
//  exact defect this fixture was written to hunt — and all 27 of that harness's
//  assertions stay GREEN. This one fails at view (1, 0): got 3813.19, want
//  2923.57. Verified by breaking it, 2026-08-28, before it was trusted.
//
//  The answer it returned was NEGATIVE: the shipped code is correct, because
//  `descriptor` is the loaded VIEW's descriptor and that is exactly the stride
//  `makeResident` fills at. The fixture exists so that stays true.
//
//  Ground truth is computed here by explicit source-coordinate arithmetic —
//  NOT through LoadView's fromFullCube helpers — so a shared convention error
//  between the reader and the view cannot cancel (the L3 self-consistency trap
//  that tools/virtual-detector-residency documents in its own pattern loop).
//  The one place the helper is used, it is CROSS-CHECKED against that truth
//  rather than trusted.
//

import Foundation
import Metal

struct Aperture {
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}
func pass(_ message: String) { print("PASS: \(message)") }

func expectIdentical(_ actual: [Float], _ expected: [Float], _ what: String) {
    guard actual.count == expected.count else {
        fail("\(what): count \(actual.count), expected \(expected.count)")
    }
    for i in actual.indices where actual[i] != expected[i] {
        fail("\(what): differs at index \(i) — got \(actual[i]), expected \(expected[i])")
    }
    pass("\(what) — bit-identical over \(actual.count) values")
}

// MARK: - The source

let source = DatasetDescriptor(
    filePath: "synthetic-crop", datasetPath: "/synthetic",
    shape: [8, 6, 12, 10], dtypeDescription: "float32", chunkShape: nil
)
let sourcePatternFloats = source.qy * source.qx
var sourceCube = [Float](repeating: 0, count: source.ry * source.rx * sourcePatternFloats)
for scan in 0..<(source.ry * source.rx) {
    for y in 0..<source.qy {
        for x in 0..<source.qx {
            // Every (scan, y, x) distinct and non-cancelling, as in the shipped
            // fixture: a plain ramp lets several wrong offsets sum the same.
            let value = Float(scan &* 37 &+ y &* 13 &+ x &* 3) * 1.0009765625
                + Float((scan &+ y &* x) % 17) * 0.03125
            sourceCube[scan * sourcePatternFloats + y * source.qx + x] = value
        }
    }
}

// MARK: - The view: scan-cropped, detector-cropped AND binned

// scan crop 5x3 at (2,1)  ->  view rx = 3, source rx = 6
// detector crop 9x7 at (1,2), bin 2 -> read 8x6 (remainder 1 row, 1 column
//                                      dropped off the END), view detector 4x3
let specification = LoadSpecification(
    scanCrop: AxisCrop(yOffset: 2, xOffset: 1, height: 5, width: 3),
    detectorCrop: AxisCrop(yOffset: 1, xOffset: 2, height: 9, width: 7),
    detectorBin: 2
)
let view = try LoadView(source: source, specification: specification)
let d = view.descriptor
guard d.shape == [5, 3, 4, 3] else { fail("view shape is \(d.shape), expected [5, 3, 4, 3]") }
let bytesPerViewScanRow = d.rx * d.qy * d.qx * MemoryLayout<Float>.stride
print("view \(d.shape); bytes per VIEW scan row = \(bytesPerViewScanRow) "
      + "(source scan row would be \(source.rx * sourcePatternFloats * 4))")
guard bytesPerViewScanRow % 256 != 0 else {
    fail("the fixture must exercise a NON-256-aligned offset to test the alignment claim")
}

// MARK: - Independent ground truth

/// One view pattern, from first principles: pick the source frame, take the
/// crop rectangle trimmed to a whole number of bins, sum each bin box.
func expectedPattern(viewRY: Int, viewRX: Int) -> [Float] {
    let sourceY = 2 + viewRY
    let sourceX = 1 + viewRX
    let frame = (sourceY * source.rx + sourceX) * sourcePatternFloats
    var out = [Float](repeating: 0, count: d.qy * d.qx)
    for outY in 0..<d.qy {
        for outX in 0..<d.qx {
            var sum: Float = 0
            for dy in 0..<2 {
                for dx in 0..<2 {
                    let sy = 1 + outY * 2 + dy      // detectorCrop.yOffset + ...
                    let sx = 2 + outX * 2 + dx      // detectorCrop.xOffset + ...
                    sum += sourceCube[frame + sy * source.qx + sx]
                }
            }
            out[outY * d.qx + outX] = sum
        }
    }
    return out
}

var expectedViewCube = [Float](repeating: 0, count: d.ry * d.rx * d.qy * d.qx)
for ry in 0..<d.ry {
    for rx in 0..<d.rx {
        let p = expectedPattern(viewRY: ry, viewRX: rx)
        let base = (ry * d.rx + rx) * d.qy * d.qx
        for i in p.indices { expectedViewCube[base + i] = p[i] }
    }
}

// MARK: - A reader written independently of LoadView's fromFullCube helpers

actor IndependentReader: FourDDataSource {
    private(set) var patternReads = 0
    private(set) var tileReads = 0

    func discoverPrimaryDataset() throws -> DatasetDescriptor { source }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        patternReads += 1
        return expectedPattern(viewRY: ry, viewRX: rx)
    }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        var row = [Float]()
        for rx in 0..<view.descriptor.rx {
            row.append(contentsOf: expectedPattern(viewRY: ry, viewRX: rx))
        }
        return row
    }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        tileReads += 1
        var pixels = [Float]()
        for ry in yRange { pixels.append(contentsOf: try readScanRow(view, ry: ry)) }
        return FourDScanTile(
            yRange: yRange, scanWidth: view.descriptor.rx,
            detectorHeight: view.descriptor.qy, detectorWidth: view.descriptor.qx,
            pixels: pixels
        )
    }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

// Cross-check the independent truth against the shipped LoadView helper once.
// They must agree; if they do not, one of the two is wrong and every later
// comparison is meaningless.
do {
    for ry in 0..<d.ry {
        for rx in 0..<d.rx {
            let viaHelper = view.pattern(fromFullCube: sourceCube, ry: ry, rx: rx)
            expectIdentical(viaHelper, expectedPattern(viewRY: ry, viewRX: rx),
                            "LoadView.pattern(fromFullCube:) at (\(ry),\(rx))")
        }
    }
}

// MARK: - Resident vs streaming, on the cropped + binned view

let residentSource = IndependentReader()
let residentData = FourDArray(reader: residentSource, view: view)
await residentData.setResidencyRequest(.resident)
// Force a multi-tile fill: ry = 5, tile 2 -> 2+2+1, two of three at non-zero
// destination offsets.
let admitted = try await residentData.makeResident(maximumRows: 2)
guard admitted, await residentData.isResident else {
    fail("the cropped/binned view refused to go resident")
}
guard await residentData.residentByteCount == d.byteCountAsFloat32 else {
    fail("resident byte count \(await residentData.residentByteCount) != \(d.byteCountAsFloat32)")
}
pass("cropped + binned view went resident, filled in 3 tiles")

let streamSource = IndependentReader()
let streamData = FourDArray(reader: streamSource, view: view)

// 1. THE CLAIM UNDER TEST: pattern(ry:rx:) sliced out of the resident cube of a
//    view whose row stride is NOT the source scan width.
do {
    await residentData.clearCache()
    let before = await residentSource.patternReads
    for ry in 0..<d.ry {
        for rx in 0..<d.rx {
            let got = try await residentData.pattern(ry: ry, rx: rx)
            let want = expectedPattern(viewRY: ry, viewRX: rx)
            guard got.pixels == want else {
                fail("""
                     resident pattern at view (\(ry), \(rx)) is WRONG on a cropped \
                     view. got[0..3]=\(Array(got.pixels.prefix(3))) \
                     want[0..3]=\(Array(want.prefix(3)))
                     """)
            }
            guard got.qy == d.qy, got.qx == d.qx else {
                fail("resident pattern declares \(got.qy)x\(got.qx), expected \(d.qy)x\(d.qx)")
            }
        }
    }
    let after = await residentSource.patternReads
    guard after == before else {
        fail("browsing a resident CROPPED cube still read the file \(after - before) time(s)")
    }
    pass("all \(d.ry * d.rx) cropped+binned patterns match independent truth, zero reader reads")
}

// 2. TileGPUSource binds the cube's own buffer at a VIEW-row offset.
do {
    guard let cube = await residentData.resident(for: d) else {
        fail("resident(for:) refused the view's own descriptor")
    }
    var gpuSource = TileGPUSource(data: residentData, descriptor: d, cube: cube)
    for range in [0..<2, 2..<4, 4..<5] {
        let bound = try await gpuSource.binding(for: range, prefetching: nil, label: "crop")
        guard bound.buffer === cube.buffer else { fail("staged a copy for rows \(range)") }
        guard bound.offset == range.lowerBound * bytesPerViewScanRow else {
            fail("""
                 rows \(range) bound at byte offset \(bound.offset), expected \
                 \(range.lowerBound * bytesPerViewScanRow) — a VIEW row, not a source row
                 """)
        }
        guard bound.offset % 4 == 0 else { fail("offset \(bound.offset) is not 4-byte aligned") }
    }
    pass("TileGPUSource offsets are whole VIEW scan rows (\(bytesPerViewScanRow) B), 4-byte aligned")
}

// 3. The resident buffer holds exactly the expected view cube.
do {
    guard let cube = await residentData.resident(for: d) else { fail("cube vanished") }
    let floats = cube.byteCount / MemoryLayout<Float>.stride
    let base = cube.buffer.contents().bindMemory(to: Float.self, capacity: floats)
    let held = Array(UnsafeBufferPointer(start: base, count: floats))
    expectIdentical(held, expectedViewCube, "the resident buffer's bytes")
}

// 4. The four tiled reducers, resident vs streaming, on the cropped view.
let copiesBefore = await residentData.residentTileCopies
let rs = try await VirtualDetector.tiledDPStatistics(data: residentData, descriptor: d,
                                                     maximumTileRows: 2)
let ss = try await VirtualDetector.tiledDPStatistics(data: streamData, descriptor: d,
                                                     maximumTileRows: 2)
expectIdentical(rs.maxDP, ss.maxDP, "cropped DP statistics [max]")
expectIdentical(rs.meanDP, ss.meanDP, "cropped DP statistics [mean]")

let region = DetectorShape.rectangle(xMin: 0, xMax: 2, yMin: 1, yMax: 4)
let rd = try await VirtualDetector.tiledDiffraction(data: residentData, descriptor: d,
                                                    region: region, maximumTileRows: 2)
let sd = try await VirtualDetector.tiledDiffraction(data: streamData, descriptor: d,
                                                    region: region, maximumTileRows: 2)
expectIdentical(rd.pixels, sd.pixels, "cropped selected-area diffraction")

let ro = try await VirtualDetector.tiledMeasuredOrigins(data: residentData, descriptor: d,
                                                        probeRadius: 1.5, maximumTileRows: 2)
let so = try await VirtualDetector.tiledMeasuredOrigins(data: streamData, descriptor: d,
                                                        probeRadius: 1.5, maximumTileRows: 2)
expectIdentical(ro, so, "cropped measured origins")

let rc = try await VirtualDetector.tiledCenterOfMass(data: residentData, descriptor: d,
                                                     center: (1, 2), maximumTileRows: 2)
let sc = try await VirtualDetector.tiledCenterOfMass(data: streamData, descriptor: d,
                                                     center: (1, 2), maximumTileRows: 2)
expectIdentical(rc, sc, "cropped centre of mass")

let copiesAfter = await residentData.residentTileCopies
guard copiesAfter == copiesBefore else {
    fail("the cropped resident reducers copied \(copiesAfter - copiesBefore) tile(s)")
}
pass("cropped resident reducers made zero staging copies")

// 5. The whole-cube fast path on the cropped view.
for (name, shape) in [
    ("circle", DetectorShape.circle(centerX: 1.5, centerY: 2.0, radius: 1.75)),
    ("point at the origin", DetectorShape.point(x: 0, y: 0)),
    ("point on the edge", DetectorShape.point(x: d.qx - 1, y: d.qy - 1)),
] {
    let r = try await VirtualDetector.tiledImage(data: residentData, descriptor: d, shape: shape)
    let s = try await VirtualDetector.tiledImage(data: streamData, descriptor: d,
                                                 shape: shape, maximumTileRows: 1)
    expectIdentical(r.pixels, s.pixels, "cropped virtual image [\(name)]")
}

print("resident-cropped-view: all passed")
