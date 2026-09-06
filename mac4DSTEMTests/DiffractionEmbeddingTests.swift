//
//  DiffractionEmbeddingTests.swift
//  Diffraction-groups classical v1 (docs/ai-ml/README.md §6): PCA on
//  box-binned patterns, then k-means. Every assertion below states the
//  mutation it catches — this session could not build, so nothing here was
//  run against a compiler.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// An in-memory `FourDDataSource` over a fixed list of scan-position patterns
/// (row-major) — the same shape as `LearnedDiskDetectionScanTests`'
/// `FixturePatternSource`, redeclared here (private/file-scoped in that
/// file) so this file has no cross-file dependency on it.
private actor DiffractionGroupsFixtureSource: FourDDataSource {
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

final class DiffractionEmbeddingTests: XCTestCase {
    private let scanWidth = 6
    private let scanHeight = 6
    private let detectorSize = 32

    /// A tiny, deterministic (NOT `SystemRandomNumberGenerator`) hash used
    /// only to give each pattern within a family a slightly different noise
    /// floor — xorshift64*, seeded by an arbitrary function of the pattern
    /// and pixel index so the same fixture is bit-identical across runs.
    private func deterministicNoise(_ seed: Int) -> Float {
        var x = UInt64(bitPattern: Int64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 1))
        x ^= x >> 12; x ^= x << 25; x ^= x >> 27
        x = x &* 0x2545_F491_4F6C_DD1D
        return Float(x % 1024) / 1024.0
    }

    /// Three pattern families on a `detectorSize`×`detectorSize` detector,
    /// distinguished by WHERE their bright spots sit — family 0: four corner
    /// spots; family 1: two left/right spots; family 2: two top/bottom spots
    /// — each with a small per-pixel noise floor so no two patterns in a
    /// family are bit-identical. The spot layouts are far enough apart
    /// (disjoint after binning to as few as 5×5) that the classical PCA
    /// baseline should separate them cleanly; this is a discriminability
    /// fixture, not a claim about any real material's diffraction.
    private func syntheticFamilyPattern(family: Int, positionSeed: Int) -> [Float] {
        let size = detectorSize
        let spotCenters: [(Int, Int)]
        switch family {
        case 0: spotCenters = [(8, 8), (8, 24), (24, 8), (24, 24)]
        case 1: spotCenters = [(16, 4), (16, 28)]
        default: spotCenters = [(4, 16), (28, 16)]
        }
        var pattern = [Float](repeating: 1, count: size * size)
        for (cy, cx) in spotCenters {
            for dy in -3...3 {
                for dx in -3...3 {
                    let y = cy + dy, x = cx + dx
                    guard y >= 0, y < size, x >= 0, x < size, dy * dy + dx * dx <= 9 else { continue }
                    pattern[y * size + x] = 60
                }
            }
        }
        for i in pattern.indices {
            pattern[i] += deterministicNoise(positionSeed * 100_003 + i) * 0.5
        }
        return pattern
    }

    /// `families[i]` is the TRUE family (0, 1, or 2) of position `i` —
    /// `i % 3`, so every family has exactly 12 of the 36 positions and no
    /// family is confined to one region of the scan.
    private func makeThreeFamilyFixture() async throws -> (
        data: FourDArray, descriptor: DatasetDescriptor, families: [Int]
    ) {
        let positions = scanWidth * scanHeight
        var families = [Int](repeating: 0, count: positions)
        var patterns = [[Float]](repeating: [], count: positions)
        for i in 0..<positions {
            let family = i % 3
            families[i] = family
            patterns[i] = syntheticFamilyPattern(family: family, positionSeed: i)
        }
        let source = DiffractionGroupsFixtureSource(
            scanHeight: scanHeight, scanWidth: scanWidth,
            qy: detectorSize, qx: detectorSize, patterns: patterns
        )
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)
        return (data, descriptor, families)
    }

    // MARK: - PCA explains the family separation

    /// Breaks under: `totalVariance` computed from the wrong source (e.g.
    /// summing only the RETAINED eigenvalues instead of the covariance
    /// TRACE, which would read as ~100% regardless of how good the basis
    /// is — this dataset's near-100%-in-3-components truth would then hide
    /// a basis that actually captured only noise); a mean/covariance
    /// accumulation bug that skips the log1p/max-normalise/box-bin pipeline
    /// (raw pixel sums dilute the family signal with the flat background);
    /// or an eigensolver whose Rayleigh-Ritz step returns eigenvectors NOT
    /// sorted by eigenvalue (a dropped or reversed `sorted` would put a
    /// low-variance direction first).
    func testPCAExplainsThreeFamiliesInFirstThreeComponents() async throws {
        let (data, descriptor, _) = try await makeThreeFamilyFixture()
        let settings = DiffractionEmbedding.Settings(
            binnedSize: 16, components: 8, groups: 3, seed: 42
        )
        let computed = try await DiffractionEmbedding.compute(
            data: data, descriptor: descriptor, settings: settings,
            cancellation: nil, progress: nil
        )
        let result = try XCTUnwrap(computed, "compute returns nil ONLY on cancellation")
        XCTAssertEqual(result.componentCount, 8)

        let firstThree = result.explainedVariance.prefix(3).reduce(0, +)
        XCTAssertGreaterThan(
            firstThree, 0.8,
            "three well-separated spot layouts should live almost entirely "
            + "in the first three principal components; got \(firstThree)"
        )
    }

    // MARK: - k-means recovers the families exactly, up to permutation

    /// Breaks under: a k-means assignment step that does not actually pick
    /// the nearest centroid (e.g. always the first cluster, or ties resolved
    /// by array order instead of distance); an empty-cluster reseed that
    /// discards a whole family instead of re-entering it; or a k-means++
    /// seeding bug that starts all three centroids inside the same family
    /// (this fixture's disjoint clusters make that recoverable in principle,
    /// but a truly broken seed plus a broken Lloyd's step would still fail
    /// this). Would also fail if the PCA coordinates themselves collapsed
    /// the three families together, even were the earlier test's aggregate
    /// >80% threshold to still (wrongly) pass on some other reading.
    func testKMeansRecoversThreeFamiliesUpToPermutation() async throws {
        let (data, descriptor, families) = try await makeThreeFamilyFixture()
        let settings = DiffractionEmbedding.Settings(
            binnedSize: 16, components: 8, groups: 3, seed: 42
        )
        let computed = try await DiffractionEmbedding.compute(
            data: data, descriptor: descriptor, settings: settings,
            cancellation: nil, progress: nil
        )
        let result = try XCTUnwrap(computed)
        XCTAssertEqual(result.groupOf.count, families.count)
        XCTAssertEqual(result.groupCount, 3)

        var groupToFamilies: [Int: Set<Int>] = [:]
        var familyToGroups: [Int: Set<Int>] = [:]
        for i in 0..<families.count {
            groupToFamilies[result.groupOf[i], default: []].insert(families[i])
            familyToGroups[families[i], default: []].insert(result.groupOf[i])
        }
        for (group, fams) in groupToFamilies {
            XCTAssertEqual(fams.count, 1, "k-means group \(group) mixes two different families: \(fams)")
        }
        for (family, groups) in familyToGroups {
            XCTAssertEqual(groups.count, 1, "family \(family) is split across k-means groups: \(groups)")
        }
    }

    // MARK: - similarity is highest within the reference's own family

    /// Breaks under: a similarity formula that omits normalisation (a raw
    /// dot product would be biased by coordinate magnitude, not direction);
    /// an off-by-one that computes similarity against a neighbouring
    /// position instead of the requested one (the reference chosen below is
    /// neither index 0 nor the last index, so a `position ± 1` bug shifts
    /// which family scores highest); or a `groupOf`/`coordinates` index
    /// mismatch that silently compares the wrong two vectors.
    func testSimilarityIsHighestWithinReferenceFamily() async throws {
        let (data, descriptor, families) = try await makeThreeFamilyFixture()
        let settings = DiffractionEmbedding.Settings(
            binnedSize: 16, components: 8, groups: 3, seed: 42
        )
        let computed = try await DiffractionEmbedding.compute(
            data: data, descriptor: descriptor, settings: settings,
            cancellation: nil, progress: nil
        )
        let result = try XCTUnwrap(computed)

        let referencePosition = 7   // family 7 % 3 == 1; neither the first nor the last index.
        let similarity = DiffractionEmbedding.similarity(to: referencePosition, in: result)
        XCTAssertEqual(similarity.count, families.count)
        XCTAssertEqual(similarity[referencePosition], 1, accuracy: 1e-4, "self-similarity must be exactly 1")

        let referenceFamily = families[referencePosition]
        let sameFamily = (0..<families.count).filter {
            $0 != referencePosition && families[$0] == referenceFamily
        }
        let otherFamily = (0..<families.count).filter { families[$0] != referenceFamily }
        let minSameFamily = try XCTUnwrap(sameFamily.map { similarity[$0] }.min())
        let maxOtherFamily = try XCTUnwrap(otherFamily.map { similarity[$0] }.max())
        XCTAssertGreaterThan(
            minSameFamily, maxOtherFamily,
            "every same-family position (min \(minSameFamily)) must be more "
            + "similar to the reference than every other-family position (max \(maxOtherFamily))"
        )
    }

    // MARK: - non-divisible binned size runs without crashing

    /// `detectorSize` (32) is not a multiple of `binnedSize` (5): the
    /// largest divisible region is 30×30 (box 6, 5 bins, offset 1 on each
    /// side), a genuinely non-trivial box size — not the degenerate
    /// box = 1 case a smaller mismatch (e.g. 32 vs. 24) would hit instead.
    /// Breaks under: `BinGeometry.compute` dividing by a bin count that can
    /// be zero when an axis is smaller than `binnedSize` (crash on THIS
    /// fixture it would not, since 32 > 5, but a fix that only special-cases
    /// axisSize < binnedSize without handling the general non-divisible case
    /// would still read/write outside the intended box here); or a centring
    /// offset that pushes a box past the pattern's `qy*qx` bounds, which
    /// would surface here as a non-finite value in `coordinates` or `mean`.
    func testNonDivisibleBinnedSizeRuns() async throws {
        let (data, descriptor, _) = try await makeThreeFamilyFixture()
        let settings = DiffractionEmbedding.Settings(
            binnedSize: 5, components: 4, groups: 3, seed: 7
        )
        let computed = try await DiffractionEmbedding.compute(
            data: data, descriptor: descriptor, settings: settings,
            cancellation: nil, progress: nil
        )
        let result = try XCTUnwrap(computed, "a non-divisible binnedSize must still produce a result")
        XCTAssertEqual(result.scanWidth, scanWidth)
        XCTAssertEqual(result.scanHeight, scanHeight)
        XCTAssertEqual(result.componentCount, 4)
        XCTAssertEqual(result.basis.count, result.componentCount * 5 * 5)
        XCTAssertEqual(result.mean.count, 5 * 5)
        XCTAssertTrue(result.coordinates.allSatisfy(\.isFinite), "no coordinate may be NaN/Inf")
        XCTAssertTrue(result.mean.allSatisfy(\.isFinite), "no mean-vector entry may be NaN/Inf")
        XCTAssertTrue(result.basis.allSatisfy(\.isFinite), "no basis entry may be NaN/Inf")
    }
}
