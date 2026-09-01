//
//  FFT2D.swift
//  Role: The one 2D FFT implementation in the app — a thin wrapper around
//        vDSP's complex FFT/DFT primitives with cached setups. Used by DPC
//        (iDPC integration) and disk detection (cross-correlation).
//
//  Power-of-two grids use vDSP's fast native 2D FFT. Other grids use separable
//  transforms at their exact dimensions: native radix-2 FFTs or cached exact
//  radix-3/5 plans when possible, a vDSP complex DFT where vDSP supports the
//  length (f·2ⁿ, f ∈ {1,3,5,15}), and otherwise an exact Bluestein (chirp-z)
//  transform that evaluates the length-N DFT through radix-2 FFTs of length
//  M ≥ 2N−1. Every path is the EXACT N-point DFT: the data grid is never
//  zero-padded, so NumPy/py4DSTEM circular-correlation semantics hold for any
//  detector size. (Until 2026-09-01 the last case was an O(N²) scalar loop
//  with per-element sin/cos — 256 ms per 250×250 pattern in a Release build,
//  the whole story behind the 14-minute Detect All Disks on
//  calibrationData_circularProbe.h5; docs/s22-ux-design.md §5.5 P1.)
//
//  THREADING: an FFTSetup is immutable after creation and Apple documents it
//  as shareable across threads, so one FFT2D instance can serve concurrent
//  workers — hence the @unchecked Sendable. The transform buffers themselves
//  are caller-owned (inout), never shared.
//

import Foundation
import Accelerate

nonisolated private struct ExactRadixStage: Sendable {
    let groupSize: Int
    let butterflyStride: Int
    let twiddleReal: [Float]
    let twiddleImaginaryForward: [Float]
}

nonisolated private struct ExactRadixPlan: Sendable {
    let length: Int
    let radix: Int
    let reversedIndices: [Int]
    let stages: [ExactRadixStage]

    init(length: Int, radix: Int, exponent: Int) {
        self.length = length
        self.radix = radix

        var reversed = [Int](repeating: 0, count: length)
        for index in 0..<length {
            var source = index
            var destination = 0
            for _ in 0..<exponent {
                destination = destination * radix + source % radix
                source /= radix
            }
            reversed[index] = destination
        }
        reversedIndices = reversed

        var builtStages: [ExactRadixStage] = []
        var groupSize = radix
        for _ in 0..<exponent {
            let stride = groupSize / radix
            var twiddleReal = [Float](repeating: 1, count: radix * stride)
            var twiddleImaginary = [Float](repeating: 0, count: radix * stride)
            for branch in 1..<radix {
                for offset in 0..<stride {
                    let angle = -2 * Float.pi * Float(branch * offset) / Float(groupSize)
                    let index = branch * stride + offset
                    twiddleReal[index] = cos(angle)
                    twiddleImaginary[index] = sin(angle)
                }
            }
            builtStages.append(ExactRadixStage(
                groupSize: groupSize,
                butterflyStride: stride,
                twiddleReal: twiddleReal,
                twiddleImaginaryForward: twiddleImaginary
            ))
            groupSize *= radix
        }
        stages = builtStages
    }
}

