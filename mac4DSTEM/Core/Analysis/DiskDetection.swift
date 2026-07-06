//
//  DiskDetection.swift
//  Role: Bragg disk detection — the workhorse of 4DSTEM crystallography.
//        Port of py4DSTEM's find_Bragg_disks pipeline per pattern:
//
//   (1) hybrid cross-correlation with the probe kernel:
//         m  = FFT(pattern) · conj(FFT(kernel))
//         cc = |m|^p · exp(i·arg m)  =  m · |m|^(p−1)     (p = corrPower)
//         CC = max(Re(IFFT(cc)), 0)
//   (2) maxima of CC (optionally Gaussian-smoothed by sigmaCC), via strict
//       8-neighbor comparison (get_maxima_2D)
//   (3) the filter cascade: absolute / relative intensity, edge boundary,
//       min spacing (keep-brighter), max count
//   (4) subpixel refinement: parabolic ('poly'), or DFT-upsampled matrix-
//       multiply correlation ('multicorr', Guizar-Sicairos et al.) on the
//       UNsmoothed complex correlation — needed for strain-grade precision.
//
//  Coordinates: peaks are (x = detector column, y = row), app convention.
//  py4DSTEM's (qx, qy) has x as the row axis — translated here, nowhere else.
//
//  The full-scan pass parallelizes over scan rows with one detector (and its
//  FFT scratch) per worker; the cube is read straight from the shared
//  MTLBuffer. multicorr is ~10× slower than poly per pattern — poly is the
//  interactive default, multicorr the strain-analysis choice.
//

import Foundation
import Accelerate
import Metal

// MARK: - Types

/// One detected Bragg reflection, in detector pixels (x = column, y = row).
struct BraggPeak {
    var x: Float
    var y: Float
    var intensity: Float
}

enum SubpixelMode: String, CaseIterable, Identifiable {
    case pixel     = "Pixel"
    case poly      = "Parabolic"
    case multicorr = "Fourier (multicorr)"
    var id: String { rawValue }
}

/// Detection parameters, mirroring find_Bragg_disks. Defaults follow
/// py4DSTEM where scale-free; AppState adapts the pixel-scaled ones
/// (minPeakSpacing, edgeBoundary) to the detector size on dataset load.
struct DiskDetectionParams {
    var corrPower: Float = 1              // 1 = cross, 0 = phase correlation
    var sigmaCC: Float = 2                // gaussian smoothing of CC before maxima
    var subpixel: SubpixelMode = .poly
    var upsampleFactor: Int = 16
    var minAbsoluteIntensity: Float = 0
    var minRelativeIntensity: Float = 0.005
    var relativeToPeak: Int = 0
    var minPeakSpacing: Float = 60
    var edgeBoundary: Int = 20
    var maxNumPeaks: Int = 70
}

/// Detected peaks for every scan position, row-major [ry][rx].
struct BraggVectors {
    let scanWidth: Int
    let scanHeight: Int
    let peaks: [[BraggPeak]]              // count == scanWidth * scanHeight

    var totalPeakCount: Int { peaks.reduce(0) { $0 + $1.count } }

    /// Bragg vector map: intensity-weighted 2D histogram of all peak
    /// positions in detector space (bilinear deposition, py4DSTEM's
    /// add_to_2D_array_from_floats).
    func map(qy: Int, qx: Int) -> FloatImage {
        var out = [Float](repeating: 0, count: qy * qx)
        for positionPeaks in peaks {
            for p in positionPeaks {
                let x0 = Int(p.x.rounded(.down)), y0 = Int(p.y.rounded(.down))
                let fx = p.x - Float(x0), fy = p.y - Float(y0)
                for (xi, yi, w) in [(x0, y0, (1 - fx) * (1 - fy)),
                                    (x0 + 1, y0, fx * (1 - fy)),
                                    (x0, y0 + 1, (1 - fx) * fy),
                                    (x0 + 1, y0 + 1, fx * fy)] {
                    if xi >= 0, xi < qx, yi >= 0, yi < qy {
                        out[yi * qx + xi] += w * p.intensity
                    }
                }
            }
        }
        return FloatImage(width: qx, height: qy, pixels: out)
    }
}

// MARK: - DiskDetector

