//
//  VirtualDetector.swift
//  Role: The Analysis-layer wrapper for virtual-detector imaging. It turns a
//        high-level intent (a preset, a dragged annulus, or any py4DSTEM
//        detector geometry) into a GPU dispatch and hands back a `FloatImage`.
//
//  Two compute paths, same convention as py4DSTEM make_detector:
//  circle r² < rOut²; annulus rIn² < r² < rOut².
//   • analytic annulus kernel — used while dragging, no mask rebuild
//   • mask kernel — one detector-space weight image covers every geometry
//     (py4DSTEM get_virtual_image modes: circle, annulus, rectangle, point)
//
//  THREADING: `run(...)`/`image(...)` are synchronous and call into Metal
//  with waitUntilCompleted. Call them from a background task (AppState wraps
//  them in `Task.detached`), never directly on the main actor.
//

import Foundation
import Metal

// MARK: - Detector geometry (py4DSTEM get_virtual_image modes)

/// A detector geometry in detector-pixel coordinates
/// (X = column / qx index, Y = row / qy index).
enum DetectorShape: Equatable {
    case circle(centerX: Float, centerY: Float, radius: Float)
    case annulus(centerX: Float, centerY: Float, inner: Float, outer: Float)
    /// Half-open pixel-index bounds, [xMin, xMax) × [yMin, yMax).
    case rectangle(xMin: Int, xMax: Int, yMin: Int, yMax: Int)
    /// Single detector pixel.
    case point(x: Int, y: Int)
}

// MARK: - Detector presets

/// Standard virtual-detector geometries. Radii are expressed as fractions of
/// the maximum usable detector radius so they scale to any pattern size.
enum DetectorPreset: String, CaseIterable, Identifiable {
    case brightField = "Bright Field"
    case adf         = "ADF"
    case haadf       = "HAADF"
    case custom      = "Custom"

    var id: String { rawValue }

    /// Inner/outer radii in *pixels* given the largest radius that fits.
    /// (Custom returns nil — the UI's draggable aperture drives it instead.)
    func radii(maxRadius r: Float) -> (inner: Float, outer: Float)? {
        switch self {
        case .brightField: return (0,        0.20 * r)   // central disk
        case .adf:         return (0.25 * r, 0.55 * r)   // mid annulus
        case .haadf:       return (0.55 * r, 0.95 * r)   // high-angle annulus
        case .custom:      return nil
        }
    }
}

// MARK: - Tile prefetching (overlap tile I/O with GPU compute)

/// Reads the next scan tile while the caller's current tile is on the GPU.
/// At most two tiles are resident (one processing, one arriving); with the
/// halved per-tile row budget in FourDArray.scanTileRows, total staging
/// memory stays within the prior single-tile bound.
nonisolated struct TilePrefetcher {
    private let data: FourDArray
    private var pending: Task<FourDScanTile, Error>?

    init(data: FourDArray) { self.data = data }

    /// Return the tile for `range` (from the prefetch when one is pending),
    /// then begin reading `nextRange` in the background.
    mutating func tile(
        for range: Range<Int>, prefetching nextRange: Range<Int>?
    ) async throws -> FourDScanTile {
        let current: FourDScanTile
        if let pending {
            current = try await pending.value
        } else {
            current = try await data.scanTile(yRange: range)
        }
        precondition(current.yRange == range, "prefetch order broke")
        pending = nextRange.map { next in
            let data = data
            return Task { try await data.scanTile(yRange: next) }
        }
        return current
    }

    /// Abandon a pending read (it completes in the background and is
    /// discarded — bounded at one tile, same spirit as uninterruptible GPU
    /// commands).
    func cancel() { pending?.cancel() }
}

// MARK: - Tile bytes on the GPU (resident: bound in place; streaming: staged)

