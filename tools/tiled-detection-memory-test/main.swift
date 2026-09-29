import Foundation
import Metal

// Memory-growth gate for DiskDetection.detectAll(data:) — the app's own tiled
// full-scan path. Gate D 2026-09-29: with no autorelease pool per tile, the
// tile MTLBuffers and the resident detector's Metal objects survived until the
// scan ended, so phys_footprint grew by about one tile per tile.
//
// Second mode, `learned` (Gate D S11, 2026-09-29): the same measurement on
// LearnedDiskDetector.detectAll(data:) — the learned twin, whose tile loop
// awaits Core ML and so cannot sit inside one autorelease pool. It loads the
// shipped Models/DiskDetector package (path in argv[2]). Measured: it does NOT
// grow per tile — each batch awaits Core ML, a real suspension, and the
// worker's autorelease pool drains at that job boundary (an `await
// Task.yield()` per tile does the same for the classical loop with its pool
// removed). Its footprint swings inside a tile, so its gate is the slope of
// the per-tile mean footprint: FAIL above 0.25 tile per tile.
//
// The cube is GENERATED tile by tile (never held whole), so the harness itself
// adds no growth. FAIL when (max − baseline) > 2 × tile bytes, where the
// baseline is the footprint at the first tick of tile 1 (tile 0 resident).

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

nonisolated func physFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : .nan
}

/// Deterministic per-position pattern: a bright central disk plus two
/// position-dependent Bragg disks, Gaussian, on a flat floor. Generated on
/// demand for the requested scan rows only.
nonisolated func generatePattern(ry: Int, rx: Int, qy: Int, qx: Int,
                                 into out: UnsafeMutablePointer<Float>) {
    for i in 0..<qy * qx { out[i] = 1 }
    var h = UInt32(truncatingIfNeeded: ry &* 73_856_093 ^ rx &* 19_349_663) | 1
    func next() -> Float {
        h ^= h << 13; h ^= h >> 17; h ^= h << 5
        return Float(h & 0xFFFF) / 65536
    }
    let cy = Float(qy) / 2, cx = Float(qx) / 2
    let disks: [(Float, Float, Float)] = [
        (cy, cx, 1000),
        (cy + 20 + 10 * next(), cx + 10 + 10 * next(), 400 + 100 * next()),
        (cy - 20 - 10 * next(), cx - 10 - 10 * next(), 300 + 100 * next()),
    ]
    let sigma: Float = 1.2
    for (dy, dx, amplitude) in disks {
        let y0 = max(0, Int(dy) - 5), y1 = min(qy - 1, Int(dy) + 5)
        let x0 = max(0, Int(dx) - 5), x1 = min(qx - 1, Int(dx) + 5)
        for y in y0...y1 {
            for x in x0...x1 {
                let r2 = (Float(y) - dy) * (Float(y) - dy) + (Float(x) - dx) * (Float(x) - dx)
                out[y * qx + x] += amplitude * exp(-r2 / (2 * sigma * sigma))
            }
        }
    }
}

/// Flat-topped disks (radius `learnedDiskRadius`) on a square lattice about
/// the detector centre, amplitudes varying by position — a pattern the learned
/// net answers (it was trained on disks, not on the Gaussian dots above).
let learnedDiskRadius: Float = 6
nonisolated func generateDiskPattern(ry: Int, rx: Int, qy: Int, qx: Int,
                                     into out: UnsafeMutablePointer<Float>) {
    for i in 0..<qy * qx { out[i] = 2 }
    var h = UInt32(truncatingIfNeeded: ry &* 73_856_093 ^ rx &* 19_349_663) | 1
    func next() -> Float {
        h ^= h << 13; h ^= h >> 17; h ^= h << 5
        return Float(h & 0xFFFF) / 65536
    }
    let cy = Float(qy) / 2, cx = Float(qx) / 2, a: Float = 26
    let r = learnedDiskRadius
    for i in -1...1 {
        for j in -1...1 {
            let dy = cy + Float(i) * a, dx = cx + Float(j) * a
            let amplitude: Float = (i == 0 && j == 0) ? 2000 : 150 + 250 * next()
            let y0 = max(0, Int(dy - r) - 1), y1 = min(qy - 1, Int(dy + r) + 1)
            let x0 = max(0, Int(dx - r) - 1), x1 = min(qx - 1, Int(dx + r) + 1)
            for y in y0...y1 {
                for x in x0...x1 {
                    let d = ((Float(y) - dy) * (Float(y) - dy) + (Float(x) - dx) * (Float(x) - dx)).squareRoot()
                    // a one-pixel soft edge
                    out[y * qx + x] += amplitude * min(max(r + 0.5 - d, 0), 1)
                }
            }
        }
    }
}

