//
//  FFT2D.swift
//  Role: The one 2D FFT implementation in the app — a thin wrapper around
//        vDSP's radix-2 complex 2D FFT with a cached setup. Used by DPC
//        (iDPC integration) and disk detection (cross-correlation).
//
//  vDSP's 2D FFT requires power-of-two dimensions; callers zero-pad with
//  `nextPow2` (see integrateIDPC / DiskDetector for the padding strategy and
//  its documented artifacts).
//
//  THREADING: an FFTSetup is immutable after creation and Apple documents it
//  as shareable across threads, so one FFT2D instance can serve concurrent
//  workers — hence the @unchecked Sendable. The transform buffers themselves
//  are caller-owned (inout), never shared.
//

import Foundation
import Accelerate

nonisolated final class FFT2D: @unchecked Sendable {

    let nx: Int          // columns (power of two)
    let ny: Int          // rows (power of two)
    private let log2x: vDSP_Length
    private let log2y: vDSP_Length
    private let setup: FFTSetup

    /// Fails if either dimension is not a power of two (or a setup can't be
    /// allocated).
    init?(nx: Int, ny: Int) {
        guard nx > 0, ny > 0,
              nx & (nx - 1) == 0, ny & (ny - 1) == 0 else { return nil }
        self.nx = nx
        self.ny = ny
        self.log2x = vDSP_Length(log2(Double(nx)))
        self.log2y = vDSP_Length(log2(Double(ny)))
        guard let s = vDSP_create_fftsetup(max(log2x, log2y), FFTRadix(kFFTRadix2))
        else { return nil }
        self.setup = s
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// In-place complex 2D FFT over row-major [ny * nx] split-complex data.
    /// The inverse is unnormalized, matching vDSP — `scaleInverse` divides by
    /// nx*ny so forward→inverse round-trips to the input.
    func transform(re: inout [Float], im: inout [Float],
                   forward: Bool, scaleInverse: Bool = true) {
        precondition(re.count == nx * ny && im.count == nx * ny)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft2d_zip(setup, &split, 1, 0, log2x, log2y,
                               FFTDirection(forward ? kFFTDirection_Forward
                                                    : kFFTDirection_Inverse))
            }
        }
        if !forward && scaleInverse {
            var s = 1 / Float(nx * ny)
            vDSP_vsmul(re, 1, &s, &re, 1, vDSP_Length(re.count))
            vDSP_vsmul(im, 1, &s, &im, 1, vDSP_Length(im.count))
        }
    }

    static func nextPow2(_ v: Int) -> Int {
        var p = 1
        while p < v { p <<= 1 }
        return p
    }

    /// Frequency of bin k for an N-point FFT, in cycles per pixel (np.fftfreq).
    static func fftfreq(_ k: Int, _ n: Int) -> Float {
        let kk = k <= (n - 1) / 2 ? k : k - n
        return Float(kk) / Float(n)
    }
}
