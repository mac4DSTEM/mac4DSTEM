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
//  The full-scan pass reads bounded scan-row tiles, then parallelizes each
//  tile with one detector (and its FFT scratch) per worker. multicorr is
//  ~10× slower than poly per pattern — poly is the interactive default,
//  multicorr the strain-analysis choice.
//

import Foundation
import Accelerate
import Metal

// MARK: - Types

/// One detected Bragg reflection, in detector pixels (x = column, y = row).
struct BraggPeak: Sendable {
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
struct BraggVectors: Sendable {
    let scanWidth: Int
    let scanHeight: Int
    let peaks: [[BraggPeak]]              // count == scanWidth * scanHeight

    var totalPeakCount: Int { peaks.reduce(0) { $0 + $1.count } }

    /// Vectors for calibrated scientific analysis. Raw detector coordinates
    /// remain stored for overlays and py4DSTEM `_v_uncal` export. Per-position
    /// origins are first collapsed onto `referenceOrigin`, then py4DSTEM's
    /// ellipse matrix is applied in its native qx/qy axis convention.
    nonisolated func calibrated(
        with calibration: Calibration,
        referenceOrigin: (x: Float, y: Float)
    ) -> BraggVectors {
        let origins = calibration.origin
        let canUseMaps = origins?.width == scanWidth
            && origins?.height == scanHeight
            && origins?.fittedX.count == peaks.count
            && origins?.fittedY.count == peaks.count
        guard canUseMaps || calibration.hasEllipse else { return self }

        var transformed = peaks
        for scan in transformed.indices {
            let localX = canUseMaps ? origins!.fittedX[scan] : referenceOrigin.x
            let localY = canUseMaps ? origins!.fittedY[scan] : referenceOrigin.y
            for peak in transformed[scan].indices {
                let raw = transformed[scan][peak]
                let offset = calibration.ellipseCorrectedOffset(
                    dx: raw.x - localX, dy: raw.y - localY
                )
                transformed[scan][peak].x = referenceOrigin.x + offset.x
                transformed[scan][peak].y = referenceOrigin.y + offset.y
            }
        }
        return BraggVectors(scanWidth: scanWidth, scanHeight: scanHeight, peaks: transformed)
    }

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
    private let px: Int, py: Int          // exact detector/FFT dims
    private let qx: Int, qy: Int          // detector dims

    // Scratch (native detector grid)
    private var re: [Float]
    private var im: [Float]
    private var ccRe: [Float]             // complex correlation, kept for multicorr
    private var ccIm: [Float]
    private var cc: [Float]               // real correlation
    private var smooth: [Float]
    private var blurTemp: [Float]
    private var blurPadded: [Float] = []
    private var blurTaps: [Float] = []
    private var cachedBlurSigma: Float = -.greatestFiniteMagnitude

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
        blurTemp = [Float](repeating: 0, count: n)
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
        // Copy the pattern onto the native circular-correlation grid.
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
        // the detector region minus the edge boundary.
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