actor GeneratingDataSource: FourDDataSource {
    let descriptor: DatasetDescriptor
    let disks: Bool
    init(descriptor: DatasetDescriptor, disks: Bool = false) { self.descriptor = descriptor; self.disks = disks }
    nonisolated func generate(ry: Int, rx: Int, into out: UnsafeMutablePointer<Float>) {
        if disks { generateDiskPattern(ry: ry, rx: rx, qy: descriptor.qy, qx: descriptor.qx, into: out) }
        else { generatePattern(ry: ry, rx: rx, qy: descriptor.qy, qx: descriptor.qx, into: out) }
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        var out = [Float](repeating: 0, count: descriptor.qy * descriptor.qx)
        out.withUnsafeMutableBufferPointer {
            generate(ry: ry, rx: rx, into: $0.baseAddress!)
        }
        return out
    }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        try readScanTile(view, yRange: ry..<ry + 1).pixels
    }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        let d = descriptor
        let perPattern = d.qy * d.qx
        var pixels = [Float](repeating: 0, count: yRange.count * d.rx * perPattern)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for (i, ry) in yRange.enumerated() {
                for rx in 0..<d.rx {
                    generate(ry: ry, rx: rx, into: buffer.baseAddress! + (i * d.rx + rx) * perPattern)
                }
            }
        }
        return FourDScanTile(yRange: yRange, scanWidth: d.rx,
                             detectorHeight: d.qy, detectorWidth: d.qx, pixels: pixels)
    }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

/// Samples phys_footprint from the progress callback (any thread).
nonisolated final class FootprintLog: @unchecked Sendable {
    private let lock = NSLock()
    let ry: Int, rowsPerTile: Int, nTiles: Int
    private(set) var firstTick: [Double]
    private var sum: [Double], count: [Int]
    private(set) var maxSeen = 0.0
    init(ry: Int, rowsPerTile: Int, nTiles: Int) {
        self.ry = ry; self.rowsPerTile = rowsPerTile; self.nTiles = nTiles
        firstTick = [Double](repeating: .nan, count: nTiles)
        sum = [Double](repeating: 0, count: nTiles); count = [Int](repeating: 0, count: nTiles)
    }
    func tick(_ fraction: Double) {
        let fp = physFootprintMB()
        let tile = min(nTiles - 1, Int(fraction * Double(ry) + 1e-9) / rowsPerTile)
        lock.withLock {
            maxSeen = max(maxSeen, fp)
            if firstTick[tile].isNaN { firstTick[tile] = fp }
            sum[tile] += fp; count[tile] += 1
        }
    }
    func note(_ fp: Double) { lock.withLock { maxSeen = max(maxSeen, fp) } }
    /// Mean footprint of every tick inside each tile (NaN where none landed).
    var tileMeans: [Double] { lock.withLock { zip(sum, count).map { $1 > 0 ? $0 / Double($1) : .nan } } }
}

/// Least-squares slope (MB per tile) of the per-tile mean footprint over
/// tiles 1..<n — tile 0 carries the warm-up (model, FFT plans, first batch).
nonisolated func growthSlope(_ means: [Double]) -> Double {
    let pts = means.enumerated().dropFirst().filter { !$0.element.isNaN }
    let n = Double(pts.count)
    let mx = pts.reduce(0) { $0 + Double($1.offset) } / n
    let my = pts.reduce(0) { $0 + $1.element } / n
    let sxy = pts.reduce(0) { $0 + (Double($1.offset) - mx) * ($1.element - my) }
    let sxx = pts.reduce(0) { $0 + (Double($1.offset) - mx) * (Double($1.offset) - mx) }
    return sxy / sxx
}

