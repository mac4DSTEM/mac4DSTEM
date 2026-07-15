//
//  FFT2D.swift
//  Role: The one 2D FFT implementation in the app — a thin wrapper around
//        vDSP's complex FFT/DFT primitives with cached setups. Used by DPC
//        (iDPC integration) and disk detection (cross-correlation).
//
//  Power-of-two grids use vDSP's fast native 2D FFT. Other grids use separable
//  transforms at their exact dimensions: native radix-2 FFTs or cached exact
//  radix-3/5 plans when possible, otherwise a vDSP complex DFT (with a
//  correctness fallback for unsupported lengths). This preserves NumPy/
//  py4DSTEM circular-correlation semantics without zero-padding.
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
            var horizontalRe = [Float](repeating: 0, count: nx * ny)
            var horizontalIm = [Float](repeating: 0, count: nx * ny)
            re.withUnsafeBufferPointer { inputRe in
                im.withUnsafeBufferPointer { inputIm in
                    horizontalRe.withUnsafeMutableBufferPointer { outputRe in
                        horizontalIm.withUnsafeMutableBufferPointer { outputIm in
                            for y in 0..<ny {
                                executeAxis(
                                    fftSetup: axisXSetup, fftLog: axisXLog,
                                    exactPlan: axisXPlan,
                                    dftSetup: xSetup, length: nx, forward: forward,
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
                                executeAxis(
                                    fftSetup: axisYSetup, fftLog: axisYLog,
                                    exactPlan: axisYPlan,
                                    dftSetup: ySetup, length: ny, forward: forward,
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

    private func executeAxis(
        fftSetup: FFTSetup?, fftLog: vDSP_Length,
        exactPlan: ExactRadixPlan?,
        dftSetup: vDSP_DFT_Setup?, length: Int, forward: Bool,
        _ inputRe: UnsafePointer<Float>, _ inputIm: UnsafePointer<Float>,
        _ outputRe: UnsafeMutablePointer<Float>, _ outputIm: UnsafeMutablePointer<Float>
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
        executeDFT(
            setup: dftSetup, length: length, forward: forward,
            inputRe, inputIm, outputRe, outputIm
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
