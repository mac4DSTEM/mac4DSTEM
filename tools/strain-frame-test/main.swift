//
//  tools/strain-frame-test — v2 S8's Gate B fixture.
//
//  Claim under test: `StrainFrameRotation.rotate` (Core/Analysis/
//  StrainFrame.swift) expresses a detector-frame strain tensor field in the
//  scan frame exactly as py4DSTEM does — by the calibrated-vector transform
//  v_scan = R(θ)·F·v_det — so the app may rotate the FITTED tensor at
//  presentation instead of refitting from rotated vectors.
//
//  Three independent arbiters, so no case is self-consistent:
//    A. py4DSTEM itself: golden.json is produced by the vendored
//       `get_rotated_strain_map` (reference.py, which also source-locks the
//       conventions and cross-checks against an independent numpy transform).
//    B. The refit: `StrainMapping.compute` on vectors rotated the way
//       py4DSTEM rotates calibrated vectors must equal rotating the raw fit's
//       output — the ground truth the presentation shortcut stands on.
//    C. Known answers a reader can verify by hand (90° swap, 45° shear).
//
//  NEGATIVE CONTROLS name the line they break and why the failure follows —
//  "it went red" is not evidence (the L4 phantom-control lesson).
//

import Foundation

@main
enum Harness {

    static var failures = 0

    static func fail(_ message: String) {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        failures += 1
    }

    static func check(_ condition: Bool, _ message: String) {
        if !condition { fail(message) }
    }

    // MARK: A — py4DSTEM golden comparison

    struct Golden: Decodable {
        struct Case: Decodable {
            let rotation_rad: Double
            let transposed: Bool
            let expected_exx: [Double]
            let expected_eyy: [Double]
            let expected_exy: [Double]
            let expected_theta: [Double]
        }
        let shape: [Int]
        let input_exx: [Double]
        let input_eyy: [Double]
        let input_exy: [Double]
        let input_theta: [Double]
        let cases: [Case]
    }

