//
//  OrientationMatcher.swift
//  Role: ACOM orientation matching. Turn a pattern's detected Bragg peaks into
//        a polar image, then correlate it against every template in an
//        OrientationPlan — recovering the best zone axis AND its in-plane
//        rotation in one shot via azimuthal FFT correlation:
//
//          corr(Δφ) = IFFT_φ( Σ_ring conj(FFT(exp_ring)) · FFT(template_ring) )
//
//        The peak of corr over Δφ is the in-plane angle; its height is the
//        match score. Best template → orientation; best/second → reliability.
//
//  CALIBRATION: peak radii are in detector pixels; the plan is in Å⁻¹. Pass
//  `invAngstromPerPixel` (the Q pixel size) to convert. Without a Q
//  calibration this is qualitative — the radial scale must roughly match the
//  crystal for the correlation to lock on.
//
//  ISOLATION: `nonisolated` per-worker object (owns an FFT + scratch); create
//  one per concurrent worker in matchAll.
//

import Foundation
import Accelerate
import Metal

nonisolated final class OrientationMatcher {

    private let plan: OrientationPlan
    private let symmetry: ACOMCrystalSymmetry
    private let geo: PolarGeometry
    private let fft: FFT1D

    // Scratch (per-ring FFT of the experimental pattern + correlation buffers).
    private var expRe: [Float]
    private var expIm: [Float]
    private var corrRe: [Float]
    private var corrIm: [Float]
    private var productRe: [Float]
    private var productIm: [Float]

    init?(plan: OrientationPlan, symmetry: ACOMCrystalSymmetry = .cubic) {
        guard let fft = FFT1D(n: plan.geometry.nAzimuthal) else { return nil }
        self.plan = plan
        self.symmetry = symmetry
        self.geo = plan.geometry
        self.fft = fft
        let n = geo.nRadial * geo.nAzimuthal
        expRe = [Float](repeating: 0, count: n)
        expIm = [Float](repeating: 0, count: n)
        corrRe = [Float](repeating: 0, count: geo.nAzimuthal)
        corrIm = [Float](repeating: 0, count: geo.nAzimuthal)
        productRe = [Float](repeating: 0, count: n)
        productIm = [Float](repeating: 0, count: n)
    }

    /// Match one pattern's peaks against the plan.
    func match(peaks: [BraggPeak], originX: Float, originY: Float,
               invAngstromPerPixel: Double = 1) -> OrientationResult {
        guard prepareExperimentalFFT(
            peaks: peaks, originX: originX, originY: originY,
            invAngstromPerPixel: invAngstromPerPixel
        ) else { return .empty }

        let na = geo.nAzimuthal, nr = geo.nRadial
        let invScale = 1 / Float(na)     // undo vDSP's unnormalized inverse FFT
        var best: Float = -.greatestFiniteMagnitude, second = best
        var bestT = -1, bestBin = 0

        for t in 0..<plan.count {
            let templateOffset = t * nr * na
            // Vectorized full-grid complex multiply:
            // Template * conj(Experimental) == conj(Experimental) * Template.
            expRe.withUnsafeMutableBufferPointer { experimentalReal in
                expIm.withUnsafeMutableBufferPointer { experimentalImaginary in
                    plan.templateFFTRe.withUnsafeBufferPointer { templateReal in
                        plan.templateFFTIm.withUnsafeBufferPointer { templateImaginary in
                            productRe.withUnsafeMutableBufferPointer { outputReal in
                                productIm.withUnsafeMutableBufferPointer { outputImaginary in
                                    var experimental = DSPSplitComplex(
                                        realp: experimentalReal.baseAddress!,
                                        imagp: experimentalImaginary.baseAddress!
                                    )
                                    var template = DSPSplitComplex(
                                        realp: UnsafeMutablePointer(
                                            mutating: templateReal.baseAddress! + templateOffset
                                        ),
                                        imagp: UnsafeMutablePointer(
                                            mutating: templateImaginary.baseAddress! + templateOffset
                                        )
                                    )
                                    var output = DSPSplitComplex(
                                        realp: outputReal.baseAddress!,
                                        imagp: outputImaginary.baseAddress!
                                    )
                                    vDSP_zvmul(
                                        &experimental, 1, &template, 1, &output, 1,
                                        vDSP_Length(nr * na), -1
                                    )
                                }
                            }
                        }
                    }
                }
            }
            for a in 0..<na {
                var real: Float = 0, imaginary: Float = 0
                for r in 0..<nr {
                    real += productRe[r * na + a]
                    imaginary += productIm[r * na + a]
                }
                corrRe[a] = real; corrIm[a] = imaginary
            }
            fft.transform(re: &corrRe, im: &corrIm, forward: false)
            var localBest: Float = -.greatestFiniteMagnitude
            var localBin = 0
            for a in 0..<na where corrRe[a] > localBest { localBest = corrRe[a]; localBin = a }
            localBest *= invScale
            if localBest > best {
                second = best; best = localBest; bestT = t; bestBin = localBin
            } else if localBest > second {
                second = localBest
            }
        }
        return makeOrientationResult(
            plan: plan, symmetry: symmetry,
            bestTemplate: bestT, bestBin: bestBin,
            bestScore: best, secondScore: second
        )
    }

    /// Prepare a copy for a Metal batch. The CPU and GPU paths therefore share
    /// exactly the same polar deposition, normalization, and forward FFT.
    func experimentalFFT(peaks: [BraggPeak], originX: Float, originY: Float,
                         invAngstromPerPixel: Double) -> (real: [Float], imaginary: [Float])? {
        guard prepareExperimentalFFT(
            peaks: peaks, originX: originX, originY: originY,
            invAngstromPerPixel: invAngstromPerPixel
        ) else { return nil }
        return (expRe, expIm)
    }

    private func prepareExperimentalFFT(
        peaks: [BraggPeak], originX: Float, originY: Float,
        invAngstromPerPixel: Double
    ) -> Bool {
        guard peaks.count >= 2 else { return false }
        var spots: [(r: Double, azim: Double, weight: Double)] = []
        spots.reserveCapacity(peaks.count)
        for p in peaks {
            let dx = Double(p.x - originX), dy = Double(p.y - originY)
            let r = (dx * dx + dy * dy).squareRoot() * invAngstromPerPixel
            spots.append((r: r, azim: atan2(dy, dx), weight: Double(max(p.intensity, 0))))
        }
        var polar = OrientationPlan.buildPolar(spots: spots, geometry: geo, azimBlurBins: 1.5)
        OrientationPlan.normalizeUnit(&polar)
        writeRingFFTs(polar)
        return true
    }

    private func writeRingFFTs(_ polar: [Float]) {
        let na = geo.nAzimuthal
        var re = [Float](repeating: 0, count: na)
        var im = [Float](repeating: 0, count: na)
        for r in 0..<geo.nRadial {
            let base = r * na
            for a in 0..<na { re[a] = polar[base + a]; im[a] = 0 }
            fft.transform(re: &re, im: &im, forward: true)
            for a in 0..<na { expRe[base + a] = re[a]; expIm[base + a] = im[a] }
        }
    }
}

