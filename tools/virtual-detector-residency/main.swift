//
//  virtual-detector-residency
//  Stage L2 of docs/load-pipeline-plan.md: a resident cube must be
//  BIT-IDENTICAL to the tiled path, not merely close.
//
//  Why exact `==` and not a tolerance (invariant I2). `virtualMaskSum` and
//  `virtualAperture` run one thread per SCAN position, summing over the
//  detector in a fixed order, from a mask built out of qy/qx only. Tiles
//  partition the SCAN axis, so a tile boundary never splits a per-output-pixel
//  reduction and every tile sees the identical mask. Equality is therefore
//  derived, not hoped for.
//
//  READ THIS BEFORE COPYING THE ASSERTION ELSEWHERE. `tiledDPStatistics`
//  (weighted mean) and `tiledDiffraction` (running sum) DO reduce across tiles
//  and are float-order dependent. They are still compared with `==` here — but
//  only because a resident array walks the SAME tile ranges as a streaming one,
//  so the same partials combine in the same order. If a future change makes a
//  resident array tile differently from a streaming one, those two comparisons
//  become tolerance comparisons and this comment is the reason. Do NOT widen a
//  tolerance to make one of them pass — that is invariant I7.
//
//  v2 S18 changed HOW those tiles reach the GPU, and deliberately not WHICH
//  tiles they are: the four reducers now bind the resident buffer at the tile's
//  byte offset instead of copying the tile out to `[Float]` and back into a
//  fresh MTLBuffer. The equality above is therefore the same claim as before —
//  and `residentTileCopies` below is the separate claim that the copy is gone,
//  which no comparison of outputs could make on its own.
//

import Foundation
import Metal

// `Aperture` now lives in Core/Analysis/VirtualDetector.swift (2026-09-02);
// the local mirror this file carried is gone.

