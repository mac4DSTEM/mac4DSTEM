//
//  DiffractionEmbedding.swift
//  Role: the classical v1 baseline docs/ai-ml/README.md §6 calls for before
//        any learned encoder — PCA on box-binned diffraction patterns, then
//        k-means on the resulting coordinates. Streams the cube exactly like
//        VirtualDetector/TiledDiskDetection: bounded scan-row tiles via
//        TilePrefetcher, cooperative cancellation, fractional progress.
//
//  Eigen decomposition: Accelerate's LAPACK `dsyevd_` (divide-and-conquer,
//  real symmetric), replacing the hand-written subspace iteration this file
//  used until 2026-09-06. That earlier revision justified avoiding LAPACK by
//  saying there was no build available to verify the Fortran-ABI boundary.
//  The reason no longer holds — the branch builds — and the hand-written
//  loop was WRONG: its convergence test started `previousValues` at
//  `.infinity`, so `abs(v - .infinity) / .infinity` is NaN, `max(0, .nan)`
//  is 0 in Swift, and the loop broke after exactly ONE subspace iteration on
//  every input. Everything past the dominant direction was an unconverged
//  Ritz pair, and the reported explained variance for those components ran
//  20-36 % low. Diagnosis, refutation and the discriminating fixture:
//  References/training_runs/disk-detector-2026-09-06-polish/fix-c/gateD-C1.md.
//
//  `dsyevd_` computes the FULL spectrum of the d×d covariance (d = binnedSize²,
//  ≤ 1024) exactly and deterministically; `symmetricEigenTop` keeps the top
//  `components` pairs in descending eigenvalue order. The matrix is
//  symmetric, so the row-major Swift buffer already IS the column-major
//  Fortran matrix LAPACK expects and no transpose is needed; on return,
//  eigenvector j is the contiguous slice a[j*d ..< (j+1)*d]. The workspace is
//  sized by LAPACK's own query (lwork = liwork = -1) rather than a guessed
//  constant. The non-deprecated declarations (`lapack.h`, `__LAPACK_int`)
//  are behind `-DACCELERATE_NEW_LAPACK`, set in Package.swift's DSTEMCore
//  swiftSettings and in the Xcode project's OTHER_SWIFT_FLAGS.
//
//  DEVIATION (py4DSTEM parity, PCA): py4DSTEM's classification featurisation
//  — References/py4DSTEM-dev/py4DSTEM/process/classification/featurization.py
//  :366-373 — calls sklearn's `PCA`, i.e. an exact, mean-centred,
//  variance-ordered decomposition (LAPACK underneath). `dsyevd_` on the
//  mean-centred covariance agrees with that; the subspace iteration it
//  replaced did not.
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

