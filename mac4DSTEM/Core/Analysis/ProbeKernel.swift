//
//  ProbeKernel.swift
//  Role: Build the cross-correlation kernel for Bragg disk detection
//        (py4DSTEM: Probe.generate_synthetic_probe + get_probe_kernel_edge_
//        sigmoid). The kernel is the probe normalized to unit sum, minus a
//        sine²-sigmoid "trench" normalized to unit sum — so it integrates to
//        zero and responds to disk-shaped features, not to background.
//
//  NATIVE-GRID CONVENTION: detection runs on the detector's exact Q shape so
//  its circular correlation matches NumPy/py4DSTEM for non-radix-2 data. The
//  kernel is built directly on that grid using *wrapped* coordinates — i.e. it
//  is corner-centered from birth, exactly the layout circular correlation
//  needs — which sidesteps py4DSTEM's Fourier-shift step entirely. Patterns
//  and correlation peaks land at the disk's original detector coordinates.
//
//  Supports a synthetic logistic disk, a measured vacuum pattern selected
//  with the app's real-space ROI, and a probe image carried by the file. A
//  measured probe takes one of two MODES (py4DSTEM Probe.get_kernel): the
//  sine² trench above, or FLAT — the probe normalized to unit sum and shifted
//  to the corner, nothing subtracted — which py4DSTEM recommends "for
//  bullseye or other structured probes" (probe.py, get_kernel docstring).
//  Measured 2026-09-05 on calibrationData_bullseyeProbe: with the trench at
//  the ESTIMATOR'S radii (7.4, 14.7 px — the probe-size estimator reads a
//  ring-shaped probe's radius small) the beam is never the brightest
//  correlation peak; at the disk's true radii the trench works as well as
//  flat. Flat needs no radius, which is why it is the safe route here
//  (open-items.md; the Gate B refuter corrected the mechanism).
//

import Foundation

package nonisolated enum ProbeKernelSource: String, Sendable {
    case synthetic = "Synthetic"
    case measured = "Measured ROI"
    case fileProbe = "File probe"

    package var provenanceID: String {
        switch self {
        case .synthetic: "synthetic"
        case .measured: "measured_roi"
        case .fileProbe: "measured_file_probe"
        }
    }
}

/// How a MEASURED probe becomes a kernel (py4DSTEM `Probe.get_kernel` modes
/// "sigmoid" and "flat"). The synthetic kernel is always the trench form.
package nonisolated enum ProbeKernelMode: String, Sendable, CaseIterable, Identifiable {
    case sigmoidTrench = "Sigmoid trench"
    case flat = "Flat"

    package var id: String { rawValue }
    package var provenanceID: String {
        switch self {
        case .sigmoidTrench: "sigmoid_trench"
        case .flat: "flat"
        }
    }
}

