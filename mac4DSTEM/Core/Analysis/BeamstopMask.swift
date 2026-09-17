//
//  BeamstopMask.swift
//  mac4DSTEM
//
//  A port of py4DSTEM's `DataCube.get_beamstop_mask`
//  (datacube/datacube.py). It turns a mean (or max) diffraction pattern into a
//  boolean mask of the beamstop region, so `FriedelOrigin` can find the beam
//  centre behind a beamstop it cannot see through otherwise.
//
//  Convention, matching py4DSTEM: the returned mask is `true` UNDER the
//  beamstop (and the dim border it also excludes), `false` in the bright
//  pattern. `FriedelOrigin.origin` wants the opposite (`true` in the pattern),
//  so a caller passes `mask.map { !$0 }` — the same inversion py4DSTEM applies
//  at the call site.
//
//  DEVIATION from py4DSTEM: none in the algorithm. The morphology py4DSTEM gets
//  from scipy is reproduced exactly here — `binary_fill_holes` as a
//  4-connected flood fill of the background from the border (scipy's default
//  structure), and `distance_transform_edt(mask) < distance_edge` as an exact
//  Euclidean test against every pixel within `ceil(distance_edge)`. The
//  friedel-origin-test harness pins both against scipy directly.
//

import Foundation

package nonisolated enum BeamstopMask {

    /// The beamstop mask of a mean (or max) diffraction pattern, row-major
    /// `[row * width + col]`. `threshold` is py4DSTEM's percentile (0.25 = the
    /// dimmest 25 % of pixels fall outside the pattern); `distanceEdge` expands
    /// the mask that many pixels past the beamstop; `includeEdges` drops the
    /// border row/column. Returns `true` under the beamstop, `false` in the
    /// pattern.
    package static func mask(meanDP: [Float], height: Int, width: Int,
                             threshold: Float = 0.25, distanceEdge: Float = 2.0,
                             includeEdges: Bool = true) -> [Bool] {
        let n = height * width
        precondition(meanDP.count == n, "meanDP must be height*width")

        // 1. Percentile threshold: sort, take the value at round(N·threshold),
        //    keep pixels at or above it. np.round is round-half-to-even; the
        //    index is clipped into range exactly as py4DSTEM clips it.
        let sorted = meanDP.sorted()
        let raw = (Double(n) * Double(threshold)).rounded(.toNearestOrEven)
        let index = min(max(Int(raw), 0), n - 1)
        let intensityThreshold = sorted[index]
        var keep = meanDP.map { $0 >= intensityThreshold }   // true = pattern

        // 2. Remove bright specks stranded in the dim region:
        //    keep = NOT( fillHoles( NOT keep ) ).
        var dim = keep.map { !$0 }
        fillHoles(&dim, height: height, width: width)
        keep = dim.map { !$0 }

        // 3. Fill dark specks inside the pattern (e.g. between diffraction disks).
        fillHoles(&keep, height: height, width: width)

        // 4. Drop the border.
        if includeEdges {
            for col in 0..<width { keep[col] = false; keep[(height - 1) * width + col] = false }
            for row in 0..<height { keep[row * width] = false; keep[row * width + (width - 1)] = false }
        }

        // 5. distance_transform_edt(keep) < distanceEdge, which flips the sense
        //    to true = beamstop (the dim/edge region, dilated `distanceEdge` px).
        return dilateBackground(keep, height: height, width: width, distance: distanceEdge)
    }

    /// scipy `binary_fill_holes`: set to `true` every `false` pixel not
    /// 4-connected to the border. In place; `true` pixels are untouched.
    private static func fillHoles(_ mask: inout [Bool], height: Int, width: Int) {
        var reachable = [Bool](repeating: false, count: height * width)
        var stack = [Int]()
        func push(_ row: Int, _ col: Int) {
            guard row >= 0, row < height, col >= 0, col < width else { return }
            let i = row * width + col
            if !mask[i] && !reachable[i] { reachable[i] = true; stack.append(i) }
        }
        for col in 0..<width { push(0, col); push(height - 1, col) }
        for row in 0..<height { push(row, 0); push(row, width - 1) }
        while let i = stack.popLast() {
            let row = i / width, col = i % width
            push(row - 1, col); push(row + 1, col); push(row, col - 1); push(row, col + 1)
        }
        for i in 0..<(height * width) where !mask[i] && !reachable[i] { mask[i] = true }
    }

    /// `distance_transform_edt(keep) < distance`: `true` where the Euclidean
    /// distance to the nearest `false` pixel is `< distance` — i.e. the `false`
    /// (background) region dilated by `distance`. A `false` pixel is at distance
    /// 0, so it is always `true` in the result; that is what flips the sense to
    /// true = beamstop.
    private static func dilateBackground(_ keep: [Bool], height: Int, width: Int,
                                         distance: Float) -> [Bool] {
        let radius = Int(distance.rounded(.up))          // no pixel past this can qualify
        let distanceSquared = distance * distance
        var out = [Bool](repeating: false, count: height * width)
        for row in 0..<height {
            for col in 0..<width {
                if !keep[row * width + col] { out[row * width + col] = true; continue }
                var hit = false
                var dRow = -radius
                loop: while dRow <= radius {
                    let r = row + dRow
                    if r >= 0, r < height {
                        var dCol = -radius
                        while dCol <= radius {
                            let c = col + dCol
                            if c >= 0, c < width, !keep[r * width + c],
                               Float(dRow * dRow + dCol * dCol) < distanceSquared {
                                hit = true; break loop
                            }
                            dCol += 1
                        }
                    }
                    dRow += 1
                }
                out[row * width + col] = hit
            }
        }
        return out
    }
}
