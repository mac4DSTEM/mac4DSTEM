//
//  CuboCubeSource.swift
//  Role: the app's cube, seen by CuboKit. A `CubeSource` over `FourDArray` (CuboKit consumer note 0.0.1 §2): the kit's
//        reductions read their pixels through it, and the app keeps its load views, crops, binning, pattern cache and
//        resident cube exactly as they are. No pixel is copied beyond the tile a pass asks for.
//
//  The storage order matches: the app's `[ry][rx][qy][qx]` Float32 is the kit's `[scanRow][scanColumn][detectorRow]
//  [detectorColumn]`, so the app's `y` is the kit's row and its `x` the kit's column.
//
//  Two things the kit's sources do not do and the app's passes did (`TilePrefetcher`, `AnalysisCancellationToken`),
//  kept here so a switch does not lose them: the next block of scan rows is read while the current one is reduced
//  (at most one tile in flight, as before), and a cancelled operation stops at its next read.
//

import CuboCore
import Foundation

package actor CuboCubeSource: CubeSource {
    private let array: FourDArray
    package nonisolated let shape: CubeShape
    private let cancellation: AnalysisCancellationToken?
    /// The read already under way for the block that follows the last one served.
    private var pending: (rows: Range<Int>, read: Task<FourDScanTile, Error>)?

    /// - Parameter descriptor: the shape the passes run over (the view's), as `VirtualDetector`'s callers pass it.
    package init(_ array: FourDArray, descriptor d: DatasetDescriptor,
                 cancellation: AnalysisCancellationToken? = nil) throws {
        self.array = array
        self.shape = try CubeShape(scanRows: d.ry, scanColumns: d.rx, detectorRows: d.qy, detectorColumns: d.qx)
        self.cancellation = cancellation
    }

    package func readPattern(row: Int, column: Int) async throws -> CuboCore.DiffractionPattern {
        try shape.requirePositionForApp(row: row, column: column)
        try checkCancelled()
        let pattern = try await array.pattern(ry: row, rx: column)
        return try CuboCore.DiffractionPattern(detectorRows: pattern.qy, detectorColumns: pattern.qx,
                                               values: pattern.pixels)
    }

    package func readScanTile(rows: Range<Int>) async throws -> ScanTile {
        try checkCancelled()
        let tile: FourDScanTile
        if let pending, pending.rows == rows {
            self.pending = nil
            tile = try await pending.read.value
        } else {
            pending?.read.cancel()
            pending = nil
            tile = try await array.scanTile(yRange: rows)
        }
        // A pass walks equal blocks in scan order, so the block after this one is predictable; a wrong guess (the
        // last block, a caller that stops) costs one abandoned read, bounded at one tile as `TilePrefetcher` was.
        let next = rows.upperBound..<min(shape.scanRows, rows.upperBound + rows.count)
        if !next.isEmpty {
            let array = array
            pending = (next, Task { try await array.scanTile(yRange: next) })
        }
        try checkCancelled()
        return try ScanTile(shape: shape, rows: rows, values: tile.pixels)
    }

    private func checkCancelled() throws {
        if cancellation?.isCancelled == true {
            pending?.read.cancel()
            pending = nil
            throw CancellationError()
        }
    }
}

private extension CubeShape {
    /// `requirePosition` is the kit's package-scoped helper; the adapter states the same refusal itself.
    nonisolated func requirePositionForApp(row: Int, column: Int) throws {
        guard (0..<scanRows).contains(row), (0..<scanColumns).contains(column) else {
            throw CuboError.outOfRange("Scan position (\(row), \(column))")
        }
    }
}
