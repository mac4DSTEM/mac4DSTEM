//
//  TiledDiskDetection.swift
//  Role: Out-of-core orchestration for full-scan Bragg disk detection. The
//        numerical detector remains in DiskDetection.swift and is reused per
//        bounded scan-row tile.
//

import Foundation
import Metal

extension DiskDetection {

    /// Why a full-scan detection over a streamed cube failed. Typed and
    /// attributed, because the previous contract collapsed every failure into
    /// `nil` — and the caller then reported all of them as "failed to
    /// initialize its FFT plan", so a NAS read error wore an FFT costume
    /// (docs/open-items.md, routed to v2 S7). A tile-read failure names the
    /// scan rows and carries the underlying error — which, since S1
    /// un-silenced `H5Eset_auto2`, includes the HDF5 detail. // v2 S7
    enum FullScanError: Error, CustomStringConvertible, LocalizedError {
        /// Reading these scan rows from the source dataset failed.
        case tileRead(rows: Range<Int>, underlying: Error)
        /// The Metal buffer for a tile could not be allocated.
        case bufferAllocation(rows: Range<Int>, bytes: Int)
        /// The detection parameters fail validation for this dataset.
        case invalidParameters([String])
        /// The per-worker disk detector (probe-kernel FFT plan and scratch)
        /// could not be built.
        case detectorUnavailable

        var description: String {
            switch self {
            case .tileRead(let rows, let underlying):
                return "Reading scan rows \(rows.lowerBound)–\(rows.upperBound - 1) "
                    + "from the dataset failed: \(underlying.localizedDescription)"
            case .bufferAllocation(let rows, let bytes):
                return "Could not allocate the \(bytes)-byte GPU buffer for "
                    + "scan rows \(rows.lowerBound)–\(rows.upperBound - 1)."
            case .invalidParameters(let messages):
                return "Disk-detection settings are invalid: "
                    + messages.joined(separator: " ")
            case .detectorUnavailable:
                return "Disk detection could not build its detector "
                    + "(FFT plan for the probe-kernel grid)."
            }
        }

        var errorDescription: String? { description }
    }

    /// Detect every scan position without materializing the full datacube.
    /// Each bounded tile delegates to the resident detector so the numerical
    /// pipeline remains identical while progress spans all tiles.
    ///
    /// Returns nil ONLY on cancellation — every failure throws a
    /// `FullScanError` naming what failed and where. // v2 S7
    nonisolated static func detectAll(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        kernel: ProbeKernel,
        params: DiskDetectionParams,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> BraggVectors? {
        guard cancellation?.isCancelled != true else { return nil }
        let context = DiskDetectionContext(
            qy: d.qy, qx: d.qx, probeRadius: kernel.probeRadius
        )
        let issues = params.validationIssues(in: context).filter {
            $0.severity == .error
        }
        guard issues.isEmpty else {
            throw FullScanError.invalidParameters(issues.map(\.message))
        }
        let rowsPerTile = await data.scanTileRows(maximumRows: maximumTileRows)
        var allPeaks = [[BraggPeak]](repeating: [], count: d.ry * d.rx)

        let ranges: [Range<Int>] = stride(from: 0, to: d.ry, by: rowsPerTile).map {
            $0..<min(d.ry, $0 + rowsPerTile)
        }
        var prefetcher = TilePrefetcher(data: data)
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
                // A read aborted BY a cancel is a cancel, not a failure.
                guard cancellation?.isCancelled != true else { return nil }
                throw FullScanError.tileRead(rows: range, underlying: error)
            }
            guard cancellation?.isCancelled != true else { prefetcher.cancel(); return nil }
            let byteCount = tile.pixels.count * MemoryLayout<Float>.stride
            guard let buffer = MetalEngine.shared.device.makeBuffer(
                bytes: tile.pixels,
                length: byteCount,
                options: .storageModeShared
            ) else {
                prefetcher.cancel()
                // Same rule as the other two throw branches: a cancel racing
                // this failure is a cancel, honoring "nil ONLY on
                // cancellation" from both sides (Gate B, 2026-08-25).
                guard cancellation?.isCancelled != true else { return nil }
                throw FullScanError.bufferAllocation(rows: range, bytes: byteCount)
            }
            buffer.label = "Disk detection tile rows \(range.lowerBound)..<\(range.upperBound)"
            let tileDescriptor = DatasetDescriptor(
                filePath: d.filePath, datasetPath: d.datasetPath,
                shape: [range.count, d.rx, d.qy, d.qx],
                dtypeDescription: d.dtypeDescription, chunkShape: nil
            )
            guard let detected = detectAll(
                cube: buffer, descriptor: tileDescriptor, kernel: kernel,
                params: params, cancellation: cancellation,
                progress: { fraction in
                    progress?(
                        (Double(lower) + fraction * Double(range.count)) / Double(d.ry)
                    )
                }
            ) else {
                prefetcher.cancel()
                // The resident detector returns nil for exactly three
                // reasons: cancellation, parameter validation (already
                // checked above against the same context), or a failed
                // detector build. Not-cancelled therefore means the build.
                guard cancellation?.isCancelled != true else { return nil }
                throw FullScanError.detectorUnavailable
            }
            allPeaks.replaceSubrange(
                lower * d.rx..<upper * d.rx,
                with: detected.peaks
            )
        }

        progress?(1)
        return BraggVectors(
            scanWidth: d.rx, scanHeight: d.ry, peaks: allPeaks,
            detectionProvenance: params.provenance(
                kernel: kernel, qy: d.qy, qx: d.qx
            )
        )
    }
}
