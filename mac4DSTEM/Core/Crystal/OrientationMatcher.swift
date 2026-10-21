//
//  OrientationMatcher.swift
//  Role: ACOM orientation matching in the app. The CPU matcher (a pattern's peaks to a polar image, the azimuthal FFT
//        correlation against every template, the forward and the mirrored pass, the distinct runner-up, the symmetry
//        reduction), the choice of a winner from per-template scores a caller computed (`ACOMMatcher.result(scores:...)`)
//        and the scan loop with its selection, workers, progress and cancellation are DiffractoKit's (`ACOMMatcher`,
//        `ACOMMatcher.matchAll(peaksAt:)`, `ACOMScanSelection`, `ACOMScanResults`; 0.7.0). What stays here is what the kit
//        does not offer: the Metal backend (`MetalACOMMatcher`: the batched correlation on the GPU, reading the kit
//        library's template FFTs), the choice of backend, and the adapters from the app's `BraggPeak` / `BraggVectors`
//        and `OrientationMap`.
//

import Foundation
import Accelerate
import DiffractoOrientation
import Metal
import simd

// MARK: - Adapters from the app's peak type

extension ACOMPeak {
    package nonisolated init(_ peak: BraggPeak) {
        self.init(x: peak.x, y: peak.y, intensity: peak.intensity)
    }
}

extension ACOMMatcher {
    /// The app's `BraggPeak` spellings of the kit matcher's per-pattern calls (same peaks, same numbers).
    package nonisolated func match(peaks: [BraggPeak], originX: Float, originY: Float,
                                   invAngstromPerPixel: Double = 1) -> OrientationResult {
        match(peaks: peaks.map(ACOMPeak.init), originX: originX, originY: originY,
              invAngstromPerPixel: invAngstromPerPixel)
    }

    package nonisolated func templateScores(peaks: [BraggPeak], originX: Float, originY: Float,
                                            invAngstromPerPixel: Double = 1) -> [Float] {
        templateScores(peaks: peaks.map(ACOMPeak.init), originX: originX, originY: originY,
                       invAngstromPerPixel: invAngstromPerPixel)
    }

    package nonisolated func experimentalPolarImage(peaks: [BraggPeak], originX: Float, originY: Float,
                                                    invAngstromPerPixel: Double = 1) -> [Float]? {
        experimentalPolarImage(peaks: peaks.map(ACOMPeak.init), originX: originX, originY: originY,
                               invAngstromPerPixel: invAngstromPerPixel)
    }

    package nonisolated func experimentalFFT(peaks: [BraggPeak], originX: Float, originY: Float,
                                             invAngstromPerPixel: Double = 1) -> (re: [Float], im: [Float])? {
        experimentalFFT(peaks: peaks.map(ACOMPeak.init), originX: originX, originY: originY,
                        invAngstromPerPixel: invAngstromPerPixel)
    }
}

private nonisolated struct ACOMMetalParams {
    package var positions: UInt32
    package var templates: UInt32
    package var radial: UInt32
    package var azimuthal: UInt32
}

