import Foundation
import Metal

// Memory-growth gate for DiskDetection.detectAll(data:) — the app's own tiled
// full-scan path. Gate D 2026-09-29: with no autorelease pool per tile, the
// tile MTLBuffers and the resident detector's Metal objects survived until the
// scan ended, so phys_footprint grew by about one tile per tile.
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

actor GeneratingDataSource: FourDDataSource {
    let descriptor: DatasetDescriptor
    init(descriptor: DatasetDescriptor) { self.descriptor = descriptor }

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
        let d = descriptor
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

/// Samples phys_footprint from the progress callback (any thread).
nonisolated final class FootprintLog: @unchecked Sendable {
    private let lock = NSLock()
    let ry: Int, rowsPerTile: Int, nTiles: Int
    private(set) var firstTick: [Double]
    private(set) var maxSeen = 0.0
    init(ry: Int, rowsPerTile: Int, nTiles: Int) {
        self.ry = ry; self.rowsPerTile = rowsPerTile; self.nTiles = nTiles
        firstTick = [Double](repeating: .nan, count: nTiles)
    }
    func tick(_ fraction: Double) {
        let fp = physFootprintMB()
        let tile = min(nTiles - 1, Int(fraction * Double(ry) + 1e-9) / rowsPerTile)
        lock.withLock {
            maxSeen = max(maxSeen, fp)
            if firstTick[tile].isNaN { firstTick[tile] = fp }
        }
    }
    func note(_ fp: Double) { lock.withLock { maxSeen = max(maxSeen, fp) } }
}

let ry = 96, rx = 64, q = 128, tileRows = 8
let d = DatasetDescriptor(
    filePath: "synthetic", datasetPath: "/synthetic",
    shape: [ry, rx, q, q], dtypeDescription: "float32", chunkShape: nil
)
let source = GeneratingDataSource(descriptor: d)
let data = FourDArray(reader: source, descriptor: d)

guard let kernel = ProbeKernel.synthetic(radius: 1.25, width: 0.75, qy: q, qx: q)
else { fail("could not construct disk kernel") }
var params = DiskDetectionParams()
params.sigmaCC = 0
params.subpixel = .pixel
params.minRelativeIntensity = 0
params.minPeakSpacing = 0
params.edgeBoundary = 1
params.maxNumPeaks = 8

let rowsPerTile = await data.scanTileRows(maximumRows: tileRows)
let nTiles = (ry + rowsPerTile - 1) / rowsPerTile
let tileBytes = rowsPerTile * rx * q * q * MemoryLayout<Float>.stride
let tileMB = Double(tileBytes) / 1_048_576
print(String(format: "rowsPerTile %d, tile %.1f MB, %d tiles, cube %.0f MB (never resident)",
             rowsPerTile, tileMB, nTiles, Double(ry * rx * q * q * 4) / 1_048_576))
guard nTiles >= 4 else { fail("need at least 4 tiles for a growth measurement, got \(nTiles)") }

let log = FootprintLog(ry: ry, rowsPerTile: rowsPerTile, nTiles: nTiles)
log.note(physFootprintMB())
guard let tiled = try await DiskDetection.detectAll(
    data: data, descriptor: d, kernel: kernel, params: params,
    maximumTileRows: tileRows, progress: { log.tick($0) }
) else { fail("tiled detection returned nil (cancelled)") }
log.note(physFootprintMB())

for (i, fp) in log.firstTick.enumerated() {
    print(String(format: "  tile %2d/%d first tick: phys_footprint %.0f MB", i, nTiles, fp))
}
let baseline = log.firstTick[1]
guard !baseline.isNaN else { fail("no progress tick reached tile 1") }
let growth = log.maxSeen - baseline
let limit = 2 * tileMB

// Correctness: the first tile's rows must match a resident detection of the
// same rows exactly, and the scan must contain peaks.
let totalPeaks = tiled.peaks.reduce(0) { $0 + $1.count }
guard totalPeaks > 0 else { fail("tiled detection found no peaks") }
let tile0 = try await source.readScanTile(
    LoadView(fullExtentOf: d), yRange: 0..<rowsPerTile)
let tile0Descriptor = DatasetDescriptor(
    filePath: d.filePath, datasetPath: d.datasetPath,
    shape: [rowsPerTile, rx, q, q], dtypeDescription: d.dtypeDescription, chunkShape: nil
)
guard let buffer = MetalEngine.shared.device.makeBuffer(
    bytes: tile0.pixels, length: tile0.pixels.count * MemoryLayout<Float>.stride,
    options: .storageModeShared),
    let resident = DiskDetection.detectAll(
        cube: buffer, descriptor: tile0Descriptor, kernel: kernel, params: params)
else { fail("resident detection of the first tile failed") }
for scan in 0..<rowsPerTile * rx {
    let a = resident.peaks[scan], b = tiled.peaks[scan]
    guard a.count == b.count else { fail("first-tile peak count differs at scan \(scan)") }
    for k in a.indices {
        guard a[k].x == b[k].x, a[k].y == b[k].y, a[k].intensity == b[k].intensity else {
            fail("first-tile peak value differs at scan \(scan), peak \(k)")
        }
    }
}
print("PASS: tiled_detection_first_tile exact resident parity, \(totalPeaks) peaks in total")

guard growth <= limit else {
    fail(String(format: "tiled_detection_memory grew %.0f MB over %d tiles (baseline %.0f MB at tile 1, max %.0f MB, limit %.0f MB = 2 tiles)",
                growth, nTiles, baseline, log.maxSeen, limit))
}
print(String(format: "PASS: tiled_detection_memory_flat growth %.0f MB over %d tiles (limit %.0f MB)",
             growth, nTiles, limit))