/// Hands each tiled pass the GPU bytes for one scan-row range, from the
/// cheapest source available.
///
/// **Resident** — the tile's floats are already inside the cube's `MTLBuffer`,
/// contiguous and in scan order, so the binding is just that buffer at the
/// tile's byte offset. Nothing is read, copied or allocated. This is what
/// removes the ~0.375 x working set of staging a resident cube used to pay:
/// `FourDArray.scanTile` copied the tile out into a Swift `[Float]`,
/// `TilePrefetcher` held two of those, and each pass then built a third copy as
/// a fresh `MTLBuffer` (adversarial review, 2026-08-17; v2 S18).
///
/// **Streaming** — unchanged: `TilePrefetcher` reads ahead one tile and each
/// tile is staged into its own buffer.
///
/// The tiling itself is IDENTICAL in both cases — the caller still walks the
/// same `scanTileRows` ranges and still combines the same per-tile partials in
/// the same order — so a resident pass returns bit-identical floats to the
/// streaming pass it replaces. That equality is what
/// `tools/virtual-detector-residency` asserts.
// BEHAVIOUR CHANGE, undocumented until the Gate B second read named it
// (2026-08-28): this captures the `ResidentCube` ONCE, at construction, and
// holds it for the whole pass. Before v2 S18, `scanTile` re-checked residency
// per tile, so a `releaseResident()` mid-pass freed the buffer and the pass
// finished from disk. Now the pass pins the cube until it completes.
//
// Numbers are unaffected — the view is a `let`, so the bytes cannot differ —
// and mixing resident with streamed tiles inside one pass is now impossible,
// which is the better guarantee. The cost is that "Release cube" no longer
// returns the memory promptly while a reduction is running. Unreachable in the
// shipping app today (nothing requests `.resident`), but this is the kind of
// property that gets discovered under memory pressure rather than read.
nonisolated struct TileGPUSource {
    private let cube: ResidentCube?
    private let bytesPerScanRow: Int
    private var prefetcher: TilePrefetcher

    /// - Parameter cube: the array's resident cube when it holds one *for this
    ///   descriptor* (`FourDArray.resident(for:)`), else nil.
    init(data: FourDArray, descriptor d: DatasetDescriptor, cube: ResidentCube?) {
        self.cube = cube
        self.bytesPerScanRow = d.rx * d.qy * d.qx * MemoryLayout<Float>.stride
        self.prefetcher = TilePrefetcher(data: data)
    }

    var isResident: Bool { cube != nil }

    /// The buffer and byte offset holding `range`'s floats.
    mutating func binding(
        for range: Range<Int>, prefetching nextRange: Range<Int>?, label: @autoclosure () -> String
    ) async throws -> (buffer: MTLBuffer, offset: Int) {
        if let cube {
            let offset = range.lowerBound * bytesPerScanRow
            // The resident path skips `scanTile`, and with it the length check
            // `scanTile` performs on every read. Re-assert it here against the
            // buffer itself: an offset past the end would otherwise be read by
            // the GPU as whatever follows it in the allocation.
            guard offset >= 0,
                  offset + range.count * bytesPerScanRow <= cube.buffer.length else {
                throw FourDError.allocationFailed
            }
            return (cube.buffer, offset)
        }
        let tile = try await prefetcher.tile(for: range, prefetching: nextRange)
        guard let buffer = MetalEngine.shared.device.makeBuffer(
            bytes: tile.pixels,
            length: tile.pixels.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            prefetcher.cancel()
            throw FourDError.allocationFailed
        }
        buffer.label = label()
        return (buffer, 0)
    }

    func cancel() { prefetcher.cancel() }
}

// MARK: - VirtualDetector