/// Per-worker detector: owns the FFT plan and scratch buffers, so one
/// instance must not be used from two threads at once. Create one per
/// concurrent worker (they share the kernel, which is immutable).
nonisolated final class DiskDetector {

    private let kernel: ProbeKernel
    private let fft: FFT2D
    private let px: Int, py: Int          // padded dims
    private let qx: Int, qy: Int          // detector dims

    // Scratch (padded grid)
    private var re: [Float]
    private var im: [Float]
    private var ccRe: [Float]             // complex correlation, kept for multicorr
    private var ccIm: [Float]
    private var cc: [Float]               // real correlation
    private var smooth: [Float]

    init?(kernel: ProbeKernel) {
        guard let fft = FFT2D(nx: kernel.px, ny: kernel.py) else { return nil }
        self.kernel = kernel
        self.fft = fft
        self.px = kernel.px; self.py = kernel.py
        self.qx = kernel.qx; self.qy = kernel.qy
        let n = px * py
        re = [Float](repeating: 0, count: n)
        im = [Float](repeating: 0, count: n)
        ccRe = [Float](repeating: 0, count: n)
        ccIm = [Float](repeating: 0, count: n)
        cc = [Float](repeating: 0, count: n)
        smooth = [Float](repeating: 0, count: n)
    }

    // MARK: Detection (one pattern)

    /// Detect Bragg disks in one [qy * qx] pattern.
    func detect(pattern: UnsafePointer<Float>, params: DiskDetectionParams) -> [BraggPeak] {
        crossCorrelate(pattern: pattern, corrPower: params.corrPower)

        // Smooth (or copy) the real CC for maxima finding.
        if params.sigmaCC > 0 {
            gaussianBlur(src: cc, dst: &smooth, sigma: params.sigmaCC)
        } else {
            smooth = cc
        }

        var peaks = findMaxima(in: smooth, params: params)

        if params.subpixel != .pixel {
            polyRefine(&peaks, in: smooth)
        }
        if params.subpixel == .multicorr {
            multicorrRefine(&peaks, upsampleFactor: params.upsampleFactor)
        }
        return peaks
    }

    /// Convenience for [Float] input (live single-pattern path).
    func detect(pattern: [Float], params: DiskDetectionParams) -> [BraggPeak] {
        precondition(pattern.count == qy * qx)
        return pattern.withUnsafeBufferPointer { detect(pattern: $0.baseAddress!, params: params) }
    }

    // MARK: Stage 1 — hybrid cross correlation

    private func crossCorrelate(pattern: UnsafePointer<Float>, corrPower: Float) {
        // Zero-pad the pattern at the origin corner.
        let n = px * py
        for i in 0..<n { re[i] = 0; im[i] = 0 }
        for y in 0..<qy {
            re.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.advanced(by: y * px)
                    .update(from: pattern + y * qx, count: qx)
            }
        }
        fft.transform(re: &re, im: &im, forward: true)

        // m = FFT(pattern) · conj(FFT(kernel));  hybrid: m · |m|^(p−1)
        let kRe = kernel.ftRe, kIm = kernel.ftIm
        for i in 0..<n {
            var mr = re[i] * kRe[i] - im[i] * kIm[i]
            var mi = re[i] * kIm[i] + im[i] * kRe[i]
            if corrPower != 1 {
                let mag = (mr * mr + mi * mi).squareRoot()
                let f = mag > 0 ? pow(mag, corrPower - 1) : 0
                mr *= f; mi *= f
            }
            ccRe[i] = mr; ccIm[i] = mi
        }

        // CC = max(Re(IFFT(cc)), 0). Keep ccRe/ccIm for multicorr.
        re = ccRe; im = ccIm
        fft.transform(re: &re, im: &im, forward: false)
        vDSP_vthres(re, 1, [0], &cc, 1, vDSP_Length(n))
    }

    // MARK: Stage 2+3 — maxima + filter cascade (get_maxima_2D port)

    private func findMaxima(in ar: [Float], params p: DiskDetectionParams) -> [BraggPeak] {
        // Local maxima by strict/loose 8-neighbor comparison, restricted to
        // the real detector region minus the edge boundary (peaks can't sit
        // in the zero padding).
        let eb = max(1, p.edgeBoundary)
        var found: [BraggPeak] = []
        guard qy - eb > eb, qx - eb > eb else { return [] }
        for y in eb..<(qy - eb) {
            for x in eb..<(qx - eb) {
                let i = y * px + x
                let v = ar[i]
                // Ties break toward the earlier (lower-index) pixel, matching
                // py4DSTEM's mixed >=/> roll comparison.
                if v >= ar[i + 1], v > ar[i - 1],
                   v >= ar[i + px], v > ar[i - px],
                   v >= ar[i + px + 1], v > ar[i + px - 1],
                   v >= ar[i - px + 1], v > ar[i - px - 1] {
                    found.append(BraggPeak(x: Float(x), y: Float(y), intensity: v))
                }
            }
        }
        found.sort { $0.intensity > $1.intensity }

        // Intensity thresholds.
        if p.minAbsoluteIntensity > 0 {
            found.removeAll { $0.intensity < p.minAbsoluteIntensity }
        }
        if p.minRelativeIntensity > 0, found.count > p.relativeToPeak {
            let ref = found[p.relativeToPeak].intensity
            found.removeAll { $0.intensity / ref < p.minRelativeIntensity }
        }

        // Min spacing: walk brightest-first, drop anything too close to a
        // kept peak.
        if p.minPeakSpacing > 0 {
            let d2 = p.minPeakSpacing * p.minPeakSpacing
            var kept: [BraggPeak] = []
            outer: for cand in found {
                for k in kept {
                    let dx = cand.x - k.x, dy = cand.y - k.y
                    if dx * dx + dy * dy < d2 { continue outer }
                }
                kept.append(cand)
            }
            found = kept
        }

        if found.count > p.maxNumPeaks {
            found.removeLast(found.count - p.maxNumPeaks)
        }
        return found
    }

    // MARK: Stage 4a — parabolic subpixel

    private func polyRefine(_ peaks: inout [BraggPeak], in ar: [Float]) {
        for i in 0..<peaks.count {
            let x = Int(peaks[i].x), y = Int(peaks[i].y)
            let c = y * px + x
            let ix0 = ar[c], ix1 = ar[c + 1], ix1_ = ar[c - 1]
            let iy1 = ar[c + px], iy1_ = ar[c - px]
            let dx = (ix1 - ix1_) / (4 * ix0 - 2 * ix1 - 2 * ix1_)
            let dy = (iy1 - iy1_) / (4 * ix0 - 2 * iy1 - 2 * iy1_)
            if dx.isFinite { peaks[i].x += dx }
            if dy.isFinite { peaks[i].y += dy }
        }
    }

    // MARK: Stage 4b — multicorr (DFT-upsampled) subpixel

    /// Refine each peak on the unsmoothed complex correlation via the
    /// matrix-multiply DFT of Guizar-Sicairos et al. (upsampled_correlation).
    private func multicorrRefine(_ peaks: inout [BraggPeak], upsampleFactor: Int) {
        guard upsampleFactor > 2 else { return }
        let u = Float(upsampleFactor)
        for i in 0..<peaks.count {
            // Half-pixel start (py4DSTEM rounds the poly result to 0.5 px),
            // then snap to the upsampled grid.
            var sx = (peaks[i].x * 2).rounded() / 2
            var sy = (peaks[i].y * 2).rounded() / 2
            sx = (sx * u).rounded() / u
            sy = (sy * u).rounded() / u

            let globalShift = (Float(ceil(u * 1.5)) / 2).rounded(.down)
            let up = dftUpsample(centerX: globalShift - u * sx,
                                 centerY: globalShift - u * sy,
                                 upsampleFactor: upsampleFactor)

            // argmax of the upsampled patch + parabolic polish.
            let m = Int(ceil(1.5 * u))
            var bi = 0
            for j in 1..<up.count where up[j] > up[bi] { bi = j }
            var subY = Float(bi / m), subX = Float(bi % m)
            let yy = bi / m, xx = bi % m
            if yy > 0, yy < m - 1, xx > 0, xx < m - 1 {
                let c = up[bi]
                let xp = up[bi + 1], xm = up[bi - 1]
                let yp = up[bi + m], ym = up[bi - m]
                let ddx = (xp - xm) / (4 * c - 2 * xp - 2 * xm)
                let ddy = (yp - ym) / (4 * c - 2 * yp - 2 * ym)
                if ddx.isFinite { subX += ddx }
                if ddy.isFinite { subY += ddy }
            }
            peaks[i].x = sx + (subX - globalShift) / u
            peaks[i].y = sy + (subY - globalShift) / u
        }
    }

    /// real(rowKern · conj(m) · colKern) on an upsampled patch around the
    /// peak (dftUpsample). centerX/Y are in upsampled-grid units.
    private func dftUpsample(centerX: Float, centerY: Float, upsampleFactor: Int) -> [Float] {
        let m = Int(ceil(1.5 * Float(upsampleFactor)))
        let n = px * py

        // t = conj(cc) · colKern   (complex [py × m])
        // colKern[j,c] = exp(-2πi/(px·u) · wrap(j)·(c − centerX))
        var tRe = [Float](repeating: 0, count: py * m)
        var tIm = [Float](repeating: 0, count: py * m)
        let wx = -2 * Float.pi / (Float(px) * Float(upsampleFactor))
        for j in 0..<px {
            let wj = Float(j < px / 2 ? j : j - px)
            for c in 0..<m {
                let ang = wx * wj * (Float(c) - centerX)
                let (ca, sa) = (cos(ang), sin(ang))
                for r in 0..<py {
                    let i = r * px + j
                    // conj(cc)[r,j] = (ccRe, −ccIm)
                    tRe[r * m + c] += ccRe[i] * ca + ccIm[i] * sa
                    tIm[r * m + c] += -ccIm[i] * ca + ccRe[i] * sa
                }
            }
        }
        _ = n

        // up[r,c] = real( Σ_k rowKern[r,k] · t[k,c] )
        // rowKern[r,k] = exp(-2πi/(py·u) · (r − centerY)·wrap(k))
        var up = [Float](repeating: 0, count: m * m)
        let wy = -2 * Float.pi / (Float(py) * Float(upsampleFactor))
        for r in 0..<m {
            for k in 0..<py {
                let wk = Float(k < py / 2 ? k : k - py)
                let ang = wy * (Float(r) - centerY) * wk
                let (ca, sa) = (cos(ang), sin(ang))
                for c in 0..<m {
                    up[r * m + c] += ca * tRe[k * m + c] - sa * tIm[k * m + c]
                }
            }
        }
        return up
    }

    // MARK: Gaussian smoothing (separable, truncated at 4σ)

    private func gaussianBlur(src: [Float], dst: inout [Float], sigma: Float) {
        let radius = max(1, Int((4 * sigma).rounded()))
        var taps = [Float](repeating: 0, count: 2 * radius + 1)
        var s: Float = 0
        for i in -radius...radius {
            let v = exp(-Float(i * i) / (2 * sigma * sigma))
            taps[i + radius] = v
            s += v
        }
        for i in 0..<taps.count { taps[i] /= s }

        // Horizontal pass into scratch `im` reuse is unsafe (used elsewhere);
        // use a local temp sized to the padded grid.
        var tmp = [Float](repeating: 0, count: px * py)
        for y in 0..<py {
            let row = y * px
            for x in 0..<px {
                var acc: Float = 0
                for t in -radius...radius {
                    let xx = min(max(x + t, 0), px - 1)
                    acc += src[row + xx] * taps[t + radius]
                }
                tmp[row + x] = acc
            }
        }
        for y in 0..<py {
            for x in 0..<px {
                var acc: Float = 0
                for t in -radius...radius {
                    let yy = min(max(y + t, 0), py - 1)
                    acc += tmp[yy * px + x] * taps[t + radius]
                }
                dst[y * px + x] = acc
            }
        }
    }
}

