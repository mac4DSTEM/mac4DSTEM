//
//  main.swift -- tools/embedding-pca-parity
//  Writes the feature matrix DiffractionEmbedding actually used, its PCA
//  result, and a standalone symmetric matrix with symmetricEigenTop's
//  eigenpairs, for verify_py4dstem.py to check against py4DSTEM and numpy.
//
//  The fixture is NON-SQUARE IN BOTH AXES (16x25 scan, 32x30 detector) so an
//  axis swap cannot cancel -- the S4/S8 lesson. 400 positions is deliberate and
//  load-bearing: sklearn's 'auto' SVD solver flips to `randomized` above 500
//  rows, and py4DSTEM passes neither svd_solver nor random_state, so the
//  upstream number becomes nondeterministic. Measured 2026-09-11: n=500 gives
//  0.0 run-to-run drift in explained_variance_ratio_, n=501 gives 5.9e-4.
//
import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif

actor DiffractionGroupsFixtureSource: FourDDataSource {
    private let shape: [Int]
    private let patterns: [[Float]]

    init(scanHeight: Int, scanWidth: Int, qy: Int, qx: Int, patterns: [[Float]]) {
        precondition(patterns.count == scanHeight * scanWidth)
        self.shape = [scanHeight, scanWidth, qy, qx]
        self.patterns = patterns
    }

    private var qy: Int { shape[2] }
    private var qx: Int { shape[3] }

    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(
            filePath: "/synthetic/diffraction-groups-fixture.h5", datasetPath: "/data",
            shape: shape, dtypeDescription: "float32", chunkShape: nil
        )
    }

    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        patterns[ry * view.descriptor.rx + rx]
    }

    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        var out = [Float]()
        out.reserveCapacity(view.descriptor.rx * qy * qx)
        for rx in 0..<view.descriptor.rx {
            out.append(contentsOf: patterns[ry * view.descriptor.rx + rx])
        }
        return out
    }

    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        var pixels = [Float]()
        pixels.reserveCapacity(yRange.count * view.descriptor.rx * qy * qx)
        for ry in yRange { pixels.append(contentsOf: try readScanRow(view, ry: ry)) }
        return FourDScanTile(
            yRange: yRange, scanWidth: view.descriptor.rx,
            detectorHeight: qy, detectorWidth: qx, pixels: pixels
        )
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

func writeF64(_ values: [Double], to path: String) {
    var d = Data(capacity: values.count * 8)
    for v in values { withUnsafeBytes(of: v.bitPattern.littleEndian) { d.append(contentsOf: $0) } }
    try! d.write(to: URL(fileURLWithPath: path))
}

func writeJSON(_ o: [String: Any], to path: String) {
    let d = try! JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys])
    try! d.write(to: URL(fileURLWithPath: path))
}

@main
enum Harness {
    static func main() async throws {
        let out = CommandLine.arguments[1]
        let scanW = 16, scanH = 25, qy = 32, qx = 30
        let binned = 8, components = 8, groups = 4

        var seed: UInt64 = 0xC0FFEE
        func rnd() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) % 1_000_000) / 1_000_000
        }
        // Eight well-separated components in the binned domain, so the
        // eigenvalue gaps are wide enough that per-component vector comparison
        // means something. Guard F in verify_py4dstem.py asserts that.
        var patterns = [[Float]]()
        for p in 0..<(scanW * scanH) {
            var img = [Float](repeating: 0, count: qy * qx)
            // Per-position amplitudes with a STEEP geometric decay: variance
            // goes as amplitude squared, so this is what separates the
            // eigenvalues. Guard F in the verifier asserts the separation --
            // a first version decayed as 240>>k and left the smallest relative
            // gap at 0.101 against a 0.1 guard, i.e. a gate one fixture tweak
            // away from flaking.
            let base: [Float] = [420, 210, 100, 46, 21, 9.5, 4.2, 1.8]
            for k in 0..<8 {
                let amp = base[k] * (0.45 + 1.1 * rnd())
                let cy = 4 + (k % 4) * 7, cx = 3 + (k / 4) * 13
                for dy in -2...2 {
                    for dx in -2...2 {
                        let y = cy + dy + (p % 3), x = cx + dx
                        if y >= 0, y < qy, x >= 0, x < qx { img[y * qx + x] += amp }
                    }
                }
            }
            for i in 0..<img.count { img[i] += 3 + 2 * rnd() }
            patterns.append(img)
        }

        let source = DiffractionGroupsFixtureSource(
            scanHeight: scanH, scanWidth: scanW, qy: qy, qx: qx, patterns: patterns)
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)
        let settings = DiffractionEmbedding.Settings(
            binnedSize: binned, components: components, groups: groups, seed: 7)
        guard let r = try await DiffractionEmbedding.compute(
            data: data, descriptor: descriptor, settings: settings,
            cancellation: nil, progress: nil
        ) else { fatalError("compute returned nil") }

        // The SAME feature matrix the engine consumed -- `embed` is called
        // here, never reimplemented, so the two sides cannot drift.
        let geom = DiffractionEmbedding.BinGeometry.compute(qy: qy, qx: qx, binnedSize: binned)
        var features = [Double]()
        features.reserveCapacity(patterns.count * binned * binned)
        for img in patterns {
            let v = DiffractionEmbedding.embed(
                pixels: img, base: 0, qy: qy, qx: qx, geometry: geom, binnedSize: binned)
            features.append(contentsOf: v.map(Double.init))
        }
        writeF64(features, to: out + "/features.f64")

        // Scope 2: the eigensolver alone, on a dense symmetric matrix with a
        // deliberately decaying diagonal so the top eigenvalues separate.
        let d = 64
        var m = [Double](repeating: 0, count: d * d)
        for i in 0..<d {
            for j in 0...i {
                let v = Double(rnd()) - 0.5 + (i == j ? Double(d - i) : 0)
                m[i * d + j] = v
                m[j * d + i] = v
            }
        }
        let (vecs, vals) = DiffractionEmbedding.symmetricEigenTop(
            matrix: m, dimension: d, count: 8, cancellation: nil)
        writeF64(m, to: out + "/eigen_input.f64")

        writeJSON([
            "positions": patterns.count,
            "dims": binned * binned,
            "scanWidth": r.scanWidth,
            "scanHeight": r.scanHeight,
            "componentCount": r.componentCount,
            "mean": r.mean.map(Double.init),
            "basis": r.basis.map(Double.init),
            "explainedVariance": r.explainedVariance.map(Double.init),
            "coordinates": r.coordinates.map(Double.init),
            "groupOf": r.groupOf,
            "eigenDimension": d,
            "eigenValues": vals,
            "eigenVectors": vecs.flatMap { $0 },
        ], to: out + "/result.json")
        print("harness: wrote features.f64, eigen_input.f64, result.json")
    }
}