private nonisolated func makeOrientationResult(
    plan: OrientationPlan, symmetry: ACOMCrystalSymmetry,
    bestTemplate: Int, bestBin: Int, bestScore: Float, secondScore: Float
) -> OrientationResult {
    guard bestTemplate >= 0 else { return .empty }
    let azimuthalCount = plan.geometry.nAzimuthal
    // The correlation peaks at −θ; negate to report the pattern rotation.
    let bin = (azimuthalCount - bestBin) % azimuthalCount
    let angle = Float(Double(bin) / Double(azimuthalCount) * 2 * Double.pi)
    let orientationMatrix = ACOMOrientation.matrix(
        detectorBasis: plan.detectorBases[bestTemplate], inPlaneAngle: angle
    )
    let reduced = symmetry.reduce(orientationMatrix)
    return OrientationResult(
        templateIndex: bestTemplate,
        euler: EulerAngles(py4DSTEMOrientationMatrix: reduced.matrix),
        inPlaneAngle: angle,
        score: max(bestScore, 0), secondScore: max(secondScore, 0), phaseID: 0,
        symmetryDisorientationRad: reduced.disorientationRad
    )
}

private nonisolated struct ACOMMetalParams {
    var positions: UInt32
    var templates: UInt32
    var radial: UInt32
    var azimuthal: UInt32
}

