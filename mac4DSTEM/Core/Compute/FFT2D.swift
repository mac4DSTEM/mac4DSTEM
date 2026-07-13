//
//  FFT2D.swift
//  Role: The one 2D FFT implementation in the app — a thin wrapper around
//        vDSP's complex FFT/DFT primitives with cached setups. Used by DPC
//        (iDPC integration) and disk detection (cross-correlation).
//
//  Power-of-two grids use vDSP's fast native 2D FFT. Other grids use separable
//  complex DFTs at their exact dimensions (vDSP when supported, a correctness
//  fallback otherwise), preserving NumPy/py4DSTEM circular-correlation
//  semantics without zero-padding.
//
//  THREADING: an FFTSetup is immutable after creation and Apple documents it
//  as shareable across threads, so one FFT2D instance can serve concurrent
//  workers — hence the @unchecked Sendable. The transform buffers themselves
//  are caller-owned (inout), never shared.
//

import Foundation
import Accelerate

nonisolated final class FFT2D: @unchecked Sendable {

    let nx: Int
    let ny: Int
    private let log2x: vDSP_Length
    private let log2y: vDSP_Length
    private let radix2Setup: FFTSetup?
    private let forwardX: vDSP_DFT_Setup?
    private let inverseX: vDSP_DFT_Setup?
    private let forwardY: vDSP_DFT_Setup?
    private let inverseY: vDSP_DFT_Setup?

    /// Fails only when a power-of-two Accelerate FFT setup cannot be allocated.
    init?(nx: Int, ny: Int) {
        guard nx > 0, ny > 0 else { return nil }
        self.nx = nx
        self.ny = ny
        let isRadix2 = nx & (nx - 1) == 0 && ny & (ny - 1) == 0
        self.log2x = isRadix2 ? vDSP_Length(log2(Double(nx))) : 0
        self.log2y = isRadix2 ? vDSP_Length(log2(Double(ny))) : 0
        if isRadix2 {
            guard let setup = vDSP_create_fftsetup(
                max(log2x, log2y), FFTRadix(kFFTRadix2)
            ) else { return nil }
            radix2Setup = setup
            forwardX = nil; inverseX = nil; forwardY = nil; inverseY = nil
        } else {
            let fx = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nx), .FORWARD)
            let ix = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nx), .INVERSE)
            let fy = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(ny), .FORWARD)
            let iy = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(ny), .INVERSE)
            radix2Setup = nil
            forwardX = fx; inverseX = ix; forwardY = fy; inverseY = iy
        }
    }

    deinit {
        if let radix2Setup { vDSP_destroy_fftsetup(radix2Setup) }
        if let forwardX { vDSP_DFT_DestroySetup(forwardX) }
        if let inverseX { vDSP_DFT_DestroySetup(inverseX) }
        if let forwardY { vDSP_DFT_DestroySetup(forwardY) }
        if let inverseY { vDSP_DFT_DestroySetup(inverseY) }
    }

    /// In-place complex 2D FFT over row-major [ny * nx] split-complex data.
    /// The inverse is unnormalized, matching vDSP — `scaleInverse` divides by
    /// nx*ny so forward→inverse round-trips to the input.
    func transform(re: inout [Float], im: inout [Float],
                   forward: Bool, scaleInverse: Bool = true) {
        precondition(re.count == nx * ny && im.count == nx * ny)
        if let radix2Setup {
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    vDSP_fft2d_zip(radix2Setup, &split, 1, 0, log2x, log2y,
                                   FFTDirection(forward ? kFFTDirection_Forward
                                                        : kFFTDirection_Inverse))
                }
            }
        } else {
            let xSetup = forward ? forwardX : inverseX
            let ySetup = forward ? forwardY : inverseY
            var horizontalRe = [Float](repeating: 0, count: nx * ny)
            var horizontalIm = [Float](repeating: 0, count: nx * ny)
            re.withUnsafeBufferPointer { inputRe in
                im.withUnsafeBufferPointer { inputIm in
                    horizontalRe.withUnsafeMutableBufferPointer { outputRe in
                        horizontalIm.withUnsafeMutableBufferPointer { outputIm in
                            for y in 0..<ny {
                                executeDFT(
                                    setup: xSetup, length: nx, forward: forward,
                                    inputRe.baseAddress! + y * nx,
                                    inputIm.baseAddress! + y * nx,
                                    outputRe.baseAddress! + y * nx,
                                    outputIm.baseAddress! + y * nx
                                )
                            }
                        }
                    }
                }
            }
            var columnInRe = [Float](repeating: 0, count: ny)
            var columnInIm = [Float](repeating: 0, count: ny)
            var columnOutRe = [Float](repeating: 0, count: ny)
            var columnOutIm = [Float](repeating: 0, count: ny)
            for x in 0..<nx {
                for y in 0..<ny {
                    columnInRe[y] = horizontalRe[y * nx + x]
                    columnInIm[y] = horizontalIm[y * nx + x]
                }
                columnInRe.withUnsafeBufferPointer { inputRe in
                    columnInIm.withUnsafeBufferPointer { inputIm in
                        columnOutRe.withUnsafeMutableBufferPointer { outputRe in
                            columnOutIm.withUnsafeMutableBufferPointer { outputIm in
                                executeDFT(
                                    setup: ySetup, length: ny, forward: forward,
                                    inputRe.baseAddress!, inputIm.baseAddress!,
                                    outputRe.baseAddress!, outputIm.baseAddress!
                                )
                            }
                        }
                    }
                }
                for y in 0..<ny {
                    re[y * nx + x] = columnOutRe[y]
                    im[y * nx + x] = columnOutIm[y]
                }
            }
        }
        if !forward && scaleInverse {
            var s = 1 / Float(nx * ny)
            vDSP_vsmul(re, 1, &s, &re, 1, vDSP_Length(re.count))
            vDSP_vsmul(im, 1, &s, &im, 1, vDSP_Length(im.count))
        }
    }

    /// vDSP deliberately omits some exact DFT lengths (notably small primes).
    /// The scalar fallback keeps those shapes scientifically correct; common
    /// microscope sizes of `f·2ⁿ` continue through the accelerated setup.
    private func executeDFT(
        setup: vDSP_DFT_Setup?, length: Int, forward: Bool,
        _ inputRe: UnsafePointer<Float>, _ inputIm: UnsafePointer<Float>,
        _ outputRe: UnsafeMutablePointer<Float>, _ outputIm: UnsafeMutablePointer<Float>
    ) {
        if let setup {
            vDSP_DFT_Execute(setup, inputRe, inputIm, outputRe, outputIm)
            return
        }
        let sign: Float = forward ? -1 : 1
        for k in 0..<length {
            var sumRe: Float = 0
            var sumIm: Float = 0
            for j in 0..<length {
                let angle = sign * 2 * .pi * Float(j * k) / Float(length)
                let cosine = cos(angle), sine = sin(angle)
                sumRe += inputRe[j] * cosine - inputIm[j] * sine
                sumIm += inputRe[j] * sine + inputIm[j] * cosine
            }
            outputRe[k] = sumRe
            outputIm[k] = sumIm
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
