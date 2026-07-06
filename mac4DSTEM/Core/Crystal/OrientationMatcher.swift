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
import Metal

nonisolated final class OrientationMatcher {

    private let plan: OrientationPlan
    private let geo: PolarGeometry
    private let fft: FFT1D

    // Scratch (per-ring FFT of the experimental pattern + correlation buffers).
    private var expRe: [Float]
    private var expIm: [Float]
    private var corrRe: [Float]
    private var corrIm: [Float]

    init?(plan: OrientationPlan) {
        guard let fft = FFT1D(n: plan.geometry.nAzimuthal) else { return nil }
        self.plan = plan
        self.geo = plan.geometry
        self.fft = fft
        let n = geo.nRadial * geo.nAzimuthal
        expRe = [Float](repeating: 0, count: n)
        expIm = [Float](repeating: 0, count: n)
        corrRe = [Float](repeating: 0, count: geo.nAzimuthal)
        corrIm = [Float](repeating: 0, count: geo.nAzimuthal)
    }

    /// Match one pattern's peaks against the plan.
    func match(peaks: [BraggPeak], originX: Float, originY: Float,
               invAngstromPerPixel: Double = 1) -> OrientationResult {
        guard peaks.count >= 2 else { return .empty }

        // Experimental polar image (unit-normalized so the score is a proper
        // normalized correlation).
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

        let na = geo.nAzimuthal, nr = geo.nRadial
        let invScale = 1 / Float(na)     // undo vDSP's unnormalized inverse FFT
        var best: Float = -.greatestFiniteMagnitude, second = best
        var bestT = -1, bestBin = 0

        for t in 0..<plan.count {
            let tRe = plan.templateFFTRe[t], tIm = plan.templateFFTIm[t]
            for a in 0..<na { corrRe[a] = 0; corrIm[a] = 0 }
            // corr_freq = Σ_ring conj(Exp) · Template
            for r in 0..<nr {
                let base = r * na
                for a in 0..<na {
                    let er = expRe[base + a], ei = expIm[base + a]
                    let tr = tRe[base + a], ti = tIm[base + a]
                    corrRe[a] += er * tr + ei * ti      // Re[(er - i·ei)(tr + i·ti)]
                    corrIm[a] += er * ti - ei * tr      // Im
                }
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
        guard bestT >= 0 else { return .empty }

        // The correlation peaks at −θ (experimental = template rotated by +θ ⇒
        // circular shift of −θ), so negate to report the pattern's in-plane
        // rotation. It is determined only mod 180°: Friedel's law makes the
        // |F|² pattern centrosymmetric.
        let bin = (na - bestBin) % na
        let angle = Float(Double(bin) / Double(na) * 2 * Double.pi)
        return OrientationResult(templateIndex: bestT, euler: .zero, inPlaneAngle: angle,
                                 score: max(best, 0), secondScore: max(second, 0), phaseID: 0)
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

// MARK: - Full-scan matching

enum OrientationMatching {

    /// Match every scan position's Bragg peaks against the plan, parallelized
    /// over scan rows. Progress in [0, 1] reported from workers.
    nonisolated static func matchAll(bragg: BraggVectors, plan: OrientationPlan,
                                     originX: Float, originY: Float,
                                     invAngstromPerPixel: Double = 1,
                                     progress: (@Sendable (Double) -> Void)? = nil) -> OrientationMap {
        var map = OrientationMap(width: bragg.scanWidth, height: bragg.scanHeight)
        let w = bragg.scanWidth
        let lock = NSLock()
        var done = 0

        map.results.withUnsafeMutableBufferPointer { out in
            let ptr = SendableBox(out.baseAddress!)
            // One matcher (FFT + scratch) per worker, rows strided (same
            // pattern as DiskDetection.detectAll).
            let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, bragg.scanHeight))
            DispatchQueue.concurrentPerform(iterations: workers) { worker in
                guard let matcher = OrientationMatcher(plan: plan) else { return }
                for ry in stride(from: worker, to: bragg.scanHeight, by: workers) {
                    for rx in 0..<w {
                        let peaks = bragg.peaks[ry * w + rx]
                        ptr.value[ry * w + rx] = matcher.match(
                            peaks: peaks, originX: originX, originY: originY,
                            invAngstromPerPixel: invAngstromPerPixel)
                    }
                    if let progress {
                        lock.lock(); done += 1; let f = Double(done) / Double(bragg.scanHeight); lock.unlock()
                        progress(f)
                    }
                }
            }
        }
        return map
    }

    /// Minimal wrapper to pass a mutable pointer into the concurrent closure.
    private struct SendableBox: @unchecked Sendable {
        let value: UnsafeMutablePointer<OrientationResult>
        init(_ v: UnsafeMutablePointer<OrientationResult>) { value = v }
    }
}
