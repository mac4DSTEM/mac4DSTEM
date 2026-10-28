//
//  MatrixDFTCorrelationRow9Tests.swift
//  Lane F-B row 9 (archived docs/archive/v4/review-2026-09-30-findings.md): the matrix-DFT
//  upsampler's frequency wrap on an ODD axis. py4DSTEM's multicorr uses
//  ifftshift(arange(N)) - floor(N/2) (References/py4DSTEM-dev/py4DSTEM/process/utils/
//  multicorr.py:186, :195), whose middle bin is +(N-1)/2, not -(N+1)/2.
//  Oracle: a correlation spectrum of a band-limited peak at a KNOWN fractional
//  position (phase ramp on numpy-style frequencies); the refined peak must land on it.
//
//  The upsampler is CuboParallax's since 0.7.0 (the app's Float copy is gone); this is the app's consumer test of it, through
//  `ParallaxAlignment.correlationShift` (cross-power reference * conj(moving), moving = a delta at the origin, so the cross-power
//  is the ramp itself).
//

import XCTest
import struct CuboParallax.ParallaxShift
import struct CuboParallax.ParallaxSpectrum
import enum CuboParallax.ParallaxAlignment
@testable import mac4DSTEM

final class MatrixDFTCorrelationRow9Tests: XCTestCase {

    /// numpy fftfreq(n) * n : [0 ... (n-1)/2, -(n/2) ... -1] (odd n: the middle bin is positive).
    private func numpyFrequency(_ k: Int, _ n: Int) -> Double {
        Double(k < (n + 1) / 2 ? k : k - n)
    }

    private func refined(width: Int, height: Int, row: Double, column: Double) throws -> ParallaxShift {
        var re = [Double](repeating: 0, count: width * height)
        var im = re
        for r in 0..<height {
            for c in 0..<width {
                let angle = -2 * Double.pi * (
                    numpyFrequency(r, height) * row / Double(height)
                    + numpyFrequency(c, width) * column / Double(width))
                re[r * width + c] = cos(angle)
                im[r * width + c] = sin(angle)
            }
        }
        let delta = ParallaxSpectrum(rows: height, columns: width,
                                     real: [Double](repeating: 1, count: width * height),
                                     imaginary: [Double](repeating: 0, count: width * height))
        return try ParallaxAlignment.correlationShift(
            reference: ParallaxSpectrum(rows: height, columns: width, real: re, imaginary: im),
            moving: delta, upsampleFactor: 16)
    }

    func testRow9OddAxesRecoverTheKnownSubpixelShift() throws {
        for (w, h) in [(13, 11), (13, 12), (14, 11)] {
            let peak = try refined(width: w, height: h, row: 2.3, column: 3.6)
            XCTAssertEqual(peak.row, 2.3, accuracy: 0.03, "\(w)x\(h) row")
            XCTAssertEqual(peak.column, 3.6, accuracy: 0.03, "\(w)x\(h) column")
        }
    }

    func testRow9EvenAxesControl() throws {
        let peak = try refined(width: 14, height: 12, row: 2.3, column: 3.6)
        XCTAssertEqual(peak.row, 2.3, accuracy: 0.03)
        XCTAssertEqual(peak.column, 3.6, accuracy: 0.03)
    }
}
