//
//  ProbeKernel.swift
//  Role: Build the cross-correlation kernel for Bragg disk detection
//        (py4DSTEM: Probe.generate_synthetic_probe + get_probe_kernel_edge_
//        sigmoid). The kernel is the probe normalized to unit sum, minus a
//        sine²-sigmoid "trench" normalized to unit sum — so it integrates to
//        zero and responds to disk-shaped features, not to background.
//
//  PADDED-GRID CONVENTION: vDSP's FFT needs power-of-two sizes, so detection
//  runs on a padded grid (Py × Px ≥ Qy × Qx, see DiskDetector). The kernel is
//  built directly on that padded grid using *wrapped* coordinates — i.e. it
//  is corner-centered from birth, exactly the layout circular correlation
//  needs — which sidesteps py4DSTEM's Fourier-shift step entirely. Patterns
//  are zero-padded at the origin corner, so correlation peaks land at the
//  disk's original detector coordinates.
//
//  Currently the probe is SYNTHETIC: a logistic-edge disk from the calibrated
//  probe radius. That matches py4DSTEM's generate_synthetic_probe and works
//  well for data with sharp disks. // FUTURE: measured vacuum probe from a
//  scan ROI (Probe.from_vacuum_data) once ROI selection exists in the UI.
//

import Foundation

/// A ready-to-use detection kernel: real-space form (for inspection) plus its
/// precomputed conjugated Fourier transform on the padded grid.
struct ProbeKernel {
    /// Padded (power-of-two) grid dimensions the kernel lives on.
    let px: Int
    let py: Int
    /// Detector dimensions the kernel was built for.
    let qx: Int
    let qy: Int
    /// The probe radius (px) and sigmoid trench radii used to build it.
    let probeRadius: Float
    let trenchRadii: (inner: Float, outer: Float)

    /// Corner-centered, zero-sum kernel on the padded grid [py * px].
    let kernel: [Float]
    /// conj(FFT2(kernel)) — the term every pattern's FFT is multiplied with.
    let ftRe: [Float]
    let ftIm: [Float]

    // MARK: Construction

    /// Synthetic probe kernel from the calibrated probe radius.
    /// - Parameters:
    ///   - radius: central-disk radius in detector px (Calibration.probeRadius).
    ///   - width: edge blur of the synthetic probe (px); py4DSTEM examples
    ///     typically use ~1–2 px for sharp disks.
    ///   - trenchRadii: sigmoid trench inner/outer radii; nil → (r, 2r),
    ///     the standard choice.
    nonisolated static func synthetic(radius: Float, width: Float = 2,
                          qy: Int, qx: Int,
                          trenchRadii: (Float, Float)? = nil) -> ProbeKernel? {
        let px = FFT2D.nextPow2(qx)
        let py = FFT2D.nextPow2(qy)
        guard let fft = FFT2D(nx: px, ny: py), radius > 0 else { return nil }

        let (ri, ro) = trenchRadii ?? (radius, 2 * radius)

        // Both the probe and the trench are radial functions of the wrapped
        // (corner-centered) radius on the padded grid.
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
                           kernel: kernel, ftRe: re, ftIm: im)
    }
}
