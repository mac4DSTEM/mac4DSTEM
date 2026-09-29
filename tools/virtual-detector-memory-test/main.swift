import Foundation
import Metal

// Memory-growth gate for the streaming (never-resident) tiled passes of
// VirtualDetector: tiledImage, tiledRun, tiledDPStatistics, tiledDiffraction,
// tiledMeasuredOrigins, tiledCenterOfMass. Sibling of tools/tiled-detection-
// memory-test (Gate D 2026-09-29: an async tile loop with an MTLBuffer made
// from each tile and no autorelease pool grew phys_footprint by one tile per
// tile). These loops have the same shape; S16 (2026-09-30) measures them.
//
// The cube is GENERATED tile by tile (never held whole). All six paths take a
// FourDArray, so one sampling point serves them all: the data source samples
// phys_footprint at the start of every tile READ (one per tile, made by the
// prefetcher just before the previous tile is processed), plus one sample after
// the pass. FAIL when (max sample - sample at read 2) > 2 x tile bytes — the
// statistic of the A1 harness, whose classical variant it copies.
//
// Each invocation measures ONE path (argv[1]) so that a leak in one path cannot
// move another's baseline. The result's FNV-1a checksum is printed so a change
// to a loop can be shown byte-identical before and after.

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
/// position-dependent Gaussian disks on a flat floor.
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

/// Samples phys_footprint once per tile read (any thread).
nonisolated final class FootprintLog: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var samples: [Double] = []
    func sample() { let fp = physFootprintMB(); lock.withLock { samples.append(fp) } }
}

actor GeneratingDataSource: FourDDataSource {
    let descriptor: DatasetDescriptor
    let log: FootprintLog
    /// `fast`: every tile read returns ONE pre-generated array (shared
    /// storage, no work), so the prefetch Task is finished long before the loop
    /// awaits it and that `await` need not suspend.
    let cached: [Float]?
    init(descriptor: DatasetDescriptor, log: FootprintLog, fast: Bool, tileRows: Int) {
        self.descriptor = descriptor; self.log = log
        if fast {
            let d = descriptor, perPattern = d.qy * d.qx
            var pixels = [Float](repeating: 0, count: tileRows * d.rx * perPattern)
            pixels.withUnsafeMutableBufferPointer { buffer in
                for ry in 0..<tileRows {
                    for rx in 0..<d.rx {
                        generatePattern(ry: ry, rx: rx, qy: d.qy, qx: d.qx,
                                        into: buffer.baseAddress! + (ry * d.rx + rx) * perPattern)
                    }
                }
            }
            cached = pixels
        } else { cached = nil }
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        var out = [Float](repeating: 0, count: descriptor.qy * descriptor.qx)
        out.withUnsafeMutableBufferPointer {
            generatePattern(ry: ry, rx: rx, qy: descriptor.qy, qx: descriptor.qx, into: $0.baseAddress!)
        }
        return out
    }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        try readScanTile(view, yRange: ry..<ry + 1).pixels
    }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        log.sample()
        let d = descriptor
        if let cached {
            return FourDScanTile(yRange: yRange, scanWidth: d.rx,
                                 detectorHeight: d.qy, detectorWidth: d.qx, pixels: cached)
        }
        let perPattern = d.qy * d.qx
        var pixels = [Float](repeating: 0, count: yRange.count * d.rx * perPattern)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for (i, ry) in yRange.enumerated() {
                for rx in 0..<d.rx {
                    generatePattern(ry: ry, rx: rx, qy: d.qy, qx: d.qx,
                                    into: buffer.baseAddress! + (i * d.rx + rx) * perPattern)
                }
            }
        }
        return FourDScanTile(yRange: yRange, scanWidth: d.rx,
                             detectorHeight: d.qy, detectorWidth: d.qx, pixels: pixels)
    }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

nonisolated func fnv1a(_ values: [Float]) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for v in values {
        var bits = v.bitPattern
        for _ in 0..<4 { h = (h ^ UInt64(bits & 0xFF)) &* 0x100000001b3; bits >>= 8 }
    }
    return h
}

let paths = ["image", "aperture", "dp", "diffraction", "origins", "com"]
let arguments = CommandLine.arguments
guard arguments.count >= 2, arguments.count <= 3, paths.contains(arguments[1]),
      arguments.count == 2 || arguments[2] == "fast" else {
    fail("usage: harness [\(paths.joined(separator: " | "))] [fast]")
}
let path = arguments[1]
let fast = arguments.count == 3