let arguments = CommandLine.arguments
let mode = arguments.count > 1 ? arguments[1] : "classical"
guard mode == "classical" || (mode == "learned" && arguments.count == 3) else {
    fail("usage: harness [classical | learned <asset.mlpackage>]")
}
// Learned: 24 tiles of 64 MB (256-px patterns, the model's own frame, so no
// padding), not 12 of 32 MB. Its footprint swings by 100–250 MB inside and
// between tiles whatever the tile size (measured at 32 and 128 MB tiles), so
// the gate is a slope over many tiles, and larger tiles put a one-tile-per-
// tile leak further above that fixed swing.
let learned = mode == "learned"
let ry = learned ? 192 : 96, rx = learned ? 32 : 64, q = learned ? 256 : 128, tileRows = 8
let d = DatasetDescriptor(
    filePath: "synthetic", datasetPath: "/synthetic",
    shape: [ry, rx, q, q], dtypeDescription: "float32", chunkShape: nil
)
let source = GeneratingDataSource(descriptor: d, disks: learned)
let data = FourDArray(reader: source, descriptor: d)

let rowsPerTile = await data.scanTileRows(maximumRows: tileRows)
let nTiles = (ry + rowsPerTile - 1) / rowsPerTile
let tileBytes = rowsPerTile * rx * q * q * MemoryLayout<Float>.stride
let tileMB = Double(tileBytes) / 1_048_576
print(String(format: "[%@] rowsPerTile %d, tile %.1f MB, %d tiles, cube %.0f MB (never resident)",
             mode, rowsPerTile, tileMB, nTiles, Double(ry * rx * q * q * 4) / 1_048_576))
guard nTiles >= 4 else { fail("need at least 4 tiles for a growth measurement, got \(nTiles)") }

let log = FootprintLog(ry: ry, rowsPerTile: rowsPerTile, nTiles: nTiles)
let tile0 = try await source.readScanTile(LoadView(fullExtentOf: d), yRange: 0..<rowsPerTile)
let tile0Descriptor = DatasetDescriptor(
    filePath: d.filePath, datasetPath: d.datasetPath,
    shape: [rowsPerTile, rx, q, q], dtypeDescription: d.dtypeDescription, chunkShape: nil
)
let tiledPeaks: [[BraggPeak]]
let residentPeaks: [[BraggPeak]]

if mode == "classical" {
    guard let kernel = ProbeKernel.synthetic(radius: 1.25, width: 0.75, qy: q, qx: q)
    else { fail("could not construct disk kernel") }
    var params = DiskDetectionParams()
    params.sigmaCC = 0
    params.subpixel = .pixel
    params.minRelativeIntensity = 0
    params.minPeakSpacing = 0
    params.edgeBoundary = 1
    params.maxNumPeaks = 8

    log.note(physFootprintMB())
    guard let tiled = try await DiskDetection.detectAll(
        data: data, descriptor: d, kernel: kernel, params: params,
        maximumTileRows: tileRows, progress: { log.tick($0) }
    ) else { fail("tiled detection returned nil (cancelled)") }
    log.note(physFootprintMB())
    tiledPeaks = tiled.peaks

    guard let buffer = MetalEngine.shared.device.makeBuffer(
        bytes: tile0.pixels, length: tile0.pixels.count * MemoryLayout<Float>.stride,
        options: .storageModeShared),
        let resident = DiskDetection.detectAll(
            cube: buffer, descriptor: tile0Descriptor, kernel: kernel, params: params)
    else { fail("resident detection of the first tile failed") }
    residentPeaks = resident.peaks
} else {
    // The learned twin at the app's realistic settings (scan-bench's), the
    // shipped threshold, the Neural Engine preferred — as the app runs it.
    let asset = URL(fileURLWithPath: arguments[2])
    let detector: LearnedDiskDetector
    do { detector = try await LearnedDiskDetector.load(assetURL: asset) }
    catch { fail("learned asset \(asset.path) did not load: \(error)") }
    print("learned asset \(asset.lastPathComponent) sha \(detector.assetSHA256.prefix(8)), batch \(detector.batch)")
    var probePixels = [Float](repeating: 0, count: q * q)
    let c = Float(q) / 2
    for y in 0..<q {
        for x in 0..<q {
            let r = ((Float(y) - c) * (Float(y) - c) + (Float(x) - c) * (Float(x) - c)).squareRoot()
            probePixels[y * q + x] = 2000 * min(max(learnedDiskRadius + 0.5 - r, 0), 1)
        }
    }
    let probe = DiffractionPattern(qy: q, qx: q, pixels: probePixels)
    var params = DiskDetectionParams()
    params.sigmaCC = 2; params.subpixel = .poly; params.minPeakSpacing = 8
    params.edgeBoundary = 6; params.minRelativeIntensity = 0.05; params.maxNumPeaks = 70

    log.note(physFootprintMB())
    guard let tiled = try await detector.detectAll(
        data: data, descriptor: d, probe: probe, probeCentre: (x: c, y: c),
        probeRadius: learnedDiskRadius, params: params,
        maximumTileRows: tileRows, progress: { log.tick($0) }
    ) else { fail("learned tiled detection returned nil (cancelled)") }
    log.note(physFootprintMB())
    tiledPeaks = tiled.peaks

    guard let buffer = MetalEngine.shared.device.makeBuffer(
        bytes: tile0.pixels, length: tile0.pixels.count * MemoryLayout<Float>.stride,
        options: .storageModeShared),
        let resident = await detector.detectAll(
            cube: buffer, descriptor: tile0Descriptor, probe: probe, probeCentre: (x: c, y: c),
            probeRadius: learnedDiskRadius, params: params)
    else { fail("resident learned detection of the first tile failed") }
    residentPeaks = resident.peaks
}

