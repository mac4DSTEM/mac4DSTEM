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
//  Supports a synthetic logistic disk and a measured vacuum pattern selected
//  with the app's real-space ROI. Both use the same normalized sine² trench.
//

import Foundation

package nonisolated enum ProbeKernelSource: String, Sendable {
    case synthetic = "Synthetic"
    case measured = "Measured ROI"

    package var provenanceID: String {
        switch self {
        case .synthetic: "synthetic"
        case .measured: "measured_roi"
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
    package let trenchRadii: (inner: Float, outer: Float)
    package let source: ProbeKernelSource

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
                           source: .synthetic,
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
        trenchRadii: (Float, Float)? = nil
    ) -> ProbeKernel? {
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
            probeRadius: radius, trenchRadii: (ri, ro), source: .measured,
            kernel: kernel, ftRe: re, ftIm: im
        )
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(px: Int, py: Int, qx: Int, qy: Int, probeRadius: Float, trenchRadii: (inner: Float, outer: Float), source: ProbeKernelSource, kernel: [Float], ftRe: [Float], ftIm: [Float]) {
        self.px = px
        self.py = py
        self.qx = qx
        self.qy = qy
        self.probeRadius = probeRadius
        self.trenchRadii = trenchRadii
        self.source = source
        self.kernel = kernel
        self.ftRe = ftRe
        self.ftIm = ftIm
    }
}