/// Batched Metal matcher. Polar deposition and forward FFT deliberately remain
/// shared with the CPU oracle; Metal accelerates the dominant template/ring
/// correlation and inverse-angle search, then the CPU applies identical
/// best/second selection and symmetry reporting.
nonisolated final class MetalACOMMatcher {
    private let plan: OrientationPlan
    private let symmetry: ACOMCrystalSymmetry
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let spectrumPipeline: MTLComputePipelineState
    private let argmaxPipeline: MTLComputePipelineState
    private let templateReal: MTLBuffer
    private let templateImaginary: MTLBuffer
    private let batchSize: Int

    init?(plan: OrientationPlan, symmetry: ACOMCrystalSymmetry) {
        let engine = MetalEngine.shared
        let azimuthal = plan.geometry.nAzimuthal
        guard azimuthal > 0, azimuthal & (azimuthal - 1) == 0,
              azimuthal <= 1024,
              let spectrumFunction = engine.library.makeFunction(name: "acomCorrelationSpectrum"),
              let argmaxFunction = engine.library.makeFunction(name: "acomInverseArgmax"),
              let spectrum = try? engine.device.makeComputePipelineState(function: spectrumFunction),
              let argmax = try? engine.device.makeComputePipelineState(function: argmaxFunction),
              azimuthal <= argmax.maxTotalThreadsPerThreadgroup,
              !plan.templateFFTRe.isEmpty,
              let templateReal = engine.device.makeBuffer(
                bytes: plan.templateFFTRe,
                length: plan.templateFFTRe.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ),
              let templateImaginary = engine.device.makeBuffer(
                bytes: plan.templateFFTIm,
                length: plan.templateFFTIm.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ) else { return nil }
        self.plan = plan
        self.symmetry = symmetry
        self.device = engine.device
        self.queue = engine.queue
        self.spectrumPipeline = spectrum
        self.argmaxPipeline = argmax
        self.templateReal = templateReal
        self.templateImaginary = templateImaginary
        let bytesPerPosition = plan.count * azimuthal * 2 * MemoryLayout<Float>.stride
            + plan.count * (MemoryLayout<Float>.stride + MemoryLayout<UInt32>.stride)
            + plan.geometry.nRadial * azimuthal * 2 * MemoryLayout<Float>.stride
        let workingBudget = min(Int(engine.device.recommendedMaxWorkingSetSize / 8), 128 << 20)
        self.batchSize = max(1, min(64, workingBudget / max(1, bytesPerPosition)))
    }

    func matchAll(
        bragg: BraggVectors,
        originX: Float, originY: Float,
        invAngstromPerPixel: Double,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?
    ) -> OrientationMap? {
        guard cancellation?.isCancelled != true,
              let preparer = OrientationMatcher(plan: plan, symmetry: symmetry) else { return nil }
        let total = bragg.scanWidth * bragg.scanHeight
        var map = OrientationMap(
            width: bragg.scanWidth, height: bragg.scanHeight,
            matchingBackend: .metal, symmetry: symmetry, templateCount: plan.count
        )
        let gridCount = plan.geometry.nRadial * plan.geometry.nAzimuthal
        for lower in stride(from: 0, to: total, by: batchSize) {
            if cancellation?.isCancelled == true { return nil }
            let upper = min(total, lower + batchSize)
            let count = upper - lower
            var experimentalReal: [Float] = []
            var experimentalImaginary: [Float] = []
            var valid = [Bool](repeating: false, count: count)
            experimentalReal.reserveCapacity(count * gridCount)
            experimentalImaginary.reserveCapacity(count * gridCount)
            for local in 0..<count {
                if cancellation?.isCancelled == true { return nil }
                if let prepared = preparer.experimentalFFT(
                    peaks: bragg.peaks[lower + local],
                    originX: originX, originY: originY,
                    invAngstromPerPixel: invAngstromPerPixel
                ) {
                    experimentalReal.append(contentsOf: prepared.real)
                    experimentalImaginary.append(contentsOf: prepared.imaginary)
                    valid[local] = true
                } else {
                    experimentalReal.append(contentsOf: repeatElement(0, count: gridCount))
                    experimentalImaginary.append(contentsOf: repeatElement(0, count: gridCount))
                }
            }
            guard let results = runBatch(
                experimentalReal: experimentalReal,
                experimentalImaginary: experimentalImaginary,
                positionCount: count
            ) else { return nil }
            for local in 0..<count where valid[local] {
                var best: Float = -.greatestFiniteMagnitude
                var second = best
                var bestTemplate = -1
                var bestBin = 0
                let offset = local * plan.count
                for template in 0..<plan.count {
                    let score = results.scores[offset + template]
                    if score > best {
                        second = best; best = score
                        bestTemplate = template; bestBin = Int(results.bins[offset + template])
                    } else if score > second {
                        second = score
                    }
                }
                map.results[lower + local] = makeOrientationResult(
                    plan: plan, symmetry: symmetry,
                    bestTemplate: bestTemplate, bestBin: bestBin,
                    bestScore: best, secondScore: second
                )
            }
            progress?(Double(upper) / Double(total))
        }
        return cancellation?.isCancelled == true ? nil : map
    }

    private func runBatch(
        experimentalReal: [Float], experimentalImaginary: [Float], positionCount: Int
    ) -> (scores: [Float], bins: [UInt32])? {
        let spectrumCount = positionCount * plan.count * plan.geometry.nAzimuthal
        let resultCount = positionCount * plan.count
        guard let inputReal = device.makeBuffer(
                bytes: experimentalReal,
                length: experimentalReal.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ),
              let inputImaginary = device.makeBuffer(
                bytes: experimentalImaginary,
                length: experimentalImaginary.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ),
              let spectrumReal = device.makeBuffer(
                length: spectrumCount * MemoryLayout<Float>.stride,
                options: .storageModePrivate
              ),
              let spectrumImaginary = device.makeBuffer(
                length: spectrumCount * MemoryLayout<Float>.stride,
                options: .storageModePrivate
              ),
              let scores = device.makeBuffer(
                length: resultCount * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ),
              let bins = device.makeBuffer(
                length: resultCount * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
              ),
              let command = queue.makeCommandBuffer() else { return nil }
        var params = ACOMMetalParams(
            positions: UInt32(positionCount), templates: UInt32(plan.count),
            radial: UInt32(plan.geometry.nRadial),
            azimuthal: UInt32(plan.geometry.nAzimuthal)
        )
        guard let spectrumEncoder = command.makeComputeCommandEncoder() else { return nil }
        spectrumEncoder.setComputePipelineState(spectrumPipeline)
        spectrumEncoder.setBuffer(inputReal, offset: 0, index: 0)
        spectrumEncoder.setBuffer(inputImaginary, offset: 0, index: 1)
        spectrumEncoder.setBuffer(templateReal, offset: 0, index: 2)
        spectrumEncoder.setBuffer(templateImaginary, offset: 0, index: 3)
        spectrumEncoder.setBuffer(spectrumReal, offset: 0, index: 4)
        spectrumEncoder.setBuffer(spectrumImaginary, offset: 0, index: 5)
        spectrumEncoder.setBytes(&params, length: MemoryLayout<ACOMMetalParams>.stride, index: 6)
        let threadWidth = min(spectrumPipeline.maxTotalThreadsPerThreadgroup, 256)
        spectrumEncoder.dispatchThreads(
            MTLSize(width: spectrumCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadWidth, height: 1, depth: 1)
        )
        spectrumEncoder.endEncoding()

        guard let argmaxEncoder = command.makeComputeCommandEncoder() else { return nil }
        argmaxEncoder.setComputePipelineState(argmaxPipeline)
        argmaxEncoder.setBuffer(spectrumReal, offset: 0, index: 0)
        argmaxEncoder.setBuffer(spectrumImaginary, offset: 0, index: 1)
        argmaxEncoder.setBuffer(scores, offset: 0, index: 2)
        argmaxEncoder.setBuffer(bins, offset: 0, index: 3)
        argmaxEncoder.setBytes(&params, length: MemoryLayout<ACOMMetalParams>.stride, index: 4)
        argmaxEncoder.setThreadgroupMemoryLength(
            plan.geometry.nAzimuthal * MemoryLayout<Float>.stride, index: 0
        )
        argmaxEncoder.setThreadgroupMemoryLength(
            plan.geometry.nAzimuthal * MemoryLayout<UInt32>.stride, index: 1
        )
        argmaxEncoder.dispatchThreadgroups(
            MTLSize(width: 1, height: plan.count, depth: positionCount),
            threadsPerThreadgroup: MTLSize(
                width: plan.geometry.nAzimuthal, height: 1, depth: 1
            )
        )
        argmaxEncoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        let scorePointer = scores.contents().bindMemory(to: Float.self, capacity: resultCount)
        let binPointer = bins.contents().bindMemory(to: UInt32.self, capacity: resultCount)
        return (
            Array(UnsafeBufferPointer(start: scorePointer, count: resultCount)),
            Array(UnsafeBufferPointer(start: binPointer, count: resultCount))
        )
    }
}