nonisolated enum VirtualDetector {

    private enum TileOperation {
        case shape(DetectorShape)
        case aperture(Aperture)
    }

    /// Bounded-memory virtual imaging. Scan rows are read as contiguous tiles;
    /// each tile uses the existing production Metal kernels and is copied into
    /// its stable output rows only after the dispatch completes.
    static func tiledImage(
        data: FourDArray,
        descriptor: DatasetDescriptor,
        shape: DetectorShape,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> FloatImage {
        try await tiled(data: data, descriptor: descriptor, operation: .shape(shape),
                        maximumTileRows: maximumTileRows,
                        cancellation: cancellation, progress: progress)
    }

    static func tiledRun(
        data: FourDArray,
        descriptor: DatasetDescriptor,
        aperture: Aperture,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> FloatImage {
        try await tiled(data: data, descriptor: descriptor, operation: .aperture(aperture),
                        maximumTileRows: maximumTileRows,
                        cancellation: cancellation, progress: progress)
    }

    private static func tiled(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        operation: TileOperation,
        maximumTileRows: Int?,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> FloatImage {
        // Resident fast path: one dispatch over the whole cube instead of one
        // per tile. Exact, not approximate — virtualMaskSum and virtualAperture
        // run one thread per SCAN position over a mask built from qy/qx only,
        // and tiles partition the scan axis, so no tile boundary ever splits a
        // per-output-pixel reduction. The two images are bit-identical and
        // tools/virtual-detector-residency asserts `==`. See ResidentCube.swift.
        if let cube = await data.resident(for: d) {
            guard cancellation?.isCancelled != true else { throw CancellationError() }
            let produced: FloatImage
            switch operation {
            case .shape(let shape):
                produced = try image(cube: cube.buffer, descriptor: d, shape: shape)
            case .aperture(let aperture):
                produced = try run(cube: cube.buffer, descriptor: d, aperture: aperture)
            }
            guard cancellation?.isCancelled != true else { throw CancellationError() }
            progress?(1)
            return produced
        }
        let rowsPerTile = await data.scanTileRows(maximumRows: maximumTileRows)
        var output = [Float](repeating: 0, count: d.ry * d.rx)
        let ranges: [Range<Int>] = stride(from: 0, to: d.ry, by: rowsPerTile).map {
            $0..<min(d.ry, $0 + rowsPerTile)
        }
        var prefetcher = TilePrefetcher(data: data)
        for (index, range) in ranges.enumerated() {
            guard cancellation?.isCancelled != true else {
                prefetcher.cancel(); throw CancellationError()
            }
            let tile = try await prefetcher.tile(
                for: range,
                prefetching: index + 1 < ranges.count ? ranges[index + 1] : nil
            )
            guard cancellation?.isCancelled != true else {
                prefetcher.cancel(); throw CancellationError()
            }
            guard let buffer = MetalEngine.shared.device.makeBuffer(
                bytes: tile.pixels,
                length: tile.pixels.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
            ) else { prefetcher.cancel(); throw FourDError.allocationFailed }
            buffer.label = "4D scan tile rows \(range.lowerBound)..<\(range.upperBound)"
            let tileDescriptor = DatasetDescriptor(
                filePath: d.filePath, datasetPath: d.datasetPath,
                shape: [range.count, d.rx, d.qy, d.qx],
                dtypeDescription: d.dtypeDescription, chunkShape: nil
            )
            let tileImage: FloatImage
            switch operation {
            case .shape(let shape):
                tileImage = try image(cube: buffer, descriptor: tileDescriptor, shape: shape)
            case .aperture(let aperture):
                tileImage = try run(cube: buffer, descriptor: tileDescriptor, aperture: aperture)
            }
            output.replaceSubrange(range.lowerBound * d.rx..<range.upperBound * d.rx,
                                   with: tileImage.pixels)
            progress?(Double(range.upperBound) / Double(d.ry))
        }
        guard cancellation?.isCancelled != true else {
            prefetcher.cancel(); throw CancellationError()
        }
        return FloatImage(width: d.rx, height: d.ry, pixels: output)
    }

    /// Tiled max/mean diffraction patterns. Per-tile statistics stay on Metal;
    /// a weighted reduction combines them without retaining any prior tile.
    static func tiledDPStatistics(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (maxDP: [Float], meanDP: [Float]) {
        let rowsPerTile = await data.scanTileRows(maximumRows: maximumTileRows)
        let detectorCount = d.qy * d.qx
        var maximum = [Float](repeating: -.greatestFiniteMagnitude, count: detectorCount)
        var weightedMean = [Double](repeating: 0, count: detectorCount)
        let ranges: [Range<Int>] = stride(from: 0, to: d.ry, by: rowsPerTile).map {
            $0..<min(d.ry, $0 + rowsPerTile)
        }
        var source = TileGPUSource(data: data, descriptor: d,
                                   cube: await data.resident(for: d))
        for (index, range) in ranges.enumerated() {
            guard cancellation?.isCancelled != true else {
                source.cancel(); throw CancellationError()
            }
            let bound = try await source.binding(
                for: range,
                prefetching: index + 1 < ranges.count ? ranges[index + 1] : nil,
                label: "dpStatistics tile rows \(range.lowerBound)..<\(range.upperBound)"
            )
            let tileDescriptor = DatasetDescriptor(
                filePath: d.filePath, datasetPath: d.datasetPath,
                shape: [range.count, d.rx, d.qy, d.qx],
                dtypeDescription: d.dtypeDescription, chunkShape: nil
            )
            let stats = try MetalEngine.shared.dpStatistics(
                cube: bound.buffer, cubeOffset: bound.offset,
                dims: CubeDims(tileDescriptor)
            )
            let scanCount = Double(range.count * d.rx)
            for index in 0..<detectorCount {
                maximum[index] = max(maximum[index], stats.maxDP[index])
                weightedMean[index] += Double(stats.meanDP[index]) * scanCount
            }
            progress?(Double(range.upperBound) / Double(d.ry))
        }
        guard cancellation?.isCancelled != true else {
            source.cancel(); throw CancellationError()
        }
        let total = Double(d.ry * d.rx)
        return (maximum, weightedMean.map { Float($0 / total) })
    }

    /// Bounded selected-area diffraction. Each tile contributes one partial
    /// detector sum; only that Q-sized accumulator survives between tiles.
    static func tiledDiffraction(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        region: DetectorShape,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil
    ) async throws -> DiffractionPattern {
        let rowsPerTile = await data.scanTileRows(maximumRows: maximumTileRows)
        let fullMask = makeMask(shape: region, qy: d.ry, qx: d.rx)
        var sum = [Float](repeating: 0, count: d.qy * d.qx)
        let ranges: [Range<Int>] = stride(from: 0, to: d.ry, by: rowsPerTile).map {
            $0..<min(d.ry, $0 + rowsPerTile)
        }
        var source = TileGPUSource(data: data, descriptor: d,
                                   cube: await data.resident(for: d))
        for (index, range) in ranges.enumerated() {
            guard cancellation?.isCancelled != true else {
                source.cancel(); throw CancellationError()
            }
            let bound = try await source.binding(
                for: range,
                prefetching: index + 1 < ranges.count ? ranges[index + 1] : nil,
                label: "virtualDiffraction tile rows \(range.lowerBound)..<\(range.upperBound)"
            )
            let tileDescriptor = DatasetDescriptor(
                filePath: d.filePath, datasetPath: d.datasetPath,
                shape: [range.count, d.rx, d.qy, d.qx],
                dtypeDescription: d.dtypeDescription, chunkShape: nil
            )
            let mask = Array(fullMask[range.lowerBound * d.rx..<range.upperBound * d.rx])
            let partial = try MetalEngine.shared.virtualDiffraction(
                cube: bound.buffer, cubeOffset: bound.offset,
                dims: CubeDims(tileDescriptor), scanMask: mask
            )
            for index in sum.indices { sum[index] += partial[index] }
        }
        return DiffractionPattern(qy: d.qy, qx: d.qx, pixels: sum)
    }

    /// Bounded origin measurement after a probe radius has been established.
    static func tiledMeasuredOrigins(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        probeRadius: Float,
        rscale: Float = 1.2,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [Float] {
        let rowsPerTile = await data.scanTileRows(maximumRows: maximumTileRows)
        var output = [Float](repeating: 0, count: d.ry * d.rx * 2)
        let ranges: [Range<Int>] = stride(from: 0, to: d.ry, by: rowsPerTile).map {
            $0..<min(d.ry, $0 + rowsPerTile)
        }
        var source = TileGPUSource(data: data, descriptor: d,
                                   cube: await data.resident(for: d))
        for (index, range) in ranges.enumerated() {
            guard cancellation?.isCancelled != true else {
                source.cancel(); throw CancellationError()
            }
            let bound = try await source.binding(
                for: range,
                prefetching: index + 1 < ranges.count ? ranges[index + 1] : nil,
                label: "measureOrigins tile rows \(range.lowerBound)..<\(range.upperBound)"
            )
            let params = OriginParams(
                ry: UInt32(range.count), rx: UInt32(d.rx),
                qy: UInt32(d.qy), qx: UInt32(d.qx),
                r: probeRadius, rscale: rscale
            )
            let measured = try MetalEngine.shared.measureOrigins(
                cube: bound.buffer, cubeOffset: bound.offset, params: params
            )
            output.replaceSubrange(range.lowerBound * d.rx * 2..<range.upperBound * d.rx * 2,
                                   with: measured)
            progress?(Double(range.upperBound) / Double(d.ry))
        }
        return output
    }

    /// Bounded center-of-mass measurement with optional per-position origins.
    static func tiledCenterOfMass(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        center: (x: Float, y: Float),
        origins: [Float]? = nil,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [Float] {
        precondition(origins == nil || origins?.count == d.ry * d.rx * 2)
        let rowsPerTile = await data.scanTileRows(maximumRows: maximumTileRows)
        var output = [Float](repeating: 0, count: d.ry * d.rx * 2)
        let ranges: [Range<Int>] = stride(from: 0, to: d.ry, by: rowsPerTile).map {
            $0..<min(d.ry, $0 + rowsPerTile)
        }
        var source = TileGPUSource(data: data, descriptor: d,
                                   cube: await data.resident(for: d))
        for (index, range) in ranges.enumerated() {
            guard cancellation?.isCancelled != true else {
                source.cancel(); throw CancellationError()
            }
            let bound = try await source.binding(
                for: range,
                prefetching: index + 1 < ranges.count ? ranges[index + 1] : nil,
                label: "centerOfMass tile rows \(range.lowerBound)..<\(range.upperBound)"
            )
            let tileOrigins = origins.map {
                Array($0[range.lowerBound * d.rx * 2..<range.upperBound * d.rx * 2])
            }
            let params = CoMParams(
                ry: UInt32(range.count), rx: UInt32(d.rx),
                qy: UInt32(d.qy), qx: UInt32(d.qx),
                cx: center.x, cy: center.y, useOrigins: 0
            )
            let measured = try MetalEngine.shared.centerOfMass(
                cube: bound.buffer, cubeOffset: bound.offset,
                params: params, origins: tileOrigins
            )
            output.replaceSubrange(range.lowerBound * d.rx * 2..<range.upperBound * d.rx * 2,
                                   with: measured)
            progress?(Double(range.upperBound) / Double(d.ry))
        }
        return output
    }

    // MARK: Fast path — analytic annulus (interactive dragging)

    /// Dispatch the annular-sum kernel over the whole cube.
    /// - Returns: a real-space `FloatImage` of shape [Rx × Ry].
    nonisolated static func run(cube: MTLBuffer,
                    descriptor d: DatasetDescriptor,
                    aperture a: Aperture) throws -> FloatImage {
        let params = ApertureParams(
            ry: UInt32(d.ry), rx: UInt32(d.rx),
            qy: UInt32(d.qy), qx: UInt32(d.qx),
            cx: a.centerX, cy: a.centerY,
            rInner: a.inner, rOuter: a.outer
        )
        let pixels = try MetalEngine.shared.virtualDetector(cube: cube, params: params)
        return FloatImage(width: d.rx, height: d.ry, pixels: pixels)
    }

    // MARK: General path — arbitrary detector mask

    /// Virtual image for any detector geometry, via the mask kernel.
    nonisolated static func image(cube: MTLBuffer,
                      descriptor d: DatasetDescriptor,
                      shape: DetectorShape) throws -> FloatImage {
        let mask = makeMask(shape: shape, qy: d.qy, qx: d.qx)
        let pixels = try MetalEngine.shared.virtualImage(cube: cube,
                                                         dims: CubeDims(d),
                                                         mask: mask)
        return FloatImage(width: d.rx, height: d.ry, pixels: pixels)
    }

    // MARK: Virtual diffraction (real-space region → summed pattern)

    /// Sum the diffraction patterns of the scan positions selected by `region`
    /// (in scan coordinates) into a single pattern — selected-area diffraction.
    nonisolated static func diffraction(cube: MTLBuffer,
                                        descriptor d: DatasetDescriptor,
                                        region: DetectorShape) throws -> DiffractionPattern {
        // The region is a mask over the SCAN grid (Ry × Rx), so reuse makeMask
        // with the scan dimensions in place of the detector dimensions.
        let mask = makeMask(shape: region, qy: d.ry, qx: d.rx)
        let pixels = try MetalEngine.shared.virtualDiffraction(cube: cube,
                                                              dims: CubeDims(d),
                                                              scanMask: mask)
        return DiffractionPattern(qy: d.qy, qx: d.qx, pixels: pixels)
    }

    /// Build the binary detector-space mask for a geometry, [Qy*Qx] row-major.
    /// Radial shapes match py4DSTEM's `make_detector` predicates exactly:
    /// circle r² < rOut²; annulus rIn² < r² < rOut².
    nonisolated static func makeMask(shape: DetectorShape, qy: Int, qx: Int) -> [Float] {
        var mask = [Float](repeating: 0, count: qy * qx)
        switch shape {
        case .circle(let cx, let cy, let radius):
            fillRadial(&mask, qy: qy, qx: qx, cx: cx, cy: cy,
                       rIn: 0, rOut: radius, includeInnerBoundary: true)
        case .annulus(let cx, let cy, let inner, let outer):
            fillRadial(&mask, qy: qy, qx: qx, cx: cx, cy: cy,
                       rIn: inner, rOut: outer, includeInnerBoundary: false)
        case .rectangle(let xMin, let xMax, let yMin, let yMax):
            let x0 = max(0, xMin), x1 = min(qx, xMax)
            let y0 = max(0, yMin), y1 = min(qy, yMax)
            guard x0 < x1, y0 < y1 else { break }
            for y in y0..<y1 {
                for x in x0..<x1 { mask[y * qx + x] = 1 }
            }
        case .point(let x, let y):
            if (0..<qx).contains(x), (0..<qy).contains(y) { mask[y * qx + x] = 1 }
        }
        return mask
    }

    private static func fillRadial(_ mask: inout [Float], qy: Int, qx: Int,
                                   cx: Float, cy: Float, rIn: Float, rOut: Float,
                                   includeInnerBoundary: Bool) {
        let rIn2 = rIn * rIn
        let rOut2 = rOut * rOut
        for y in 0..<qy {
            let dy = Float(y) - cy
            let dy2 = dy * dy
            for x in 0..<qx {
                let dx = Float(x) - cx
                let r2 = dx * dx + dy2
                let passesInner = includeInnerBoundary ? r2 >= rIn2 : r2 > rIn2
                if passesInner && r2 < rOut2 { mask[y * qx + x] = 1 }
            }
        }
    }
}