/// Bluestein / chirp-z plan for one axis of arbitrary length N.
///
/// Identity: nk = (n² + k² − (k−n)²)/2, so
///   X_k = w_k · Σ_n (x_n · w_n) · conj(w_{k−n}),  w_m = exp(−iπ m²/N),
/// a linear convolution of the chirped input with conj(w), which a length-M
/// circular convolution (M ≥ 2N−1, power of two) computes exactly through
/// vDSP's radix-2 FFT. The inverse transform uses conj(w) throughout and is
/// left unnormalized, matching vDSP's convention that `FFT2D.transform`
/// already relies on. The padding is internal to evaluating the exact
/// N-point DFT — the data itself is never padded.
///
/// The chirp phase is built from n² reduced modulo 2N, so its accuracy does
/// not degrade with N (a Float angle of 2π·n·k/N, as the old scalar loop
/// used, loses ~1e-4 rad by n·k ≈ 60 000). The reduction is what matters:
/// Gate B (2026-09-02) measured a Float chirp with the same reduction at the
/// same accuracy; the Double is belt-and-braces.
///
/// Immutable after construction (an FFTSetup is documented shareable across
/// threads), so one plan serves every concurrent detection worker.
nonisolated private final class BluesteinPlan: @unchecked Sendable {
    let length: Int
    let paddedLength: Int
    let paddedLog2: vDSP_Length
    let setup: FFTSetup
    /// w_n = exp(−iπ n²/N) for n < N (the FORWARD chirp; inverse = conj).
    let chirpRe: [Float]
    let chirpIm: [Float]
    /// FFT_M of the symmetric conj-chirp filter, one per direction.
    let filterForwardRe: [Float]
    let filterForwardIm: [Float]
    let filterInverseRe: [Float]
    let filterInverseIm: [Float]

    init?(length: Int) {
        guard length > 0 else { return nil }
        let padded = FFT2D.nextPow2(2 * length - 1)
        let log2Padded = vDSP_Length(log2(Double(padded)))
        guard let setup = vDSP_create_fftsetup(log2Padded, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        self.length = length
        self.paddedLength = padded
        self.paddedLog2 = log2Padded
        self.setup = setup

        var wRe = [Float](repeating: 0, count: length)
        var wIm = [Float](repeating: 0, count: length)
        for n in 0..<length {
            // exp(−iπ n²/N) has period 2N in n², so reduce first — exact in
            // integer arithmetic, and it keeps the Double angle small.
            let reduced = (n * n) % (2 * length)
            let angle = -Double.pi * Double(reduced) / Double(length)
            wRe[n] = Float(cos(angle))
            wIm[n] = Float(sin(angle))
        }
        chirpRe = wRe
        chirpIm = wIm

        // Filter for a direction whose chirp is c: b_m = conj(c_m) for
        // |m| < N, placed at index m (m ≥ 0) and M + m (m < 0); symmetric in
        // m because m² is. Forward: c = w → b = conj(w). Inverse: c = conj(w)
        // → b = w.
        func filter(conjugateChirp: Bool) -> ([Float], [Float]) {
            var bRe = [Float](repeating: 0, count: padded)
            var bIm = [Float](repeating: 0, count: padded)
            let sign: Float = conjugateChirp ? -1 : 1
            for m in 0..<length {
                bRe[m] = wRe[m]
                bIm[m] = sign * wIm[m]
                if m > 0 {
                    bRe[padded - m] = wRe[m]
                    bIm[padded - m] = sign * wIm[m]
                }
            }
            bRe.withUnsafeMutableBufferPointer { rp in
                bIm.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    vDSP_fft_zip(setup, &split, 1, log2Padded,
                                 FFTDirection(kFFTDirection_Forward))
                }
            }
            return (bRe, bIm)
        }
        (filterForwardRe, filterForwardIm) = filter(conjugateChirp: true)
        (filterInverseRe, filterInverseIm) = filter(conjugateChirp: false)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Exact length-N DFT of one line. `scratchRe/Im` must hold
    /// `paddedLength` floats each; they are caller-owned so concurrent
    /// workers never share them.
    func execute(
        forward: Bool,
        _ inputRe: UnsafePointer<Float>, _ inputIm: UnsafePointer<Float>,
        _ outputRe: UnsafeMutablePointer<Float>, _ outputIm: UnsafeMutablePointer<Float>,
        scratchRe: UnsafeMutablePointer<Float>, scratchIm: UnsafeMutablePointer<Float>
    ) {
        let n = vDSP_Length(length)
        let m = vDSP_Length(paddedLength)
        // vDSP_zvmul's conjugate flag applies to its FIRST operand: 1 = plain
        // product, −1 = conj(A)·B. The forward chirp is w, the inverse conj(w).
        let conjugate: Int32 = forward ? 1 : -1
        chirpRe.withUnsafeBufferPointer { cr in
            chirpIm.withUnsafeBufferPointer { ci in
                var chirp = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: cr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: ci.baseAddress!)
                )
                var input = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: inputRe),
                    imagp: UnsafeMutablePointer(mutating: inputIm)
                )
                var work = DSPSplitComplex(realp: scratchRe, imagp: scratchIm)

                // 1. a_n = x_n · c_n, zero-padded to M.
                vDSP_zvmul(&chirp, 1, &input, 1, &work, 1, n, conjugate)
                if paddedLength > length {
                    (scratchRe + length).update(repeating: 0, count: paddedLength - length)
                    (scratchIm + length).update(repeating: 0, count: paddedLength - length)
                }
                // 2. A = FFT_M(a).
                vDSP_fft_zip(setup, &work, 1, paddedLog2, FFTDirection(kFFTDirection_Forward))
                // 3. A ·= B (the direction's precomputed filter spectrum).
                let filterRe = forward ? filterForwardRe : filterInverseRe
                let filterIm = forward ? filterForwardIm : filterInverseIm
                filterRe.withUnsafeBufferPointer { fr in
                    filterIm.withUnsafeBufferPointer { fi in
                        var filter = DSPSplitComplex(
                            realp: UnsafeMutablePointer(mutating: fr.baseAddress!),
                            imagp: UnsafeMutablePointer(mutating: fi.baseAddress!)
                        )
                        vDSP_zvmul(&work, 1, &filter, 1, &work, 1, m, 1)
                    }
                }
                // 4. a = IFFT_M(A) / M (vDSP's inverse is unnormalized).
                vDSP_fft_zip(setup, &work, 1, paddedLog2, FFTDirection(kFFTDirection_Inverse))
                var scale = 1 / Float(paddedLength)
                vDSP_vsmul(scratchRe, 1, &scale, scratchRe, 1, m)
                vDSP_vsmul(scratchIm, 1, &scale, scratchIm, 1, m)
                // 5. X_k = c_k · a_k for k < N.
                var output = DSPSplitComplex(realp: outputRe, imagp: outputIm)
                vDSP_zvmul(&chirp, 1, &work, 1, &output, 1, n, conjugate)
            }
        }
    }
}

