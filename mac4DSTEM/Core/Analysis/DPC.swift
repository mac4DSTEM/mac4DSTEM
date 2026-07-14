//
//  DPC.swift
//  Role: Differential Phase Contrast. The center-of-mass Metal kernel returns
//        a per-position CoM *shift* vector field (interleaved [cx,cy,...]);
//        this file turns that field into every DPC view the app offers:
//
//    • magnitude image   = |CoM|                       (scalar, any colormap)
//    • angle image       = atan2(cy, cx) → [0,1]       (scalar)
//    • color wheel       = HSV (hue = angle, value = magnitude) → RGBA
//    • iDPC              = Fourier integration of the vector field (scalar)
//
//  iDPC NOTE: the integration assumes the CoM field is expressed in the scan
//  frame. AppState applies the calibrated R–Q rotation/transpose
//  (RotationCalibration → applyRotation below) before any DPC view; without
//  that calibration, a rotation offset shows up as swirl artifacts in iDPC.
//  A 180° ambiguity remains inherent to the method — inverted iDPC contrast
//  means the true rotation is θ + 180°.
//

import Foundation
import Accelerate

nonisolated enum IDPCBoundaryCondition: String, Sendable {
    /// Treat opposite scan edges as adjacent. Best for explicitly periodic
    /// synthetic fields; real specimens can show wrap-around seams.
    case periodic
    /// Center the measured field in a larger zero-valued domain before the
    /// Fourier solve, reducing opposite-edge coupling at additional cost.
    case zeroPadded
}

/// Physical inputs needed to turn detector-pixel CoM shifts into a projected
/// phase gradient. Scan sampling is in Å/pixel and reciprocal sampling is in
/// Å⁻¹/detector-pixel, matching py4DSTEM's calibrated CoM convention.
nonisolated struct IDPCPhysicalCalibration: Equatable, Sendable {
    let rowSamplingAngstrom: Float
    let columnSamplingAngstrom: Float
    let reciprocalAngstromPerDetectorPixel: Float
}

enum DPC {

    /// Express the CoM field in the scan frame: optionally swap the detector
    /// components (transpose), then rotate by the calibrated R–Q angle.
    /// `com` is interleaved [cx0,cy0,...]; returns the same layout.
    nonisolated static func applyRotation(com: [Float], rotationRad: Float, transpose: Bool) -> [Float] {
        let c = cos(rotationRad), s = sin(rotationRad)
        var out = [Float](repeating: 0, count: com.count)
        for i in 0..<(com.count / 2) {
            let a = transpose ? com[2 * i + 1] : com[2 * i]
            let b = transpose ? com[2 * i]     : com[2 * i + 1]
            out[2 * i]     = c * a - s * b
            out[2 * i + 1] = s * a + c * b
        }
        return out
    }