let means = log.tileMeans
for (i, fp) in log.firstTick.enumerated() {
    let step = i > 0 ? fp - log.firstTick[i - 1] : .nan
    print(String(format: "  tile %2d/%d first tick: phys_footprint %.0f MB (%+.0f MB), tile mean %.0f MB",
                 i, nTiles, fp, step, means[i]))
}
let baseline = log.firstTick[1]
guard !baseline.isNaN else { fail("no progress tick reached tile 1") }
let growth = log.maxSeen - baseline
let limit = 2 * tileMB

// Correctness: the first tile's rows must match a resident detection of the
// same rows exactly, and the scan must contain peaks.
let totalPeaks = tiledPeaks.reduce(0) { $0 + $1.count }
guard totalPeaks > 0 else { fail("[\(mode)] tiled detection found no peaks") }
for scan in 0..<rowsPerTile * rx {
    let a = residentPeaks[scan], b = tiledPeaks[scan]
    guard a.count == b.count else { fail("[\(mode)] first-tile peak count differs at scan \(scan)") }
    for k in a.indices {
        guard a[k].x == b[k].x, a[k].y == b[k].y, a[k].intensity == b[k].intensity else {
            fail("[\(mode)] first-tile peak value differs at scan \(scan), peak \(k)")
        }
    }
}

if mode == "classical" {
    print("PASS: tiled_detection_first_tile exact resident parity, \(totalPeaks) peaks in total")
    guard growth <= limit else {
        fail(String(format: "tiled_detection_memory grew %.0f MB over %d tiles (baseline %.0f MB at tile 1, max %.0f MB, limit %.0f MB = 2 tiles)",
                    growth, nTiles, baseline, log.maxSeen, limit))
    }
    print(String(format: "PASS: tiled_detection_memory_flat growth %.0f MB over %d tiles (limit %.0f MB)",
                 growth, nTiles, limit))
} else {
    print("PASS: learned_tiled_detection_first_tile exact resident parity, \(totalPeaks) peaks in total")
    // A tile buffer that outlives its tile adds one tile per tile: retaining
    // every tile's MTLBuffer in detectAll(data:) measured 0.99 tiles per tile
    // (FAIL); unmodified, 0.01–0.02 in three runs (S11, 2026-09-29).
    let slope = growthSlope(means)
    let slopeLimit = 0.25 * tileMB
    guard slope <= slopeLimit else {
        fail(String(format: "learned_tiled_detection_memory grows %.1f MB per tile (%.2f tiles per tile) over %d tiles, limit %.1f MB (0.25 tile); max %.0f MB, %.0f MB over tile 1",
                    slope, slope / tileMB, nTiles, slopeLimit, log.maxSeen, growth))
    }
    print(String(format: "PASS: learned_tiled_detection_memory_flat slope %+.1f MB per tile (%.2f tiles per tile, limit 0.25) over %d tiles; max %.0f MB, %.0f MB over tile 1",
                 slope, slope / tileMB, nTiles, log.maxSeen, growth))
}