/// Counts reads so the harness can prove a resident cube stops touching the
/// reader — the property that makes residency worth having.
actor CountingDataSource: FourDDataSource {
    let descriptor: DatasetDescriptor
    let cube: [Float]
    private(set) var tileReads = 0
    private(set) var rowsRead = 0
    private(set) var patternReads = 0

    init(descriptor: DatasetDescriptor, cube: [Float]) {
        self.descriptor = descriptor
        self.cube = cube
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { descriptor }

    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        patternReads += 1
        return view.pattern(fromFullCube: cube, ry: ry, rx: rx)
    }

    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        view.scanRow(fromFullCube: cube, ry: ry)
    }

    func readScanTile(_ view: LoadView,
                      yRange: Range<Int>) throws -> FourDScanTile {
        tileReads += 1
        rowsRead += yRange.count
        return view.scanTile(fromFullCube: cube, yRange: yRange)
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func pass(_ message: String) {
    print("PASS: \(message)")
}

/// Exact equality. No tolerance parameter on purpose — see the file header.
func expectIdentical(_ actual: [Float], _ expected: [Float], _ what: String) {
    guard actual.count == expected.count else {
        fail("\(what): count \(actual.count), expected \(expected.count)")
    }
    for i in actual.indices where actual[i] != expected[i] {
        fail("\(what): differs at index \(i) — resident \(actual[i]), tiled \(expected[i])")
    }
    pass("\(what) — bit-identical over \(actual.count) values")
}

// MARK: - Fixture

// Deliberately awkward numbers: a plain ramp would make several wrong tile
// offsets produce the same sums. These vary per scan position AND per detector
// pixel, with magnitudes that do not cancel.
let d = DatasetDescriptor(
    filePath: "synthetic", datasetPath: "/synthetic",
    shape: [7, 5, 9, 11], dtypeDescription: "float32", chunkShape: nil
)
let detectorPixels = d.qy * d.qx
let scanCount = d.ry * d.rx
var cube = [Float](repeating: 0, count: scanCount * detectorPixels)
for scan in 0..<scanCount {
    for y in 0..<d.qy {
        for x in 0..<d.qx {
            let value = Float(scan &* 31 &+ y &* 7 &+ x) * 1.0009765625
                + Float((scan &+ y &* x) % 13) * 0.03125
            cube[scan * detectorPixels + y * d.qx + x] = value
        }
    }
}

// MARK: - Admission rule (no GPU needed)

do {
    let eightGB: UInt64 = 8 << 30
    guard ResidencyAdmission.admits(d, workingSetSize: eightGB, fraction: 0.5) else {
        fail("admission rejected a cube that trivially fits")
    }
    let huge = DatasetDescriptor(
        filePath: "synthetic", datasetPath: "/synthetic",
        // 4 GB as float32.
        shape: [1024, 1024, 32, 32], dtypeDescription: "uint16", chunkShape: nil
    )
    guard huge.byteCountAsFloat32 == 4 << 30 else {
        fail("byteCountAsFloat32 must size a uint16 file by its FLOAT32 working size")
    }
    guard ResidencyAdmission.admits(huge, workingSetSize: eightGB, fraction: 0.6) else {
        fail("4 GB cube should fit 60% of an 8 GB working set")
    }
    guard !ResidencyAdmission.admits(huge, workingSetSize: eightGB, fraction: 0.4) else {
        fail("4 GB cube must NOT fit 40% of an 8 GB working set")
    }
    // The threshold stays unmeasured, and since `.automatic` was dropped
    // (v2 S3) nothing resolves against it — but `admits` above is the contract
    // a returning `.automatic` re-enters, so the constant staying nil is still
    // the recorded fact this harness pins.
    guard ResidencyAdmission.measuredWorkingSetFraction == nil else {
        fail("""
             measuredWorkingSetFraction is set — if the residency sweep has now \
             been run and `.automatic` is returning (docs/v2-release.md §3), \
             update this harness to assert the measured value and its boundary \
             instead of asserting that it is unmeasured.
             """)
    }
    guard ResidencyAdmission.shouldAdmit(
        .resident, descriptor: d, maximumBufferLength: .max
    ) else { fail("an explicit .resident request must be honoured without a threshold") }
    guard !ResidencyAdmission.shouldAdmit(
        .streamed, descriptor: d, maximumBufferLength: .max
    ) else { fail(".streamed must never admit") }
    // .resident bypasses the THRESHOLD but not the device's buffer limit. It
    // used to bypass both, on the grounds that an explicit caller "takes
    // responsibility" — for a limit the repo never consulted anywhere.
    guard !ResidencyAdmission.shouldAdmit(
        .resident, descriptor: d, maximumBufferLength: d.byteCountAsFloat32 - 1
    ) else { fail(".resident admitted a cube larger than the device's maxBufferLength") }
    guard ResidencyAdmission.shouldAdmit(
        .resident, descriptor: d, maximumBufferLength: d.byteCountAsFloat32
    ) else { fail(".resident refused a cube exactly at maxBufferLength") }
    pass("admission rule — working-set fraction, float32 sizing, buffer-length clamp")
}

// MARK: - Preload

let residentSource = CountingDataSource(descriptor: d, cube: cube)
let residentData = FourDArray(reader: residentSource, descriptor: d)
await residentData.setResidencyRequest(.resident)

// FORCE A MULTI-TILE FILL. `ry` is 7 and the tile is 2, so the fill runs
// 2+2+2+1 — four tiles, the last one short, and three of them writing at a
// NON-ZERO destination offset.
//
// This is the single most important line in the file. Without `maximumRows`
// the default budget (a working-set eighth, ~683 MB) swallowed this 14 KB
// fixture whole, so every preload in the entire suite was ONE tile, `filled`
// was always 0, and the destination offset in `makeResident` was dead code:
// rewriting it to `base + 0 * floatsPerScanRow` left all 22 assertions below
// green, plus the whole unit suite. On a real multi-gigabyte cube that fill is
// a dozen tiles and the arithmetic decides whether every later analysis reads
// the right bytes. Adversarial review, 2026-08-17.
let fillTileRows = 2
nonisolated(unsafe) var preloadFractions: [Double] = []
let admitted = try await residentData.makeResident(maximumRows: fillTileRows) { fraction in
    preloadFractions.append(fraction)
}
let expectedTiles = (d.ry + fillTileRows - 1) / fillTileRows
guard preloadFractions.count == expectedTiles else {
    fail("""
         the preload filled in \(preloadFractions.count) tiles, expected \
         \(expectedTiles). A single-tile fill makes every progress assertion \
         below vacuous and leaves the destination offset untested.
         """)
}
guard admitted, await residentData.isResident else {
    fail("an explicit .resident request did not produce a resident cube")
}
guard await residentData.residentByteCount == d.byteCountAsFloat32 else {
    fail("resident byte count disagrees with the descriptor's float32 size")
}
guard !preloadFractions.isEmpty else { fail("the preload reported no progress at all") }
guard preloadFractions == preloadFractions.sorted() else {
    fail("preload progress went backwards: \(preloadFractions)")
}
guard preloadFractions.last == 1.0 else {
    fail("preload progress ended at \(preloadFractions.last!), not exactly 1.0")
}
guard preloadFractions.filter({ $0 == 1.0 }).count == 1 else {
    fail("preload reported completion more than once")
}
pass("preload progress — measured, monotonic, ends at exactly 1.0")

let readsAfterPreload = await residentSource.tileReads
guard await residentSource.rowsRead == d.ry else {
    fail("the preload read \(await residentSource.rowsRead) scan rows, expected \(d.ry)")
}

// The streaming comparand: same data, same reader, never made resident.
let streamSource = CountingDataSource(descriptor: d, cube: cube)
let streamData = FourDArray(reader: streamSource, descriptor: d)
guard await !streamData.isResident else { fail("control array is unexpectedly resident") }

// MARK: - Virtual images, every geometry the plan names

let shapes: [(String, DetectorShape)] = [
    ("circle", .circle(centerX: 5.5, centerY: 4.5, radius: 3.25)),
    ("annulus", .annulus(centerX: 5.5, centerY: 4.5, inner: 1.5, outer: 3.75)),
    ("off-centre annulus", .annulus(centerX: 2.25, centerY: 6.75, inner: 0.75, outer: 2.5)),
    ("rectangle", .rectangle(xMin: 2, xMax: 8, yMin: 1, yMax: 6)),
    ("point", .point(x: 4, y: 3)),
    // Edge pixels: the mask predicates and the flat index are most likely to
    // disagree at a boundary, and a resident dispatch indexes the cube
    // differently from a tiled one.
    ("point on the detector edge", .point(x: d.qx - 1, y: d.qy - 1)),
    ("point at the origin", .point(x: 0, y: 0)),
]

for (name, shape) in shapes {
    let resident = try await VirtualDetector.tiledImage(
        data: residentData, descriptor: d, shape: shape
    )
    let tiled = try await VirtualDetector.tiledImage(
        data: streamData, descriptor: d, shape: shape, maximumTileRows: 1
    )
    expectIdentical(resident.pixels, tiled.pixels, "virtual image [\(name)]")
}

// MARK: - Proof that the fast path actually ran
//
// WITHOUT THIS THE HARNESS IS WORTHLESS, and that is not a guess — it was
// verified. Making FourDArray.resident() return nil (residency silently never
// engaging, the exact failure docs/load-pipeline-plan.md L2.3 warns about) left
// every comparison above GREEN, because a resident array still serves its TILES
// out of the buffer, so the tiled fallback produced identical numbers without
// hitting the reader. Equality and read counts both prove residency is holding
// data; only the dispatch COUNT proves the single-dispatch branch was taken.
//
// The shape of the evidence: the resident branch reports progress exactly once,
// at 1.0. The tiled path reports once per tile, and `maximumTileRows: 1` forces
// one tile per scan row. So asking the resident array for one-row tiles and
// getting a single callback is only possible if the fast path pre-empted them.
do {
    nonisolated(unsafe) var residentTicks: [Double] = []
    _ = try await VirtualDetector.tiledImage(
        data: residentData, descriptor: d, shape: shapes[0].1,
        maximumTileRows: 1, progress: { residentTicks.append($0) }
    )
    guard residentTicks == [1.0] else {
        fail("""
             the resident fast path did not run: progress reported \
             \(residentTicks.count) times (\(residentTicks)), expected exactly one \
             tick at 1.0. A resident array asked for one-row tiles still dispatched \
             per tile, so this stage is holding the cube in memory and not using it.
             """)
    }

    nonisolated(unsafe) var streamTicks: [Double] = []
    _ = try await VirtualDetector.tiledImage(
        data: streamData, descriptor: d, shape: shapes[0].1,
        maximumTileRows: 1, progress: { streamTicks.append($0) }
    )
    guard streamTicks.count == d.ry else {
        fail("""
             the streaming control did not tile as forced: \(streamTicks.count) \
             progress ticks for \(d.ry) one-row tiles. If this drifts, the comparison \
             above stops being resident-vs-tiled and becomes resident-vs-resident.
             """)
    }
    pass("fast path engaged — 1 dispatch resident vs \(d.ry) tiles streaming")

    nonisolated(unsafe) var apertureTicks: [Double] = []
    _ = try await VirtualDetector.tiledRun(
        data: residentData, descriptor: d,
        aperture: Aperture(centerX: 5.5, centerY: 4.5, inner: 1.5, outer: 3.75),
        maximumTileRows: 1, progress: { apertureTicks.append($0) }
    )
    guard apertureTicks == [1.0] else {
        fail("the analytic aperture path did not take the resident branch: \(apertureTicks)")
    }
    pass("fast path engaged — analytic aperture")
}

for (name, aperture) in [
    ("centred", Aperture(centerX: 5.5, centerY: 4.5, inner: 1.5, outer: 3.75)),
    ("off-centre", Aperture(centerX: 2.25, centerY: 6.75, inner: 0, outer: 2.5)),
] {
    let resident = try await VirtualDetector.tiledRun(
        data: residentData, descriptor: d, aperture: aperture
    )
    let tiled = try await VirtualDetector.tiledRun(
        data: streamData, descriptor: d, aperture: aperture, maximumTileRows: 1
    )
    expectIdentical(resident.pixels, tiled.pixels, "analytic aperture [\(name)]")
}

// MARK: - The reader must be untouched once the cube is resident

guard await residentSource.tileReads == readsAfterPreload else {
    fail("""
         the resident path read the file again: \(await residentSource.tileReads) tile \
         reads against \(readsAfterPreload) after the preload. Residency that still \
         hits the disk is the regression this stage exists to prevent.
         """)
}
pass("resident dispatches touched the reader zero times after the preload")

// MARK: - Tiles served from the resident buffer

// These paths still tile (their reductions combine across tiles), but a
// resident array never leaves memory to get them. Same tiling, same order, so
// still exactly equal — and with `maximumTileRows: 2` against ry = 7 the ranges
// are 0..<2, 2..<4, 4..<6, 6..<7, so THREE of the four dispatches bind at a
// non-zero byte offset. That is what catches an offset error in
// `TileGPUSource.binding(for:prefetching:label:)`; before v2 S18 the same
// ranges caught one in `FourDArray.tile(yRange:from:)`.

// MARK: - The instrument itself, before anything trusts its zero (v2 S18, Gate B)

// `residentTileCopies` reads 0 before and 0 after in a healthy run, so
// `after == before` holds whether the counter WORKS or is dead code. Gate B
// proved that by combination rather than argument: deleting the sole
// `residentTileCopies += 1` is green on its own, and it also makes the author's
// own negative control (#2, forcing the reducers back through `scanTile`) stop
// failing. An instrument with no positive control is not evidence.
do {
    let before = await residentData.residentTileCopies
    _ = try await residentData.scanTile(yRange: 0..<1)
    let after = await residentData.residentTileCopies
    guard after == before + 1 else {
        fail("""
             residentTileCopies did not move when a tile WAS copied out of the \
             resident cube (\(before) -> \(after)). The counter is dead, and \
             every "zero staging copies" claim below it is vacuous.
             """)
    }
    pass("residentTileCopies is alive — one copied tile moves it by exactly 1")
}

// MARK: - TileGPUSource returns the cube's OWN buffer, not a copy of it

// The counter above cannot see this. It lives in `FourDArray.tile(yRange:from:)`
// — the route `TileGPUSource` deliberately no longer takes — so reinstating a
// staging copy INSIDE `TileGPUSource.binding` leaves it reading 0/0 while every
// value stays bit-identical (they are the same bytes). Gate B demonstrated
// exactly that, three different ways (C02, C10, C20), all green here and green
// across all 37 scientific harnesses.
//
// Assert the contract directly instead of inferring it from a counter: while
// resident, the binding IS the cube's buffer, at the tile's byte offset. A copy
// of any spelling fails `===`.
do {
    guard let cube = await residentData.resident(for: d) else {
        fail("the resident cube vanished before the binding contract check")
    }
    var source = TileGPUSource(data: residentData, descriptor: d, cube: cube)
    let bytesPerScanRow = d.rx * d.qy * d.qx * MemoryLayout<Float>.stride
    for range in [0..<2, 2..<4, 4..<6, 6..<7] {
        let bound = try await source.binding(
            for: range, prefetching: nil, label: "binding contract"
        )
        guard bound.buffer === cube.buffer else {
            fail("""
                 TileGPUSource staged a COPY for rows \(range) instead of \
                 binding the resident cube — this is the ~0.375x working-set \
                 waste v2 S18 removed, silently reintroduced.
                 """)
        }
        guard bound.offset == range.lowerBound * bytesPerScanRow else {
            fail("""
                 binding for rows \(range) is at byte offset \(bound.offset), \
                 expected \(range.lowerBound * bytesPerScanRow)
                 """)
        }
    }
    pass("TileGPUSource binds the cube's own buffer at the right offset, no staging")
}

// Re-baselined AFTER the positive control's deliberate copy.
let copiesBeforeReducers = await residentData.residentTileCopies
let residentStatistics = try await VirtualDetector.tiledDPStatistics(
    data: residentData, descriptor: d, maximumTileRows: 2
)
let streamStatistics = try await VirtualDetector.tiledDPStatistics(
    data: streamData, descriptor: d, maximumTileRows: 2
)
expectIdentical(residentStatistics.maxDP, streamStatistics.maxDP, "DP statistics [max]")
expectIdentical(residentStatistics.meanDP, streamStatistics.meanDP, "DP statistics [mean]")

let region = DetectorShape.rectangle(xMin: 1, xMax: 4, yMin: 0, yMax: 3)
let residentDiffraction = try await VirtualDetector.tiledDiffraction(
    data: residentData, descriptor: d, region: region, maximumTileRows: 2
)
let streamDiffraction = try await VirtualDetector.tiledDiffraction(
    data: streamData, descriptor: d, region: region, maximumTileRows: 2
)
expectIdentical(residentDiffraction.pixels, streamDiffraction.pixels,
                "selected-area diffraction")

let residentOrigins = try await VirtualDetector.tiledMeasuredOrigins(
    data: residentData, descriptor: d, probeRadius: 2.0, maximumTileRows: 2
)
let streamOrigins = try await VirtualDetector.tiledMeasuredOrigins(
    data: streamData, descriptor: d, probeRadius: 2.0, maximumTileRows: 2
)
expectIdentical(residentOrigins, streamOrigins, "measured origins")

let residentCoM = try await VirtualDetector.tiledCenterOfMass(
    data: residentData, descriptor: d, center: (5, 4), maximumTileRows: 2
)
let streamCoM = try await VirtualDetector.tiledCenterOfMass(
    data: streamData, descriptor: d, center: (5, 4), maximumTileRows: 2
)
expectIdentical(residentCoM, streamCoM, "centre of mass")

// MARK: - The staging copy is GONE, not merely still correct (v2 S18)

// Equality above proves the numbers did not change. It cannot distinguish
// "bound the cube in place" from "copied every tile out and back again" — a
// silently reintroduced staging copy passes every comparison in this file.
// This is the assertion that fails when the copy comes back.
let copiesAfterReducers = await residentData.residentTileCopies
guard copiesAfterReducers == copiesBeforeReducers else {
    fail("""
         the four tiled reducers copied \(copiesAfterReducers - copiesBeforeReducers) \
         tile(s) out of the resident cube. They must bind the cube's buffer at \
         each tile's byte offset instead — that copy is ~0.375 x working set of \
         pure staging waste and v2 S18 removed it.
         """)
}
pass("resident reducers made zero staging copies (\(copiesBeforeReducers) before, \(copiesAfterReducers) after)")

// MARK: - Browsing patterns comes out of the resident cube too (v2 S18)

// `pattern(ry:rx:)` used to go to the reader unconditionally, so browsing
// patterns stayed disk-bound even with the whole cube already in memory. Two
// claims here, and they are different:
//   1. the bytes are the same ones the reader would have returned, and
//   2. the reader is not consulted to get them.
//
// **Only claim 2 is actually tested here, and the comment that used to sit in
// this spot was wrong twice over (Gate B, 2026-08-27).** It said "nothing else
// in this repo asserts that a reader's two entry points agree pattern for
// pattern". Two harnesses already do, against independent ground truth:
// `tools/calibration-test:35` ("multi-row tile differs from row reads") and
// `tools/vendor-reader-test:18-47`, which compares `readPattern` against
// `readScanTile` for EMPAD and MIB directly.
//
// Worse, this loop cannot assert claim 1 at all. `CountingDataSource` answers
// `readScanTile` through `LoadView.scanTile(fromFullCube:)`, which concatenates
// `scanRow(fromFullCube:)` out of the same array and the same index arithmetic
// `pattern(fromFullCube:)` uses — so both sides of the comparison come from one
// family, and a shared convention error would cancel. That is precisely the L3
// self-consistency trap this repo has been bitten by before, reproduced inside
// the check written to guard against it.
//
// What this loop DOES prove, and it is worth keeping: the resident slice's
// offset arithmetic and its declared geometry match the streaming path on a
// 9x11 detector, and the reader is untouched. Claim 1 against a real reader is
// covered by the two harnesses named above, not by this one.
do {
    await residentData.clearCache()
    let readsBeforePatterns = await residentSource.patternReads
    for ry in 0..<d.ry {
        for rx in 0..<d.rx {
            let resident = try await residentData.pattern(ry: ry, rx: rx)
            let streamed = try await streamData.pattern(ry: ry, rx: rx)
            guard resident.pixels == streamed.pixels else {
                fail("pattern at (ry \(ry), rx \(rx)) differs between resident and streaming")
            }
            // The DECLARED geometry, not just the pixels. Gate B (2026-08-27)
            // showed this loop was blind without it: returning
            // `DiffractionPattern(qy: descriptor.qx, qx: descriptor.qy, …)` —
            // correct pixels, transposed geometry — was GREEN here AND across
            // all 37 scientific harnesses. `normalized()` builds
            // `FloatImage(width: qx, height: qy)`, so the CBED viewer, the PNG
            // export and any probe measured off it would inherit a transposed
            // shape with entirely plausible intensities. Nothing else in
            // mac4DSTEMTests/ or tools/ asserts any pattern's qy or qx. The
            // fixture's 9x11 detector is what makes this discriminating; at a
            // square detector it would prove nothing.
            guard resident.qy == streamed.qy, resident.qx == streamed.qx else {
                fail("""
                     pattern at (ry \(ry), rx \(rx)) declares \
                     \(resident.qy)x\(resident.qx), streaming says \
                     \(streamed.qy)x\(streamed.qx) — the pixels match but the \
                     geometry does not
                     """)
            }
        }
    }
    let readsAfterPatterns = await residentSource.patternReads
    guard readsAfterPatterns == readsBeforePatterns else {
        fail("""
             browsing \(d.ry * d.rx) patterns on a RESIDENT cube read the file \
             \(readsAfterPatterns - readsBeforePatterns) time(s). A resident cube \
             already holds every pattern.
             """)
    }
    pass("all \(d.ry * d.rx) patterns served from the resident cube, zero reader reads")
}

// MARK: - Degrade to streaming (invariant I6)

do {
    let source = CountingDataSource(descriptor: d, cube: cube)
    let data = FourDArray(reader: source, descriptor: d)
    await data.setResidencyRequest(.streamed)
    let admitted = try await data.makeResident()
    guard !admitted, await !data.isResident else {
        fail(".streamed produced a resident cube")
    }
    let streamed = try await VirtualDetector.tiledImage(
        data: data, descriptor: d, shape: shapes[0].1, maximumTileRows: 1
    )
    let reference = try await VirtualDetector.tiledImage(
        data: streamData, descriptor: d, shape: shapes[0].1, maximumTileRows: 1
    )
    expectIdentical(streamed.pixels, reference.pixels, "streaming after a refused preload")
}

// MARK: - Release returns to streaming, with identical numbers

do {
    let source = CountingDataSource(descriptor: d, cube: cube)
    let data = FourDArray(reader: source, descriptor: d)
    await data.setResidencyRequest(.resident)
    _ = try await data.makeResident()
    guard await data.isResident else { fail("could not make a cube resident to release it") }
    let before = try await VirtualDetector.tiledImage(
        data: data, descriptor: d, shape: shapes[1].1
    )
    await data.releaseResident()
    guard await !data.isResident, await data.residentByteCount == 0 else {
        fail("releaseResident left the cube resident")
    }
    let after = try await VirtualDetector.tiledImage(
        data: data, descriptor: d, shape: shapes[1].1, maximumTileRows: 1
    )
    expectIdentical(after.pixels, before.pixels, "release, then stream")
}

// MARK: - A cancelled preload must not publish a half-filled buffer

do {
    let source = CountingDataSource(descriptor: d, cube: cube)
    let data = FourDArray(reader: source, descriptor: d)
    await data.setResidencyRequest(.resident)
    let token = AnalysisCancellationToken()
    token.cancel()
    do {
        _ = try await data.makeResident(cancellation: token)
        fail("a cancelled preload reported success")
    } catch is CancellationError {
        guard await !data.isResident else {
            fail("a cancelled preload published a partially filled cube")
        }
        // And the array still works, streaming.
        let streamed = try await VirtualDetector.tiledImage(
            data: data, descriptor: d, shape: shapes[0].1, maximumTileRows: 1
        )
        let reference = try await VirtualDetector.tiledImage(
            data: streamData, descriptor: d, shape: shapes[0].1, maximumTileRows: 1
        )
        expectIdentical(streamed.pixels, reference.pixels, "streaming after a cancelled preload")
    }
}

// MARK: - The staleness guard

do {
    guard let buffer = MetalEngine.shared.device.makeBuffer(
        length: d.byteCountAsFloat32, options: .storageModeShared
    ) else { fail("could not allocate a buffer for the staleness check") }
    let held = ResidentCube(buffer: buffer, descriptor: d, specification: .fullExtent)
    guard held.matches(d, specification: .fullExtent) else {
        fail("a cube must match its own descriptor and specification")
    }
    let cropped = DatasetDescriptor(
        filePath: d.filePath, datasetPath: d.datasetPath,
        shape: [d.ry, d.rx, d.qy, d.qx - 2],
        dtypeDescription: d.dtypeDescription, chunkShape: nil
    )
    guard !held.matches(cropped, specification: .fullExtent) else {
        fail("a resident cube matched a differently shaped descriptor")
    }
    let otherFile = DatasetDescriptor(
        filePath: "/elsewhere.h5", datasetPath: d.datasetPath, shape: d.shape,
        dtypeDescription: d.dtypeDescription, chunkShape: nil
    )
    guard !held.matches(otherFile, specification: .fullExtent) else {
        fail("a resident cube matched a descriptor for a different file")
    }

    // THE CASE THE DESCRIPTOR CANNOT SEE, and the reason `matches` takes a
    // specification at all. Two detector crops of EQUAL EXTENT at DIFFERENT
    // OFFSETS have an identical filePath, datasetPath and shape, over
    // completely disjoint pixels. Shape-only matching returned `true` here and
    // would hand a stale buffer to the resident fast path — a correct number
    // about the wrong data. Adversarial review 2026-08-17; closed in L3.
    let halfDetector = [d.ry, d.rx, d.qy / 2, d.qx / 2]
    let topLeftShape = DatasetDescriptor(
        filePath: d.filePath, datasetPath: d.datasetPath, shape: halfDetector,
        dtypeDescription: d.dtypeDescription, chunkShape: nil
    )
    let topLeft = LoadSpecification(detectorCrop: AxisCrop(
        yOffset: 0, xOffset: 0, height: d.qy / 2, width: d.qx / 2
    ))
    let bottomRight = LoadSpecification(detectorCrop: AxisCrop(
        yOffset: d.qy / 2, xOffset: d.qx / 2, height: d.qy / 2, width: d.qx / 2
    ))
    guard topLeftShape.shape == halfDetector else { fail("fixture built wrong") }
    let heldTopLeft = ResidentCube(
        buffer: buffer, descriptor: topLeftShape, specification: topLeft
    )
    guard heldTopLeft.matches(topLeftShape, specification: topLeft) else {
        fail("a cube must match its own crop")
    }
    guard !heldTopLeft.matches(topLeftShape, specification: bottomRight) else {
        fail("""
             a resident cube matched a DIFFERENT crop of the same shape — the \
             descriptors are identical and the pixels are disjoint, so the \
             resident fast path would compute a correct number about the wrong data
             """)
    }
    // And a full-extent load is not the same view as a crop that happens to
    // cover everything by shape alone.
    guard !heldTopLeft.matches(topLeftShape, specification: .fullExtent) else {
        fail("a cropped cube matched a full-extent load of the same shape")
    }
    pass("staleness guard — source, shape AND load specification must all match")
}

print("virtual-detector-residency: all passed")
