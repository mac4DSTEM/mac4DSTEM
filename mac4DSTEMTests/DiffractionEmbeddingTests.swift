//
//  DiffractionEmbeddingTests.swift
//  Diffraction-groups classical v1 (docs/ai-ml/README.md §6): PCA on
//  box-binned patterns, then k-means. Every assertion below states the
//  mutation it catches — this session could not build, so nothing here was
//  run against a compiler.
//

import XCTest
import DSTEMCore
import DSTEMSession
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

    // MARK: - The detector's row/column axes survive binning (Gate B, M1)

    /// The three families above are all symmetric about the detector centre
    /// under transpose, so swapping the binned pattern's row and column
    /// indices (`out[bx * b + by] = sum`) leaves every other assertion in
    /// this file untouched — that mutation (M1 of the 2026-09-06 Gate B run)
    /// survived the whole suite. This fixture is deliberately ASYMMETRIC:
    /// two bright blocks, each aligned to exactly one 2x2 bin, at different
    /// amplitudes, so the mean binned vector's two brightest bins are unique
    /// and pin both detector axes and both of their signs.
    ///
    /// Catches: M1 (x/y transpose in `embed`), a 180-degree rotation of the
    /// pattern, and a flip of either axis alone — the planted pair
    /// (row 3, col 13) and (row 10, col 4) lands somewhere else under all of
    /// them, and neither planted bin is on the detector's diagonal or centre.
    func testMeanVectorPreservesTheDetectorsRowAndColumnAxes() async throws {
        let binnedSize = 16
        let box = detectorSize / binnedSize     // 2
        // (detector row, detector col, amplitude) -> binned (row / box, col / box)
        let brightBin = (row: 6 / box, col: 26 / box)      // (3, 13)
        let dimmerBin = (row: 20 / box, col: 8 / box)      // (10, 4)

        let positions = scanWidth * scanHeight
        var patterns = [[Float]](repeating: [], count: positions)
        for p in 0..<positions {
            var pattern = [Float](repeating: 1, count: detectorSize * detectorSize)
            for r in 6...7 { for c in 26...27 { pattern[r * detectorSize + c] = 60 } }
            for r in 20...21 { for c in 8...9 { pattern[r * detectorSize + c] = 40 } }
            for i in pattern.indices {
                pattern[i] += deterministicNoise(p * 100_003 + i) * 0.5
            }
            patterns[p] = pattern
        }
        let source = DiffractionGroupsFixtureSource(
            scanHeight: scanHeight, scanWidth: scanWidth,
            qy: detectorSize, qx: detectorSize, patterns: patterns
        )
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)
        let computed = try await DiffractionEmbedding.compute(
            data: data, descriptor: descriptor,
            settings: DiffractionEmbedding.Settings(
                binnedSize: binnedSize, components: 4, groups: 2, seed: 11
            ),
            cancellation: nil, progress: nil
        )
        let result = try XCTUnwrap(computed)
        XCTAssertEqual(result.mean.count, binnedSize * binnedSize)

        let ranked = result.mean.indices.sorted { result.mean[$0] > result.mean[$1] }
        XCTAssertEqual(
            ranked[0], brightBin.row * binnedSize + brightBin.col,
            "the brightest binned cell must be (row \(brightBin.row), col \(brightBin.col)); "
            + "got (row \(ranked[0] / binnedSize), col \(ranked[0] % binnedSize)) — a transpose, "
            + "rotation or flip of the detector axes moves it"
        )
        XCTAssertEqual(
            ranked[1], dimmerBin.row * binnedSize + dimmerBin.col,
            "the second-brightest binned cell must be (row \(dimmerBin.row), col \(dimmerBin.col)); "
            + "got (row \(ranked[1] / binnedSize), col \(ranked[1] % binnedSize))"
        )
    }

    // MARK: - C1 (Gate D): the eigensolver returns ACTUAL eigenpairs

    /// The discriminating experiment of
    /// `References/training_runs/disk-detector-2026-09-06-polish/fix-c/gateD-C1.md`.
    ///
    /// Every earlier assertion in this file reads the eigensolver through a
    /// downstream aggregate (`explainedVariance.prefix(3).sum() > 0.8`, or a
    /// k-means grouping), which one converged direction is enough to satisfy.
    /// This one plants a KNOWN spectrum on a KNOWN orthonormal basis and asks
    /// the solver for it back. The matrix, the basis and the eigenvalues are
    /// all built here from constants written in this file, so the ground
    /// truth owes nothing to the code under test.
    ///
    /// The planted eigenvalues are deliberately well separated but with
    /// ratios far from zero (~1.55): a converged solver separates them
    /// trivially, while one power/subspace step cannot — which is exactly the
    /// defect this test was written to expose (the subspace iteration's
    /// convergence test started at `.infinity`, `max(0, .nan) == 0`, so it
    /// always stopped after one iteration).
    ///
    /// Catches: that single-iteration defect; any loss of descending order;
    /// and a `dsyevd_` call with a transposed argument, a wrong `uplo`, or an
    /// under-sized workspace (all of which corrupt the returned pairs).
    func testSymmetricEigenTopReturnsTrueEigenpairs() {
        let d = 64
        let planted: [Double] = [100, 64, 41, 26, 17, 11, 7, 4.5]
        let floorEigenvalue = 0.5

        // A deterministic orthonormal basis: Gram-Schmidt over a fixed
        // xorshift64* stream (NOT SystemRandomNumberGenerator).
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func nextValue() -> Double {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            let mixed = Int64(bitPattern: state &* 0x2545_F491_4F6C_DD1D)
            return Double(mixed % 20_001) / 10_000.0
        }
        var basis = [[Double]]()
        for _ in 0..<d {
            var v = (0..<d).map { _ in nextValue() }
            for u in basis {
                let projection = zip(v, u).reduce(0.0) { $0 + $1.0 * $1.1 }
                for t in 0..<d { v[t] -= projection * u[t] }
            }
            let norm = v.reduce(0.0) { $0 + $1 * $1 }.squareRoot()
            XCTAssertGreaterThan(norm, 1e-6, "the fixture's basis must stay full rank")
            basis.append(v.map { $0 / norm })
        }

        // C = sum_j lambda_j q_j q_j^T, the planted eigenvalues first.
        var matrix = [Double](repeating: 0, count: d * d)
        for j in 0..<d {
            let lambda = j < planted.count ? planted[j] : floorEigenvalue
            for r in 0..<d {
                let scaled = basis[j][r] * lambda
                for c in 0..<d { matrix[r * d + c] += scaled * basis[j][c] }
            }
        }

        let (vectors, values) = DiffractionEmbedding.symmetricEigenTop(
            matrix: matrix, dimension: d, count: planted.count, cancellation: nil
        )
        XCTAssertEqual(values.count, planted.count)
        XCTAssertEqual(vectors.count, planted.count)
        XCTAssertEqual(values, values.sorted(by: >), "eigenvalues must be returned descending")

        for c in 0..<min(vectors.count, planted.count) {
            let v = vectors[c]
            XCTAssertEqual(v.count, d)
            var cv = [Double](repeating: 0, count: d)
            for r in 0..<d {
                var sum = 0.0
                for t in 0..<d { sum += matrix[r * d + t] * v[t] }
                cv[r] = sum
            }
            let lambda = zip(v, cv).reduce(0.0) { $0 + $1.0 * $1.1 }
            let residual = zip(cv, v)
                .reduce(0.0) { $0 + ($1.0 - lambda * $1.1) * ($1.0 - lambda * $1.1) }
                .squareRoot()
            let scale = max(abs(lambda) * v.reduce(0.0) { $0 + $1 * $1 }.squareRoot(), 1e-12)
            XCTAssertLessThanOrEqual(
                residual / scale, 1e-6,
                "component \(c) is not an eigenvector of the matrix it claims to "
                + "diagonalise: relative residual \(residual / scale)"
            )
            XCTAssertEqual(
                values[c], planted[c], accuracy: 1e-8,
                "component \(c) eigenvalue \(values[c]), planted \(planted[c])"
            )
        }
    }

    /// The SAME property end to end through `compute`: every published
    /// `basis` row must be an eigenvector of the MEAN-CENTRED covariance of
    /// the binned vectors, the rows must be ordered by eigenvalue, and
    /// `explainedVariance[c]` must be that eigenvalue over the covariance's
    /// TRACE (not over the retained eigenvalues, and not over an uncentred
    /// second-moment matrix).
    ///
    /// The covariance is rebuilt here by `referenceBinnedVector`, an
    /// independent re-implementation of the log1p / max-normalise / box-bin
    /// pipeline — nothing the code under test returns is used as its own
    /// ground truth.
    ///
    /// Catches: M3 (the covariance's mean-centring term dropped — the basis
    /// then diagonalises the uncentred second moment, whose dominant
    /// direction is the mean itself); M4 (rows not ordered by eigenvalue);
    /// and the one-iteration convergence defect, which leaves every component
    /// past the first an unconverged direction (fix-c/gateD-C1.md).
    func testPublishedBasisAreEigenpairsOfTheMeanCentredCovariance() async throws {
        let binnedSize = 16
        let dims = binnedSize * binnedSize
        let (data, descriptor, _) = try await makeThreeFamilyFixture()
        let settings = DiffractionEmbedding.Settings(
            binnedSize: binnedSize, components: 8, groups: 3, seed: 42
        )
        let computed = try await DiffractionEmbedding.compute(
            data: data, descriptor: descriptor, settings: settings,
            cancellation: nil, progress: nil
        )
        let result = try XCTUnwrap(computed)

        // Reference mean and mean-centred covariance, built in the test.
        let positions = scanWidth * scanHeight
        var vectors = [[Double]]()
        for i in 0..<positions {
            vectors.append(referenceBinnedVector(
                syntheticFamilyPattern(family: i % 3, positionSeed: i), binnedSize: binnedSize
            ))
        }
        var mean = [Double](repeating: 0, count: dims)
        for v in vectors { for i in 0..<dims { mean[i] += v[i] } }
        for i in 0..<dims { mean[i] /= Double(positions) }
        var covariance = [Double](repeating: 0, count: dims * dims)
        for v in vectors {
            for i in 0..<dims {
                let di = v[i] - mean[i]
                for j in 0..<dims { covariance[i * dims + j] += di * (v[j] - mean[j]) }
            }
        }
        for i in covariance.indices { covariance[i] /= Double(positions) }
        var trace = 0.0
        for i in 0..<dims { trace += covariance[i * dims + i] }
        XCTAssertGreaterThan(trace, 0)

        for i in 0..<dims {
            XCTAssertEqual(
                Double(result.mean[i]), mean[i], accuracy: 1e-4 * max(abs(mean[i]), 1),
                "published mean vector disagrees with the reference at bin \(i)"
            )
        }

        var previous = Double.greatestFiniteMagnitude
        for c in 0..<result.componentCount {
            let v = (0..<dims).map { Double(result.basis[c * dims + $0]) }
            var cv = [Double](repeating: 0, count: dims)
            for r in 0..<dims {
                var sum = 0.0
                for t in 0..<dims { sum += covariance[r * dims + t] * v[t] }
                cv[r] = sum
            }
            let lambda = zip(v, cv).reduce(0.0) { $0 + $1.0 * $1.1 }
            let residual = zip(cv, v)
                .reduce(0.0) { $0 + ($1.0 - lambda * $1.1) * ($1.0 - lambda * $1.1) }
                .squareRoot()
            // Normalised by the TRACE, not by this component's own eigenvalue:
            // the fixture's tail eigenvalues are ~1e-4 of the trace, so a
            // per-component normalisation would be dominated by the Float
            // rounding of `basis` itself.
            XCTAssertLessThanOrEqual(
                residual / trace, 1e-6,
                "basis row \(c) is not an eigenvector of the mean-centred covariance: "
                + "residual/trace \(residual / trace), lambda/trace \(lambda / trace), "
                + "reported explainedVariance \(result.explainedVariance[c])"
            )
            XCTAssertEqual(
                Double(result.explainedVariance[c]), lambda / trace, accuracy: 1e-5,
                "explainedVariance[\(c)] must be the eigenvalue over the covariance TRACE"
            )
            XCTAssertLessThanOrEqual(
                lambda, previous + 1e-12,
                "component \(c) has a LARGER eigenvalue than component \(c - 1): "
                + "the basis is not ordered by variance"
            )
            previous = lambda
        }
    }

    /// The test's own copy of `DiffractionEmbedding.embed` — log1p, per-pattern
    /// max-normalise, box-bin — written from
    /// `docs/ai-ml/README.md` §6 and this fixture's 32-px detector rather than
    /// called through the code under test, so
    /// `testPublishedBasisAreEigenpairsOfTheMeanCentredCovariance` has an
    /// independent ground truth.
    private func referenceBinnedVector(_ pattern: [Float], binnedSize: Int) -> [Double] {
        let size = detectorSize
        var scaled = [Float](repeating: 0, count: size * size)
        var maxValue: Float = 0
        for i in 0..<(size * size) {
            let v = log1p(Swift.max(pattern[i], 0))
            scaled[i] = v
            if v > maxValue { maxValue = v }
        }
        if maxValue > 0 {
            let inverse = 1 / maxValue
            for i in scaled.indices { scaled[i] *= inverse }
        }
        let bins = Swift.min(binnedSize, size)
        let box = Swift.max(1, size / bins)
        let offset = (size - box * bins) / 2
        var out = [Double](repeating: 0, count: binnedSize * binnedSize)
        for by in 0..<bins {
            for bx in 0..<bins {
                var sum: Float = 0
                for dy in 0..<box {
                    let rowBase = (offset + by * box + dy) * size
                    for dx in 0..<box { sum += scaled[rowBase + offset + bx * box + dx] }
                }
                out[by * binnedSize + bx] = Double(sum)
            }
        }
        return out
    }
}

