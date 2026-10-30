//
//  VirtualDetector.swift
//  Role: The Analysis-layer wrapper for virtual-detector imaging. It turns a
//        high-level intent (a preset, a dragged annulus, or any py4DSTEM
//        detector geometry) into a CuboKit reduction (C1/C2, 2026-10-15:
//        virtual images, mean and max patterns, centre of mass; CuboKit 0.7.0:
//        the per-position origin) and hands back a `FloatImage`. What stays here
//        is the app's: the real-space region and the selected-area diffraction
//        (a Metal sum over the resident cube; the kit's weighted pattern is CPU
//        only) and the presets.
//
//  Detector convention, py4DSTEM make_detector (the kit's DetectorMask):
//  circle r² < rOut²; annulus rIn² < r² < rOut².
//
//  THREADING: `run(...)`/`image(...)` are synchronous and call into Metal
//  with waitUntilCompleted. Call them from a background task (AppState wraps
//  them in `Task.detached`), never directly on the main actor.
//

import CuboCore
import CuboPhase
import CuboVirtual
import Foundation
import Metal
import ShellMetal

// Moved here from App/AppState.swift 2026-09-02 (v2.5 step 2): Core consumed
// it, so it belongs to Core.
/// The virtual-detector aperture in detector pixels.
package struct Aperture: Equatable {
    package var centerX: Float
    package var centerY: Float
    package var inner: Float
    package var outer: Float

    package init(centerX: Float = 0, centerY: Float = 0, inner: Float = 0, outer: Float = 20) {
        self.centerX = centerX
        self.centerY = centerY
        self.inner = inner
        self.outer = outer
    }

    /// A gesture's raw edit (`self`) snapped to whole detector pixels, given the
    /// aperture it started from. A virtual detector sums whole pixels, so
    /// fractional radii are meaningless and stay rounded; the CENTRE is
    /// snapped only when the gesture actually moved it. After an origin fit or
    /// restore the live centre is fractional (the fitted mean, e.g.
    /// (69.3133, 54.5009)); rounding it on a radius-only drag published a
    /// "changed" centre, tripped `updateAperture`'s centre-change branch and
    /// discarded the fitted origin on rounding alone (open item "Radius-only
    /// aperture drag destroys the fitted origin", Gate D 2026-09-30). The
    /// clamp is AFTER rounding (ui-08): clamping the raw point to `width`
    /// first and then rounding would publish `width`, one past the last pixel,
    /// which `VirtualDetector` silently answers with an empty mask.
    package func snappedEdit(from previous: Aperture,
                             patternWidth: Int, patternHeight: Int) -> Aperture {
        var snapped = self
        snapped.centerX = centerX == previous.centerX
            ? previous.centerX
            : min(max(0, centerX.rounded()), Float(patternWidth - 1))
        snapped.centerY = centerY == previous.centerY
            ? previous.centerY
            : min(max(0, centerY.rounded()), Float(patternHeight - 1))
        snapped.inner = inner.rounded()
        snapped.outer = outer.rounded()
        return snapped
    }

    /// The recipe step's parameters for a `virtual_detector` run — mirrors
    /// `DiskDetectionParams.replayParameters(kernel:)` (C4(b)). `shape` is a
    /// `VirtualShapeMode.rawValue`: that enum is a Session-layer recipe
    /// vocabulary type and Core does not depend on Session, so the caller
    /// passes the already-live string instead of the enum.
    package nonisolated static func replayParameters(shape: String, aperture: Aperture) -> [String: String] {
        [
            "shape": shape,
            "center_x": String(aperture.centerX), "center_y": String(aperture.centerY),
            "inner": String(aperture.inner), "outer": String(aperture.outer),
        ]
    }
}


// MARK: - Detector geometry (py4DSTEM get_virtual_image modes)