let ry = 96, rx = 64, q = 128, tileRows = 8
let d = DatasetDescriptor(
    filePath: "synthetic", datasetPath: "/synthetic",
    shape: [ry, rx, q, q], dtypeDescription: "float32", chunkShape: nil
)
let log = FootprintLog()
let data = FourDArray(reader: GeneratingDataSource(descriptor: d, log: log, fast: fast, tileRows: tileRows), descriptor: d)
let rowsPerTile = await data.scanTileRows(maximumRows: tileRows)
let nTiles = (ry + rowsPerTile - 1) / rowsPerTile
let tileMB = Double(rowsPerTile * rx * q * q * MemoryLayout<Float>.stride) / 1_048_576
print(String(format: "[%@%@] rowsPerTile %d, tile %.1f MB, %d tiles, cube %.0f MB (never resident)",
             path, fast ? " fast" : "", rowsPerTile, tileMB, nTiles, Double(ry * rx * q * q * 4) / 1_048_576))
guard nTiles >= 4, rowsPerTile == tileRows else { fail("need 8-row tiles and at least 4 of them") }
let c = Float(q) / 2

let checksum: UInt64
switch path {
case "image":
    let image = try await VirtualDetector.tiledImage(
        data: data, descriptor: d, shape: .annulus(centerX: c, centerY: c, inner: 4, outer: 30),
        maximumTileRows: tileRows)
    checksum = fnv1a(image.pixels)
case "aperture":
    let image = try await VirtualDetector.tiledRun(
        data: data, descriptor: d, aperture: Aperture(centerX: c, centerY: c, inner: 4, outer: 30),
        maximumTileRows: tileRows)
    checksum = fnv1a(image.pixels)
case "dp":
    let stats = try await VirtualDetector.tiledDPStatistics(
        data: data, descriptor: d, maximumTileRows: tileRows)
    checksum = fnv1a(stats.maxDP) ^ (fnv1a(stats.meanDP) &* 31)
case "diffraction":
    let pattern = try await VirtualDetector.tiledDiffraction(
        data: data, descriptor: d, region: .circle(centerX: Float(rx) / 2, centerY: Float(ry) / 2, radius: 20),
        maximumTileRows: tileRows)
    checksum = fnv1a(pattern.pixels)
case "origins":
    checksum = fnv1a(try await VirtualDetector.tiledMeasuredOrigins(
        data: data, descriptor: d, probeRadius: 8, maximumTileRows: tileRows))
default:
    checksum = fnv1a(try await VirtualDetector.tiledCenterOfMass(
        data: data, descriptor: d, center: (x: c, y: c), maximumTileRows: tileRows))
}
log.sample()

let samples = log.samples
guard samples.count == nTiles + 1 else {
    fail("expected \(nTiles) tile reads plus the final sample, got \(samples.count) samples")
}
for (i, fp) in samples.enumerated() {
    let step = i > 0 ? fp - samples[i - 1] : .nan
    print(String(format: "  %@ %2d: phys_footprint %.0f MB (%+.0f MB)",
                 i < nTiles ? "read tile" : "after pass", i, fp, step))
}
// Baseline = the read of tile 2, issued after tile 0 has been processed: the
// first pass's one-time cost (Metal library, pipelines, first buffers; about
// 3 tiles' worth, m1-*.log) is behind it. Reads 2...n and the final sample are
// the ten intervals a per-tile leak would show in.
let baseline = samples[2]
let maxSeen = samples[2...].max()!
let growth = maxSeen - baseline
let limit = 2 * tileMB
print(String(format: "checksum %016llx", checksum))
guard growth <= limit else {
    fail(String(format: "virtual_detector_memory[%@] grew %.0f MB over %d tiles (baseline %.0f MB at tile 2, max %.0f MB, limit %.0f MB = 2 tiles)",
                path + (fast ? " fast" : ""), growth, nTiles, baseline, maxSeen, limit))
}
print(String(format: "PASS: virtual_detector_memory_flat[%@] growth %.0f MB over %d tiles (limit %.0f MB)",
             path + (fast ? " fast" : ""), growth, nTiles, limit))
