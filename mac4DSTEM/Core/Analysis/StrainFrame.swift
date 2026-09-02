//
//  StrainFrame.swift
//  Role: Express a computed strain tensor field in the scan frame using the
//        calibrated R–Q rotation (py4DSTEM: process/strain get_rotated_strain_map
//        and the calibrated Bragg-vector transform).
//
//  The strain map is COMPUTED in detector x/y (`StrainMapping.compute`) and is
//  stored that way; this file is presentation. Display and export derive the
//  scan-frame view from the CURRENT calibration every time — the
//  `DPC.applyRotation` pattern — so re-running rotation calibration updates
//  what is shown instead of silently desyncing from a baked-in angle. When no
//  measured rotation exists there is nothing to rotate BY: the components stay
//  detector-frame and every carrier (screen, caption, provenance) says so.
//  py4DSTEM makes the same split: calibrated Bragg vectors are rotated into
//  the scan-aligned frame before the strain fit when `QR_rotation` exists
//  (braggvectors.py:528–545, auto-enabled), and without it `StrainMap.__init__`
//  warns "Real to reciprocal space rotation not calibrated" and stays in
//  detector x/y.
//
//  Math: py4DSTEM transforms calibrated vectors v_scan = R(θ)·F·v_det, where
//  F swaps the components when `QR_flip` is set. Refitting the lattice from
//  transformed vectors transforms the strain tensor by the same similarity,
//  E_scan = (R·F)·E_det·(R·F)ᵀ — `tools/strain-frame-test` pins that
//  equivalence against a refit — so the symmetric components rotate as
//      ε'xx = c²·εxx − 2sc·εxy + s²·εyy
//      ε'yy = s²·εxx + 2sc·εxy + c²·εyy
//      ε'xy = sc·(εxx − εyy) + (c²−s²)·εxy
//  with the transpose applied first (swap εxx ↔ εyy; εxy unchanged). The
//  lattice-rotation θ is a pseudo-scalar: invariant under the proper rotation,
//  NEGATED by the improper transpose (py4DSTEM's `flip_theta`).
//
//  DEVIATION (measured 2026-08-25, tools/strain-frame-test NC5): rotating the
//  fitted tensor matches py4DSTEM's `get_rotated_strain_map` path exactly,
//  but py4DSTEM's CALIBRATED pipeline refits from rotated vectors, and its
//  reference lattice (`get_reference_g1g2`) is a component-wise MEDIAN —
//  which is rotation-equivariant only when one lattice holds a strict
//  majority of scan positions. On a majority-free mixture the two paths
//  differ (~0.3 px of reference; up to ~2×10⁻² of strain at 37.2° on the
//  fixture — εxy the largest at 0.0201, εxx 0.0159, measured by the Gate B
//  reviewer 2026-08-25);
//  with a majority reference — or a user-selected unstrained reference
//  region — they agree to float precision. This presentation keeps the
//  measurement IDENTITY (one reference, defined in the frame the fit ran in,
//  re-expressed), so the numbers never change under a later rotation
//  calibration; the whole-scan-median-over-mixed-lattices case is already the
//  one the strain failure message warns against referencing.
//

import Foundation

/// Which frame strain components are presented in. Carried everywhere the
/// numbers go — screen, burned caption, export provenance — never implied.
package nonisolated enum StrainPresentationFrame: Equatable, Sendable {
    /// Rotated into the scan frame by the calibrated R–Q rotation.
    case scan(rotationRad: Float, transposed: Bool)
    /// Detector x/y exactly as computed — no measured rotation exists to
    /// apply, so claiming any other frame would be fabrication.
    case detector

    /// Resolve the frame the current calibration supports. A non-finite
    /// stored rotation is treated as absent, matching `Calibration`'s own
    /// validity test (`rotationRad?.isFinite == true`).
    package static func resolve(rotationRad: Float?, transposeQR: Bool?) -> StrainPresentationFrame {
        guard let rotation = rotationRad, rotation.isFinite else { return .detector }
        return .scan(rotationRad: rotation, transposed: transposeQR ?? false)
    }

    /// Machine token for provenance ("strain_frame" key).
    package var provenanceValue: String {
        switch self {
        case .scan: "scan"
        case .detector: "detector"
        }
    }

    /// The one human-facing wording, shared by the controls row and anything
    /// else that names the frame — two sites deriving the label differently is
    /// the S7 two-gates shape.
    package var displayLabel: String {
        switch self {
        case .scan(let rotationRad, let transposed):
            String(format: "Scan frame (R–Q %.1f°%@ applied)",
                   rotationRad * 180 / .pi, transposed ? " · transposed" : "")
        case .detector:
            "Detector x/y — R–Q rotation not calibrated"
        }
    }
}