            // py4DSTEM updates the reported peak intensity after polynomial
            // refinement using bilinear interpolation of the same correlation
            // image. Keeping the integer-pixel value biases refined peaks high.
            let refinedX = peaks[i].x
            let refinedY = peaks[i].y
            let x0 = Int(refinedX.rounded(.down))
            let x1 = Int(refinedX.rounded(.up))
            let y0 = Int(refinedY.rounded(.down))
            let y1 = Int(refinedY.rounded(.up))
            let fx = refinedX - Float(x0)
            let fy = refinedY - Float(y0)
            peaks[i].intensity =
                (1 - fx) * (1 - fy) * ar[y0 * px + x0]
                + fx * (1 - fy) * ar[y0 * px + x1]
                + (1 - fx) * fy * ar[y1 * px + x0]
                + fx * fy * ar[y1 * px + x1]
        }
    }

    // MARK: Stage 4b — multicorr (DFT-upsampled) subpixel

    /// Refine each peak on the unsmoothed complex correlation via the
    /// matrix-multiply DFT of Guizar-Sicairos et al. (upsampled_correlation).
    private func multicorrRefine(_ peaks: inout [BraggPeak], upsampleFactor: Int) {
        guard upsampleFactor > 2 else { return }
        for i in 0..<peaks.count {
            let refined = MatrixDFTCorrelation.refine(
                correlationRe: ccRe, correlationIm: ccIm,
                width: px, height: py,
                initial: CorrelationPeak(row: peaks[i].y, column: peaks[i].x),
                upsampleFactor: upsampleFactor
            )
            peaks[i].x = refined.column
            peaks[i].y = refined.row
        }
    }

    // MARK: Gaussian smoothing (separable, truncated at 4σ)

    private func gaussianBlur(src: [Float], dst: inout [Float], sigma: Float) {
        let radius = max(1, Int((4 * sigma).rounded()))
        if sigma != cachedBlurSigma {
            blurTaps = [Float](repeating: 0, count: 2 * radius + 1)
            var sum: Float = 0
            for i in -radius...radius {
                let value = exp(-Float(i * i) / (2 * sigma * sigma))
                blurTaps[i + radius] = value
                sum += value
            }
            for index in blurTaps.indices { blurTaps[index] /= sum }
            blurPadded = [Float](
                repeating: 0, count: max(px, py) + 2 * radius
            )
            cachedBlurSigma = sigma
        }

        // vDSP performs the same separable convolution as the prior scalar
        // loops. Explicit padding retains scipy.ndimage's half-sample reflect
        // boundary instead of substituting Accelerate's edge extension.
        // scipy.ndimage.gaussian_filter defaults to half-sample symmetric
        // `reflect`: -1 -> 0, -2 -> 1, n -> n-1.
        func reflected(_ raw: Int, count: Int) -> Int {
            var value = raw
            while value < 0 || value >= count {
                value = value < 0 ? -value - 1 : 2 * count - value - 1
            }
            return value
        }

        for y in 0..<py {
            let row = y * px
            for paddedIndex in 0..<(px + 2 * radius) {
                let x = reflected(paddedIndex - radius, count: px)
                blurPadded[paddedIndex] = src[row + x]
            }
            blurPadded.withUnsafeBufferPointer { input in
                blurTaps.withUnsafeBufferPointer { filter in
                    blurTemp.withUnsafeMutableBufferPointer { output in
                        vDSP_conv(
                            input.baseAddress!, 1,
                            filter.baseAddress!, 1,
                            output.baseAddress!.advanced(by: row), 1,
                            vDSP_Length(px), vDSP_Length(filter.count)
                        )
                    }
                }
            }
        }

        for x in 0..<px {
            for paddedIndex in 0..<(py + 2 * radius) {
                let y = reflected(paddedIndex - radius, count: py)
                blurPadded[paddedIndex] = blurTemp[y * px + x]
            }
            blurPadded.withUnsafeBufferPointer { input in
                blurTaps.withUnsafeBufferPointer { filter in
                    dst.withUnsafeMutableBufferPointer { output in
                        vDSP_conv(
                            input.baseAddress!, 1,
                            filter.baseAddress!, 1,
                            output.baseAddress!.advanced(by: x), vDSP_Stride(px),
                            vDSP_Length(py), vDSP_Length(filter.count)
                        )
                    }
                }
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
                          cancellation: AnalysisCancellationToken? = nil,
                          progress: (@Sendable (Double) -> Void)? = nil) -> BraggVectors? {
        guard cancellation?.isCancelled != true else { return nil }
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
                guard cancellation?.isCancelled != true else { return }
                guard let det = DiskDetector(kernel: kernel) else {
                    rowsDone.lock(); failed = true; rowsDone.unlock(); return
                }
                for ry in stride(from: w, to: d.ry, by: workers) {
                    if cancellation?.isCancelled == true { break }
                    for rx in 0..<d.rx {
                        if cancellation?.isCancelled == true { break }
                        let pat = slots.cubeBase + ry * rowPix + rx * patPix
                        slots.ptr[ry * d.rx + rx] = det.detect(pattern: pat, params: params)
                    }
                    if cancellation?.isCancelled == true { break }
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
            return !bad && cancellation?.isCancelled != true
        }
        guard ok else { return nil }
        return BraggVectors(scanWidth: d.rx, scanHeight: d.ry, peaks: results)
    }
}
