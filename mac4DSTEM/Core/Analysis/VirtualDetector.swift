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

// MARK: - VirtualDetector

nonisolated enum VirtualDetector {

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