/// A detector geometry in detector-pixel coordinates
/// (X = column / qx index, Y = row / qy index).
package enum DetectorShape: Equatable {
    case circle(centerX: Float, centerY: Float, radius: Float)
    case annulus(centerX: Float, centerY: Float, inner: Float, outer: Float)
    /// Half-open pixel-index bounds, [xMin, xMax) × [yMin, yMax).
    case rectangle(xMin: Int, xMax: Int, yMin: Int, yMax: Int)
    /// Single detector pixel.
    case point(x: Int, y: Int)
}

/// Real-space region shape for virtual diffraction. A point is plain scrubbing
/// (one position); a region sums its positions' patterns. Moved from
/// `App/AppState.swift` (C7 session 4, budget relocation) — pure geometry
/// selector, no AppState dependency.
package enum RegionShape: String, CaseIterable, Identifiable {
    case point     = "Point"
    case rectangle = "Rectangle"
    case circle    = "Circle"
    package var id: String { rawValue }
}

extension DetectorShape {
    /// The current real-space region as a scan-space `DetectorShape`,
    /// centered on the selected scan position. Moved from `AppState.
    /// realSpaceRegionShape` (C7 session 4, budget relocation) — pure
    /// geometry over the shape choice, the region radius, and the scan
    /// position, none of which need AppState.
    package static func realSpaceRegion(
        shape: RegionShape, radius: Float, scanX: Int, scanY: Int
    ) -> DetectorShape {
        let r = Int(radius.rounded())
        switch shape {
        case .point:
            return .point(x: scanX, y: scanY)
        case .rectangle:
            return .rectangle(xMin: scanX - r, xMax: scanX + r + 1,
                              yMin: scanY - r, yMax: scanY + r + 1)
        case .circle:
            // Centred on the selected pixel's CENTRE — `fillRadial` names a
            // pixel by its integer index, as the drawn ring and py4DSTEM's
            // `virtualimage.py` np.indices mask do. A `+ 0.5` on the centre
            // put the mask on the pixel corner, half a pixel off the drawn
            // ROI in both axes (register D025, Gate D 2026-09-30). The
            // `+ 0.5` on the radius is unchanged and is NOT the rectangle's
            // rule: with the strict `<` it takes pixels whose centres lie up
            // to half a pixel OUTSIDE the drawn ring (R 5: 97 px; `d ≤ R` would
            // be 81, py4DSTEM's strict `< R` 69). DEVIATION from py4DSTEM;
            // changing it moves numbers and is its own decision (open-items).
            return .circle(centerX: Float(scanX), centerY: Float(scanY),
                           radius: radius + 0.5)
        }
    }
}

// MARK: - Detector presets

/// Standard virtual-detector geometries. Radii are expressed as fractions of
/// the maximum usable detector radius so they scale to any pattern size.
package enum DetectorPreset: String, CaseIterable, Identifiable {
    case brightField = "Bright Field"
    case adf         = "ADF"
    case haadf       = "HAADF"
    case custom      = "Custom"

    package var id: String { rawValue }

    /// Inner/outer radii in *pixels* given the largest radius that fits.
    /// (Custom returns nil — the UI's draggable aperture drives it instead.)
    package func radii(maxRadius r: Float) -> (inner: Float, outer: Float)? {
        switch self {
        case .brightField: return (0,        0.20 * r)   // central disk
        case .adf:         return (0.25 * r, 0.55 * r)   // mid annulus
        case .haadf:       return (0.55 * r, 0.95 * r)   // high-angle annulus
        case .custom:      return nil
        }
    }

    /// Radii that follow the MEASURED beam when one exists (polish lane F,
    /// owner card S3): BF = 0…r, ADF = 3r…6r, each clipped to the detector
    /// edge `maxRadius`. The 3×–6× ADF rule is py4DSTEM's virtual-imaging
    /// tutorial (basics_01_visualization_and_virtualimaging.ipynb, the
    /// "Annular dark-field imaging" cell: `r_inner = probe_semiangle * 3`,
    /// `r_outer = probe_semiangle * 6`); the tutorial has no HAADF, so HAADF
    /// keeps its detector fraction. When there is no valid `probeRadius`, or
    /// 3r reaches the detector edge (no room for the annulus), the fractions
    /// of `radii(maxRadius:)` apply unchanged. BF is clipped, not refused,
    /// when r exceeds the edge.
    package func radii(
        maxRadius: Float, probeRadius: Float?
    ) -> (inner: Float, outer: Float)? {
        guard let r = probeRadius, r.isFinite, r > 0 else { return radii(maxRadius: maxRadius) }
        switch self {
        case .brightField: return (0, min(r, maxRadius))
        case .adf:
            guard 3 * r < maxRadius else { return radii(maxRadius: maxRadius) }
            return (3 * r, min(6 * r, maxRadius))
        case .haadf, .custom: return radii(maxRadius: maxRadius)
        }
    }

}

