//
//  DiffractionEmbedding.swift
//  Role: the classical v1 baseline ../_archive/mac4DSTEM/docs/ai-ml/README.md §6 calls for before
//        any learned encoder — PCA on box-binned diffraction patterns, then
//        k-means on the resulting coordinates. Streams the cube exactly like
//        VirtualDetector/TiledDiskDetection: bounded scan-row tiles via
//        TilePrefetcher, cooperative cancellation, fractional progress.
//
//  Covariance and eigen decomposition: CuboEmbedding's `PCACovarianceAccumulator` (streamed
//  per scan tile, Chan/Welford in Double) and `PCA.fit(covariance:count:mean:components:)`
//  (LAPACK `dsyevd_` underneath, exact and deterministic). They replaced the app's own
//  sum-of-outer-products accumulator and `symmetricEigenTop` on 2026-10-21 (CuboKit 0.6.0).
//  The hand-written subspace iteration used until 2026-09-06 was WRONG (its convergence test
//  broke after one iteration, so components past the first came back 20-36 % low); diagnosis:
//  ../_archive/mac4DSTEM/docs/archive/v3/ai-gateD-2026-09-06/gateD-C1.md.
//
//  DEVIATION (py4DSTEM parity, PCA): py4DSTEM's classification featurisation
//  — References/py4DSTEM-dev/py4DSTEM/process/classification/featurization.py
//  :366-373 — calls sklearn's `PCA`, i.e. an exact, mean-centred,
//  variance-ordered decomposition (LAPACK underneath). The kit's PCA on the
//  mean-centred covariance agrees with that (scikit-learn 1.4.2, 2e-12 on components); the subspace iteration did not.
//  DEVIATION (component sign): the app's former LAPACK call left each axis with an arbitrary sign. The kit
//  fits from a covariance, which has no scores for scikit-learn's `svd_flip`, so each axis takes the sign that makes
//  its largest-magnitude entry positive (deterministic). Basis and coordinates flip together; groups, variances and
//  the mean are unchanged.
//  DEVIATION (no upstream counterpart, preprocessing): the per-pattern
//  representation here — log1p, per-pattern max-normalisation, then box
//  binning to binnedSize² — has NO py4DSTEM equivalent. py4DSTEM featurises
//  user-supplied maps (Bragg-peak or virtual images), never raw binned
//  diffraction patterns, so there is no upstream number to check this
//  representation against; only the PCA that follows it is comparable.
//
//  Memory: forming the d×d covariance (d = binnedSize², ≤1024) is a single
//  streaming pass that also decides whether to CACHE every pattern's binned
//  vector for the second (projection) pass — only when
//  positions × d × 4 bytes ≤ 512 MB. Above that budget, projection re-reads
//  the cube tile by tile exactly like the first pass, recomputing each
//  pattern's binned vector rather than caching it; both paths compute the
//  identical vector because binning/normalisation is a pure per-pattern
//  function, so the two paths agree bit-for-bit modulo the covariance's own
//  numerical accumulation order.
//

import CuboEmbedding
import Foundation

/// CuboEmbedding's error, named apart from `DiffractionEmbedding.EmbeddingError` inside the enum.
private typealias KitEmbeddingError = EmbeddingError

