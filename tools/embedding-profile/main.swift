//
//  main.swift -- tools/embedding-profile (diagnostic, 2026-09-28)
//  open-items "Diffraction groups at 32 x 32 is too slow to use": the owner
//  asked to profile before deciding its fate. Times DiffractionEmbedding.compute
//  per phase on synthetic 128 x 128 patterns (the size of the Thronsen cube's
//  detector), from the progress callback's own phase boundaries:
//    streaming (embed + accumulate) ends at statsWeight (0.80 when cached),
//    eigen at +0.05, projection at +0.10, k-means the rest.
//  Content does not change the streaming or eigen cost (fixed arithmetic per
//  pattern / per matrix); k-means iterations can depend on content, so its time
//  here is indicative only. Usage: probe N BINNED [COMPONENTS GROUPS]
//
import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif

actor SyntheticSource: FourDDataSource {
    let shape: [Int]
    let patterns: [[Float]]
    init(scanHeight: Int, scanWidth: Int, qy: Int, qx: Int, patterns: [[Float]]) {
        shape = [scanHeight, scanWidth, qy, qx]; self.patterns = patterns
    }
    var qy: Int { shape[2] }
    var qx: Int { shape[3] }
    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(filePath: "/synthetic/profile.h5", datasetPath: "/data",
                          shape: shape, dtypeDescription: "float32", chunkShape: nil)
    }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] { patterns[ry * view.descriptor.rx + rx] }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        var out = [Float](); out.reserveCapacity(view.descriptor.rx * qy * qx)
        for rx in 0..<view.descriptor.rx { out.append(contentsOf: patterns[ry * view.descriptor.rx + rx]) }
        return out
    }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        var pixels = [Float](); pixels.reserveCapacity(yRange.count * view.descriptor.rx * qy * qx)
        for ry in yRange { pixels.append(contentsOf: try readScanRow(view, ry: ry)) }
        return FourDScanTile(yRange: yRange, scanWidth: view.descriptor.rx,
                             detectorHeight: qy, detectorWidth: qx, pixels: pixels)
    }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

final class Marks: @unchecked Sendable {
    private let lock = NSLock()
    private var t: [(Double, Double)] = []
    func add(_ f: Double) { lock.lock(); t.append((Date().timeIntervalSinceReferenceDate, f)); lock.unlock() }
    func firstTime(atLeast f: Double) -> Double? { lock.lock(); defer { lock.unlock() }; return t.first { $0.1 >= f - 1e-9 }?.0 }
}

@main
enum Probe {
    static func main() async throws {
        let a = CommandLine.arguments
        let n = Int(a[1])!, binned = Int(a[2])!
        let components = a.count > 3 ? Int(a[3])! : 8, groups = a.count > 4 ? Int(a[4])! : 4
        let qy = 128, qx = 128
        let scanW = 50, scanH = max(1, n / 50)
        var seed: UInt64 = 0xC0FFEE
        func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float((seed >> 33) % 1_000_000) / 1_000_000 }
        var patterns = [[Float]]()
        for p in 0..<(scanW * scanH) {
            var img = [Float](repeating: 0, count: qy * qx)
            for i in 0..<img.count { img[i] = 3 + 2 * rnd() }
            for k in 0..<6 { // a few disks per pattern, varying by position
                let cy = 20 + (k * 17 + p % 5) % 90, cx = 15 + (k * 29 + p % 7) % 95
                for dy in -3...3 { for dx in -3...3 { img[(cy + dy) * qx + cx + dx] += 200 * rnd() } }
            }
            patterns.append(img)
        }
        let source = SyntheticSource(scanHeight: scanH, scanWidth: scanW, qy: qy, qx: qx, patterns: patterns)
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)
        let settings = DiffractionEmbedding.Settings(binnedSize: binned, components: components, groups: groups, seed: 7)
        let marks = Marks()
        let t0 = Date().timeIntervalSinceReferenceDate
        guard let r = try await DiffractionEmbedding.compute(
            data: data, descriptor: descriptor, settings: settings, cancellation: nil,
            progress: { marks.add($0) }) else { fatalError("nil") }
        let t1 = Date().timeIntervalSinceReferenceDate
        let stream = (marks.firstTime(atLeast: 0.80) ?? t1) - t0
        let eigen = (marks.firstTime(atLeast: 0.85) ?? t1) - t0 - stream
        let project = (marks.firstTime(atLeast: 0.95) ?? t1) - t0 - stream - eigen
        let rest = t1 - t0 - stream - eigen - project
        // Streaming split: embed alone, timed directly over the same patterns.
        let geom = DiffractionEmbedding.BinGeometry.compute(qy: qy, qx: qx, binnedSize: binned)
        let e0 = Date().timeIntervalSinceReferenceDate
        var sink: Float = 0
        for img in patterns { sink += DiffractionEmbedding.embed(pixels: img, base: 0, qy: qy, qx: qx, geometry: geom, binnedSize: binned)[0] }
        let embed = Date().timeIntervalSinceReferenceDate - e0
        print(String(format: "N %d  binned %d (d=%d)  comps %d groups %d | total %.3f s | stream %.3f (embed %.3f, accumulate+tiles %.3f) | eigen %.3f | project %.3f | kmeans+rest %.3f | groups %d sink %.1f",
                     patterns.count, binned, binned * binned, components, groups, t1 - t0, stream, embed, stream - embed, eigen, project, rest, r.groupCount, sink))
    }
}