    /// |CoM| per scan position. `com` is interleaved [cx0,cy0,cx1,cy1,...].
    nonisolated static func magnitudeImage(com: [Float], width: Int, height: Int) -> FloatImage {
        let n = width * height
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let cx = com[2 * i]
            let cy = com[2 * i + 1]
            out[i] = (cx * cx + cy * cy).squareRoot()
        }
        return FloatImage(width: width, height: height, pixels: out)
    }

    /// Relativistic electron wavelength for accelerating voltage in kV.
    /// λ[Å] = 12.2639 / sqrt(V[eV] · (1 + 0.97845e-6 V[eV])).
    nonisolated static func electronWavelengthAngstrom(voltageKV: Double) -> Double? {
        guard voltageKV.isFinite, voltageKV > 0 else { return nil }
        let volts = voltageKV * 1_000
        return 12.2639 / sqrt(volts * (1 + 0.97845e-6 * volts))
    }

    /// Small-angle scattering conversion: θ ≈ λ·q. Returns milliradians per
    /// detector pixel for q calibration in Å⁻¹/pixel.
    nonisolated static func milliradiansPerDetectorPixel(
        voltageKV: Double,
        invAngstromPerPixel: Double
    ) -> Float? {
        guard invAngstromPerPixel.isFinite, invAngstromPerPixel > 0,
              let wavelength = electronWavelengthAngstrom(voltageKV: voltageKV)
        else { return nil }
        return Float(1_000 * wavelength * invAngstromPerPixel)
    }

    /// Normalize the calibration spellings accepted elsewhere in the app into
    /// the two physical quantities required by quantitative iDPC.
    nonisolated static func physicalIDPCCalibration(
        realPixelSize: Double?,
        realPixelUnits: String?,
        reciprocalPixelSize: Double?,
        reciprocalPixelUnits: String?,
        voltageKV: Double?
    ) -> IDPCPhysicalCalibration? {
        guard let realPixelSize, realPixelSize.isFinite, realPixelSize > 0,
              let reciprocalPixelSize,
              reciprocalPixelSize.isFinite, reciprocalPixelSize > 0 else { return nil }

        let realUnits = normalizedUnit(realPixelUnits)
        let scanAngstrom: Double
        switch realUnits {
        case "a", "å", "angstrom", "ang": scanAngstrom = realPixelSize
        case "nm", "nanometer", "nanometre": scanAngstrom = realPixelSize * 10
        case "pm", "picometer", "picometre": scanAngstrom = realPixelSize * 0.01
        default: return nil
        }

        let reciprocalUnits = normalizedUnit(reciprocalPixelUnits)
        let reciprocalAngstrom: Double
        switch reciprocalUnits {
        case "1/a", "1/å", "a^-1", "å^-1", "angstrom^-1", "1/angstrom":
            reciprocalAngstrom = reciprocalPixelSize
        case "1/nm", "nm^-1", "1/nanometer", "nanometer^-1":
            reciprocalAngstrom = reciprocalPixelSize * 0.1
        case "mrad":
            guard let voltageKV,
                  let wavelength = electronWavelengthAngstrom(voltageKV: voltageKV)
            else { return nil }
            reciprocalAngstrom = reciprocalPixelSize / (1_000 * wavelength)
        default: return nil
        }
        guard scanAngstrom.isFinite, reciprocalAngstrom.isFinite,
              scanAngstrom > 0, reciprocalAngstrom > 0 else { return nil }
        return IDPCPhysicalCalibration(
            rowSamplingAngstrom: Float(scanAngstrom),
            columnSamplingAngstrom: Float(scanAngstrom),
            reciprocalAngstromPerDetectorPixel: Float(reciprocalAngstrom)
        )
    }

    private nonisolated static func normalizedUnit(_ unit: String?) -> String {
        (unit ?? "")
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "ångström", with: "angstrom")
    }

    nonisolated static func physicalMagnitudeImage(
        com: [Float], width: Int, height: Int, milliradiansPerPixel: Float
    ) -> FloatImage {
        var pixels = magnitudeImage(com: com, width: width, height: height).pixels
        for index in pixels.indices { pixels[index] *= milliradiansPerPixel }
        return FloatImage(width: width, height: height, pixels: pixels)
    }

    /// Direction of the CoM shift, in radians mapped to [0, 1] for display.
    nonisolated static func angleImage(com: [Float], width: Int, height: Int) -> FloatImage {
        let n = width * height
        var out = [Float](repeating: 0, count: n)
        let twoPi = Float(2.0 * Double.pi)
        for i in 0..<n {
            let cx = com[2 * i]
            let cy = com[2 * i + 1]
            var a = atan2(cy, cx)            // [-π, π]
            if a < 0 { a += twoPi }          // [0, 2π)
            out[i] = a / twoPi               // [0, 1)
        }
        return FloatImage(width: width, height: height, pixels: out)
    }

    // MARK: - Color wheel (vector display)

    /// Full HSV color wheel: hue = CoM direction, value = CoM magnitude
    /// (saturation fixed at 1). Magnitude is normalized to its 99th percentile
    /// so a few hot pixels don't dim the whole map. Returns packed RGBA8.
    nonisolated static func colorWheelRGBA(com: [Float], width: Int, height: Int) -> RGBAImage {
        let n = width * height
        var rgba = [UInt8](repeating: 255, count: n * 4)

        // Robust magnitude scale.
        var mags = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let cx = com[2 * i], cy = com[2 * i + 1]
            mags[i] = (cx * cx + cy * cy).squareRoot()
        }
        let sorted = mags.sorted()
        let p99 = sorted[min(n - 1, Int(Double(n - 1) * 0.99))]
        let scale = p99 > 0 ? 1 / p99 : 0

        for i in 0..<n {
            let cx = com[2 * i], cy = com[2 * i + 1]
            let hue = atan2(cy, cx) / (2 * .pi) + 0.5      // [0, 1)
            let value = min(mags[i] * scale, 1)
            let (r, g, b) = hsvToRGB(h: hue, s: 1, v: value)
            rgba[4 * i]     = UInt8(r * 255)
            rgba[4 * i + 1] = UInt8(g * 255)
            rgba[4 * i + 2] = UInt8(b * 255)
        }
        return RGBAImage(width: width, height: height, rgba: rgba)
    }

    /// Standard HSV→RGB, all components in [0, 1].
    nonisolated static func hsvToRGB(h: Float, s: Float, v: Float) -> (Float, Float, Float) {
        let h6 = (h - h.rounded(.down)) * 6            // wrap hue into [0,6)
        let i = Int(h6) % 6
        let f = h6 - Float(Int(h6))
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    // MARK: - iDPC (Fourier integration)

    /// Integrate the CoM vector field into a scalar potential-like map:
    ///     φ̂(q) = (qx·ĈoMx + qy·ĈoMy) / (i·2π·(|q|² + ε·|q|²max))
    /// i.e. the least-squares solution of ∇φ = CoM. The regularization ε damps
    /// the 1/|q|² amplification of low-frequency noise (ε = 0 → pure inverse).
    ///
    /// The field is mean-subtracted (removes residual descan → the undefined
    /// q=0 term). `periodic` solves on the exact native scan grid;
    /// `zeroPadded` centers it in an exact `paddingFactor`-larger grid. Both
    /// choices are explicit because they encode different edge assumptions.
    ///
    /// For qualitative use, leave sampling and `comToGradientScale` at one.
    /// For quantitative projected phase, use scan sampling in Å and convert
    /// detector-pixel shifts to rad/Å with 2π·Q_pixel_size.
    nonisolated static func integrateIDPC(com: [Float], width: Int, height: Int,
                              regularization: Float = 1e-4,
                              rowSampling: Float = 1,
                              columnSampling: Float = 1,
                              comToGradientScale: Float = 1,
                              boundary: IDPCBoundaryCondition = .zeroPadded,
                              paddingFactor: Int = 2) -> FloatImage {
        let n = width * height
        guard n > 0, width > 1, height > 1,
              com.count == n * 2,
              regularization.isFinite, regularization >= 0,
              rowSampling.isFinite, rowSampling > 0,
              columnSampling.isFinite, columnSampling > 0,
              comToGradientScale.isFinite,
              paddingFactor > 0 else {
            return FloatImage(width: width, height: height,
                              pixels: [Float](repeating: 0, count: n))
        }

        // Split + mean-subtract the field.
        var cx = [Float](repeating: 0, count: n)
        var cy = [Float](repeating: 0, count: n)
        for i in 0..<n {
            cx[i] = com[2 * i] * comToGradientScale
            cy[i] = com[2 * i + 1] * comToGradientScale
        }
        var mean: Float = 0
        vDSP_meanv(cx, 1, &mean, vDSP_Length(n)); vDSP_vsadd(cx, 1, [-mean], &cx, 1, vDSP_Length(n))
        vDSP_meanv(cy, 1, &mean, vDSP_Length(n)); vDSP_vsadd(cy, 1, [-mean], &cy, 1, vDSP_Length(n))

        let factor = boundary == .periodic ? 1 : max(1, paddingFactor)
        guard width <= Int.max / factor, height <= Int.max / factor else {
            return FloatImage(width: width, height: height,
                              pixels: [Float](repeating: 0, count: n))
        }
        let nx = width * factor
        let ny = height * factor
        guard let fft = FFT2D(nx: nx, ny: ny) else {
            // Never disguise an integration failure as a scientifically
            // different magnitude image.
            return FloatImage(width: width, height: height,
                              pixels: [Float](repeating: 0, count: n))
        }

        let xOffset = (nx - width) / 2
        let yOffset = (ny - height) / 2

        func pad(_ src: [Float]) -> [Float] {
            var out = [Float](repeating: 0, count: nx * ny)
            for y in 0..<height {
                let destination = (y + yOffset) * nx + xOffset
                out.replaceSubrange(destination ..< destination + width,
                                    with: src[y * width ..< (y + 1) * width])
            }
            return out
        }

        var xRe = pad(cx), xIm = [Float](repeating: 0, count: nx * ny)
        var yRe = pad(cy), yIm = [Float](repeating: 0, count: nx * ny)
        fft.transform(re: &xRe, im: &xIm, forward: true)
        fft.transform(re: &yRe, im: &yIm, forward: true)

        // φ̂ = (qx·X̂ + qy·Ŷ) / (i·2π·(q² + ε·q²max));  1/i → (re,im) = (im,-re)
        var pRe = [Float](repeating: 0, count: nx * ny)
        var pIm = [Float](repeating: 0, count: nx * ny)
        let qxMax: Float = 0.5 / columnSampling
        let qyMax: Float = 0.5 / rowSampling
        let q2max = qxMax * qxMax + qyMax * qyMax
        let eps = regularization * q2max
        for ky in 0..<ny {
            let qy = FFT2D.fftfreq(ky, ny) / rowSampling
            for kx in 0..<nx {
                let qx = FFT2D.fftfreq(kx, nx) / columnSampling
                let q2 = qx * qx + qy * qy
                if q2 == 0 { continue }
                let idx = ky * nx + kx
                let numRe = qx * xRe[idx] + qy * yRe[idx]
                let numIm = qx * xIm[idx] + qy * yIm[idx]
                let d = 1 / (2 * Float.pi * (q2 + eps))
                pRe[idx] =  numIm * d
                pIm[idx] = -numRe * d
            }
        }

        fft.transform(re: &pRe, im: &pIm, forward: false)

        // Crop back to the scan size.
        var out = [Float](repeating: 0, count: n)
        for y in 0..<height {
            let source = (y + yOffset) * nx + xOffset
            out.replaceSubrange(y * width ..< (y + 1) * width,
                                with: pRe[source ..< source + width])
        }
        // Phase has an arbitrary additive constant. Make that gauge explicit
        // and deterministic for display, persistence, and numeric comparison.
        vDSP_meanv(out, 1, &mean, vDSP_Length(n))
        vDSP_vsadd(out, 1, [-mean], &out, 1, vDSP_Length(n))
        return FloatImage(width: width, height: height, pixels: out)
    }

    nonisolated static func integratePhysicalIDPC(
        com: [Float], width: Int, height: Int,
        calibration: IDPCPhysicalCalibration,
        regularization: Float = 1e-4,
        boundary: IDPCBoundaryCondition = .zeroPadded,
        paddingFactor: Int = 2
    ) -> FloatImage {
        integrateIDPC(
            com: com, width: width, height: height,
            regularization: regularization,
            rowSampling: calibration.rowSamplingAngstrom,
            columnSampling: calibration.columnSamplingAngstrom,
            comToGradientScale: 2 * .pi
                * calibration.reciprocalAngstromPerDetectorPixel,
            boundary: boundary, paddingFactor: paddingFactor
        )
    }

}