// MARK: - Full-scan detection

enum DiskDetection {

    /// Detect disks at every scan position, parallelized over scan rows.
    /// `cube` is the resident float32 cube [ry][rx][qy][qx]; progress is
    /// reported in [0, 1] from worker threads.
    nonisolated static func detectAll(cube: MTLBuffer,
                          descriptor d: DatasetDescriptor,
                          kernel: ProbeKernel,
                          params: DiskDetectionParams,
                          progress: (@Sendable (Double) -> Void)? = nil) -> BraggVectors? {
        let base = cube.contents().bindMemory(to: Float.self,
                                              capacity: d.ry * d.rx * d.qy * d.qx)
        let patPix = d.qy * d.qx
        let rowPix = d.rx * patPix

        // One result slot per scan position; rows are disjoint, so workers
        // never touch the same slot. The buffer is captured via a wrapper to
        // sidestep Sendable checking on the raw pointer (read-only access).
        struct Slots: @unchecked Sendable {
            let ptr: UnsafeMutablePointer<[BraggPeak]>
            let cubeBase: UnsafePointer<Float>
        }
        var results = [[BraggPeak]](repeating: [], count: d.ry * d.rx)
        let rowsDone = NSLock()
        var doneCount = 0

        let ok = results.withUnsafeMutableBufferPointer { buf -> Bool in
            let slots = Slots(ptr: buf.baseAddress!, cubeBase: base)
            // One detector (FFT plan + padded scratch) per WORKER, rows strided
            // across workers — not one per row, which churned multi-MB
            // allocations on large scans. `failed` is guarded by the lock.
            var failed = false
            let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, d.ry))
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                guard let det = DiskDetector(kernel: kernel) else {
                    rowsDone.lock(); failed = true; rowsDone.unlock(); return
                }
                for ry in stride(from: w, to: d.ry, by: workers) {
                    for rx in 0..<d.rx {
                        let pat = slots.cubeBase + ry * rowPix + rx * patPix
                        slots.ptr[ry * d.rx + rx] = det.detect(pattern: pat, params: params)
                    }
                    if let progress {
                        rowsDone.lock()
                        doneCount += 1
                        let f = Double(doneCount) / Double(d.ry)
                        rowsDone.unlock()
                        progress(f)
                    }
                }
            }
            rowsDone.lock(); let bad = failed; rowsDone.unlock()
            return !bad
        }
        guard ok else { return nil }
        return BraggVectors(scanWidth: d.rx, scanHeight: d.ry, peaks: results)
    }
}
