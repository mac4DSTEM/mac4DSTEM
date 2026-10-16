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
//  kernel is corner-centered, exactly the layout circular correlation needs;
//  the arithmetic (probe, shift, trench) is CuboKit's CuboVirtual, in Double,
//  and this file keeps the Float container, the provenance and the FFT.
//  Patterns and correlation peaks land at the disk's original detector
//  coordinates.
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

import CuboVirtual
import Foundation
import ImagoCore

package nonisolated enum ProbeKernelSource: String, Sendable {
    case synthetic = "Synthetic"
    case measured = "Measured ROI"
    case fileProbe = "File probe"
    case vacuumScan = "Vacuum scan"

    package var provenanceID: String {
        switch self {
        case .synthetic: "synthetic"
        case .measured: "measured_roi"
        case .fileProbe: "measured_file_probe"
        case .vacuumScan: "measured_vacuum_scan"
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
    //
    // The kernel arithmetic is CuboKit's (`CuboVirtual.ProbeKernel`, `SyntheticProbe`; CuboKit 0.2.0, Double, step for step
    // py4DSTEM's probe.py). This type stays the app's container: the provenance, the Float kernel the detector reads and
    // its conjugated FFT on the native grid. Module-qualified because the kit's `ProbeKernel` enum has this struct's name.

    /// Synthetic probe kernel from the calibrated probe radius.
    /// - Parameters:
    ///   - radius: central-disk radius in detector px (Calibration.probeRadius).
    ///   - width: edge blur of the synthetic probe (px); py4DSTEM examples
    ///     typically use ~1–2 px for sharp disks.
    ///   - trenchRadii: sigmoid trench inner/outer radii; nil → (r, 2r),
    ///     the standard choice.
    ///
    /// The probe is py4DSTEM's generate_synthetic_probe, the shift to the corner, the normalisation and the sine² trench
    /// are the kit's.
    ///
    /// DEVIATION (kept in the app, "delete at CuboKit with a centre parameter"): the kit's `SyntheticProbe.make` centres
    /// the disk on (rows/2, columns/2), a half pixel for an odd detector side, and the shift then blurs it bilinearly.
    /// The app's kernel has always centred the disk on the pixel (rows/2, columns/2) with integer division, so the
    /// shift is exact. For an even side the two probes are the same numbers; for an odd side (125 × 125 on
    /// sim_Au_data_all_binned) the kit's probe would change the detected-candidate counts, so the logistic disk is
    /// built here on the pixel centre.
    package nonisolated static func synthetic(radius: Float, width: Float = 2,
                          qy: Int, qx: Int,
                          trenchRadii: (Float, Float)? = nil) -> ProbeKernel? {
        let px = qx
        let py = qy
        guard let fft = FFT2D(nx: px, ny: py), radius > 0 else { return nil }
        let (ri, ro) = trenchRadii ?? (radius, 2 * radius)
        let centreRow = py / 2, centreColumn = px / 2
        var disk = [Double](repeating: 0, count: py * px)
        for y in 0..<py {
            for x in 0..<px {
                let r = Double(y - centreRow), c = Double(x - centreColumn)
                disk[y * px + x] = 1 / (1 + exp(4 * ((r * r + c * c).squareRoot() - Double(radius)) / Double(width)))
            }
        }
        guard let built = try? CuboVirtual.ProbeKernel.sigmoid(
                DetectorImage(detectorRows: py, detectorColumns: px, values: disk, path: .cpu),
                innerRadius: Double(ri), outerRadius: Double(ro),
                origin: (row: Double(centreRow), column: Double(centreColumn)), bilinear: true)
        else { return nil }
        return finish(built, px: px, py: py, probeRadius: radius, trenchRadii: (ri, ro),
                      source: .synthetic, mode: .sigmoidTrench, probePath: nil, fft: fft)
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

        // DEVIATION from py4DSTEM `Probe.from_vacuum_data` (braggvectors/probe.py):
        // masking here is a cosine shoulder from r to 2r centered on the
        // supplied origin, not from_vacuum_data's intensity threshold +
        // binary expansion + binary opening mask. A cosine shoulder from r to
        // 2r is the native lightweight analogue of that mask. The bilinear
        // shift, the normalisation and the trench are the kit's.
        var masked = [Double](repeating: 0, count: py * px)
        var probeSum: Double = 0
        for y in 0..<qy {
            for x in 0..<qx {
                let dx = Float(x) - originX, dy = Float(y) - originY
                let distance = (dx * dx + dy * dy).squareRoot()
                let shoulder = min(max((distance - radius) / max(radius, 1e-6), 0), 1)
                let mask = cos(.pi / 2 * shoulder) * cos(.pi / 2 * shoulder)
                let value = max(pattern.pixels[y * qx + x], 0) * mask
                guard value > 0 else { continue }
                masked[y * qx + x] = Double(value)
                probeSum += Double(value)
            }
        }
        guard probeSum > 0,
              let built = try? CuboVirtual.ProbeKernel.sigmoid(
                DetectorImage(detectorRows: py, detectorColumns: px, values: masked, path: .cpu),
                innerRadius: Double(ri), outerRadius: Double(ro),
                origin: (row: Double(originY), column: Double(originX)), bilinear: true)
        else { return nil }
        return finish(built, px: px, py: py, probeRadius: radius, trenchRadii: (ri, ro),
                      source: source, mode: .sigmoidTrench, probePath: probePath, fft: fft)
    }

    /// py4DSTEM `Probe.get_probe_kernel_flat` (probe.py): the probe divided by
    /// its sum, then shifted so its centre lands on the array corner by the
    /// Fourier shift theorem. The kit's `ProbeKernel.flat`. Nothing is masked and
    /// nothing is subtracted: the kernel integrates to one, so the correlation
    /// responds to the probe's whole structure — rings included — instead of to
    /// a disk edge.
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
        let values = pattern.pixels.map { $0.isFinite ? Double($0) : 0 }
        guard values.reduce(0, +) > 0,
              let built = try? CuboVirtual.ProbeKernel.flat(
                DetectorImage(detectorRows: py, detectorColumns: px, values: values, path: .cpu),
                origin: (row: Double(originY), column: Double(originX)), bilinear: false)
        else { return nil }
        return finish(built, px: px, py: py, probeRadius: radius, trenchRadii: (0, 0),
                      source: source, mode: .flat, probePath: probePath, fft: fft)
    }

    /// The kit's Double kernel as the app's Float container, with conj(FFT2(kernel)) precomputed on the native grid.
    private nonisolated static func finish(
        _ built: DetectorImage, px: Int, py: Int, probeRadius: Float, trenchRadii: (Float, Float),
        source: ProbeKernelSource, mode: ProbeKernelMode, probePath: String?, fft: FFT2D
    ) -> ProbeKernel {
        let kernel = built.values.map { Float($0) }
        var re = kernel
        var im = [Float](repeating: 0, count: kernel.count)
        fft.transform(re: &re, im: &im, forward: true)
        for index in im.indices { im[index] = -im[index] }
        return ProbeKernel(px: px, py: py, qx: px, qy: py,
                           probeRadius: probeRadius, trenchRadii: trenchRadii,
                           source: source, mode: mode, probePath: probePath,
                           kernel: kernel, ftRe: re, ftIm: im)
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