/// A ready-to-use detection kernel: real-space form (for inspection) plus its
/// precomputed conjugated Fourier transform on the native detector grid.
package nonisolated struct ProbeKernel: Sendable {
    /// Exact detector grid dimensions the kernel lives on.
    package let px: Int
    package let py: Int
    /// Detector dimensions the kernel was built for.
    package let qx: Int
    package let qy: Int
    /// The probe radius (px) and sigmoid trench radii used to build it.
    package let probeRadius: Float
    /// (0, 0) for a flat kernel: nothing was subtracted.
    package let trenchRadii: (inner: Float, outer: Float)
    package let source: ProbeKernelSource
    package let mode: ProbeKernelMode
    /// The HDF5 path the probe image was read from, for `.fileProbe` kernels.
    package let probePath: String?

    /// Corner-centered, zero-sum kernel on the native grid [py * px].
    package let kernel: [Float]
    /// conj(FFT2(kernel)) — the term every pattern's FFT is multiplied with.
    package let ftRe: [Float]
    package let ftIm: [Float]

    // MARK: Construction

    /// Synthetic probe kernel from the calibrated probe radius.
    /// - Parameters:
    ///   - radius: central-disk radius in detector px (Calibration.probeRadius).
    ///   - width: edge blur of the synthetic probe (px); py4DSTEM examples
    ///     typically use ~1–2 px for sharp disks.
    ///   - trenchRadii: sigmoid trench inner/outer radii; nil → (r, 2r),
    ///     the standard choice.
    package nonisolated static func synthetic(radius: Float, width: Float = 2,
                          qy: Int, qx: Int,
                          trenchRadii: (Float, Float)? = nil) -> ProbeKernel? {
        let px = qx
        let py = qy
        guard let fft = FFT2D(nx: px, ny: py), radius > 0 else { return nil }

        let (ri, ro) = trenchRadii ?? (radius, 2 * radius)

        // Both the probe and the trench are radial functions of the wrapped
        // (corner-centered) radius on the native grid.
        var probe = [Float](repeating: 0, count: py * px)
        var trench = [Float](repeating: 0, count: py * px)
        var probeSum: Float = 0
        var trenchSum: Float = 0
        for y in 0..<py {
            let wy = Float(y < py / 2 ? y : y - py)          // wrapped row coord
            for x in 0..<px {
                let wx = Float(x < px / 2 ? x : x - px)      // wrapped col coord
                let qr = (wx * wx + wy * wy).squareRoot()

                // Logistic-edge disk (generate_synthetic_probe).
                let p = 1 / (1 + exp(4 * (qr - radius) / width))
                probe[y * px + x] = p
                probeSum += p

                // sine² sigmoid: 1 inside ri, 0 outside ro
                // (get_probe_kernel_edge_sigmoid, type "sine_squared").
                let t = min(max((qr - ri) / (ro - ri), 0), 1)
                let s = cos(.pi / 2 * t) * cos(.pi / 2 * t)
                trench[y * px + x] = s
                trenchSum += s
            }
        }
        guard probeSum > 0, trenchSum > 0 else { return nil }

        var kernel = [Float](repeating: 0, count: py * px)
        for i in 0..<kernel.count {
            kernel[i] = probe[i] / probeSum - trench[i] / trenchSum
        }

        // Precompute conj(FFT(kernel)).
        var re = kernel
        var im = [Float](repeating: 0, count: py * px)
        fft.transform(re: &re, im: &im, forward: true)
        for i in 0..<im.count { im[i] = -im[i] }

        return ProbeKernel(px: px, py: py, qx: qx, qy: qy,
                           probeRadius: radius, trenchRadii: (ri, ro),
                           source: .synthetic, mode: .sigmoidTrench, probePath: nil,
                           kernel: kernel, ftRe: re, ftIm: im)
    }

    /// Vacuum-probe kernel following py4DSTEM's measured-probe sigmoid route:
    /// mask outside the bright probe, bilinearly shift its supplied center to
    /// the correlation origin, normalize, then subtract the sine² trench.
    package nonisolated static func measured(
        pattern: DiffractionPattern,
        originX: Float,
        originY: Float,
        radius: Float,
        trenchRadii: (Float, Float)? = nil,
        mode: ProbeKernelMode = .sigmoidTrench,
        source: ProbeKernelSource = .measured,
        probePath: String? = nil
    ) -> ProbeKernel? {
        if mode == .flat {
            return flat(pattern: pattern, originX: originX, originY: originY,
                        radius: radius, source: source, probePath: probePath)
        }
        let qx = pattern.qx, qy = pattern.qy
        let px = qx, py = qy
        guard let fft = FFT2D(nx: px, ny: py), radius > 0,
              pattern.pixels.count == qx * qy else { return nil }
        let (ri, ro) = trenchRadii ?? (radius, 2 * radius)
        guard ro > ri else { return nil }

        // A cosine shoulder from r to 2r is the native lightweight analogue
        // of Probe.from_vacuum_data's threshold/dilation distance mask.
        var centered = [Float](repeating: 0, count: py * px)
        let rowFloor = Int(floor(-originY))
        let colFloor = Int(floor(-originX))
        let rowFraction = -originY - Float(rowFloor)
        let colFraction = -originX - Float(colFloor)
        var probeSum: Float = 0
        func wrapped(_ value: Int, _ count: Int) -> Int { (value % count + count) % count }
        for y in 0..<qy {
            for x in 0..<qx {
                let dx = Float(x) - originX, dy = Float(y) - originY
                let distance = (dx * dx + dy * dy).squareRoot()
                let shoulder = min(max((distance - radius) / max(radius, 1e-6), 0), 1)
                let mask = cos(.pi / 2 * shoulder) * cos(.pi / 2 * shoulder)
                let value = max(pattern.pixels[y * qx + x], 0) * mask
                guard value > 0 else { continue }
                probeSum += value
                let y0 = wrapped(y + rowFloor, py), y1 = wrapped(y + rowFloor + 1, py)
                let x0 = wrapped(x + colFloor, px), x1 = wrapped(x + colFloor + 1, px)
                centered[y0 * px + x0] += value * (1 - rowFraction) * (1 - colFraction)
                centered[y1 * px + x0] += value * rowFraction * (1 - colFraction)
                centered[y0 * px + x1] += value * (1 - rowFraction) * colFraction
                centered[y1 * px + x1] += value * rowFraction * colFraction
            }
        }
        guard probeSum > 0 else { return nil }

        var trench = [Float](repeating: 0, count: py * px)
        var trenchSum: Float = 0
        for y in 0..<py {
            let wy = Float(y < py / 2 ? y : y - py)
            for x in 0..<px {
                let wx = Float(x < px / 2 ? x : x - px)
                let distance = (wx * wx + wy * wy).squareRoot()
                let t = min(max((distance - ri) / (ro - ri), 0), 1)
                let value = cos(.pi / 2 * t) * cos(.pi / 2 * t)
                trench[y * px + x] = value
                trenchSum += value
            }
        }
        guard trenchSum > 0 else { return nil }
        var kernel = [Float](repeating: 0, count: py * px)
        for index in kernel.indices {
            kernel[index] = centered[index] / probeSum - trench[index] / trenchSum
        }
        var re = kernel
        var im = [Float](repeating: 0, count: kernel.count)
        fft.transform(re: &re, im: &im, forward: true)
        for index in im.indices { im[index] = -im[index] }
        return ProbeKernel(
            px: px, py: py, qx: qx, qy: qy,
            probeRadius: radius, trenchRadii: (ri, ro), source: source,
            mode: .sigmoidTrench, probePath: probePath,
            kernel: kernel, ftRe: re, ftIm: im
        )
    }

    /// py4DSTEM `Probe.get_probe_kernel_flat` (probe.py): the probe divided by
    /// its sum, then shifted so its centre lands on the array corner by the
    /// Fourier shift theorem (`get_shifted_ar`, preprocess/utils.py:
    /// `w = exp(-2πi (yshift·qy + xshift·qx))`, the real part of the inverse
    /// transform). Nothing is masked and nothing is subtracted: the kernel
    /// integrates to one, so the correlation responds to the probe's whole
    /// structure — rings included — instead of to a disk edge.
    ///
    /// DEVIATION: py4DSTEM feeds the array as stored; here a non-finite pixel
    /// counts as zero, because one NaN would otherwise poison the transform
    /// and every peak with it (the probe-size estimator made the same choice
    /// on 2026-09-05).
    package nonisolated static func flat(
        pattern: DiffractionPattern,
        originX: Float,
        originY: Float,
        radius: Float,
        source: ProbeKernelSource = .measured,
        probePath: String? = nil
    ) -> ProbeKernel? {
        let qx = pattern.qx, qy = pattern.qy
        let px = qx, py = qy
        guard let fft = FFT2D(nx: px, ny: py), radius > 0,
              pattern.pixels.count == qx * qy,
              originX.isFinite, originY.isFinite else { return nil }
        var re = [Float](repeating: 0, count: py * px)
        var total: Float = 0
        for index in re.indices where pattern.pixels[index].isFinite {
            re[index] = pattern.pixels[index]
            total += pattern.pixels[index]
        }
        guard total > 0 else { return nil }
        for index in re.indices { re[index] /= total }

        // Fourier shift by (−originX, −originY): F(k) · exp(−2πi (dy·ky/py + dx·kx/px))
        // with the frequency index in its wrapped (fftfreq) form.
        var im = [Float](repeating: 0, count: py * px)
        fft.transform(re: &re, im: &im, forward: true)
        let dx = -originX, dy = -originY
        for y in 0..<py {
            let ky = Float(y < (py + 1) / 2 ? y : y - py)
            for x in 0..<px {
                let kx = Float(x < (px + 1) / 2 ? x : x - px)
                let phase = -2 * Float.pi * (dy * ky / Float(py) + dx * kx / Float(px))
                let c = cos(phase), s = sin(phase)
                let index = y * px + x
                let r0 = re[index], i0 = im[index]
                re[index] = r0 * c - i0 * s
                im[index] = r0 * s + i0 * c
            }
        }
        fft.transform(re: &re, im: &im, forward: false)
        let kernel = re                                   // real part of the shifted probe

        var ftRe = kernel
        var ftIm = [Float](repeating: 0, count: kernel.count)
        fft.transform(re: &ftRe, im: &ftIm, forward: true)
        for index in ftIm.indices { ftIm[index] = -ftIm[index] }
        return ProbeKernel(
            px: px, py: py, qx: qx, qy: qy,
            probeRadius: radius, trenchRadii: (0, 0), source: source,
            mode: .flat, probePath: probePath,
            kernel: kernel, ftRe: ftRe, ftIm: ftIm
        )
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(px: Int, py: Int, qx: Int, qy: Int, probeRadius: Float, trenchRadii: (inner: Float, outer: Float), source: ProbeKernelSource, mode: ProbeKernelMode = .sigmoidTrench, probePath: String? = nil, kernel: [Float], ftRe: [Float], ftIm: [Float]) {
        self.px = px
        self.py = py
        self.qx = qx
        self.qy = qy
        self.probeRadius = probeRadius
        self.trenchRadii = trenchRadii
        self.source = source
        self.mode = mode
        self.probePath = probePath
        self.kernel = kernel
        self.ftRe = ftRe
        self.ftIm = ftIm
    }
}
