//
//  FFT1D.swift
//  Role: 1D complex FFT (vDSP radix-2), used for the azimuthal circular
//        correlation in ACOM orientation matching — correlating a polar
//        pattern against templates over all in-plane rotation angles at once.
//
//  Like FFT2D: nonisolated + @unchecked Sendable (an FFTSetup is immutable and
//  thread-shareable); transform buffers are caller-owned.
//

import Foundation
import Accelerate

package nonisolated final class FFT1D: @unchecked Sendable {

    package let n: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup

    package init?(n: Int) {
        guard n > 0, n & (n - 1) == 0 else { return nil }
        self.n = n
        self.log2n = vDSP_Length(log2(Double(n)))
        guard let s = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        self.setup = s
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// In-place complex FFT. Inverse is unnormalized (vDSP convention); ACOM
    /// only needs the argmax of the correlation, so the scale is irrelevant.
    package func transform(re: inout [Float], im: inout [Float], forward: Bool) {
        precondition(re.count == n && im.count == n)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n,
                             FFTDirection(forward ? kFFTDirection_Forward : kFFTDirection_Inverse))
            }
        }
    }

    package static func nextPow2(_ v: Int) -> Int {
        var p = 1
        while p < v { p <<= 1 }
        return p
    }
}
