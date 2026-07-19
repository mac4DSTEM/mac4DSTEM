//
//  TiledDiskDetection.swift
//  Role: Out-of-core orchestration for full-scan Bragg disk detection. The
//        numerical detector remains in DiskDetection.swift and is reused per
//        bounded scan-row tile.
//

import Foundation
import Metal

extension DiskDetection {
    /// Detect every scan position without materializing the full datacube.
    /// Each bounded tile delegates to the resident detector so the numerical
    /// pipeline remains identical while progress spans all tiles.
    nonisolated static func detectAll(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        kernel: ProbeKernel,
        params: DiskDetectionParams,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> BraggVectors? {
        guard cancellation?.isCancelled != true else { return nil }
        let context = DiskDetectionContext(
            qy: d.qy, qx: d.qx, probeRadius: kernel.probeRadius
        )
        guard !params.validationIssues(in: context).contains(where: {
            $0.severity == .error
        }) else { return nil }
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
            guard let tile = try? await prefetcher.tile(
                for: range,
                prefetching: index + 1 < ranges.count ? ranges[index + 1] : nil
            ) else { prefetcher.cancel(); return nil }
            guard cancellation?.isCancelled != true else { prefetcher.cancel(); return nil }
            guard let buffer = MetalEngine.shared.device.makeBuffer(
                bytes: tile.pixels,
                length: tile.pixels.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
            ) else { prefetcher.cancel(); return nil }
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
            ) else { prefetcher.cancel(); return nil }
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