/// Batched Metal matcher. Polar deposition and forward FFT deliberately remain
/// shared with the CPU oracle; Metal accelerates the dominant template/ring
/// correlation and inverse-angle search, then the CPU applies identical
/// best/second selection and symmetry reporting.
package nonisolated final class MetalACOMMatcher {
    private let plan: OrientationPlan
    private let preparer: ACOMMatcher
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let spectrumPipeline: MTLComputePipelineState
    private let argmaxPipeline: MTLComputePipelineState
    private let templateReal: MTLBuffer
    private let templateImaginary: MTLBuffer
    private let batchSize: Int

    package init?(plan: OrientationPlan) {
        // try? OK (v2 S7 audit): this is a failable init whose nil contract
        // is "the GPU matcher is unavailable" — the two pipeline-state
        // creations are just two of the seven ways the guard can refuse.
        // Verified consumer: `OrientationMatching.matchAll` returns nil on
        // it, and the ACOM run reports "failed to initialize", which is the
        // true mechanism here (cancellation is checked separately first).
        // Converting the init to throwing would rename the same refusal,
        // not sharpen it.
        let engine = MetalEngine.shared
        guard let preparer = ACOMMatcher(library: plan.library) else { return nil }
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
        self.preparer = preparer
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

    package func matchAll(
        bragg: BraggVectors,
        originX: Float, originY: Float,
        invAngstromPerPixel: Double,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?
    ) -> OrientationMap? {
        guard cancellation?.isCancelled != true else { return nil }
        let total = bragg.scanWidth * bragg.scanHeight
        var map = OrientationMap(
            width: bragg.scanWidth, height: bragg.scanHeight,
            matchingBackend: .metal, symmetry: plan.symmetry, templateCount: plan.count
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
                    experimentalReal.append(contentsOf: prepared.re)
                    experimentalImaginary.append(contentsOf: prepared.im)
                    valid[local] = true
                } else {
                    experimentalReal.append(contentsOf: repeatElement(0, count: gridCount))
                    experimentalImaginary.append(contentsOf: repeatElement(0, count: gridCount))
                }
            }
            guard let forward = runBatch(
                experimentalReal: experimentalReal,
                experimentalImaginary: experimentalImaginary,
                positionCount: count
            ) else { return nil }
            // The mirrored pass (see DiffractoKit's ACOMMatcher.match): the kernel
            // computes conj(E)·T, so a negated imaginary part gives E·T —
            // the correlation of the azimuth-reversed image — unchanged.
            var conjugatedImaginary = experimentalImaginary
            vDSP_vneg(experimentalImaginary, 1, &conjugatedImaginary, 1,
                      vDSP_Length(experimentalImaginary.count))
            guard let mirror = runBatch(
                experimentalReal: experimentalReal,
                experimentalImaginary: conjugatedImaginary,
                positionCount: count
            ) else { return nil }
            for local in 0..<count where valid[local] {
                let offset = local * plan.count
                var scores = Array(forward.scores[offset..<(offset + plan.count)])
                var bins = Array(forward.bins[offset..<(offset + plan.count)])
                var mirrored = [Bool](repeating: false, count: plan.count)
                for t in 0..<plan.count where mirror.scores[offset + t] > scores[t] {
                    scores[t] = mirror.scores[offset + t]
                    bins[t] = mirror.bins[offset + t]
                    mirrored[t] = true
                }
                // The kit's own winner, distinct runner-up and symmetry reduction from the GPU's scores (DiffractoKit
                // 0.7.0 `ACOMMatcher.result(scores:bins:mirrored:)`), so the choice is the CPU path's by construction.
                map.results[lower + local] = preparer.result(scores: scores, bins: bins, mirrored: mirrored)
            }
            progress?(Double(upper) / Double(total))
        }
        return cancellation?.isCancelled == true ? nil : map
    }

    /// One Metal batch inside its own autorelease pool. `matchAll` is a long
    /// synchronous loop, so no pool drains inside it; without one the
    /// autoreleased references to each batch's buffers, command buffer and
    /// encoders survive until `matchAll` returns and device memory grows by
    /// about one batch's shared buffers per batch (Gate D, 2026-10-15,
    /// `ACOMMetalMemoryTests`: 0.125 MB per batch, 25 MB over 200
    /// batches, flat with the pool). The results leave as Swift arrays, so
    /// nothing returned depends on the pool. Same remedy as
    /// `DiskDetection.detectAll(data:)` per tile.
    private func runBatch(
        experimentalReal: [Float], experimentalImaginary: [Float], positionCount: Int
    ) -> (scores: [Float], bins: [UInt32])? {
        autoreleasepool {
            runBatchUnpooled(
                experimentalReal: experimentalReal,
                experimentalImaginary: experimentalImaginary,
                positionCount: positionCount
            )
        }
    }

    private func runBatchUnpooled(
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

package enum OrientationMatching {

    /// Match the requested scan positions against the plan. Full scans, preview and region work only touch their
    /// selected source positions. Progress is the requested work, not the full dataset size.
    package nonisolated static func matchAll(bragg: BraggVectors, plan: OrientationPlan,
                                     originX: Float, originY: Float,
                                     invAngstromPerPixel: Double = 1,
                                     backend: ACOMMatchingBackend = .automatic,
                                     selection: ACOMScanSelection = .full,
                                     cancellation: AnalysisCancellationToken? = nil,
                                     progress: (@Sendable (Double) -> Void)? = nil) -> OrientationMap? {
        guard cancellation?.isCancelled != true else { return nil }
        let selectedIndices = selection.sourceIndices(
            width: bragg.scanWidth, height: bragg.scanHeight
        )
        guard !selectedIndices.isEmpty else { return nil }
        // The exact Metal backend is retained for parity/performance testing,
        // but the current direct inverse-DFT kernel is slower than the
        // vectorized CPU path on the v1 benchmark. Automatic therefore means
        // the measured production CPU backend until a batched FFT wins.
        if backend == .metal {
            let input: BraggVectors
            if selection == .full {
                input = bragg
            } else {
                input = BraggVectors(
                    scanWidth: selectedIndices.count, scanHeight: 1,
                    peaks: selectedIndices.map { bragg.peaks[$0] }
                )
            }
            if let matcher = MetalACOMMatcher(plan: plan),
               let matched = matcher.matchAll(
                    bragg: input,
                    originX: originX, originY: originY,
                    invAngstromPerPixel: invAngstromPerPixel,
                    cancellation: cancellation, progress: progress
               ) {
                if selection == .full { return matched }
                var result = OrientationMap(
                    width: bragg.scanWidth, height: bragg.scanHeight,
                    matchingBackend: .metal, symmetry: plan.symmetry,
                    templateCount: plan.count
                )
                for (compact, source) in selectedIndices.enumerated() {
                    result.results[source] = matched.results[compact]
                }
                return expanded(result, selection: selection)
            }
            return nil
        }
        guard let matcher = ACOMMatcher(library: plan.library) else { return nil }
        let isCancelled: @Sendable () -> Bool = { cancellation?.isCancelled == true }
        // The kit's scan loop over the whole scan: the selected positions only, workers dealt round-robin, progress in
        // 1 % batches over the selection, cancellation polled before each position. The peaks of a position are a lazy
        // view of the app's `BraggPeak`s (DiffractoKit 0.7.0 `matchAll(peaksAt:)`): no `[[ACOMPeak]]` is built.
        guard let scan = matcher.matchAll(
            width: bragg.scanWidth, height: bragg.scanHeight,
            originX: originX, originY: originY, invAngstromPerPixel: invAngstromPerPixel,
            selection: selection, maxWorkers: nil, isCancelled: isCancelled, progress: progress,
            peaksAt: { bragg.peaks[$0].lazy.map(ACOMPeak.init) }
        ) else { return nil }
        var map = OrientationMap(
            width: bragg.scanWidth, height: bragg.scanHeight,
            matchingBackend: .cpu, symmetry: plan.symmetry, templateCount: plan.count
        )
        map.results = scan.results
        return map
    }

    /// `preview` copies each matched block's top-left result over the block (the kit's rule); other selections unchanged.
    private nonisolated static func expanded(_ map: OrientationMap, selection: ACOMScanSelection) -> OrientationMap {
        guard case .preview = selection else { return map }
        var scan = ACOMScanResults(width: map.width, height: map.height, templateCount: map.templateCount)
        scan.results = map.results
        var out = map
        out.results = scan.expandedPreview(selection: selection).results
        return out
    }
}
