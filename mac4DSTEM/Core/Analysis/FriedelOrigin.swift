//
//  FriedelOrigin.swift
//  mac4DSTEM
//
//  Per-pattern beam origin from Friedel symmetry — a port of py4DSTEM's
//  `get_origin_friedel` (process/calibration/origin.py). The diffraction
//  pattern is (approximately) centrosymmetric about the unscattered beam, so
//  the peak of the pattern's self-correlation with its point reflection lands
//  at twice the origin. Padding the pattern to double size and taking
//  `Re(IFFT2(FFT2(im)^2))` computes exactly that self-correlation (the
//  point-reflection of a real image is the conjugate in reciprocal space, so
//  `G^2` rather than `|G|^2`), and its argmax, halved, is the origin.
//
//  Why it earns a place beside the existing centre-of-mass origin: with a
//  boolean `mask` that is `false` under a beamstop, the masked-correlation
//  form (py4DSTEM's three-term normalisation) recovers the origin even when the
//  direct beam is occluded — the case the CoM path cannot serve. Opt-in; it
//  changes no existing origin.
//
//  DEVIATION from py4DSTEM: the subpixel parabola reads the argmax's four
//  neighbours with wraparound indexing rather than raw `cc[x+1, y]`. For a real
//  pattern the self-correlation peak is interior (≈ the doubled-array centre),
//  where wrap never triggers and the two agree bit-for-bit; py4DSTEM would
//  `IndexError` on the pathological edge peak this guards against.
//

import Foundation