package nonisolated enum DiffractionEmbedding {

    package struct Settings: Sendable, Equatable {
        /// Each pattern is box-binned to binnedSize × binnedSize after log1p
        /// scaling and per-pattern max-normalisation.
        package var binnedSize: Int
        /// Principal components retained (may be clamped down for a small or
        /// low-rank dataset — see `Result.componentCount`).
        package var components: Int
        /// k-means group count (may be clamped down when the scan has fewer
        /// positions than requested groups — see `Result.groupCount`).
        package var groups: Int
        /// Deterministic seed for the k-means++ seeding. It no longer
        /// reaches the PCA: `dsyevd_` is an exact decomposition with no
        /// random start (2026-09-06).
        package var seed: UInt64

        package nonisolated init(
            binnedSize: Int = 16, components: Int = 8, groups: Int = 6, seed: UInt64 = 1
        ) {
            self.binnedSize = binnedSize
            self.components = components
            self.groups = groups
            self.seed = seed
        }
    }

    package nonisolated struct Result: Sendable {
        package let scanWidth: Int
        package let scanHeight: Int
        /// positions × componentCount, row-major; position index is
        /// `y * scanWidth + x`, the same order as every FloatImage/scan
        /// product in Core.
        package let coordinates: [Float]
        /// The mean binned vector, length binnedSize² (the SAME binnedSize²
        /// the run was configured with — `basis.count / componentCount`).
        package let mean: [Float]
        /// componentCount × binnedSize², row-major: one principal axis per
        /// row, descending by eigenvalue.
        package let basis: [Float]
        /// Fraction (0...1, not percent) of the total binned-vector variance
        /// each component explains, same order as `basis`'s rows.
        /// Provenance: eigenvalue ÷ the TRACE of the full mean-centred
        /// binned-vector covariance — the denominator is the total variance
        /// of the d = binnedSize² dimensional data, NOT the sum of the
        /// retained eigenvalues, so these fractions sum to less than 1
        /// whenever the retained components do not span the data.
        /// The eigenvalues are exact (LAPACK `dsyevd_`, see the file header).
        package let explainedVariance: [Float]
        /// Per position, 0..<groupCount.
        package let groupOf: [Int]
        /// groupCount × componentCount, row-major.
        package let groupCentroids: [Float]

        package nonisolated init(
            scanWidth: Int, scanHeight: Int, coordinates: [Float], mean: [Float],
            basis: [Float], explainedVariance: [Float], groupOf: [Int], groupCentroids: [Float]
        ) {
            self.scanWidth = scanWidth
            self.scanHeight = scanHeight
            self.coordinates = coordinates
            self.mean = mean
            self.basis = basis
            self.explainedVariance = explainedVariance
            self.groupOf = groupOf
            self.groupCentroids = groupCentroids
        }

        /// The ACTUAL component count this run used, which may be smaller
        /// than `Settings.components` was asked for (clamped to the binned
        /// dimension and to positions − 1).
        package nonisolated var componentCount: Int { explainedVariance.count }

        /// The ACTUAL group count this run used, which may be smaller than
        /// `Settings.groups` was asked for (clamped to the position count).
        package nonisolated var groupCount: Int {
            componentCount > 0 ? groupCentroids.count / componentCount : 0
        }
    }

    /// Why a full-scan embedding over a streamed cube failed. Nil is
    /// reserved for cancellation (mirrors `DiskDetection.FullScanError`'s
    /// contract) — every other failure is typed and attributed here.
    package nonisolated enum EmbeddingError: Error, CustomStringConvertible, LocalizedError {
        case tileRead(rows: Range<Int>, underlying: Error)
        case invalidDataset(String)

        package var description: String {
            switch self {
            case .tileRead(let rows, let underlying):
                return "Reading scan rows \(rows.lowerBound)–\(rows.upperBound - 1) "
                    + "from the dataset failed: \(underlying.localizedDescription)"
            case .invalidDataset(let message):
                return message
            }
        }
        package var errorDescription: String? { description }
    }

    // MARK: - compute

    /// The cache ceiling the app runs with: 512 MB of binned Float vectors.
    package static let defaultCacheBudgetBytes = 512 * 1024 * 1024

    /// Stream the cube once (twice only when the memory budget refuses
    /// caching), embed every pattern, PCA the embeddings, then k-means the
    /// coordinates. Returns nil ONLY on cancellation.
    @concurrent
    package static func compute(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        settings: Settings,
        maximumTileRows: Int? = nil,
        cacheBudgetBytes: Int = defaultCacheBudgetBytes,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> Result? {
        guard d.is4D, d.rx > 0, d.ry > 0, d.qy > 0, d.qx > 0 else {
            throw EmbeddingError.invalidDataset(
                "The dataset has no scan positions or no detector pixels.")
        }
        let binnedSize = max(1, settings.binnedSize)
        let dims = binnedSize * binnedSize
        let totalPositions = d.ry * d.rx
        let componentCount = max(1, min(settings.components, dims, max(1, totalPositions - 1)))
        let groupCount = max(1, min(settings.groups, totalPositions))

        guard cancellation?.isCancelled != true else { return nil }

        // Decide the memory strategy up front: cache every binned vector
        // only when doing so stays at or under `cacheBudgetBytes` (512 MB by
        // default), else recompute them in a second streaming pass rather
        // than hold an unbounded array. The budget is a parameter so a test
        // can reach the two-pass path with a small cube; the app never
        // passes it.
        //
        // The two-pass path is the memory bound, not an optimisation, and is
        // not deletable: past the budget (524 288 positions at the default
        // 16 x 16 binning) there is nowhere to put the vectors. It costs one
        // extra read of the cube: on a generated 100 x 100 x 128 x 128 cube
        // (source generation included), -O, 3 runs each, 25.6-26.1 s cached
        // against 51.2-51.5 s two-pass, coordinates and groups identical
        // (S17, 2026-09-30; reproduce with `testProfileSingleVersusTwoPass`
        // in DiffractionEmbeddingTwoPassTests).
        let candidateCacheBytes = totalPositions.multipliedReportingOverflow(by: dims)
        let cacheEverything = !candidateCacheBytes.overflow
            && candidateCacheBytes.partialValue <= cacheBudgetBytes / MemoryLayout<Float>.stride

        var cachedVectors = cacheEverything
            ? [Float](repeating: 0, count: totalPositions * dims) : []

        var accumulator = try PCACovarianceAccumulator(columns: dims)

        let rowsPerTile = await data.scanTileRows(maximumRows: maximumTileRows)
        let ranges: [Range<Int>] = stride(from: 0, to: d.ry, by: rowsPerTile).map {
            $0..<min(d.ry, $0 + rowsPerTile)
        }

        // Progress budget across the phases that follow. Eigen decomposition
        // and k-means report no interior progress (both are fast relative to
        // streaming the cube), so each simply advances the running total by
        // its fixed slice when it finishes.
        let statsWeight = cacheEverything ? 0.80 : 0.50
        let eigenWeight = 0.05
        let projectWeight = cacheEverything ? 0.10 : 0.40
        // (k-means gets whatever remains before the final progress?(1).)

        var prefetcher = TilePrefetcher(data: data)
        var processed = 0
        for (index, range) in ranges.enumerated() {
            guard cancellation?.isCancelled != true else { prefetcher.cancel(); return nil }
            let tile: FourDScanTile
            do {
                tile = try await prefetcher.tile(
                    for: range,
                    prefetching: index + 1 < ranges.count ? ranges[index + 1] : nil
                )
            } catch {
                prefetcher.cancel()
                guard cancellation?.isCancelled != true else { return nil }
                throw EmbeddingError.tileRead(rows: range, underlying: error)
            }
            guard cancellation?.isCancelled != true else { prefetcher.cancel(); return nil }
            let block = try binnedBlock(tile: tile, qy: d.qy, qx: d.qx, binnedSize: binnedSize)
            let positionsInTile = range.count * d.rx
            if cacheEverything {
                let dst = range.lowerBound * d.rx * dims
                cachedVectors.replaceSubrange(dst..<(dst + block.count), with: block)
            }
            do {
                try accumulator.add(block, rows: positionsInTile)
            } catch KitEmbeddingError.nonFinite {
                throw nonFiniteRefusal
            }
            processed += positionsInTile
            progress?(statsWeight * Double(processed) / Double(max(1, totalPositions)))
        }
        guard cancellation?.isCancelled != true else { prefetcher.cancel(); return nil }
        guard processed == totalPositions else {
            throw EmbeddingError.invalidDataset(
                "Streamed \(processed) of \(totalPositions) scan positions.")
        }
        progress?(statsWeight)

        // Non-finite guard (Gate D, 2026-09-11). A NaN or +Inf detector pixel reaches the binned vectors;
        // -Inf alone is clamped by the binning. LAPACK does not reject a NaN covariance (`dsyevd_` returned
        // eigenvalues [1, nan x 7] at the shipped dims 256), so the kit's accumulator refuses the block
        // (`nonFinite`, caught above) before any fit, and the typed error is what the caller handles.

        guard cancellation?.isCancelled != true else { return nil }
        let pca: PCAResult
        do {
            if totalPositions >= 2 {
                pca = try PCA.fit(accumulator, components: componentCount)
            } else {
                // One position: no spread. A zero covariance gives the kit's identity axes and zero variance
                // (count 2 only satisfies its two-row precondition; it scales nothing the app reads).
                pca = try PCA.fit(covariance: [Double](repeating: 0, count: dims * dims), count: 2,
                                  mean: accumulator.mean, components: componentCount)
            }
        } catch {
            throw EmbeddingError.invalidDataset("Could not find any principal components.")
        }
        guard cancellation?.isCancelled != true else { return nil }
        let actualComponents = pca.componentCount
        let basis = pca.components.map(Float.init)
        // The kit's ratio is each eigenvalue over the covariance trace (negative round-off clamped at 0), the
        // contract on `explainedVariance`: 0...1, of the TOTAL variance, not of the retained eigenvalues.
        let explainedVariance = pca.explainedVarianceRatio.map(Float.init)
        let meanFloat = pca.mean.map(Float.init)
        progress?(statsWeight + eigenWeight)

        // Projection: from the cache in one pass, or a second cube read.
        var coordinates = [Float](repeating: 0, count: totalPositions * actualComponents)
        if cacheEverything {
            cachedVectors.withUnsafeBufferPointer { cache in
                basis.withUnsafeBufferPointer { basisBuf in
                    meanFloat.withUnsafeBufferPointer { meanBuf in
                        coordinates.withUnsafeMutableBufferPointer { outBuf in
                            var centred = [Float](repeating: 0, count: dims)
                            centred.withUnsafeMutableBufferPointer { cen in
                                for pos in 0..<totalPositions {
                                    PCA.project(cache.baseAddress! + pos * dims, mean: meanBuf.baseAddress!,
                                                basis: basisBuf.baseAddress!, dims: dims,
                                                components: actualComponents, centred: cen.baseAddress!,
                                                into: outBuf.baseAddress! + pos * actualComponents)
                                }
                            }
                        }
                    }
                }
            }
            guard cancellation?.isCancelled != true else { return nil }
            progress?(statsWeight + eigenWeight + projectWeight)
        } else {
            var prefetcher2 = TilePrefetcher(data: data)
            var processed2 = 0
            var centred2 = [Float](repeating: 0, count: dims)
            for (index, range) in ranges.enumerated() {
                guard cancellation?.isCancelled != true else { prefetcher2.cancel(); return nil }
                let tile: FourDScanTile
                do {
                    tile = try await prefetcher2.tile(
                        for: range,
                        prefetching: index + 1 < ranges.count ? ranges[index + 1] : nil
                    )
                } catch {
                    prefetcher2.cancel()
                    guard cancellation?.isCancelled != true else { return nil }
                    throw EmbeddingError.tileRead(rows: range, underlying: error)
                }
                guard cancellation?.isCancelled != true else { prefetcher2.cancel(); return nil }
                let block = try binnedBlock(tile: tile, qy: d.qy, qx: d.qx, binnedSize: binnedSize)
                let positionsInTile = range.count * d.rx
                let firstPosition = range.lowerBound * d.rx
                block.withUnsafeBufferPointer { v in
                    meanFloat.withUnsafeBufferPointer { m in
                        basis.withUnsafeBufferPointer { b in
                            centred2.withUnsafeMutableBufferPointer { cen in
                                coordinates.withUnsafeMutableBufferPointer { out in
                                    for local in 0..<positionsInTile {
                                        PCA.project(v.baseAddress! + local * dims, mean: m.baseAddress!,
                                                    basis: b.baseAddress!, dims: dims, components: actualComponents,
                                                    centred: cen.baseAddress!,
                                                    into: out.baseAddress! + (firstPosition + local) * actualComponents)
                                    }
                                }
                            }
                        }
                    }
                }
                processed2 += positionsInTile
                progress?(statsWeight + eigenWeight
                          + projectWeight * Double(processed2) / Double(max(1, totalPositions)))
            }
            guard cancellation?.isCancelled != true else { return nil }
        }

        guard cancellation?.isCancelled != true else { return nil }
        let groupOf: [Int], centroids: [Float]
        do {
            (groupOf, centroids) = try kMeans(
                coordinates: coordinates, positions: totalPositions, dimension: actualComponents,
                requestedGroups: groupCount, seed: settings.seed, cancellation: cancellation)
        } catch is CancellationError {
            return nil
        }
        guard cancellation?.isCancelled != true else { return nil }
        progress?(1)

        return Result(
            scanWidth: d.rx, scanHeight: d.ry, coordinates: coordinates, mean: meanFloat,
            basis: basis, explainedVariance: explainedVariance,
            groupOf: groupOf, groupCentroids: centroids
        )
    }

    // MARK: - similarity / groupMap

    /// Cosine similarity of every position's coordinates to `position`'s, in
    /// [-1, 1]. A zero-length coordinate vector (degenerate embedding) is
    /// defined as similarity 0 to everything but itself (1), rather than an
    /// undefined 0/0.
    package static func similarity(to position: Int, in result: Result) -> [Float] {
        let k = result.componentCount
        let totalPositions = result.scanWidth * result.scanHeight
        guard k > 0, totalPositions > 0, position >= 0, position < totalPositions,
              result.coordinates.count == totalPositions * k
        else { return [Float](repeating: 0, count: max(0, totalPositions)) }

        let refBase = position * k
        var refNormSq: Float = 0
        for i in 0..<k { refNormSq += result.coordinates[refBase + i] * result.coordinates[refBase + i] }
        let refNorm = sqrt(refNormSq)

        var output = [Float](repeating: 0, count: totalPositions)
        for p in 0..<totalPositions {
            if p == position { output[p] = 1; continue }
            let base = p * k
            var dot: Float = 0
            var normSq: Float = 0
            for i in 0..<k {
                let value = result.coordinates[base + i]
                dot += value * result.coordinates[refBase + i]
                normSq += value * value
            }
            let norm = sqrt(normSq)
            guard refNorm > 0, norm > 0 else { output[p] = 0; continue }
            output[p] = min(1, max(-1, dot / (refNorm * norm)))
        }
        return output
    }

    /// Group index per pixel, in scan order — a categorical map, not a
    /// quantitative one (the caller is expected to record that in
    /// provenance, `ProductQuantitativeStatus.categorical`).
    package static func groupMap(_ result: Result) -> FloatImage {
        FloatImage(width: result.scanWidth, height: result.scanHeight,
                   pixels: result.groupOf.map(Float.init))
    }

    // MARK: - Binning

    /// The refusal for a dataset with NaN or +Inf detector values.
    private static let nonFiniteRefusal = EmbeddingError.invalidDataset(
        "This dataset has non-finite detector values, so a diffraction "
        + "embedding cannot be computed. Preprocess or mask them first.")

    /// log1p-scale, per-pattern max-normalise and box-bin every pattern of a scan tile into `binnedSize²`
    /// vectors (positions x binnedSize², row-major, scan order): CuboEmbedding's
    /// `DiffractionFeatures.binnedVector` on its vDSP path (finite patterns; NaN and ±Inf take the kit's
    /// scalar loop, which keeps NaN and clamps -Inf to 0). The py4DSTEM parity harness
    /// (`embedding-pca-parity` (a retired harness; the kit's parity tests hold it)) calls the same function, so both sides see the same matrix.
    private static func binnedBlock(
        tile: FourDScanTile, qy: Int, qx: Int, binnedSize: Int
    ) throws -> [Float] {
        let patternSize = qy * qx
        let positions = tile.pixels.count / max(1, patternSize)
        let dims = binnedSize * binnedSize
        var block = [Float](repeating: 0, count: positions * dims)
        try tile.pixels.withUnsafeBufferPointer { buf in
            for p in 0..<positions {
                let pattern = UnsafeBufferPointer(rebasing: buf[(p * patternSize)..<((p + 1) * patternSize)])
                let v = try DiffractionFeatures.binnedVector(
                    pattern: pattern, rows: qy, columns: qx, binnedSize: binnedSize, implementation: .accelerate)
                block.replaceSubrange((p * dims)..<((p + 1) * dims), with: v)
            }
        }
        return block
    }

    // MARK: - k-means

    /// k-means++ seeded Lloyd's algorithm, deterministic given `seed`: CuboEmbedding's
    /// `KMeans.fitSeeded`, pinned to this app's former implementation (splitmix64 seeding
    /// from `seed + 0x5A17`, at most 50 passes, an empty cluster re-seeded at the point
    /// farthest from its own pre-update centroid). Cancellation is asked inside the fit
    /// (`CancellationError`, which `compute` turns into nil).
    /// `package` so a Gate D fixture can hand it non-finite input: that throws
    /// `invalidDataset`. `compute` refuses non-finite data upstream, so this is unreachable through the public path.
    package static func kMeans(
        coordinates: [Float], positions: Int, dimension: Int, requestedGroups: Int,
        seed: UInt64, cancellation: AnalysisCancellationToken?
    ) throws -> (assignment: [Int], centroids: [Float]) {
        guard positions > 0, dimension > 0 else { return ([], []) }
        do {
            let fit = try KMeans.fitSeeded(
                coordinates.map(Double.init), rows: positions, columns: dimension,
                groups: requestedGroups, seed: seed, isCancelled: { cancellation?.isCancelled == true })
            return (fit.labels, fit.centroids.map(Float.init))
        } catch KitEmbeddingError.nonFinite {
            throw EmbeddingError.invalidDataset("The embedding coordinates are not finite, so they cannot be clustered.")
        }
    }
}
