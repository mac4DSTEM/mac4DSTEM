//
//  TiledDiskDetection.swift
//  Role: Out-of-core orchestration for full-scan Bragg disk detection. The scan
//        loop is CuboKit's (`BraggDisks.detectAll`, CuboKit 0.7.0, failure policy
//        `.recordEmpty`); this file keeps the app's contract around it: the
//        parameter validation, typed attributed errors, nil on cancellation and
//        the `BraggVectors` the rest of the app reads.
//

import CuboBragg
import CuboCore
import Foundation

/// Full-scan Bragg disk detection (the namespace; the per-pattern detector is `DiskDetector`).
package enum DiskDetection {

    /// Why a full-scan detection over a streamed cube failed. Typed and
    /// attributed, because the previous contract collapsed every failure into
    /// `nil` — and the caller then reported all of them as "failed to
    /// initialize its FFT plan", so a NAS read error wore an FFT costume
    /// (docs/open-items.md, routed to v2 S7). A tile-read failure names the
    /// scan rows and carries the underlying error — which, since S1
    /// un-silenced `H5Eset_auto2`, includes the HDF5 detail. // v2 S7
    package enum FullScanError: Error, CustomStringConvertible, LocalizedError {
        /// Reading these scan rows from the source dataset failed.
        case tileRead(rows: Range<Int>, underlying: Error)
        /// The Metal buffer for a tile could not be allocated.
        case bufferAllocation(rows: Range<Int>, bytes: Int)
        /// The detection parameters fail validation for this dataset.
        case invalidParameters([String])
        /// The per-worker disk detector (probe-kernel FFT plan and scratch)
        /// could not be built.
        case detectorUnavailable

        package var description: String {
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

        package var errorDescription: String? { description }
    }

    /// Detect every scan position without materializing the full datacube: CuboKit's whole-cube pass over the app's cube
    /// (`CuboCubeSource`: bounded scan-row tiles, the next one read while the current one is detected, every core on a
    /// tile's patterns). A pattern whose detection fails (a non-finite refinement) keeps an empty peak list and is
    /// counted in `failedPatternCount`; the scan goes on.
    ///
    /// Returns nil ONLY on cancellation — every failure throws a
    /// `FullScanError` naming what failed and where. // v2 S7
    @concurrent
    package static func detectAll(
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
        guard let kernelImage = DiskDetector.kitKernel(kernel) else { throw FullScanError.detectorUnavailable }
        let source = TileReadAttribution(try CuboCubeSource(data, descriptor: d, cancellation: cancellation))
        let result: BraggScanResult
        do {
            result = try await BraggDisks.detectAll(
                in: source, kernel: kernelImage,
                options: DiskDetector.kitOptions(params, qy: d.qy, qx: d.qx),
                tiling: try await VirtualDetector.kitTiling(data: data, descriptor: d, maximumRows: maximumTileRows),
                failurePolicy: .recordEmpty,
                isCancelled: { cancellation?.isCancelled == true },
                progress: { fraction in progress?(fraction) })
        } catch is CancellationError {
            return nil
        } catch {
            // A read aborted BY a cancel is a cancel, not a failure.
            guard cancellation?.isCancelled != true else { return nil }
            throw error
        }
        guard cancellation?.isCancelled != true else { return nil }
        progress?(1)
        let peaks = result.vectors.peaks.map { list in
            list.map { BraggPeak(x: Float($0.column), y: Float($0.row), intensity: Float($0.intensity)) }
        }
        return BraggVectors(
            scanWidth: d.rx, scanHeight: d.ry, peaks: peaks,
            detectionProvenance: params.provenance(kernel: kernel, qy: d.qy, qx: d.qx),
            failedPatternCount: result.failedPositions.count
        )
    }
}

/// The cube as the kit's scan loop reads it, with a failed tile read named by its scan rows (`FullScanError.tileRead`)
/// where the kit would surface the bare error. A cancel passes through untouched.
private actor TileReadAttribution: CubeSource {
    private let base: CuboCubeSource
    nonisolated let shape: CubeShape

    init(_ base: CuboCubeSource) {
        self.base = base
        self.shape = base.shape
    }

    func readPattern(row: Int, column: Int) async throws -> CuboCore.DiffractionPattern {
        try await base.readPattern(row: row, column: column)
    }

    func readScanTile(rows: Range<Int>) async throws -> ScanTile {
        do {
            return try await base.readScanTile(rows: rows)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DiskDetection.FullScanError.tileRead(rows: rows, underlying: error)
        }
    }
}