package nonisolated enum FriedelOrigin {

    /// The origin of one diffraction pattern, in the pattern's own frame:
    /// `row` along the first (height) axis, `col` along the second (width) axis.
    /// Maps to the app's detector frame at the call site, the same swap
    /// `appOriginMaps` applies (py4DSTEM qx0 = row = app y; qy0 = col = app x).
    ///
    /// `pattern` is row-major `[row * width + col]`, `height * width` long.
    /// `mask`, when given, is `true` in the pattern and `false` under a
    /// beamstop, the same length and layout; supplying it is what makes the
    /// method beamstop-tolerant. Returns `nil` only if the FFT setup or the
    /// dimensions are invalid.
    package static func origin(pattern: [Float], height: Int, width: Int,
                               mask: [Bool]? = nil) -> (row: Float, col: Float)? {
        guard height > 0, width > 0, pattern.count == height * width else { return nil }
        let padH = 2 * height, padW = 2 * width
        guard let fft = FFT2D(nx: padW, ny: padH) else { return nil }

        let cc: [Float]
        if let mask {
            guard mask.count == height * width else { return nil }
            let prepared = prepareBeamstop(mask: mask, height: height, width: width, fft: fft)
            cc = maskedCorrelation(pattern: pattern, height: height, width: width,
                                   prepared: prepared, fft: fft)
        } else {
            cc = plainCorrelation(pattern: pattern, height: height, width: width, fft: fft)
        }
        return peak(cc, height: height, width: width)
    }

    /// The mask-dependent transforms, precomputed ONCE for a whole scan — the
    /// beamstop mask is the same for every pattern, so rebuilding `maskPad`, `M`
    /// and `IFFT2(M²)` per pattern (two of the eight FFTs) was pure waste. Feed
    /// this to `origin(pattern:height:width:prepared:fft:)`. // v3.1 speed
    package struct PreparedBeamstop: Sendable {
        fileprivate let maskPad: [Float]
        fileprivate let mRe: [Float], mIm: [Float]            // M = FFT2(maskPad)
        fileprivate let ifftM2Re: [Float], ifftM2Im: [Float]  // IFFT2(M²)
    }

    package static func prepareBeamstop(mask: [Bool], height: Int, width: Int,
                                        fft: FFT2D) -> PreparedBeamstop {
        let padW = 2 * width, n = 2 * height * padW
        var maskPad = [Float](repeating: 1, count: n)
        for row in 0..<height {
            for col in 0..<width { maskPad[row * padW + col] = mask[row * width + col] ? 1 : 0 }
        }
        var mRe = maskPad, mIm = [Float](repeating: 0, count: n)
        fft.transform(re: &mRe, im: &mIm, forward: true)      // M
        var m2Re = mRe, m2Im = mIm
        squareInPlace(&m2Re, &m2Im)
        fft.transform(re: &m2Re, im: &m2Im, forward: false)   // IFFT2(M²)
        return PreparedBeamstop(maskPad: maskPad, mRe: mRe, mIm: mIm,
                                ifftM2Re: m2Re, ifftM2Im: m2Im)
    }

    /// One pattern's origin from a precomputed beamstop and a SHARED `FFT2D`
    /// (`FFT2D(nx: 2*width, ny: 2*height)`) — the full-scan fast path. `FFT2D` is
    /// safe to share across concurrent workers: each call owns its own buffers. // v3.1
    package static func origin(pattern: [Float], height: Int, width: Int,
                               prepared: PreparedBeamstop, fft: FFT2D) -> (row: Float, col: Float)? {
        guard height > 0, width > 0, pattern.count == height * width else { return nil }
        let cc = maskedCorrelation(pattern: pattern, height: height, width: width,
                                   prepared: prepared, fft: fft)
        return peak(cc, height: height, width: width)
    }

    /// Argmax of the correlation surface + a parabolic subpixel refinement,
    /// folded to the pattern frame (the peak sits at twice the origin).
    private static func peak(_ cc: [Float], height: Int, width: Int) -> (row: Float, col: Float) {
        let padH = 2 * height, padW = 2 * width
        var peakIndex = 0
        var peakValue = cc[0]
        for index in 1..<cc.count where cc[index] > peakValue { peakValue = cc[index]; peakIndex = index }
        let row = peakIndex / padW, col = peakIndex % padW
        func at(_ r: Int, _ c: Int) -> Float {
            cc[((r % padH + padH) % padH) * padW + ((c % padW + padW) % padW)]
        }
        let centre = at(row, col)
        let dRow = subpixel(minus: at(row - 1, col), centre: centre, plus: at(row + 1, col))
        let dCol = subpixel(minus: at(row, col - 1), centre: centre, plus: at(row, col + 1))
        let originRow = ((Float(row) + dRow) / 2).truncatingRemainder(dividingBy: Float(height))
        let originCol = ((Float(col) + dCol) / 2).truncatingRemainder(dividingBy: Float(width))
        return (originRow, originCol)
    }

    /// py4DSTEM's `(cc[+1] - cc[-1]) / (4·cc[0] - 2·cc[+1] - 2·cc[-1])`. The
    /// denominator is `-2·(second difference)` and is negative at a maximum;
    /// zero only on a flat triple, where the shift is defined as zero.
    private static func subpixel(minus: Float, centre: Float, plus: Float) -> Float {
        let denominator = 4 * centre - 2 * plus - 2 * minus
        guard denominator != 0 else { return 0 }
        return (plus - minus) / denominator
    }

    // MARK: - No beamstop: cc = Re(IFFT2(FFT2(im)^2))

    private static func plainCorrelation(pattern: [Float], height: Int, width: Int,
                                         fft: FFT2D) -> [Float] {
        let padH = 2 * height, padW = 2 * width
        var re = zeroPadded(pattern, height: height, width: width)
        var im = [Float](repeating: 0, count: padH * padW)
        fft.transform(re: &re, im: &im, forward: true)
        squareInPlace(&re, &im)
        fft.transform(re: &re, im: &im, forward: false)
        return re
    }

    // MARK: - Beamstop: py4DSTEM's three-term masked cross-correlation
    //
    //   term1 = Re( IFFT2(FFT2(im)^2) · IFFT2(M^2) )   [IFFT2(M^2) precomputed]
    //   term2 = Re( IFFT2(FFT2(im^2) · M) )            [M precomputed]
    //   term3 = Re( IFFT2(FFT2(im · maskPad)) )        [maskPad precomputed]
    //   cc    = (term1 - term3) / (term2 - term3)

    private static func maskedCorrelation(pattern: [Float], height: Int, width: Int,
                                          prepared: PreparedBeamstop, fft: FFT2D) -> [Float] {
        let padW = 2 * width, n = 2 * height * padW

        // A = IFFT2(FFT2(im)^2); term1 = Re(A · ifftM2).
        var aRe = zeroPadded(pattern, height: height, width: width)
        var aIm = [Float](repeating: 0, count: n)
        fft.transform(re: &aRe, im: &aIm, forward: true)
        squareInPlace(&aRe, &aIm)
        fft.transform(re: &aRe, im: &aIm, forward: false)

        // term2 = Re(IFFT2(FFT2(im^2) · M)).
        var sqRe = zeroPaddedSquared(pattern, height: height, width: width)
        var sqIm = [Float](repeating: 0, count: n)
        fft.transform(re: &sqRe, im: &sqIm, forward: true)
        var t2Re = [Float](repeating: 0, count: n)
        var t2Im = [Float](repeating: 0, count: n)
        for i in 0..<n {
            t2Re[i] = sqRe[i] * prepared.mRe[i] - sqIm[i] * prepared.mIm[i]
            t2Im[i] = sqRe[i] * prepared.mIm[i] + sqIm[i] * prepared.mRe[i]
        }
        fft.transform(re: &t2Re, im: &t2Im, forward: false)

        // term3 = Re(IFFT2(FFT2(im · maskPad))).
        var imMask = [Float](repeating: 0, count: n)
        for row in 0..<height {
            for col in 0..<width {
                let idx = row * padW + col
                imMask[idx] = pattern[row * width + col] * prepared.maskPad[idx]
            }
        }
        var t3Im = [Float](repeating: 0, count: n)
        fft.transform(re: &imMask, im: &t3Im, forward: true)
        fft.transform(re: &imMask, im: &t3Im, forward: false)

        var cc = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let term1 = aRe[i] * prepared.ifftM2Re[i] - aIm[i] * prepared.ifftM2Im[i]
            let denominator = t2Re[i] - imMask[i]
            cc[i] = denominator == 0 ? 0 : (term1 - imMask[i]) / denominator
        }
        return cc
    }

    // MARK: - Small helpers

    /// The pattern placed at the top-left of a `2h × 2w` zero field.
    private static func zeroPadded(_ pattern: [Float], height: Int, width: Int) -> [Float] {
        let padW = 2 * width
        var out = [Float](repeating: 0, count: 2 * height * padW)
        for row in 0..<height {
            for col in 0..<width { out[row * padW + col] = pattern[row * width + col] }
        }
        return out
    }

    /// The squared pattern placed at the top-left of a `2h × 2w` zero field.
    private static func zeroPaddedSquared(_ pattern: [Float], height: Int, width: Int) -> [Float] {
        let padW = 2 * width
        var out = [Float](repeating: 0, count: 2 * height * padW)
        for row in 0..<height {
            for col in 0..<width {
                let v = pattern[row * width + col]
                out[row * padW + col] = v * v
            }
        }
        return out
    }

    /// Complex square in place: `(a + bi)^2 = (a^2 - b^2) + 2ab i`.
    private static func squareInPlace(_ re: inout [Float], _ im: inout [Float]) {
        for i in 0..<re.count {
            let a = re[i], b = im[i]
            re[i] = a * a - b * b
            im[i] = 2 * a * b
        }
    }
}
