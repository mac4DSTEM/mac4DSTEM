//
//  LearnedDiskDetection.swift
//  Role: The learned candidate stage's disagreement diagnostics (position-
//        matched, C7 session 3) and its
//        full-scan streaming orchestration (Core ML, the macOS 14 floor —
//        C7 2026-09-08; docs/v3-plan.md §3a, step 4 slice 2).
//

import Foundation
import Metal

// MARK: - Disagreement diagnostics (no availability gate: pure Swift over BraggVectors)

/// Where the classical and learned detectors disagree at each scan position,
/// peak against peak (v3-plan §3a; C7 session 3, 2026-09-08). The two peak
/// lists at a position are paired greedily by distance within `matchRadius`
/// — closest pair first, each peak used once — and whatever is left unpaired
/// on either side is the disagreement. Two lists of equal length at different
/// positions therefore no longer pass as agreement, which the count-only
/// first cut of sessions 1–2 (`countDifferenceMap`, deleted) let through.
package nonisolated enum DiskDisagreement {

    /// The pairing distance in detector pixels. C6's evaluation matched a
    /// prediction to a labelled centre within 2 px (`evaluate.py`), and both
    /// detectors here end in the same classical refinement, so a shared disk
    /// lands well inside it. A session-3 choice, recorded in `decisions.md`.
    package static let defaultMatchRadius: Float = 2

    /// Aggregate statistics over one position-matched map.
    package struct Summary: Sendable, Equatable {
        package let positions: Int
        /// Positions with at least one unpaired peak on either side.
        package let differing: Int
        package let matched: Int
        package let classicalOnly: Int
        package let learnedOnly: Int
        package let classicalPeaks: Int
        package let learnedPeaks: Int
        /// Median distance of the paired peaks, or nil when nothing paired.
        package let medianResidualPx: Double?
        package let matchRadiusPx: Float

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
        package nonisolated init(
            positions: Int, differing: Int, matched: Int, classicalOnly: Int, learnedOnly: Int,
            classicalPeaks: Int, learnedPeaks: Int, medianResidualPx: Double?, matchRadiusPx: Float
        ) {
            self.positions = positions
            self.differing = differing
            self.matched = matched
            self.classicalOnly = classicalOnly
            self.learnedOnly = learnedOnly
            self.classicalPeaks = classicalPeaks
            self.learnedPeaks = learnedPeaks
            self.medianResidualPx = medianResidualPx
            self.matchRadiusPx = matchRadiusPx
        }

        /// The map's own provenance rows: the statistics, both classes as a
        /// list, and the compared learned run's identity (its threshold and
        /// model hash, from `learned.detectionProvenance`).
        package func provenance(learnedRun learned: [String: String]) -> [String: String] {
            [
                "source_product": "disk_disagreement", "coordinate_space": "real",
                "detector_class": "classical,learned",
                "learned_threshold": learned["learned_threshold"] ?? "",
                "learned_model_sha256": learned["learned_model_sha256"] ?? "",
                "disagreement_match_radius_px": String(matchRadiusPx),
                "disagreement_matched": String(matched),
                "disagreement_classical_only": String(classicalOnly),
                "disagreement_learned_only": String(learnedOnly),
                "disagreement_positions": "\(differing)/\(positions)",
                "disagreement_median_residual_px": medianResidualPx.map { String(format: "%.2f", $0) } ?? "n/a",
            ]
        }

        /// The status-bar sentence, in the app's voice.
        package var statusLine: String {
            String(format: "Disagreement: %d of %d positions differ — %d peaks paired within %.0f px, %d classical-only, %d neural-net-only",
                   differing, positions, matched, matchRadiusPx, classicalOnly, learnedOnly)
        }
    }

    /// The unpaired peaks at every scan position — classical-only plus
    /// learned-only — as a scan-domain `FloatImage` (width = scanWidth,
    /// height = scanHeight, row-major like `BraggVectors.peaks`), with the
    /// pooled statistics. `nil` when the scan shapes differ.
    package static func positionMatchedMap(
        classical: BraggVectors, learned: BraggVectors,
        matchRadius: Float = defaultMatchRadius
    ) -> (image: FloatImage, summary: Summary)? {
        guard classical.scanWidth == learned.scanWidth,
              classical.scanHeight == learned.scanHeight,
              classical.peaks.count == learned.peaks.count else { return nil }

        var unmatched = [Float](repeating: 0, count: classical.peaks.count)
        var matched = 0, classicalOnly = 0, learnedOnly = 0
        var classicalTotal = 0, learnedTotal = 0
        var residuals: [Float] = []
        for i in classical.peaks.indices {
            let c = classical.peaks[i], l = learned.peaks[i]
            let pairs = pair(c, l, radius: matchRadius)
            matched += pairs.count
            residuals.append(contentsOf: pairs)
            classicalOnly += c.count - pairs.count
            learnedOnly += l.count - pairs.count
            classicalTotal += c.count
            learnedTotal += l.count
            unmatched[i] = Float(c.count + l.count - 2 * pairs.count)
        }

        let median: Double?
        if residuals.isEmpty {
            median = nil
        } else {
            let sorted = residuals.sorted()
            median = sorted.count.isMultiple(of: 2)
                ? Double(sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
                : Double(sorted[sorted.count / 2])
        }
        let summary = Summary(
            positions: unmatched.count,
            differing: unmatched.filter { $0 != 0 }.count,
            matched: matched, classicalOnly: classicalOnly, learnedOnly: learnedOnly,
            classicalPeaks: classicalTotal, learnedPeaks: learnedTotal,
            medianResidualPx: median, matchRadiusPx: matchRadius
        )
        let image = FloatImage(width: classical.scanWidth, height: classical.scanHeight, pixels: unmatched)
        return (image, summary)
    }

    /// Greedy one-to-one pairing of two peak lists: every cross pair within
    /// `radius`, closest first (ties broken by index order, so the result is
    /// deterministic), each peak taken at most once. Returns the paired
    /// distances. Lists are at most `maxNumPeaks` long, so the quadratic
    /// candidate set is small.
    static func pair(_ a: [BraggPeak], _ b: [BraggPeak], radius: Float) -> [Float] {
        let r2 = radius * radius
        var candidates: [(d: Float, i: Int, j: Int)] = []
        for i in a.indices {
            for j in b.indices {
                let dx = a[i].x - b[j].x, dy = a[i].y - b[j].y
                let d2 = dx * dx + dy * dy
                if d2 <= r2 { candidates.append((d2.squareRoot(), i, j)) }
            }
        }
        candidates.sort { $0.d != $1.d ? $0.d < $1.d : ($0.i != $1.i ? $0.i < $1.i : $0.j < $1.j) }
        var usedA = [Bool](repeating: false, count: a.count)
        var usedB = [Bool](repeating: false, count: b.count)
        var distances: [Float] = []
        for c in candidates where !usedA[c.i] && !usedB[c.j] {
            usedA[c.i] = true
            usedB[c.j] = true
            distances.append(c.d)
        }
        return distances
    }
}

// MARK: - Streamed full-scan orchestration (Core ML)

extension LearnedDiskDetector {

    /// Lock-guarded permille gate for progress callbacks, admitting a fraction
    /// only when its 0.1 % bucket differs from the last admitted one.
    ///
    /// Duplicated from `TiledDiskDetection.swift`'s file-private
    /// `ProgressCoalescer` rather than shared, on purpose (see the type doc
    /// below): the learned stage stays inside Core/ML.
    nonisolated private final class ProgressCoalescer: @unchecked Sendable {
        private let lock = NSLock()
        private var lastBucket = -1
        func admits(_ fraction: Double) -> Bool {
            let bucket = Int((fraction * 1000).rounded(.down))
            return lock.withLock {
                guard bucket != lastBucket else { return false }
                lastBucket = bucket
                return true
            }
        }
    }

    /// Streamed full-scan run, scan-row tile by tile — the same orchestration
    /// as `DiskDetection.detectAll(data:…)` in `TiledDiskDetection.swift`
    /// (`TilePrefetcher`, per-tile `MTLBuffer`, per-tile `DatasetDescriptor`,
    /// global progress coalescing, the `FullScanError` contract: nil ONLY on
    /// cancellation, every failure throws `DiskDetection.FullScanError`).
    /// Duplicated here rather than generalising the classical orchestrator, on
    /// purpose: the learned stage stays inside Core/ML.
    ///
    /// Each tile delegates to the resident `detectAll(cube:descriptor:probe:
    /// probeCentre:probeRadius:kernelSource:params:threshold:cancellation:
    /// progress:)`, which returns nil for exactly four reasons — cancellation,
    /// parameter validation, a failed detector build, a detector crop smaller
    /// than `inputSize` or a probe whose size differs from the detector.
    /// Not-cancelled therefore means one of the other three, all of which are
    /// build/validation failures the caller cannot distinguish further —
    /// reported the same way the classical orchestrator reports its own
    /// resident-detector-build failure: `FullScanError.detectorUnavailable`.
    ///
    /// The returned `BraggVectors.detectionProvenance` is the FIRST tile's
    /// provenance (it carries the learned keys — model asset, hash, threshold,
    /// window grid — which are identical across tiles since the window origins
    /// are fixed by `probeCentre` and `probeRadius`, not by scan row) — never
    /// recomputed.
    /// `nonisolated` is load-bearing, not decoration (Gate D, fix-a
    /// `gateD-A2.md`): the project builds with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and without the keyword
    /// this member — declared in an extension in a file OTHER than the
    /// `nonisolated` class's own — is `@MainActor`, so the `Task.detached`
    /// in `AppState.runDiskDetection` hopped straight back and
    /// `concurrentPerform` conscripted the main thread for every batch
    /// (measured: 5 of 5 progress callbacks on the main thread, and the
    /// owner's frozen run at 847/847 main-thread samples). The classical twin
    /// says it too: `TiledDiskDetection.detectAll(data:…)`.
    package nonisolated func detectAll(
        data: FourDArray, descriptor d: DatasetDescriptor,
        probe: DiffractionPattern, probeCentre: (x: Float, y: Float), probeRadius: Float,
        kernelSource: ProbeKernelSource = .measured, params: DiskDetectionParams,
        threshold: Float = LearnedDiskDetector.defaultThreshold, maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> BraggVectors? {
        guard cancellation?.isCancelled != true else { return nil }

        // The classical parameter validation, at the crop size — the same
        // upfront check `TiledDiskDetection.detectAll(data:…)` performs
        // before touching any tile.
        let S = Self.inputSize
        let issues = params.validationIssues(in: DiskDetectionContext(qy: S, qx: S, probeRadius: probeRadius))
            .filter { $0.severity == .error }
        guard issues.isEmpty else {
            throw DiskDetection.FullScanError.invalidParameters(issues.map(\.message))
        }

        let rowsPerTile = await data.scanTileRows(maximumRows: maximumTileRows)
        var allPeaks = [[BraggPeak]](repeating: [], count: d.ry * d.rx)
        var provenance: [String: String]?

        let ranges: [Range<Int>] = stride(from: 0, to: d.ry, by: rowsPerTile).map {
            $0..<min(d.ry, $0 + rowsPerTile)
        }
        var prefetcher = TilePrefetcher(data: data)
        let coalescer = ProgressCoalescer()
        let coalesced: (@Sendable (Double) -> Void)? = progress.map { progress in
            { @Sendable fraction in
                if coalescer.admits(fraction) { progress(fraction) }
            }
        }

        for (index, range) in ranges.enumerated() {
            guard cancellation?.isCancelled != true else { prefetcher.cancel(); return nil }
            let lower = range.lowerBound
            let upper = range.upperBound
            let tile: FourDScanTile
            do {
                tile = try await prefetcher.tile(
                    for: range,
                    prefetching: index + 1 < ranges.count ? ranges[index + 1] : nil
                )
            } catch {
                prefetcher.cancel()
                guard cancellation?.isCancelled != true else { return nil }
                throw DiskDetection.FullScanError.tileRead(rows: range, underlying: error)
            }
            guard cancellation?.isCancelled != true else { prefetcher.cancel(); return nil }

            let byteCount = tile.pixels.count * MemoryLayout<Float>.stride
            guard let buffer = MetalEngine.shared.device.makeBuffer(
                bytes: tile.pixels, length: byteCount, options: .storageModeShared
            ) else {
                prefetcher.cancel()
                guard cancellation?.isCancelled != true else { return nil }
                throw DiskDetection.FullScanError.bufferAllocation(rows: range, bytes: byteCount)
            }
            buffer.label = "Learned disk detection tile rows \(range.lowerBound)..<\(range.upperBound)"
            let tileDescriptor = DatasetDescriptor(
                filePath: d.filePath, datasetPath: d.datasetPath,
                shape: [range.count, d.rx, d.qy, d.qx],
                dtypeDescription: d.dtypeDescription, chunkShape: nil
            )

            guard let detected = await detectAll(
                cube: buffer, descriptor: tileDescriptor,
                probe: probe, probeCentre: probeCentre, probeRadius: probeRadius,
                kernelSource: kernelSource, params: params, threshold: threshold,
                cancellation: cancellation,
                progress: { fraction in
                    coalesced?(
                        (Double(lower) + fraction * Double(range.count)) / Double(d.ry)
                    )
                }
            ) else {
                prefetcher.cancel()
                // Not-cancelled means the resident call's parameter
                // validation, detector build, or size guard failed — see the
                // doc comment above.
                guard cancellation?.isCancelled != true else { return nil }
                throw DiskDetection.FullScanError.detectorUnavailable
            }
            if provenance == nil { provenance = detected.detectionProvenance }
            allPeaks.replaceSubrange(lower * d.rx..<upper * d.rx, with: detected.peaks)
        }

        progress?(1)
        return BraggVectors(
            scanWidth: d.rx, scanHeight: d.ry, peaks: allPeaks,
            detectionProvenance: provenance ?? [:]
        )
    }

    /// The pinned asset shipped verbatim in the app bundle
    /// (Contents/Resources/DiskDetector/disk-detector-heatmap-256.mlpackage), or nil.
    /// Its record is the JSON beside it in `Models/DiskDetector/`.
    package static let bundledAssetName = "disk-detector-heatmap-256"
    package static func bundledAssetURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: bundledAssetName, withExtension: "mlpackage", subdirectory: "DiskDetector")
            ?? bundle.url(forResource: bundledAssetName, withExtension: "mlpackage")
    }
}