    static func runGolden(_ path: String) throws {
        let golden = try JSONDecoder().decode(
            Golden.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        let exx = golden.input_exx.map(Float.init)
        let eyy = golden.input_eyy.map(Float.init)
        let exy = golden.input_exy.map(Float.init)
        let theta = golden.input_theta.map(Float.init)
        // Float32 inputs vs float64 reference; values are O(0.03).
        let tolerance: Float = 5e-6
        for c in golden.cases {
            let got = StrainFrameRotation.rotate(
                exx: exx, eyy: eyy, exy: exy, theta: theta,
                rotationRad: Float(c.rotation_rad), transposed: c.transposed
            )
            let label = String(format: "%.1f°, transposed %@",
                               c.rotation_rad * 180 / .pi, String(c.transposed))
            for i in 0..<exx.count {
                check(abs(got.exx[i] - Float(c.expected_exx[i])) < tolerance,
                      "εxx[\(i)] differs from py4DSTEM at \(label)")
                check(abs(got.eyy[i] - Float(c.expected_eyy[i])) < tolerance,
                      "εyy[\(i)] differs from py4DSTEM at \(label)")
                check(abs(got.exy[i] - Float(c.expected_exy[i])) < tolerance,
                      "εxy[\(i)] differs from py4DSTEM at \(label)")
                check(abs(got.theta[i] - Float(c.expected_theta[i])) < tolerance,
                      "θ[\(i)] differs from py4DSTEM at \(label)")
            }
        }
        if failures == 0 {
            print("PASS: \(golden.cases.count) py4DSTEM get_rotated_strain_map cases matched")
        }
    }

    // MARK: B — refit equivalence (the ground truth for the shortcut)

    /// 12×9 scan over a heterogeneously strained lattice. The local
    /// least-squares fits are EXACTLY rotation-equivariant, but the reference
    /// (py4DSTEM `get_reference_g1g2`, ported in StrainMapping) is a
    /// component-wise MEDIAN, which is rotation-equivariant only when one
    /// lattice holds a strict majority — so the equivalence fixture makes the
    /// unstrained lattice the majority (5 of 9 rows), pinning the median to
    /// the same physical lattice in every frame. NC5 below demonstrates what
    /// happens without the majority; this was DISCOVERED by this harness on
    /// 2026-08-25 (a mixture fixture failed at every angle except 90°, where
    /// the median components swap exactly).
    static func syntheticVectors(
        rotateBy angle: Float?, transposed: Bool, majorityReference: Bool = true
    ) -> BraggVectors {
        let origin = (x: Float(64), y: Float(64))
        func lattice(g1: (Float, Float), g2: (Float, Float)) -> [BraggPeak] {
            let hk: [(Float, Float)] = [
                (1, 0), (-1, 0), (0, 1), (0, -1),
                (1, 1), (-1, -1), (1, -1), (-1, 1),
                (2, 0), (-2, 0), (0, 2), (0, -2),
            ]
            return hk.map { h, k in
                var x = h * g1.0 + k * g2.0
                var y = h * g1.1 + k * g2.1
                if let angle {
                    // py4DSTEM's calibrated-vector transform: flip (swap the
                    // components), THEN rotate.
                    let a = transposed ? y : x
                    let b = transposed ? x : y
                    let c = cos(angle), s = sin(angle)
                    (x, y) = (c * a - s * b, s * a + c * b)
                }
                return BraggPeak(x: origin.x + x, y: origin.y + y, intensity: 1)
            }
        }
        let width = 12, height = 9
        var peaks: [[BraggPeak]] = []
        for index in 0..<(width * height) {
            let row = index / width
            let unstrained = majorityReference ? row < 5 : row % 3 == 0
            let tension = majorityReference ? (row == 5 || row == 6) : row % 3 == 1
            if unstrained {
                peaks.append(lattice(g1: (12, 0), g2: (0, 12)))
            } else if tension {
                peaks.append(lattice(g1: (12.5, 0), g2: (0, 11.5)))
            } else {
                peaks.append(lattice(g1: (12, 0.5), g2: (0.4, 12)))
            }
        }
        return BraggVectors(scanWidth: width, scanHeight: height, peaks: peaks)
    }

    static func refitCase(angleDeg: Float, transposed: Bool) {
        let origin = (x: Float(64), y: Float(64))
        let theta = angleDeg * .pi / 180
        guard let raw = StrainMapping.compute(
            bragg: syntheticVectors(rotateBy: nil, transposed: false),
            originX: origin.x, originY: origin.y
        ) else { return fail("raw fit failed at \(angleDeg)°") }
        guard let refit = StrainMapping.compute(
            bragg: syntheticVectors(rotateBy: theta, transposed: transposed),
            originX: origin.x, originY: origin.y
        ) else { return fail("rotated-input fit failed at \(angleDeg)°") }

        let rotated = StrainFrameRotation.rotate(
            exx: raw.exx, eyy: raw.eyy, exy: raw.exy, theta: raw.theta,
            rotationRad: theta, transposed: transposed
        )
        var compared = 0
        for i in 0..<raw.exx.count where raw.mask[i] && refit.mask[i] {
            compared += 1
            check(abs(refit.exx[i] - rotated.exx[i]) < 1e-4,
                  "refit εxx[\(i)] ≠ rotated output at \(angleDeg)°, transposed \(transposed)")
            check(abs(refit.eyy[i] - rotated.eyy[i]) < 1e-4,
                  "refit εyy[\(i)] ≠ rotated output at \(angleDeg)°, transposed \(transposed)")
            check(abs(refit.exy[i] - rotated.exy[i]) < 1e-4,
                  "refit εxy[\(i)] ≠ rotated output at \(angleDeg)°, transposed \(transposed)")
            check(abs(refit.theta[i] - rotated.theta[i]) < 1e-4,
                  "refit θ[\(i)] ≠ rotated output at \(angleDeg)°, transposed \(transposed)")
        }
        check(compared > 50,
              "only \(compared) positions compared at \(angleDeg)° — fixture degenerate")
    }

    // MARK: - Entry

    static func main() throws {
        let goldenPath = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1] : "golden.json"

        // A: py4DSTEM parity on the tensor rotation.
        try runGolden(goldenPath)

        // B: presentation shortcut ≡ refit from py4DSTEM-transformed vectors,
        // consensus basis (the app's default path; the manual-basis variant is
        // pinned in mac4DSTEMTests/StrainFrameTests).
        for (angle, transposed) in [
            (Float(37.2), false), (Float(90), false), (Float(-64), false),
            (Float(30), true), (Float(-71.6), true),
        ] {
            refitCase(angleDeg: angle, transposed: transposed)
        }
        if failures == 0 { print("PASS: rotate-the-fit ≡ refit-from-rotated-vectors, 5 cases") }

        // C: hand-checkable known answers.
        let tension = StrainFrameRotation.rotate(
            exx: [0.02], eyy: [0], exy: [0], theta: [0.003],
            rotationRad: .pi / 2, transposed: false
        )
        check(abs(tension.eyy[0] - 0.02) < 1e-7 && abs(tension.exx[0]) < 1e-7,
              "90°: tension along detector-x must land on scan-y")
        check(abs(tension.theta[0] - 0.003) < 1e-7,
              "90°: lattice rotation is invariant under a proper rotation")
        let shear = StrainFrameRotation.rotate(
            exx: [0], eyy: [0], exy: [0.01], theta: [0],
            rotationRad: .pi / 4, transposed: false
        )
        check(abs(shear.exx[0] + 0.01) < 1e-7 && abs(shear.eyy[0] - 0.01) < 1e-7,
              "45°: pure shear must become pure normal strain")
        if failures == 0 { print("PASS: known answers (90° swap, 45° shear)") }

        // NEGATIVE CONTROLS. Each plants one specific wrong convention and
        // demands a mismatch — proving the arbiters can actually see the
        // defect class this fixture exists for.

        // NC1 — sign of the 2sc·εxy cross term (StrainFrame.swift, the
        // `outXX` line). At 45° the cross term IS the whole εxx answer, so a
        // flipped sign must disagree with the hand answer.
        let nc1 = StrainFrameRotation.rotate(
            exx: [0], eyy: [0], exy: [0.01], theta: [0],
            rotationRad: .pi / 4, transposed: false
        )
        check(abs((-nc1.exx[0]) + 0.01) > 1e-4,
              "NC1 dead: a flipped cross-term sign would pass the 45° check")

        // NC2 — transpose order (StrainFrame.swift, the `a`/`b` swap lines).
        // Swapping AFTER the rotation instead of before differs from the
        // refit whenever the rotation is not a multiple of 90°: the refit
        // applies F first, exactly as py4DSTEM's vector transform does.
        do {
            let origin = (x: Float(64), y: Float(64))
            let theta: Float = 30 * .pi / 180
            guard let raw = StrainMapping.compute(
                bragg: syntheticVectors(rotateBy: nil, transposed: false),
                originX: origin.x, originY: origin.y
            ), let refit = StrainMapping.compute(
                bragg: syntheticVectors(rotateBy: theta, transposed: true),
                originX: origin.x, originY: origin.y
            ) else { fail("NC2 fixture failed"); return exitNow() }
            // Deliberately wrong composition: rotate first, swap outputs after.
            let wrongOrder = StrainFrameRotation.rotate(
                exx: raw.exx, eyy: raw.eyy, exy: raw.exy, theta: raw.theta,
                rotationRad: theta, transposed: false
            )
            var maxDiff: Float = 0
            for i in 0..<raw.exx.count where raw.mask[i] && refit.mask[i] {
                maxDiff = max(maxDiff, abs(refit.exx[i] - wrongOrder.eyy[i]))
            }
            check(maxDiff > 1e-3,
                  "NC2 dead: swap-after-rotation would match the refit")
        }

        // NC3 — θ negation under transpose (StrainFrame.swift, the
        // `outTheta` line). The refit from flipped vectors REALLY produces a
        // negated lattice rotation; keeping θ unchanged must disagree.
        do {
            let origin = (x: Float(64), y: Float(64))
            guard let raw = StrainMapping.compute(
                bragg: syntheticVectors(rotateBy: nil, transposed: false),
                originX: origin.x, originY: origin.y
            ), let refit = StrainMapping.compute(
                bragg: syntheticVectors(rotateBy: 0, transposed: true),
                originX: origin.x, originY: origin.y
            ) else { fail("NC3 fixture failed"); return exitNow() }
            var maxKept: Float = 0
            var maxNegated: Float = 0
            for i in 0..<raw.theta.count where raw.mask[i] && refit.mask[i] {
                maxKept = max(maxKept, abs(refit.theta[i] - raw.theta[i]))
                maxNegated = max(maxNegated, abs(refit.theta[i] + raw.theta[i]))
            }
            check(maxNegated < 1e-5 && maxKept > 1e-3,
                  "NC3 dead: the refit's θ under flip is not the negation "
                  + "(kept-diff \(maxKept), negated-diff \(maxNegated))")
        }

        // NC4 — fixture power (this file's lattice definitions): the frames
        // must actually differ on this data, or every comparison above would
        // pass under an identity 'rotation' too.
        do {
            let origin = (x: Float(64), y: Float(64))
            guard let raw = StrainMapping.compute(
                bragg: syntheticVectors(rotateBy: nil, transposed: false),
                originX: origin.x, originY: origin.y
            ) else { fail("NC4 fixture failed"); return exitNow() }
            let rotated = StrainFrameRotation.rotate(
                exx: raw.exx, eyy: raw.eyy, exy: raw.exy, theta: raw.theta,
                rotationRad: .pi / 2, transposed: false
            )
            var maxDiff: Float = 0
            for i in 0..<raw.exx.count where raw.mask[i] {
                maxDiff = max(maxDiff, abs(raw.exx[i] - rotated.exx[i]))
            }
            check(maxDiff > 0.005,
                  "NC4 dead: the fixture is too isotropic to distinguish frames")
        }

        // NC5 — the majority-reference premise (StrainMapping's port of
        // py4DSTEM get_reference_g1g2, the component-median lines). On a
        // majority-FREE mixture the median reference is not rotation-
        // equivariant, so refit-from-rotated-vectors is a slightly different
        // measurement than rotating the fit — measured 2026-08-25 at ~0.3 px
        // of reference and up to ~2e-2 of strain at 37.2° (εxy 0.0201, εxx
        // 0.0159 — Gate B reviewer's measurement). If this control dies,
        // either the reference estimator changed (check the port against
        // latticevectors.py get_reference_g1g2) or the mixture fixture
        // gained a majority — and the DEVIATION note in StrainFrame.swift
        // must be re-examined either way.
        do {
            let origin = (x: Float(64), y: Float(64))
            let theta: Float = 37.2 * .pi / 180
            guard let raw = StrainMapping.compute(
                bragg: syntheticVectors(rotateBy: nil, transposed: false,
                                        majorityReference: false),
                originX: origin.x, originY: origin.y
            ), let refit = StrainMapping.compute(
                bragg: syntheticVectors(rotateBy: theta, transposed: false,
                                        majorityReference: false),
                originX: origin.x, originY: origin.y
            ) else { fail("NC5 fixture failed"); return exitNow() }
            let rotated = StrainFrameRotation.rotate(
                exx: raw.exx, eyy: raw.eyy, exy: raw.exy, theta: raw.theta,
                rotationRad: theta, transposed: false
            )
            var maxDiff: Float = 0
            for i in 0..<raw.exx.count where raw.mask[i] && refit.mask[i] {
                maxDiff = max(maxDiff, abs(refit.exx[i] - rotated.exx[i]))
            }
            check(maxDiff > 1e-3,
                  "NC5 dead: the median reference looks rotation-equivariant "
                  + "on a majority-free mixture (max εxx diff \(maxDiff))")
        }

        if failures == 0 { print("PASS: negative controls NC1–NC5 alive") }
        exitNow()
    }

    static func exitNow() {
        if failures > 0 {
            FileHandle.standardError.write(Data("FAILED: \(failures) checks\n".utf8))
            exit(1)
        }
        print("strain-frame-test: all checks passed")
        exit(0)
    }
}
