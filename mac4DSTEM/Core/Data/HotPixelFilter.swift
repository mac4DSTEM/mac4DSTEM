//
//  HotPixelFilter.swift
//  Role: py4DSTEM's `filter_hot_pixels` (preprocess/preprocess.py:349-460,
//        pinned commit f050d207), ported for the preprocessing export. Pure
//        compute on one detector frame at a time; the streaming around it
//        (mean pattern pass, per-pattern replacement) lives in
//        `BraggVectorEMDWriter`.
//
//  The algorithm, as py4DSTEM states it:
//   1. mean pattern over every scan position;
//   2. at each pixel the `ind_compare`-th brightest of its 21-pixel
//      neighbourhood (3x3, plus the four 3-pixel edge arms ±2 away — the
//      corners of the 5x5 square excluded), the window WRAPPING at the
//      detector edge (np.roll);
//   3. mask = mean - that value > thresh;
//   4. in every pattern, each masked pixel (row-major order, in place, so a
//      later pixel's window sees an earlier replacement) <- the median of its
//      3x3 window, clipped (not wrapped) at the edge.
//
//  DEVIATION: the mean is accumulated in Double and rounded once to Float;
//  numpy accumulates a float32 axis=(0,1) mean sequentially in float32. A
//  pixel is classified differently only when its excess lies within the
//  float32 accumulation error of `thresh`. That error was measured on the
//  raw 060 cube (108 900 patterns, numpy 2.5.0; Gate B refuter 2026-10-01):
//  ~1e-5 relative at pixel values 1e3-1e4, but ~1e-3 relative (45-230
//  counts) at 2e5 against thresh 8 — so inside a bright direct disk
//  py4DSTEM's own mask is partly an accumulation artefact, and mask identity
//  with py4DSTEM holds only where |excess - thresh| exceeds that error.
//  Everything after the mean is
//  float32 arithmetic exactly as numpy does it (the subtraction, the
//  threshold cast to float32, the even-count median as (a+b)/2).
//

import Foundation

package nonisolated enum HotPixelFilter {

    /// py4DSTEM's default `ind_compare`: compare with the SECOND brightest of
    /// the neighbourhood, so a pixel only counts as hot when it exceeds even
    /// its brightest neighbour's rival. Not exposed in the app.
    package static let indCompare = 1

    /// Row-major flat indices (`row * width + column`) of the pixels
    /// py4DSTEM's mask marks in `mean` (`height * width`, row-major).
    package static func maskIndices(mean: [Float], height: Int, width: Int,
                                    threshold: Double,
                                    indCompare: Int = HotPixelFilter.indCompare) -> [Int] {
        precondition(mean.count == height * width && height > 0 && width > 0)
        // The offsets py4DSTEM rolls by: 3x3, then (a, ±2) and (±2, b) arms.
        var offsets = [(Int, Int)]()
        for dy in -1...1 { for dx in -1...1 { offsets.append((dy, dx)) } }
        for dy in -1...1 { offsets.append((dy, -2)); offsets.append((dy, 2)) }
        for dx in -1...1 { offsets.append((-2, dx)); offsets.append((2, dx)) }
        let threshold32 = Float(threshold)
        var indices = [Int]()
        var window = [Float](repeating: 0, count: offsets.count)
        for row in 0..<height {
            for column in 0..<width {
                for (slot, offset) in offsets.enumerated() {
                    let r = ((row + offset.0) % height + height) % height
                    let c = ((column + offset.1) % width + width) % width
                    window[slot] = mean[r * width + c]
                }
                window.sort()
                let compare = window[window.count - 1 - indCompare]
                if mean[row * width + column] - compare > threshold32 {
                    indices.append(row * width + column)
                }
            }
        }
        return indices
    }

    /// Replace each masked pixel of one pattern (`pixels[base ..< base +
    /// height * width]`) by the median of its clipped 3x3 window, in `mask`'s
    /// order and in place.
    package static func replace(mask: [Int], in pixels: inout [Float], base: Int,
                                height: Int, width: Int) {
        var window = [Float]()
        window.reserveCapacity(9)
        for flat in mask {
            let row = flat / width, column = flat % width
            window.removeAll(keepingCapacity: true)
            for r in max(0, row - 1)..<min(height, row + 2) {
                for c in max(0, column - 1)..<min(width, column + 2) {
                    window.append(pixels[base + r * width + c])
                }
            }
            window.sort()
            let middle = window.count / 2
            pixels[base + flat] = window.count % 2 == 1
                ? window[middle]
                : (window[middle - 1] + window[middle]) / 2
        }
    }
}