nonisolated final class FFT2D: @unchecked Sendable {

    let nx: Int
    let ny: Int
    private let log2x: vDSP_Length
    private let log2y: vDSP_Length
    private let radix2Setup: FFTSetup?
    private let axisXSetup: FFTSetup?
    private let axisXLog: vDSP_Length
    private let axisXPlan: ExactRadixPlan?
    private let axisYSetup: FFTSetup?
    private let axisYLog: vDSP_Length
    private let axisYPlan: ExactRadixPlan?
    private let forwardX: vDSP_DFT_Setup?
    private let inverseX: vDSP_DFT_Setup?
    private let forwardY: vDSP_DFT_Setup?
    private let inverseY: vDSP_DFT_Setup?
    /// Exact arbitrary-length plans, built only for an axis vDSP cannot
    /// serve natively (no radix-2 setup, no exact radix-3/5 plan, no DFT
    /// setup) — e.g. 250, 254, 300.
    private let bluesteinX: BluesteinPlan?
    private let bluesteinY: BluesteinPlan?

    /// Fails only when a required Accelerate FFT setup cannot be allocated.
    init?(nx: Int, ny: Int) {
        guard nx > 0, ny > 0 else { return nil }
        self.nx = nx
        self.ny = ny
        let isRadix2 = nx & (nx - 1) == 0 && ny & (ny - 1) == 0
        log2x = isRadix2 ? vDSP_Length(log2(Double(nx))) : 0
        log2y = isRadix2 ? vDSP_Length(log2(Double(ny))) : 0
        if isRadix2 {
            guard let setup = vDSP_create_fftsetup(
                max(log2x, log2y), FFTRadix(kFFTRadix2)
            ) else { return nil }
            radix2Setup = setup
            axisXSetup = nil; axisXLog = 0; axisXPlan = nil
            axisYSetup = nil; axisYLog = 0; axisYPlan = nil
            forwardX = nil; inverseX = nil; forwardY = nil; inverseY = nil
            bluesteinX = nil; bluesteinY = nil
        } else {
            radix2Setup = nil
            let xRadix2Log = Self.exactPowerExponent(nx, radix: 2)
            let yRadix2Log = Self.exactPowerExponent(ny, radix: 2)
            let xPlan = Self.exactRadixPlan(length: nx)
            let yPlan = Self.exactRadixPlan(length: ny)
            if let xRadix2Log {
                guard let setup = vDSP_create_fftsetup(
                    xRadix2Log, FFTRadix(kFFTRadix2)
                ) else {
                    return nil
                }
                axisXSetup = setup
                axisXLog = xRadix2Log
            } else {
                axisXSetup = nil
                axisXLog = 0
            }
            axisXPlan = xPlan
            if let yRadix2Log {
                guard let setup = vDSP_create_fftsetup(
                    yRadix2Log, FFTRadix(kFFTRadix2)
                ) else {
                    if let axisXSetup { vDSP_destroy_fftsetup(axisXSetup) }
                    return nil
                }
                axisYSetup = setup
                axisYLog = yRadix2Log
            } else {
                axisYSetup = nil
                axisYLog = 0
            }
            axisYPlan = yPlan
            let fx = xRadix2Log == nil && xPlan == nil
                ? vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nx), .FORWARD) : nil
            let ix = xRadix2Log == nil && xPlan == nil
                ? vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nx), .INVERSE) : nil
            let fy = yRadix2Log == nil && yPlan == nil
                ? vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(ny), .FORWARD) : nil
            let iy = yRadix2Log == nil && yPlan == nil
                ? vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(ny), .INVERSE) : nil
            forwardX = fx; inverseX = ix; forwardY = fy; inverseY = iy
            let needsBluesteinX = xRadix2Log == nil && xPlan == nil && fx == nil
            let needsBluesteinY = yRadix2Log == nil && yPlan == nil && fy == nil
            let bx = needsBluesteinX ? BluesteinPlan(length: nx) : nil
            let by = needsBluesteinY ? BluesteinPlan(length: ny) : nil
            if (needsBluesteinX && bx == nil) || (needsBluesteinY && by == nil) {
                if let axisXSetup { vDSP_destroy_fftsetup(axisXSetup) }
                if let axisYSetup { vDSP_destroy_fftsetup(axisYSetup) }
                if let fx { vDSP_DFT_DestroySetup(fx) }
                if let ix { vDSP_DFT_DestroySetup(ix) }
                if let fy { vDSP_DFT_DestroySetup(fy) }
                if let iy { vDSP_DFT_DestroySetup(iy) }
                return nil
            }
            bluesteinX = bx
            bluesteinY = by
        }
    }

    deinit {
        if let radix2Setup { vDSP_destroy_fftsetup(radix2Setup) }
        if let axisXSetup { vDSP_destroy_fftsetup(axisXSetup) }
        if let axisYSetup { vDSP_destroy_fftsetup(axisYSetup) }
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
            // Per-call Bluestein scratch (padded length of the larger axis):
            // caller-owned like the data, so concurrent workers sharing this
            // plan never share a buffer.
            let scratchCount = max(bluesteinX?.paddedLength ?? 0,
                                   bluesteinY?.paddedLength ?? 0)
            var scratchRe = [Float](repeating: 0, count: scratchCount)
            var scratchIm = [Float](repeating: 0, count: scratchCount)
            var horizontalRe = [Float](repeating: 0, count: nx * ny)
            var horizontalIm = [Float](repeating: 0, count: nx * ny)
            scratchRe.withUnsafeMutableBufferPointer { sr in
            scratchIm.withUnsafeMutableBufferPointer { si in
            let scratch = (sr.baseAddress, si.baseAddress)
            re.withUnsafeBufferPointer { inputRe in
                im.withUnsafeBufferPointer { inputIm in
                    horizontalRe.withUnsafeMutableBufferPointer { outputRe in
                        horizontalIm.withUnsafeMutableBufferPointer { outputIm in
                            for y in 0..<ny {
                                executeAxis(
                                    fftSetup: axisXSetup, fftLog: axisXLog,
                                    exactPlan: axisXPlan,
                                    dftSetup: xSetup, bluestein: bluesteinX,
                                    length: nx, forward: forward,
                                    inputRe.baseAddress! + y * nx,
                                    inputIm.baseAddress! + y * nx,
                                    outputRe.baseAddress! + y * nx,
                                    outputIm.baseAddress! + y * nx,
                                    scratch: scratch
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
                                executeAxis(
                                    fftSetup: axisYSetup, fftLog: axisYLog,
                                    exactPlan: axisYPlan,
                                    dftSetup: ySetup, bluestein: bluesteinY,
                                    length: ny, forward: forward,
                                    inputRe.baseAddress!, inputIm.baseAddress!,
                                    outputRe.baseAddress!, outputIm.baseAddress!,
                                    scratch: scratch
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
            }
        }
        if !forward && scaleInverse {
            var s = 1 / Float(nx * ny)
            vDSP_vsmul(re, 1, &s, &re, 1, vDSP_Length(re.count))
            vDSP_vsmul(im, 1, &s, &im, 1, vDSP_Length(im.count))
        }
    }

    private func executeAxis(
        fftSetup: FFTSetup?, fftLog: vDSP_Length,
        exactPlan: ExactRadixPlan?,
        dftSetup: vDSP_DFT_Setup?, bluestein: BluesteinPlan?,
        length: Int, forward: Bool,
        _ inputRe: UnsafePointer<Float>, _ inputIm: UnsafePointer<Float>,
        _ outputRe: UnsafeMutablePointer<Float>, _ outputIm: UnsafeMutablePointer<Float>,
        scratch: (UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?)
    ) {
        if let fftSetup {
            outputRe.update(from: inputRe, count: length)
            outputIm.update(from: inputIm, count: length)
            var split = DSPSplitComplex(realp: outputRe, imagp: outputIm)
            vDSP_fft_zip(
                fftSetup, &split, 1, fftLog,
                FFTDirection(forward ? kFFTDirection_Forward : kFFTDirection_Inverse)
            )
            return
        }
        if let exactPlan {
            executeExactRadix(
                plan: exactPlan, forward: forward,
                inputRe, inputIm, outputRe, outputIm
            )
            return
        }
        if let dftSetup {
            vDSP_DFT_Execute(dftSetup, inputRe, inputIm, outputRe, outputIm)
            return
        }
        // `init` guarantees a plan exists for every axis no other path
        // serves, so this is unreachable rather than a silent fallback.
        guard let bluestein, let scratchRe = scratch.0, let scratchIm = scratch.1 else {
            preconditionFailure("FFT2D: no transform plan for length \(length)")
        }
        bluestein.execute(
            forward: forward, inputRe, inputIm, outputRe, outputIm,
            scratchRe: scratchRe, scratchIm: scratchIm
        )
    }

    private func executeExactRadix(
        plan: ExactRadixPlan, forward: Bool,
        _ inputRe: UnsafePointer<Float>, _ inputIm: UnsafePointer<Float>,
        _ outputRe: UnsafeMutablePointer<Float>, _ outputIm: UnsafeMutablePointer<Float>
    ) {
        for source in 0..<plan.length {
            let destination = plan.reversedIndices[source]
            outputRe[destination] = inputRe[source]
            outputIm[destination] = inputIm[source]
        }
        for stage in plan.stages {
            var groupStart = 0
            while groupStart < plan.length {
                for offset in 0..<stage.butterflyStride {
                    if plan.radix == 3 {
                        radix3Butterfly(
                            groupStart: groupStart, offset: offset, stage: stage,
                            forward: forward, outputRe, outputIm
                        )
                    } else {
                        radix5Butterfly(
                            groupStart: groupStart, offset: offset, stage: stage,
                            forward: forward, outputRe, outputIm
                        )
                    }
                }
                groupStart += stage.groupSize
            }
        }
    }

    @inline(__always)
    private func twiddledValue(
        branch: Int, groupStart: Int, offset: Int,
        stage: ExactRadixStage, forward: Bool,
        _ real: UnsafeMutablePointer<Float>, _ imaginary: UnsafeMutablePointer<Float>
    ) -> (Float, Float) {
        let dataIndex = groupStart + offset + branch * stage.butterflyStride
        let twiddleIndex = branch * stage.butterflyStride + offset
        let wr = stage.twiddleReal[twiddleIndex]
        let storedWI = stage.twiddleImaginaryForward[twiddleIndex]
        let wi = forward ? storedWI : -storedWI
        let xr = real[dataIndex], xi = imaginary[dataIndex]
        return (xr * wr - xi * wi, xr * wi + xi * wr)
    }

    @inline(__always)
    private func radix3Butterfly(
        groupStart: Int, offset: Int, stage: ExactRadixStage, forward: Bool,
        _ real: UnsafeMutablePointer<Float>, _ imaginary: UnsafeMutablePointer<Float>
    ) {
        let index0 = groupStart + offset
        let index1 = index0 + stage.butterflyStride
        let index2 = index1 + stage.butterflyStride
        let x0r = real[index0], x0i = imaginary[index0]
        let (x1r, x1i) = twiddledValue(
            branch: 1, groupStart: groupStart, offset: offset,
            stage: stage, forward: forward, real, imaginary
        )
        let (x2r, x2i) = twiddledValue(
            branch: 2, groupStart: groupStart, offset: offset,
            stage: stage, forward: forward, real, imaginary
        )
        let sumR = x1r + x2r, sumI = x1i + x2i
        let differenceR = x1r - x2r, differenceI = x1i - x2i
        let baseR = x0r - 0.5 * sumR, baseI = x0i - 0.5 * sumI
        let direction: Float = forward ? -1 : 1
        let uR = direction * 0.8660254037844386 * differenceR
        let uI = direction * 0.8660254037844386 * differenceI
        real[index0] = x0r + sumR
        imaginary[index0] = x0i + sumI
        real[index1] = baseR - uI
        imaginary[index1] = baseI + uR
        real[index2] = baseR + uI
        imaginary[index2] = baseI - uR
    }

    @inline(__always)
    private func radix5Butterfly(
        groupStart: Int, offset: Int, stage: ExactRadixStage, forward: Bool,
        _ real: UnsafeMutablePointer<Float>, _ imaginary: UnsafeMutablePointer<Float>
    ) {
        let stride = stage.butterflyStride
        let index0 = groupStart + offset
        let index1 = index0 + stride, index2 = index1 + stride
        let index3 = index2 + stride, index4 = index3 + stride
        let x0r = real[index0], x0i = imaginary[index0]
        let (x1r, x1i) = twiddledValue(
            branch: 1, groupStart: groupStart, offset: offset,
            stage: stage, forward: forward, real, imaginary
        )
        let (x2r, x2i) = twiddledValue(
            branch: 2, groupStart: groupStart, offset: offset,
            stage: stage, forward: forward, real, imaginary
        )
        let (x3r, x3i) = twiddledValue(
            branch: 3, groupStart: groupStart, offset: offset,
            stage: stage, forward: forward, real, imaginary
        )
        let (x4r, x4i) = twiddledValue(
            branch: 4, groupStart: groupStart, offset: offset,
            stage: stage, forward: forward, real, imaginary
        )

        let t1r = x1r + x4r, t1i = x1i + x4i
        let t2r = x2r + x3r, t2i = x2i + x3i
        let t3r = x1r - x4r, t3i = x1i - x4i
        let t4r = x2r - x3r, t4i = x2i - x3i
        let c1: Float = 0.30901699437494745
        let c2: Float = -0.8090169943749473
        let s1: Float = 0.9510565162951535
        let s2: Float = 0.5877852522924731
        let direction: Float = forward ? -1 : 1

        let base1r = x0r + c1 * t1r + c2 * t2r
        let base1i = x0i + c1 * t1i + c2 * t2i
        let u1r = direction * (s1 * t3r + s2 * t4r)
        let u1i = direction * (s1 * t3i + s2 * t4i)
        let base2r = x0r + c2 * t1r + c1 * t2r
        let base2i = x0i + c2 * t1i + c1 * t2i
        let u2r = direction * (s2 * t3r - s1 * t4r)
        let u2i = direction * (s2 * t3i - s1 * t4i)

        real[index0] = x0r + t1r + t2r
        imaginary[index0] = x0i + t1i + t2i
        real[index1] = base1r - u1i
        imaginary[index1] = base1i + u1r
        real[index4] = base1r + u1i
        imaginary[index4] = base1i - u1r
        real[index2] = base2r - u2i
        imaginary[index2] = base2i + u2r
        real[index3] = base2r + u2i
        imaginary[index3] = base2i - u2r
    }

    private static func exactRadixPlan(length: Int) -> ExactRadixPlan? {
        for radix in [3, 5] {
            if let exponent = exactPowerExponent(length, radix: radix) {
                return ExactRadixPlan(
                    length: length, radix: radix, exponent: Int(exponent)
                )
            }
        }
        return nil
    }

    private static func exactPowerExponent(
        _ value: Int, radix: Int
    ) -> vDSP_Length? {
        guard value > 1 else { return nil }
        var remainder = value
        var exponent: vDSP_Length = 0
        while remainder.isMultiple(of: radix) {
            remainder /= radix
            exponent += 1
        }
        return remainder == 1 ? exponent : nil
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