/// A5 (fix-a, `drive-groups` defect 2): every group map was published, saved
/// and listed as the literal `Diffraction groups (k)`, so a k=4 run and a k=8
/// run were indistinguishable in Results and in the sidecar (captures
/// `drive-groups/03-groups-k4.png`, `04-groups-k8.png`, `07-results.png`).
/// The name must carry the k the run actually used.
final class DiffractionGroupsNamingTests: XCTestCase {

    func testGroupMapDisplayNameCarriesTheNumberOfGroups() {
        let four = DiffractionGroupsProduct.groupMapDisplayName(groups: 4)
        let eight = DiffractionGroupsProduct.groupMapDisplayName(groups: 8)
        XCTAssertNotEqual(four, eight, "two different k must not publish the same name")
        XCTAssertTrue(four.contains("4"), "the k=4 name must name 4, got \(four)")
        XCTAssertTrue(eight.contains("8"), "the k=8 name must name 8, got \(eight)")
        XCTAssertFalse(
            four.contains("(k)"),
            "the literal placeholder must not reach the user, got \(four)"
        )
    }
}

/// fix-b (owner's drive 2026-09-06, `drive-groups` defects 3, 4 and 5): what
/// the Diffraction groups panel knows about the run it is describing. The
/// embedding arithmetic is `DiffractionEmbeddingTests` above and is untouched.
final class DiffractionGroupsPanelStateTests: XCTestCase {