// MARK: - Tile prefetching (overlap tile I/O with GPU compute)

/// Reads the next scan tile while the caller's current tile is on the GPU.
/// At most two tiles are resident (one processing, one arriving); with the
/// halved per-tile row budget in FourDArray.scanTileRows, total staging
/// memory stays within the prior single-tile bound.
package nonisolated struct TilePrefetcher {
    private let data: FourDArray
    private var pending: Task<FourDScanTile, Error>?

    package init(data: FourDArray) { self.data = data }

    /// Return the tile for `range` (from the prefetch when one is pending),
    /// then begin reading `nextRange` in the background.
    package mutating func tile(
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
    package func cancel() { pending?.cancel() }
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
/// `tools/harnesses/virtual-detector-residency` asserts.
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
package nonisolated struct TileGPUSource {
    private let cube: ResidentCube?
    private let bytesPerScanRow: Int
    private var prefetcher: TilePrefetcher

    /// - Parameter cube: the array's resident cube when it holds one *for this
    ///   descriptor* (`FourDArray.resident(for:)`), else nil.
    package init(data: FourDArray, descriptor d: DatasetDescriptor, cube: ResidentCube?) {
        self.cube = cube
        self.bytesPerScanRow = d.rx * d.qy * d.qx * MemoryLayout<Float>.stride
        self.prefetcher = TilePrefetcher(data: data)
    }

    package var isResident: Bool { cube != nil }

    /// The buffer and byte offset holding `range`'s floats.
    package mutating func binding(
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

    package func cancel() { prefetcher.cancel() }
}

// MARK: - VirtualDetector

package nonisolated enum VirtualDetector {

    // MARK: Virtual images, mean and maximum patterns: CuboKit's (C1, 2026-10-15)

    /// Bounded-memory virtual imaging through `VirtualImaging.image`. Scan rows are read as contiguous tiles (the
    /// caller's `maximumTileRows`, else the smaller of the app's memory budget and the kit's 64 MiB), each position is
    /// summed in Double, and the result is converted to the app's Float image here, at the display edge. The CPU path:
    /// the reference definition, the same bits at every tiling and on every Mac, measured faster than the Metal
    /// dispatch it replaced on the owner's cubes (docs/archive/v5/cubokit-switch-results-2026-10-15.md).
    package static func tiledImage(
        data: FourDArray,
        descriptor: DatasetDescriptor,
        shape: DetectorShape,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> FloatImage {
        try await kitImage(data: data, descriptor: descriptor,
                           geometry: kitGeometry(for: shape, qy: descriptor.qy, qx: descriptor.qx),
                           maximumTileRows: maximumTileRows, cancellation: cancellation, progress: progress)
    }

    /// The dragged annulus: `Aperture` is the annulus `rIn² < r² < rOut²`, the kit's `.annulus`.
    package static func tiledRun(
        data: FourDArray,
        descriptor: DatasetDescriptor,
        aperture: Aperture,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> FloatImage {
        try await kitImage(data: data, descriptor: descriptor, geometry: kitGeometry(for: aperture),
                           maximumTileRows: maximumTileRows, cancellation: cancellation, progress: progress)
    }

    /// The kit's geometry for an app detector shape, or nil when the shape selects no detector pixel. The kit refuses a
    /// point off the detector, a rectangle bound below zero, a negative radius and an annulus that is not outer > inner;
    /// the app answers each with an empty mask (a zero image), so those shapes never reach the kit. The rectangle is
    /// clamped to the detector first, as `makeMask` clamps it. Row first: the app's y is the kit's row.
    package nonisolated static func kitGeometry(for shape: DetectorShape, qy: Int, qx: Int) -> DetectorGeometry? {
        switch shape {
        case .circle(let cx, let cy, let radius):
            guard cx.isFinite, cy.isFinite, radius.isFinite, radius > 0 else { return nil }
            return .circle(centerRow: Double(cy), centerColumn: Double(cx), radius: Double(radius))
        case .annulus(let cx, let cy, let inner, let outer):
            return annulusGeometry(cx: cx, cy: cy, inner: inner, outer: outer)
        case .rectangle(let xMin, let xMax, let yMin, let yMax):
            let x0 = max(0, xMin), x1 = min(qx, xMax), y0 = max(0, yMin), y1 = min(qy, yMax)
            guard x0 < x1, y0 < y1 else { return nil }
            return .rectangle(rowMin: Double(y0), rowMax: Double(y1), columnMin: Double(x0), columnMax: Double(x1))
        case .point(let x, let y):
            guard (0..<qx).contains(x), (0..<qy).contains(y) else { return nil }
            return .point(row: y, column: x)
        }
    }

    package nonisolated static func kitGeometry(for aperture: Aperture) -> DetectorGeometry? {
        annulusGeometry(cx: aperture.centerX, cy: aperture.centerY, inner: aperture.inner, outer: aperture.outer)
    }

    private nonisolated static func annulusGeometry(cx: Float, cy: Float, inner: Float, outer: Float) -> DetectorGeometry? {
        guard cx.isFinite, cy.isFinite, inner.isFinite, outer.isFinite, inner >= 0, outer > inner else { return nil }
        return .annulus(centerRow: Double(cy), centerColumn: Double(cx), inner: Double(inner), outer: Double(outer))
    }

    /// Scan rows per tile. The caller's number when it gives one; otherwise the smaller of the app's budget, which
    /// sizes from the READ extent of a binned or cropped view (`FourDArray.scanTileRows`), and the kit's `.automatic`
    /// 64 MiB, a function of the shape alone.
    package static func kitTiling(data: FourDArray, descriptor d: DatasetDescriptor, maximumRows: Int?) async throws -> ScanTiling {
        let budget = await data.scanTileRows(maximumRows: maximumRows)
        guard maximumRows == nil else { return .rows(budget) }
        let shape = try CubeShape(scanRows: d.ry, scanColumns: d.rx, detectorRows: d.qy, detectorColumns: d.qx)
        return .rows(max(1, min(budget, try ScanTiling.automatic.rowsPerTile(for: shape))))
    }

    private static func kitImage(
        data: FourDArray, descriptor d: DatasetDescriptor, geometry: DetectorGeometry?,
        maximumTileRows: Int?, cancellation: AnalysisCancellationToken?, progress: (@Sendable (Double) -> Void)?
    ) async throws -> FloatImage {
        guard cancellation?.isCancelled != true else { throw CancellationError() }
        guard let geometry else {
            progress?(1)
            return FloatImage(width: d.rx, height: d.ry, pixels: [Float](repeating: 0, count: d.ry * d.rx))
        }
        let source = try CuboCubeSource(data, descriptor: d, cancellation: cancellation)
        let image = try await VirtualImaging.image(
            of: source, geometry: geometry, path: .cpu,
            tiling: try await kitTiling(data: data, descriptor: d, maximumRows: maximumTileRows), progress: progress)
        guard cancellation?.isCancelled != true else { throw CancellationError() }
        return FloatImage(width: d.rx, height: d.ry, pixels: image.values.map { Float($0) })
    }

    /// Tiled max and mean diffraction patterns through `VirtualDiffraction.meanAndMax`. The Metal path: its kernels are
    /// compensated and agree with the CPU reference to 2.4e-13, and on the study cube it is within 1.5 x the time of the
    /// kernel it replaced where the CPU path is not (docs/archive/v5/cubokit-switch-results-2026-10-15.md, P4). A
    /// machine without a Metal device runs the CPU path.
    package static func tiledDPStatistics(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (maxDP: [Float], meanDP: [Float]) {
        guard cancellation?.isCancelled != true else { throw CancellationError() }
        let source = try CuboCubeSource(data, descriptor: d, cancellation: cancellation)
        let tiling = try await kitTiling(data: data, descriptor: d, maximumRows: maximumTileRows)
        let both: (mean: DetectorImage, max: DetectorImage)
        do {
            both = try await VirtualDiffraction.meanAndMax(of: source, path: .metal, tiling: tiling, progress: progress)
        } catch CuboVirtualError.noMetalDevice {
            both = try await VirtualDiffraction.meanAndMax(of: source, path: .cpu, tiling: tiling, progress: progress)
        }
        guard cancellation?.isCancelled != true else { throw CancellationError() }
        return (both.max.values.map { Float($0) }, both.mean.values.map { Float($0) })
    }

    /// Selected-area diffraction: the SUM of the patterns over the scan positions `region` selects (the CBED pane's
    /// definition). CuboVirtual's `VirtualDiffraction.pattern(statistic: .mean, scan: .mask)` on the Metal path (compensated
    /// Float32 sums combined in Double, relative 1e-5 of the CPU reference) times the selected count, and on a Mac without a
    /// Metal device the CPU one. An empty selection gives the zero pattern, as the sum always did.
    package static func tiledDiffraction(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        region: DetectorShape,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil
    ) async throws -> DiffractionPattern {
        guard cancellation?.isCancelled != true else { throw CancellationError() }
        let take = makeMask(shape: region, qy: d.ry, qx: d.rx).map { $0 != 0 }
        let count = take.reduce(0) { $0 + ($1 ? 1 : 0) }
        guard count > 0 else { return DiffractionPattern(qy: d.qy, qx: d.qx, pixels: [Float](repeating: 0, count: d.qy * d.qx)) }
        let source = try CuboCubeSource(data, descriptor: d, cancellation: cancellation)
        let tiling = try await kitTiling(data: data, descriptor: d, maximumRows: maximumTileRows)
        let mean: DetectorImage
        do {
            mean = try await VirtualDiffraction.pattern(of: source, statistic: .mean, scan: .mask(take), path: .metal, tiling: tiling)
        } catch CuboVirtualError.noMetalDevice {
            mean = try await VirtualDiffraction.pattern(of: source, statistic: .mean, scan: .mask(take), path: .cpu, tiling: tiling)
        }
        guard cancellation?.isCancelled != true else { throw CancellationError() }
        let n = Double(count)
        return DiffractionPattern(qy: d.qy, qx: d.qx, pixels: mean.values.map { Float($0 * n) })
    }

    /// Per-position origin measurement after a probe radius has been established: CuboVirtual's iterated-window estimator
    /// (`OriginMeasurement.measure(estimator: .iteratedWindow)`, CuboKit 0.7.0), on the Metal path (`cubo_measure_origin`) and, on a
    /// Mac without a Metal device, the CPU one (they agree within relative 1e-5). Returns interleaved [x0, y0] per scan
    /// position, x the detector column and y the detector row, as the former kernel did.
    package static func tiledMeasuredOrigins(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        probeRadius: Float,
        rscale: Float = 1.2,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [Float] {
        guard cancellation?.isCancelled != true else { throw CancellationError() }
        let source = try CuboCubeSource(data, descriptor: d, cancellation: cancellation)
        let tiling = try await kitTiling(data: data, descriptor: d, maximumRows: maximumTileRows)
        let map = try await measureIteratedWindow(source, radius: probeRadius, scale: rscale, tiling: tiling, progress: progress)
        guard cancellation?.isCancelled != true else { throw CancellationError() }
        var output = [Float](repeating: 0, count: d.ry * d.rx * 2)
        for i in 0..<d.ry * d.rx {
            output[2 * i] = Float(map.column.values[i])
            output[2 * i + 1] = Float(map.row.values[i])
        }
        return output
    }

    /// The iterated-window origin map of `source`: Metal, else CPU when the Mac has no Metal device.
    package static func measureIteratedWindow(
        _ source: some CubeSource, radius: Float, scale: Float, tiling: ScanTiling,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> OriginMap {
        do {
            return try await OriginMeasurement.measure(
                of: source, radius: Double(radius), radiusScale: Double(scale),
                estimator: .iteratedWindow(), path: .metal, tiling: tiling, progress: progress)
        } catch CuboVirtualError.noMetalDevice {
            return try await OriginMeasurement.measure(
                of: source, radius: Double(radius), radiusScale: Double(scale),
                estimator: .iteratedWindow(), path: .cpu, tiling: tiling, progress: progress)
        }
    }

    /// Bounded centre-of-mass SHIFT: `CenterOfMass.measure` (py4DSTEM's definition in Double: negative intensities count,
    /// a zero sum is NaN) and `CenterOfMassReference.normalize` against the reference, NaN to 0 as py4DSTEM's
    /// preprocessing does. The reference is the per-position `origins` when given (interleaved [x, y], x the detector
    /// column), else the one `center`; the shift is `measured - reference` in both. CPU path: the kit advises it for
    /// dark-subtracted cubes, whose small sums the Metal kernel does not resolve. Returns interleaved [x, y], as before.
    /// C2 (2026-10-15): the Metal kernel clamped each pixel at 0 and answered a non-positive sum with the reference.
    package static func tiledCenterOfMass(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        center: (x: Float, y: Float),
        origins: [Float]? = nil,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [Float] {
        precondition(origins == nil || origins?.count == d.ry * d.rx * 2)
        guard cancellation?.isCancelled != true else { throw CancellationError() }
        let count = d.ry * d.rx
        let source = try CuboCubeSource(data, descriptor: d, cancellation: cancellation)
        let maps = try await CenterOfMass.measure(
            of: source, mask: nil, path: .cpu,
            tiling: try await kitTiling(data: data, descriptor: d, maximumRows: maximumTileRows), progress: progress)
        let measured = try ScanVectorField(scanRows: d.ry, scanColumns: d.rx,
                                           row: maps.row.values, column: maps.column.values)
        let reference: ScanVectorField
        if let origins {
            reference = try ScanVectorField(scanRows: d.ry, scanColumns: d.rx,
                                            row: (0..<count).map { Double(origins[2 * $0 + 1]) },
                                            column: (0..<count).map { Double(origins[2 * $0]) })
        } else {
            reference = try ScanVectorField(scanRows: d.ry, scanColumns: d.rx,
                                            row: [Double](repeating: Double(center.y), count: count),
                                            column: [Double](repeating: Double(center.x), count: count))
        }
        let shift = try CenterOfMassReference.normalize(measured, reference: .given(reference)).normalized
        guard cancellation?.isCancelled != true else { throw CancellationError() }
        var output = [Float](repeating: 0, count: count * 2)
        for i in 0..<count {
            output[2 * i] = Float(shift.column[i])
            output[2 * i + 1] = Float(shift.row[i])
        }
        return output
    }

    /// Build the binary detector-space mask for a geometry, [Qy*Qx] row-major.
    /// Radial shapes match py4DSTEM's `make_detector` predicates exactly:
    /// circle r² < rOut²; annulus rIn² < r² < rOut².
    package nonisolated static func makeMask(shape: DetectorShape, qy: Int, qx: Int) -> [Float] {
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
