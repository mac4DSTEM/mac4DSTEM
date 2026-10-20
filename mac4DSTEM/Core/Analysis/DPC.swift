//
//  DPC.swift
//  Role: Differential Phase Contrast. The center-of-mass Metal kernel returns
//        a per-position CoM *shift* vector field (interleaved [cx,cy,...]);
//        this file turns that field into every DPC view the app offers:
//
//    • magnitude image   = |CoM|                       (scalar, any colormap)
//    • angle image       = atan2(cy, cx) → [0,2π) rad  (scalar)
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

import CuboCore
import CuboPhase
import enum DiffractoGeometry.ElectronWavelength   // the one electron wavelength of the suite (2026-10-15)
import Foundation

package enum DPC {

    /// Express the CoM field in the scan frame: optionally swap the detector
    /// components (transpose), then rotate by the calibrated R–Q angle.
    /// `com` is interleaved [cx0,cy0,...] of a `width` x `height` scan; returns the same layout.
    ///
    /// C2 (2026-10-15): the rotation is CuboKit's `RotationSolution.corrected` (x' = cos·a − sin·b,
    /// y' = sin·a + cos·b, in Double), asked for at a forced angle and transpose. The kit speaks py4DSTEM's
    /// convention — its first component is the detector-ROW one (this app's y) and its angle the negative of this
    /// app's (`RQRotationConvention`, transpose flag unchanged) — so the field goes in as (row: cy, column: cx) at −θ
    /// and comes back as (column → x', row → y'). A field the kit refuses (fewer than 3 x 3 positions, a non-finite
    /// value) is rotated by the plain formula, as before: showing such a field is the app's to do, not the kit's to
    /// refuse.
    package nonisolated static func applyRotation(com: [Float], width: Int, height: Int,
                                                  rotationRad: Float, transpose: Bool) -> [Float] {
        let count = com.count / 2
        if count == width * height,
           let field = try? ScanVectorField(
               scanRows: height, scanColumns: width,
               row: (0..<count).map { Double(com[2 * $0 + 1]) }, column: (0..<count).map { Double(com[2 * $0]) }),
           let solution = try? RotationSolver.solve(
               field, forceRotationDegrees: -Double(rotationRad) * 180 / .pi, forceTranspose: transpose) {
            var out = [Float](repeating: 0, count: com.count)
            for i in 0..<count {
                out[2 * i] = Float(solution.corrected.column[i])
                out[2 * i + 1] = Float(solution.corrected.row[i])
            }
            return out
        }
        let c = cos(rotationRad), s = sin(rotationRad)
        var out = [Float](repeating: 0, count: com.count)
        for i in 0..<count {
            let a = transpose ? com[2 * i + 1] : com[2 * i]
            let b = transpose ? com[2 * i]     : com[2 * i + 1]
            out[2 * i]     = c * a - s * b
            out[2 * i + 1] = s * a + c * b
        }
        return out
    }

    /// |CoM| per scan position. `com` is interleaved [cx0,cy0,cx1,cy1,...].
    package nonisolated static func magnitudeImage(com: [Float], width: Int, height: Int) -> FloatImage {
        let n = width * height
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let cx = com[2 * i]
            let cy = com[2 * i + 1]
            out[i] = (cx * cx + cy * cy).squareRoot()
        }
        return FloatImage(width: width, height: height, pixels: out)
    }

    /// Relativistic electron wavelength for accelerating voltage in kV: DiffractoKit's `ElectronWavelength` (CODATA 2018),
    /// 2.6e-5 to 2.8e-5 above the rounded-constant form (12.2639 / sqrt(V (1 + 0.97845e-6 V))) this replaced
    /// (registration `../_archive/mac4DSTEM/docs/registrations/diffractokit-wavelength-registration-2026-10-15.md`). nil unless the voltage is
    /// positive and finite (the kit returns NaN there).
    package nonisolated static func electronWavelengthAngstrom(voltageKV: Double) -> Double? {
        guard voltageKV.isFinite, voltageKV > 0 else { return nil }
        return ElectronWavelength.angstroms(volts: voltageKV * 1_000)
    }

    /// Small-angle scattering conversion: θ ≈ λ·q. Returns milliradians per
    /// detector pixel for q calibration in Å⁻¹/pixel.
    package nonisolated static func milliradiansPerDetectorPixel(
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
    package nonisolated static func physicalIDPCCalibration(
        realPixelSize: Double?,
        realPixelUnits: String?,
        reciprocalPixelSize: Double?,
        reciprocalPixelUnits: String?,
        voltageKV: Double?
    ) -> IDPCPhysicalCalibration? {
        guard let realPixelSize, realPixelSize.isFinite, realPixelSize > 0,
              let reciprocalPixelSize,
              reciprocalPixelSize.isFinite, reciprocalPixelSize > 0 else { return nil }

        guard let scanAngstrom = CalibrationUnitConversion.realAngstromPerPixel(
            value: realPixelSize, units: realPixelUnits
        ) else { return nil }
        let wavelength = voltageKV.flatMap {
            electronWavelengthAngstrom(voltageKV: $0)
        }
        guard let reciprocalAngstrom =
                CalibrationUnitConversion.reciprocalInvAngstromPerPixel(
                    value: reciprocalPixelSize, units: reciprocalPixelUnits,
                    wavelengthAngstrom: wavelength
                ) else { return nil }
        guard scanAngstrom.isFinite, reciprocalAngstrom.isFinite,
              scanAngstrom > 0, reciprocalAngstrom > 0 else { return nil }
        // CuboPhase's calibration (Double; its init refuses non-positive or non-finite sampling, already excluded above).
        return try? IDPCPhysicalCalibration(
            rowSamplingAngstrom: scanAngstrom,
            columnSamplingAngstrom: scanAngstrom,
            reciprocalAngstromPerDetectorPixel: reciprocalAngstrom
        )
    }

    package nonisolated static func physicalMagnitudeImage(
        com: [Float], width: Int, height: Int, milliradiansPerPixel: Float
    ) -> FloatImage {
        var pixels = magnitudeImage(com: com, width: width, height: height).pixels
        for index in pixels.indices { pixels[index] *= milliradiansPerPixel }
        return FloatImage(width: width, height: height, pixels: pixels)
    }

    /// Direction of the CoM shift in radians, wrapped to [0, 2π).
    package nonisolated static func angleImage(com: [Float], width: Int, height: Int) -> FloatImage {
        let n = width * height
        var out = [Float](repeating: 0, count: n)
        let twoPi = Float(2.0 * Double.pi)
        for i in 0..<n {
            let cx = com[2 * i]
            let cy = com[2 * i + 1]
            var a = atan2(cy, cx)            // [-π, π]
            if a < 0 { a += twoPi }          // [0, 2π)
            if a == 0 { a = 0 }              // Canonical +0 for atan2(-0, +x).
            out[i] = a                        // [0, 2π) radians
        }
        return FloatImage(width: width, height: height, pixels: out)
    }

    // MARK: - Color wheel (vector display)

    /// Full HSV color wheel: hue = CoM direction, value = CoM magnitude
    /// (saturation fixed at 1). Magnitude is normalized to its 99th percentile
    /// so a few hot pixels don't dim the whole map. Returns packed RGBA8.
    package nonisolated static func colorWheelRGBA(com: [Float], width: Int, height: Int) -> RGBAImage {
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
    package nonisolated static func hsvToRGB(h: Float, s: Float, v: Float) -> (Float, Float, Float) {
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

    /// Why an iDPC integration could not run. Typed, because the previous
    /// contract returned a zero-filled image for every failure — and a flat
    /// map that LOOKS like a computed projected phase is a fabricated result,
    /// exactly what the refusal rule bans. A caller that cannot integrate
    /// must say so, not draw zeros. // v2 S7
    /// Since 2026-10-20 the integration is CuboPhase's (`IDPC`); every refusal, the kit's included, arrives as this error.
    package enum IDPCError: Error, Equatable, CustomStringConvertible, LocalizedError {
        /// An input precondition failed; the reason names which.
        case invalidInput(String)

        package var description: String {
            switch self {
            case .invalidInput(let reason):
                return "iDPC integration refused its input: \(reason)"
            }
        }

        package var errorDescription: String? { description }
    }

    /// Integrate the interleaved CoM field `[cx0, cy0, ...]` (scan frame, detector-pixel shifts) into a scalar
    /// potential-like map: the least-squares solution of ∇φ = CoM, by CuboPhase's `IDPC.integrate` (Fourier solve in
    /// Double; ε·|q|²max regularization, field mean-subtracted, phase gauged to zero mean). The app's x component is the
    /// kit's `column` and its y the kit's `row`. Both boundary choices are explicit (`IDPCBoundary`): `.periodic` solves on
    /// the native grid, `.zeroPadded(factor:)` centres the field in an exact factor-larger grid.
    ///
    /// For qualitative use, leave sampling and `comToGradientScale` at one.
    /// For quantitative projected phase, use scan sampling in Å and convert
    /// detector-pixel shifts to rad/Å with 2π·Q_pixel_size.
    package nonisolated static func integrateIDPC(com: [Float], width: Int, height: Int,
                              regularization: Double = 1e-4,
                              rowSampling: Double = 1,
                              columnSampling: Double = 1,
                              comToGradientScale: Double = 1,
                              boundary: IDPCBoundary = .zeroPadded(factor: 2)) throws -> FloatImage {
        // Each precondition throws by name — a refusal the caller can act on,
        // never a zero image that reads as a computed result. // v2 S7
        guard width > 1, height > 1 else {
            throw IDPCError.invalidInput(
                "the scan grid is \(width)×\(height); both axes must exceed 1 px."
            )
        }
        let n = width * height
        guard com.count == n * 2 else {
            throw IDPCError.invalidInput(
                "the CoM field carries \(com.count) values for a "
                    + "\(width)×\(height) scan; \(n * 2) are required."
            )
        }
        do {
            let field = try ScanVectorField(
                scanRows: height, scanColumns: width,
                row: (0..<n).map { Double(com[2 * $0 + 1]) }, column: (0..<n).map { Double(com[2 * $0]) })
            let phase = try IDPC.integrate(
                field, rowSampling: rowSampling, columnSampling: columnSampling,
                gradientScale: comToGradientScale, regularization: regularization, boundary: boundary)
            return FloatImage(width: width, height: height, pixels: phase.map { Float($0) })
        } catch {
            throw IDPCError.invalidInput(error.localizedDescription)
        }
    }

    package nonisolated static func integratePhysicalIDPC(
        com: [Float], width: Int, height: Int,
        calibration: IDPCPhysicalCalibration,
        regularization: Double = 1e-4,
        boundary: IDPCBoundary = .zeroPadded(factor: 2)
    ) throws -> FloatImage {
        try integrateIDPC(
            com: com, width: width, height: height,
            regularization: regularization,
            rowSampling: calibration.rowSamplingAngstrom,
            columnSampling: calibration.columnSamplingAngstrom,
            comToGradientScale: 2 * .pi
                * calibration.reciprocalAngstromPerDetectorPixel,
            boundary: boundary
        )
    }

}