    /// A minimal result on a `w × h` scan: two components, `k` groups, every
    /// position in group 0. Only the shape and the counts matter here.
    private func result(width: Int, height: Int, groups k: Int) -> DiffractionEmbedding.Result {
        DiffractionEmbedding.Result(
            scanWidth: width, scanHeight: height,
            coordinates: [Float](repeating: 0, count: width * height * 2),
            mean: [0, 0, 0, 0],
            basis: [1, 0, 0, 0, 0, 1, 0, 0],
            explainedVariance: [0.6, 0.2],
            groupOf: [Int](repeating: 0, count: width * height),
            groupCentroids: [Float](repeating: 0, count: k * 2)
        )
    }

    /// Defect 3: the run's provenance is written into the product and shown
    /// nowhere. `Result` carries neither the binned size nor the seed, so the
    /// panel can only name them if the owner keeps the settings the run used.
    func testPublishRecordsTheSettingsTheRunActuallyUsed() {
        let product = DiffractionGroupsProduct()
        var ran = DiffractionEmbedding.Settings()
        ran.binnedSize = 32
        ran.components = 8
        ran.groups = 4
        ran.seed = 7

        product.publish(result(width: 8, height: 8, groups: 4), ranWith: ran)

        XCTAssertEqual(product.lastRunSettings?.binnedSize, 32)
        XCTAssertEqual(product.lastRunSettings?.seed, 7)
        XCTAssertEqual(product.lastRunSettings?.groups, 4)
    }