// MARK: - Full-scan matching

enum OrientationMatching {

    /// Match every scan position's Bragg peaks against the plan, parallelized
    /// over scan rows. Progress in [0, 1] reported from workers.
    nonisolated static func matchAll(bragg: BraggVectors, plan: OrientationPlan,
                                     originX: Float, originY: Float,
                                     invAngstromPerPixel: Double = 1,
                                     backend: ACOMMatchingBackend = .automatic,
                                     cancellation: AnalysisCancellationToken? = nil,
                                     progress: (@Sendable (Double) -> Void)? = nil) -> OrientationMap? {
        guard cancellation?.isCancelled != true else { return nil }
        // The exact Metal backend is retained for parity/performance testing,
        // but the current direct inverse-DFT kernel is slower than the
        // vectorized vDSP path on the v1 benchmark. Automatic therefore means
        // the measured production CPU backend until a batched FFT wins.
        if backend == .metal {
            if let matcher = MetalACOMMatcher(plan: plan, symmetry: plan.symmetry),
               let result = matcher.matchAll(
                    bragg: bragg,
                    originX: originX, originY: originY,
                    invAngstromPerPixel: invAngstromPerPixel,
                    cancellation: cancellation, progress: progress
               ) {
                return result
            }
            return nil
        }
        var map = OrientationMap(
            width: bragg.scanWidth, height: bragg.scanHeight,
            matchingBackend: .cpu, symmetry: plan.symmetry, templateCount: plan.count
        )
        let w = bragg.scanWidth
        let lock = NSLock()
        var done = 0

        map.results.withUnsafeMutableBufferPointer { out in
            let ptr = SendableBox(out.baseAddress!)
            // One matcher (FFT + scratch) per worker, rows strided (same
            // pattern as DiskDetection.detectAll).
            let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, bragg.scanHeight))
            DispatchQueue.concurrentPerform(iterations: workers) { worker in
                guard cancellation?.isCancelled != true else { return }
                guard let matcher = OrientationMatcher(plan: plan, symmetry: plan.symmetry) else { return }
                for ry in stride(from: worker, to: bragg.scanHeight, by: workers) {
                    if cancellation?.isCancelled == true { break }
                    for rx in 0..<w {
                        if cancellation?.isCancelled == true { break }
                        let peaks = bragg.peaks[ry * w + rx]
                        ptr.value[ry * w + rx] = matcher.match(
                            peaks: peaks, originX: originX, originY: originY,
                            invAngstromPerPixel: invAngstromPerPixel)
                    }
                    if cancellation?.isCancelled == true { break }
                    if let progress {
                        lock.lock(); done += 1; let f = Double(done) / Double(bragg.scanHeight); lock.unlock()
                        progress(f)
                    }
                }
            }
        }
        return cancellation?.isCancelled == true ? nil : map
    }

    /// Minimal wrapper to pass a mutable pointer into the concurrent closure.
    private nonisolated struct SendableBox: @unchecked Sendable {
        let value: UnsafeMutablePointer<OrientationResult>
        init(_ v: UnsafeMutablePointer<OrientationResult>) { value = v }
    }
}
