//
//  LearnedDiskDetection.swift
//  Role: The learned candidate stage's disagreement diagnostics and its
//        full-scan streaming orchestration (Core ML, the macOS 14 floor —
//        C7 2026-09-08; docs/v3-plan.md §3a, step 4 slice 2).
//

import Foundation
import Metal

// MARK: - Disagreement diagnostics (no availability gate: pure Swift over BraggVectors)

/// Where the classical and learned detectors disagree on how MANY peaks a
/// scan position holds (v3-plan §3a): a coarse first cut, count against
/// count, not peak against peak. A matched-position residual map — which
/// peak moved where — is a later refinement once the two detectors' peaks
/// can be paired up; this stage only says where the counts disagree.
package nonisolated enum DiskDisagreement {

    /// Aggregate statistics over one count-difference map.
    package struct Summary: Sendable, Equatable {
        package let positions: Int
        package let differing: Int
        package let classicalPeaks: Int
        package let learnedPeaks: Int
        package let minDifference: Int
        package let medianDifference: Double
        package let maxDifference: Int

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
        package nonisolated init(positions: Int, differing: Int, classicalPeaks: Int, learnedPeaks: Int, minDifference: Int, medianDifference: Double, maxDifference: Int) {
            self.positions = positions
            self.differing = differing
            self.classicalPeaks = classicalPeaks
            self.learnedPeaks = learnedPeaks
            self.minDifference = minDifference
            self.medianDifference = medianDifference
            self.maxDifference = maxDifference
        }
    }

    /// learned.count − classical.count at every scan position as a scan-domain
    /// `FloatImage` (width = scanWidth, height = scanHeight, row-major like
    /// `BraggVectors.peaks`). `nil` when the scan sizes differ. The
    /// disagreement map of v3-plan §3a: where the two detectors disagree by
    /// count; a matched-position residual map is a later refinement.
    package static func countDifferenceMap(
        classical: BraggVectors, learned: BraggVectors
    ) -> (image: FloatImage, summary: Summary)? {
        guard classical.scanWidth == learned.scanWidth,
              classical.scanHeight == learned.scanHeight,
              classical.peaks.count == learned.peaks.count else { return nil }

        var differences = [Int](repeating: 0, count: classical.peaks.count)
        var classicalTotal = 0
        var learnedTotal = 0
        for i in classical.peaks.indices {
            let c = classical.peaks[i].count
            let l = learned.peaks[i].count
            differences[i] = l - c
            classicalTotal += c
            learnedTotal += l
        }

        let sorted = differences.sorted()
        let median: Double
        if sorted.isEmpty {
            median = 0
        } else if sorted.count.isMultiple(of: 2) {
            median = Double(sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            median = Double(sorted[sorted.count / 2])
        }

        let summary = Summary(
            positions: differences.count,
            differing: differences.filter { $0 != 0 }.count,
            classicalPeaks: classicalTotal,
            learnedPeaks: learnedTotal,
            minDifference: sorted.first ?? 0,
            medianDifference: median,
            maxDifference: sorted.last ?? 0
        )
        let image = FloatImage(
            width: classical.scanWidth, height: classical.scanHeight,
            pixels: differences.map(Float.init)
        )
        return (image, summary)
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