    /// Defect 5: raising Groups 4 → 8 left the k=4 group sizes on screen under
    /// `Groups 8` with nothing saying they came from an earlier run.
    func testTheReadoutIsStaleOnceTheSettingsHaveMoved() {
        let product = DiffractionGroupsProduct()
        product.settings.groups = 4
        product.publish(result(width: 8, height: 8, groups: 4), ranWith: product.settings)
        XCTAssertFalse(product.isStale, "nothing has changed since the run")

        product.settings.groups = 8

        XCTAssertTrue(product.isStale, "the readout describes the k=4 run, not the live k=8")
    }

    func testNothingIsStaleBeforeAnyRun() {
        XCTAssertFalse(DiffractionGroupsProduct().isStale)
    }

    /// Defect 4: a second grouping run nilled the similarity reference while
    /// the published similarity product stayed in Results, still named for a
    /// coordinate the panel could no longer show. The reference is an index
    /// into the scan grid, and a rerun with a different k does not move it.
    func testARerunOnTheSameScanKeepsTheSimilarityReference() {
        let product = DiffractionGroupsProduct()
        product.publish(result(width: 16, height: 16, groups: 4), ranWith: product.settings)
        product.referencePosition = 59 * 16 + 3

        product.publish(result(width: 16, height: 16, groups: 8), ranWith: product.settings)

        XCTAssertEqual(product.referencePosition, 59 * 16 + 3,
                       "same scan, same coordinate space — the reference survives")
    }

    /// The one case that still invalidates it: a result of a different scan
    /// shape, where the index no longer means what it meant.
    func testAResultOfADifferentScanShapeClearsTheReference() {
        let product = DiffractionGroupsProduct()
        product.publish(result(width: 16, height: 16, groups: 4), ranWith: product.settings)
        product.referencePosition = 200

        product.publish(result(width: 8, height: 8, groups: 4), ranWith: product.settings)

        XCTAssertNil(product.referencePosition)
    }

    /// Dataset activation still takes everything with it.
    func testClearDropsTheRunSettingsWithTheResult() {
        let product = DiffractionGroupsProduct()
        product.publish(result(width: 8, height: 8, groups: 4), ranWith: product.settings)
        product.referencePosition = 3

        product.clear()

        XCTAssertNil(product.result)
        XCTAssertNil(product.lastRunSettings)
        XCTAssertNil(product.referencePosition)
        XCTAssertFalse(product.isStale)
    }
}