import Accelerate
import Foundation

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

    /// Stream the cube once (twice only when the memory budget refuses
    /// caching), embed every pattern, PCA the embeddings, then k-means the
    /// coordinates. Returns nil ONLY on cancellation.
    package static func compute(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        settings: Settings,
        maximumTileRows: Int? = nil,
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
        let geometry = BinGeometry.compute(qy: d.qy, qx: d.qx, binnedSize: binnedSize)
        let componentCount = max(1, min(settings.components, dims, max(1, totalPositions - 1)))
        let groupCount = max(1, min(settings.groups, totalPositions))

        guard cancellation?.isCancelled != true else { return nil }

        // Decide the memory strategy up front: cache every binned vector
        // only when doing so stays at or under 512 MB, else recompute them
        // in a second streaming pass rather than hold an unbounded array.
        let cacheBudgetBytes = 512 * 1024 * 1024
        let candidateCacheBytes = totalPositions.multipliedReportingOverflow(by: dims)
        let cacheEverything = !candidateCacheBytes.overflow
            && candidateCacheBytes.partialValue <= cacheBudgetBytes / MemoryLayout<Float>.stride

        var cachedVectors = cacheEverything
            ? [Float](repeating: 0, count: totalPositions * dims) : []

        var sumVec = [Double](repeating: 0, count: dims)
        var sumOuter = [Double](repeating: 0, count: dims * dims)

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
            let patternSize = d.qy * d.qx
            for localRow in 0..<range.count {
                let globalY = range.lowerBound + localRow
                for x in 0..<d.rx {
                    let posIndex = globalY * d.rx + x
                    let base = (localRow * d.rx + x) * patternSize
                    let vector = embed(
                        pixels: tile.pixels, base: base, qy: d.qy, qx: d.qx,
                        geometry: geometry, binnedSize: binnedSize
                    )
                    if cacheEverything {
                        let dst = posIndex * dims
                        for i in 0..<dims { cachedVectors[dst + i] = vector[i] }
                    }
                    accumulate(vector, dims: dims, sumVec: &sumVec, sumOuter: &sumOuter)
                    processed += 1
                }
            }
            progress?(statsWeight * Double(processed) / Double(max(1, totalPositions)))
        }
        guard cancellation?.isCancelled != true else { prefetcher.cancel(); return nil }
        guard processed == totalPositions else {
            throw EmbeddingError.invalidDataset(
                "Streamed \(processed) of \(totalPositions) scan positions.")
        }
        progress?(statsWeight)

        // Mean and covariance in double precision.
        let n = Double(totalPositions)
        var mean = [Double](repeating: 0, count: dims)
        for i in 0..<dims { mean[i] = sumVec[i] / n }
        var covariance = [Double](repeating: 0, count: dims * dims)
        for i in 0..<dims {
            let mi = mean[i]
            for j in 0..<dims {
                covariance[i * dims + j] = sumOuter[i * dims + j] / n - mi * mean[j]
            }
        }
        var totalVariance = 0.0
        for i in 0..<dims { totalVariance += covariance[i * dims + i] }

        guard cancellation?.isCancelled != true else { return nil }
        let (eigenvectors, eigenvalues) = symmetricEigenTop(
            matrix: covariance, dimension: dims, count: componentCount,
            cancellation: cancellation
        )
        guard cancellation?.isCancelled != true else { return nil }
        let actualComponents = eigenvectors.count
        guard actualComponents > 0 else {
            throw EmbeddingError.invalidDataset("Could not find any principal components.")
        }

        var basis = [Float](repeating: 0, count: actualComponents * dims)
        for c in 0..<actualComponents {
            for i in 0..<dims { basis[c * dims + i] = Float(eigenvectors[c][i]) }
        }
        var explainedVariance = [Float](repeating: 0, count: actualComponents)
        for c in 0..<actualComponents {
            explainedVariance[c] = totalVariance > 0 ? Float(eigenvalues[c] / totalVariance) : 0
        }
        let meanFloat = mean.map(Float.init)
        progress?(statsWeight + eigenWeight)

        // Projection: from the cache in one pass, or a second cube read.
        var coordinates = [Float](repeating: 0, count: totalPositions * actualComponents)
        if cacheEverything {
            cachedVectors.withUnsafeBufferPointer { cache in
                basis.withUnsafeBufferPointer { basisBuf in
                    meanFloat.withUnsafeBufferPointer { meanBuf in
                        coordinates.withUnsafeMutableBufferPointer { outBuf in
                            for pos in 0..<totalPositions {
                                let vecBase = pos * dims
                                for c in 0..<actualComponents {
                                    let rowBase = c * dims
                                    var dot: Float = 0
                                    for i in 0..<dims {
                                        dot += (cache[vecBase + i] - meanBuf[i]) * basisBuf[rowBase + i]
                                    }
                                    outBuf[pos * actualComponents + c] = dot
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
                let patternSize = d.qy * d.qx
                for localRow in 0..<range.count {
                    let globalY = range.lowerBound + localRow
                    for x in 0..<d.rx {
                        let posIndex = globalY * d.rx + x
                        let base = (localRow * d.rx + x) * patternSize
                        let vector = embed(
                            pixels: tile.pixels, base: base, qy: d.qy, qx: d.qx,
                            geometry: geometry, binnedSize: binnedSize
                        )
                        for c in 0..<actualComponents {
                            let rowBase = c * dims
                            var dot: Float = 0
                            for i in 0..<dims { dot += (vector[i] - meanFloat[i]) * basis[rowBase + i] }
                            coordinates[posIndex * actualComponents + c] = dot
                        }
                        processed2 += 1
                    }
                }
                progress?(statsWeight + eigenWeight
                          + projectWeight * Double(processed2) / Double(max(1, totalPositions)))
            }
            guard cancellation?.isCancelled != true else { return nil }
        }

        guard cancellation?.isCancelled != true else { return nil }
        let (groupOf, centroids) = kMeans(
            coordinates: coordinates, positions: totalPositions, dimension: actualComponents,
            requestedGroups: groupCount, seed: settings.seed, cancellation: cancellation
        )
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

    // MARK: - Binning geometry

    /// The box-binning geometry for one detector axis: `bins` output cells,
    /// each a `box`-wide sum, covering the largest region of `axisSize`
    /// divisible by `box`, centred with `offset` pixels excluded on each
    /// side. When `axisSize < binnedSize` there is no room to bin at all —
    /// `bins` degrades to `axisSize` with `box = 1` (every input pixel is its
    /// own cell) rather than dividing by zero; `embed` below zero-pads the
    /// remaining output cells so every vector stays exactly `binnedSize²`.
    package nonisolated struct BinGeometry: Sendable, Equatable {
        package let binnedH: Int
        package let binnedW: Int
        package let boxY: Int
        package let boxX: Int
        package let offsetY: Int
        package let offsetX: Int

        package static func compute(qy: Int, qx: Int, binnedSize: Int) -> BinGeometry {
            func axis(_ size: Int) -> (bins: Int, box: Int, offset: Int) {
                guard size > 0, binnedSize > 0 else { return (0, 0, 0) }
                let bins = min(binnedSize, size)
                let box = max(1, size / bins)
                let used = box * bins
                let offset = (size - used) / 2
                return (bins, box, offset)
            }
            let y = axis(qy)
            let x = axis(qx)
            return BinGeometry(binnedH: y.bins, binnedW: x.bins, boxY: y.box, boxX: x.box,
                                offsetY: y.offset, offsetX: x.offset)
        }
    }

    /// log1p-scale, per-pattern max-normalise, then box-bin one pattern
    /// (found at `base` in `pixels`, `qy`×`qx` row-major) into a fixed
    /// `binnedSize²`-length vector.
    private static func embed(
        pixels: [Float], base: Int, qy: Int, qx: Int, geometry: BinGeometry, binnedSize: Int
    ) -> [Float] {
        let count = qy * qx
        var scaled = [Float](repeating: 0, count: count)
        var maxVal: Float = 0
        pixels.withUnsafeBufferPointer { buf in
            for i in 0..<count {
                let v = log1p(max(buf[base + i], 0))
                scaled[i] = v
                if v > maxVal { maxVal = v }
            }
        }
        if maxVal > 0 {
            let inv = 1 / maxVal
            for i in 0..<count { scaled[i] *= inv }
        }
        var out = [Float](repeating: 0, count: binnedSize * binnedSize)
        guard geometry.binnedH > 0, geometry.binnedW > 0 else { return out }
        for by in 0..<geometry.binnedH {
            let y0 = geometry.offsetY + by * geometry.boxY
            for bx in 0..<geometry.binnedW {
                let x0 = geometry.offsetX + bx * geometry.boxX
                var sum: Float = 0
                for dy in 0..<geometry.boxY {
                    let rowBase = (y0 + dy) * qx
                    for dx in 0..<geometry.boxX { sum += scaled[rowBase + x0 + dx] }
                }
                out[by * binnedSize + bx] = sum
            }
        }
        return out
    }

    /// Fold one binned vector into the running (double precision) sum and
    /// sum-of-outer-products used to form the mean and covariance once
    /// streaming finishes. This is the dominant cost of the whole pass
    /// (O(positions × dims²)) — inherent to exact covariance PCA, not a
    /// property of this implementation, which is why `binnedSize` defaults
    /// small (16 → dims = 256).
    private static func accumulate(
        _ vector: [Float], dims: Int, sumVec: inout [Double], sumOuter: inout [Double]
    ) {
        vector.withUnsafeBufferPointer { v in
            sumVec.withUnsafeMutableBufferPointer { sv in
                for i in 0..<dims { sv[i] += Double(v[i]) }
            }
            sumOuter.withUnsafeMutableBufferPointer { so in
                for i in 0..<dims {
                    let vi = Double(v[i])
                    let rowBase = i * dims
                    for j in 0..<dims { so[rowBase + j] += vi * Double(v[j]) }
                }
            }
        }
    }

    // MARK: - Deterministic RNG

    /// splitmix64 — deterministic given `seed`, independent of any system
    /// entropy source, so a run's k-means++ seeding is exactly reproducible.
    /// (The PCA has no random start since 2026-09-06.)
    private struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    // MARK: - Symmetric eigendecomposition (Accelerate LAPACK dsyevd_)

    /// Top-`count` eigenpairs of a symmetric `dimension × dimension` matrix
    /// (row-major), largest eigenvalue first, via LAPACK's divide-and-conquer
    /// driver `dsyevd_`. Exact and deterministic — there is no iteration, no
    /// tolerance and no random start. See the file header for why this
    /// replaced a hand-written subspace iteration, and `fix-c/gateD-C1.md`
    /// for the defect that iteration carried.
    ///
    /// Returns `([], [])` when LAPACK reports failure (`info != 0`, which on
    /// a finite symmetric input means a non-finite entry reached the
    /// covariance) or when cancelled; `compute` turns an empty result into a
    /// typed `EmbeddingError`.
    ///
    /// `package` rather than `private` so the Gate D fixture
    /// (`DiffractionEmbeddingTests.testSymmetricEigenTopReturnsTrueEigenpairs`)
    /// can plant a KNOWN spectrum and check the returned pairs directly,
    /// instead of inferring the solver's health from a downstream aggregate.
    package static func symmetricEigenTop(
        matrix: [Double], dimension: Int, count: Int,
        cancellation: AnalysisCancellationToken?
    ) -> (vectors: [[Double]], values: [Double]) {
        let d = dimension
        guard d > 0, matrix.count >= d * d else { return ([], []) }
        let k = max(1, min(count, d))
        guard cancellation?.isCancelled != true else { return ([], []) }

        // `a` is overwritten with the eigenvectors, `w` filled with the
        // eigenvalues in ASCENDING order. The input is symmetric, so the
        // row-major buffer is already the column-major matrix LAPACK reads;
        // on return, eigenvector j is the contiguous slice a[j*d ..< (j+1)*d].
        var a = matrix
        var w = [Double](repeating: 0, count: d)
        var jobz = Int8(UInt8(ascii: "V"))   // eigenvalues AND eigenvectors
        var uplo = Int8(UInt8(ascii: "U"))
        var n = __LAPACK_int(d)
        var lda = __LAPACK_int(d)
        var info = __LAPACK_int(0)

        // Workspace query (lwork = liwork = -1): LAPACK computes nothing and
        // writes the optimal sizes into work[0] / iwork[0]. Sizing the
        // workspace by hand is the classic way to corrupt this call.
        var lwork = __LAPACK_int(-1)
        var liwork = __LAPACK_int(-1)
        var workQuery = [Double](repeating: 0, count: 1)
        var iworkQuery = [__LAPACK_int](repeating: 0, count: 1)
        dsyevd_(&jobz, &uplo, &n, &a, &lda, &w,
                &workQuery, &lwork, &iworkQuery, &liwork, &info)
        guard info == 0, workQuery[0].isFinite, workQuery[0] >= 1, iworkQuery[0] >= 1 else {
            return ([], [])
        }

        lwork = __LAPACK_int(workQuery[0])
        liwork = iworkQuery[0]
        var work = [Double](repeating: 0, count: Int(lwork))
        var iwork = [__LAPACK_int](repeating: 0, count: Int(liwork))
        dsyevd_(&jobz, &uplo, &n, &a, &lda, &w,
                &work, &lwork, &iwork, &liwork, &info)
        guard info == 0 else { return ([], []) }
        guard cancellation?.isCancelled != true else { return ([], []) }

        // Descending by eigenvalue: LAPACK's last column is the largest.
        var vectors = [[Double]](repeating: [], count: k)
        var values = [Double](repeating: 0, count: k)
        for c in 0..<k {
            let column = d - 1 - c
            values[c] = w[column]
            vectors[c] = Array(a[(column * d)..<((column + 1) * d)])
        }
        return (vectors, values)
    }

    // MARK: - k-means

    /// k-means++ seeded Lloyd's algorithm, deterministic given `seed`:
    /// iterates positions in index order, and re-seeds any cluster that ends
    /// an iteration with no assigned point at the point currently farthest
    /// from its own (pre-update) centroid, rather than letting it vanish.
    private static func kMeans(
        coordinates: [Float], positions: Int, dimension: Int, requestedGroups: Int,
        seed: UInt64, cancellation: AnalysisCancellationToken?
    ) -> (assignment: [Int], centroids: [Float]) {
        guard positions > 0, dimension > 0 else { return ([], []) }
        let k = max(1, min(requestedGroups, positions))
        var generator = SplitMix64(seed: seed &+ 0x5A17)

        func pointAsDouble(_ i: Int) -> [Double] {
            let base = i * dimension
            return (0..<dimension).map { Double(coordinates[base + $0]) }
        }
        func squaredDistance(_ i: Int, _ target: [Double]) -> Double {
            var sum = 0.0
            let base = i * dimension
            for j in 0..<dimension {
                let diff = Double(coordinates[base + j]) - target[j]
                sum += diff * diff
            }
            return sum
        }

        // k-means++ seeding.
        var centroidIndices: [Int] = [Int.random(in: 0..<positions, using: &generator)]
        var minDistances = [Double](repeating: .infinity, count: positions)
        while centroidIndices.count < k {
            let lastPoint = pointAsDouble(centroidIndices[centroidIndices.count - 1])
            for i in 0..<positions {
                let dist = squaredDistance(i, lastPoint)
                if dist < minDistances[i] { minDistances[i] = dist }
            }
            let total = minDistances.reduce(0, +)
            if total <= 0 {
                // Every remaining point coincides with a chosen centroid:
                // fill deterministically by index rather than loop forever.
                for i in 0..<positions where !centroidIndices.contains(i) {
                    centroidIndices.append(i)
                    if centroidIndices.count == k { break }
                }
                continue
            }
            let target = Double.random(in: 0..<total, using: &generator)
            var cumulative = 0.0
            var chosen = positions - 1
            for i in 0..<positions {
                cumulative += minDistances[i]
                if cumulative >= target { chosen = i; break }
            }
            centroidIndices.append(chosen)
        }
        var centroids = centroidIndices.flatMap(pointAsDouble)

        var assignment = [Int](repeating: 0, count: positions)
        for _ in 0..<50 {
            guard cancellation?.isCancelled != true else { break }
            var changed = false
            for i in 0..<positions {
                var bestCluster = 0
                var bestDistance = Double.infinity
                let base = i * dimension
                for c in 0..<k {
                    var sum = 0.0
                    let cbase = c * dimension
                    for j in 0..<dimension {
                        let diff = Double(coordinates[base + j]) - centroids[cbase + j]
                        sum += diff * diff
                    }
                    if sum < bestDistance { bestDistance = sum; bestCluster = c }
                }
                if assignment[i] != bestCluster { changed = true }
                assignment[i] = bestCluster
            }

            var sums = [Double](repeating: 0, count: k * dimension)
            var counts = [Int](repeating: 0, count: k)
            for i in 0..<positions {
                let c = assignment[i]
                counts[c] += 1
                let base = i * dimension
                for j in 0..<dimension { sums[c * dimension + j] += Double(coordinates[base + j]) }
            }
            let oldCentroids = centroids
            for c in 0..<k where counts[c] > 0 {
                for j in 0..<dimension { centroids[c * dimension + j] = sums[c * dimension + j] / Double(counts[c]) }
            }
            for c in 0..<k where counts[c] == 0 {
                var farthestIndex = 0
                var farthestDistance = -1.0
                for i in 0..<positions {
                    let ownCluster = assignment[i]
                    let ownCentroid = Array(oldCentroids[(ownCluster * dimension)..<(ownCluster * dimension + dimension)])
                    let d2 = squaredDistance(i, ownCentroid)
                    if d2 > farthestDistance { farthestDistance = d2; farthestIndex = i }
                }
                assignment[farthestIndex] = c
                centroids.replaceSubrange(c * dimension..<(c + 1) * dimension, with: pointAsDouble(farthestIndex))
                changed = true
            }
            if !changed { break }
        }

        return (assignment, centroids.map(Float.init))
    }
}