/// The strain tensor field expressed in a presentation frame, plus the frame
/// itself so no caller can take the numbers without the label.
package nonisolated struct PresentedStrainMap {
    package let base: StrainMap
    package let frame: StrainPresentationFrame
    package let exx: [Float]
    package let eyy: [Float]
    package let exy: [Float]
    package let theta: [Float]

    /// Same contract as `StrainMap.component`: masked positions are NaN,
    /// never 0. Residual and indexed are frame-free diagnostics and pass
    /// through from the base map.
    package func component(_ c: StrainComponent) -> FloatImage {
        let source: [Float]
        switch c {
        case .exx:   source = exx
        case .eyy:   source = eyy
        case .exy:   source = exy
        case .theta: source = theta
        case .residual, .indexed: return base.component(c)
        }
        var out = source
        for i in 0..<out.count where !base.mask[i] { out[i] = .nan }
        return FloatImage(width: base.width, height: base.height, pixels: out)
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(base: StrainMap, frame: StrainPresentationFrame, exx: [Float], eyy: [Float], exy: [Float], theta: [Float]) {
        self.base = base
        self.frame = frame
        self.exx = exx
        self.eyy = eyy
        self.exy = exy
        self.theta = theta
    }
}

extension StrainMap {
    /// The tensor components expressed in `frame`. `.detector` is the
    /// identity — the arrays pass through untouched, so an uncalibrated
    /// session presents exactly what was computed.
    package nonisolated func presented(in frame: StrainPresentationFrame) -> PresentedStrainMap {
        switch frame {
        case .detector:
            return PresentedStrainMap(base: self, frame: frame,
                                      exx: exx, eyy: eyy, exy: exy, theta: theta)
        case .scan(let rotationRad, let transposed):
            let rotated = StrainFrameRotation.rotate(
                exx: exx, eyy: eyy, exy: exy, theta: theta,
                rotationRad: rotationRad, transposed: transposed
            )
            return PresentedStrainMap(base: self, frame: frame,
                                      exx: rotated.exx, eyy: rotated.eyy,
                                      exy: rotated.exy, theta: rotated.theta)
        }
    }
}

package nonisolated enum StrainFrameRotation {

    /// Rotate a strain tensor field from the detector frame into the scan
    /// frame: transpose first (swap εxx ↔ εyy, negate θ), then the tensor
    /// rotation by the calibrated angle — the same order py4DSTEM applies to
    /// the vectors themselves (flip, then R·v). Element-wise over the raw
    /// field; masked positions hold 0 here and become NaN in `component`,
    /// exactly as in the unrotated path.
    package static func rotate(
        exx: [Float], eyy: [Float], exy: [Float], theta: [Float],
        rotationRad: Float, transposed: Bool
    ) -> (exx: [Float], eyy: [Float], exy: [Float], theta: [Float]) {
        let n = exx.count
        let c = cos(rotationRad), s = sin(rotationRad)
        let c2 = c * c, s2 = s * s, sc = s * c
        var outXX = [Float](repeating: 0, count: n)
        var outYY = [Float](repeating: 0, count: n)
        var outXY = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let a = transposed ? eyy[i] : exx[i]
            let b = transposed ? exx[i] : eyy[i]
            let d = exy[i]
            outXX[i] = c2 * a - 2 * sc * d + s2 * b
            outYY[i] = s2 * a + 2 * sc * d + c2 * b
            outXY[i] = sc * (a - b) + (c2 - s2) * d
        }
        let outTheta = transposed ? theta.map { -$0 } : theta
        return (outXX, outYY, outXY, outTheta)
    }
}
