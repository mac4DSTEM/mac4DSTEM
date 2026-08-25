import XCTest
@testable import mac4DSTEM

/// v2 S8. Strain is computed in detector x/y and presented in the scan frame
/// when the calibrated R–Q rotation exists (`StrainFrame.swift`). These pin
/// the tensor rotation against known answers and against the ground truth —
/// refitting the lattice from rotated input vectors — and pin the wiring:
/// display and export express the tensor in the presentation frame and name
/// that frame in provenance.
final class StrainFrameTests: XCTestCase {

    // MARK: - Frame resolution

    func testFrameResolutionFollowsTheCalibration() {
        XCTAssertEqual(
            StrainPresentationFrame.resolve(rotationRad: nil, transposeQR: nil),
            .detector, "no measured rotation → nothing to rotate by"
        )
        XCTAssertEqual(
            StrainPresentationFrame.resolve(rotationRad: .nan, transposeQR: nil),
            .detector, "a non-finite rotation is absent, matching Calibration's own test"
        )
        XCTAssertEqual(
            StrainPresentationFrame.resolve(rotationRad: 0.5, transposeQR: nil),
            .scan(rotationRad: 0.5, transposed: false)
        )
        XCTAssertEqual(
            StrainPresentationFrame.resolve(rotationRad: -0.25, transposeQR: true),
            .scan(rotationRad: -0.25, transposed: true)
        )
    }

    // MARK: - Known answers

    /// Uniaxial tension along detector-x under a 90° R–Q rotation lands on
    /// scan-y: a detector vector along x maps to scan (0, 1), so the tension
    /// axis is the map's vertical. εxx and εyy swap; this is the literal
    /// misread the open-item describes.
    func testNinetyDegreeRotationMovesTensionBetweenAxes() {
        let rotated = StrainFrameRotation.rotate(
            exx: [0.02], eyy: [0], exy: [0], theta: [0.003],
            rotationRad: .pi / 2, transposed: false
        )
        XCTAssertEqual(rotated.exx[0], 0, accuracy: 1e-7)
        XCTAssertEqual(rotated.eyy[0], 0.02, accuracy: 1e-7)
        XCTAssertEqual(rotated.exy[0], 0, accuracy: 1e-7)
        XCTAssertEqual(rotated.theta[0], 0.003, accuracy: 1e-7,
                       "lattice rotation is invariant under a proper rotation")
    }

    /// Pure shear changes sign under a 90° rotation — the open-item's second
    /// clause ("changes the sign convention of the shear").
    func testPureShearChangesSignUnderNinetyDegrees() {
        let rotated = StrainFrameRotation.rotate(
            exx: [0], eyy: [0], exy: [0.01], theta: [0],
            rotationRad: .pi / 2, transposed: false
        )
        XCTAssertEqual(rotated.exy[0], -0.01, accuracy: 1e-7)
        XCTAssertEqual(rotated.exx[0], 0, accuracy: 1e-7)
        XCTAssertEqual(rotated.eyy[0], 0, accuracy: 1e-7)
    }

    /// The transpose is an improper transform: normal components swap, the
    /// shear is unchanged, and the lattice-rotation pseudo-scalar NEGATES
    /// (py4DSTEM's `flip_theta`).
    func testTransposeSwapsNormalComponentsAndNegatesTheta() {
        let rotated = StrainFrameRotation.rotate(
            exx: [0.02], eyy: [-0.01], exy: [0.005], theta: [0.003],
            rotationRad: 0, transposed: true
        )
        XCTAssertEqual(rotated.exx[0], -0.01, accuracy: 1e-7)
        XCTAssertEqual(rotated.eyy[0], 0.02, accuracy: 1e-7)
        XCTAssertEqual(rotated.exy[0], 0.005, accuracy: 1e-7)
        XCTAssertEqual(rotated.theta[0], -0.003, accuracy: 1e-7)
    }

    /// At 45° the cross terms carry the whole answer (sc = ½): pure shear
    /// becomes pure normal strain. The 90° cases have sc = 0 and are BLIND to
    /// the sign of the 2sc·εxy term — this is the known answer that pins it.
    func testFortyFiveDegreeRotationTurnsShearIntoNormalStrain() {
        let rotated = StrainFrameRotation.rotate(
            exx: [0], eyy: [0], exy: [0.01], theta: [0],
            rotationRad: .pi / 4, transposed: false
        )
        XCTAssertEqual(rotated.exx[0], -0.01, accuracy: 1e-7)
        XCTAssertEqual(rotated.eyy[0], 0.01, accuracy: 1e-7)
        XCTAssertEqual(rotated.exy[0], 0, accuracy: 1e-7)
    }

    /// A 180° rotation is −I: the tensor is invariant. This is why the iDPC
    /// contrast-flip control can never corrupt a strain map.
    func testOneEightyDegreeRotationIsTheIdentityOnTheTensor() {
        let rotated = StrainFrameRotation.rotate(
            exx: [0.02], eyy: [-0.01], exy: [0.005], theta: [0.003],
            rotationRad: .pi, transposed: false
        )
        XCTAssertEqual(rotated.exx[0], 0.02, accuracy: 1e-6)
        XCTAssertEqual(rotated.eyy[0], -0.01, accuracy: 1e-6)
        XCTAssertEqual(rotated.exy[0], 0.005, accuracy: 1e-6)
        XCTAssertEqual(rotated.theta[0], 0.003, accuracy: 1e-6)
    }

    /// `.detector` passes the arrays through untouched — an uncalibrated
    /// session presents exactly what was computed.
    func testDetectorFramePresentationIsTheIdentity() throws {
        let map = try XCTUnwrap(Self.syntheticStrainMap())
        let presented = map.presented(in: .detector)
        XCTAssertEqual(presented.exx, map.exx)
        XCTAssertEqual(presented.eyy, map.eyy)
        XCTAssertEqual(presented.exy, map.exy)
        XCTAssertEqual(presented.theta, map.theta)
    }

    /// Masked positions render NaN in the presented components exactly as in
    /// the unrotated path — never 0, which a diverging colormap shows as
    /// "zero strain".
    func testMaskedPositionsRemainNaNInPresentedComponents() throws {
        let map = try XCTUnwrap(Self.syntheticStrainMap(dropPosition: 2))
        XCTAssertFalse(map.mask[2], "the dropped position must be unfittable")
        let presented = map.presented(
            in: .scan(rotationRad: 0.61, transposed: false)
        )
        for component in [StrainComponent.exx, .eyy, .exy, .theta] {
            XCTAssertTrue(presented.component(component).pixels[2].isNaN,
                          "\(component) must be NaN at the masked position")
        }
    }

    // MARK: - Ground truth: rotating inputs ≡ rotating the output tensor

    /// The scientific pin. py4DSTEM's calibrated pipeline rotates the Bragg
    /// vectors themselves (braggvectors.py:528–545) before the strain fit;
    /// this app rotates the fitted tensor at presentation. The two must be
    /// the same operation: refit from vectors transformed by v' = R(θ)·F·v
    /// and compare against `StrainFrameRotation.rotate` of the raw fit.
    func testRotatingInputVectorsEqualsRotatingTheOutputTensor() throws {
        for (angleDeg, transposed) in [
            (Float(30), false), (Float(90), false), (Float(-37.2), false),
            (Float(30), true), (Float(-71.6), true),
        ] {
            let theta = angleDeg * .pi / 180
            let raw = try XCTUnwrap(
                Self.syntheticStrainMap(),
                "raw fit failed at \(angleDeg)°"
            )
            let refit = try XCTUnwrap(
                Self.syntheticStrainMap(rotateInputsBy: theta, transposed: transposed),
                "rotated-input fit failed at \(angleDeg)°, transposed \(transposed)"
            )
            let rotated = raw.presented(
                in: .scan(rotationRad: theta, transposed: transposed)
            )
            for i in 0..<raw.exx.count where raw.mask[i] && refit.mask[i] {
                XCTAssertEqual(refit.exx[i], rotated.exx[i], accuracy: 1e-4,
                               "εxx at \(i), \(angleDeg)°, transposed \(transposed)")
                XCTAssertEqual(refit.eyy[i], rotated.eyy[i], accuracy: 1e-4,
                               "εyy at \(i), \(angleDeg)°, transposed \(transposed)")
                XCTAssertEqual(refit.exy[i], rotated.exy[i], accuracy: 1e-4,
                               "εxy at \(i), \(angleDeg)°, transposed \(transposed)")
                XCTAssertEqual(refit.theta[i], rotated.theta[i], accuracy: 1e-4,
                               "θ at \(i), \(angleDeg)°, transposed \(transposed)")
            }
        }
    }

    // MARK: - Wiring: display and export express the presentation frame

    /// 37.2°, NOT 90°: at ±90° the tensor rotation has sin·cos = 0 and is
    /// blind to the SIGN of the angle — the Gate B reviewer's M3 mutation
    /// (display rotates by −θ while export keeps +θ) passed the whole suite
    /// when this test pinned 90° (2026-08-25). 37.2° discriminates the sign.
    @MainActor
    func testDisplayedStrainComponentIsExpressedInTheScanFrame() throws {
        let state = AppState()
        let map = try XCTUnwrap(Self.syntheticStrainMap())
        state.strain.publish(map)
        let rotation: Float = 37.2 * .pi / 180
        state.calibration.rotationRad = rotation
        state.showComputedProduct(.strain)

        let image = try XCTUnwrap(state.resultImage)
        let expected = map.presented(
            in: .scan(rotationRad: rotation, transposed: false)
        ).component(.exx)
        for i in 0..<expected.pixels.count where map.mask[i] {
            XCTAssertEqual(image.pixels[i], expected.pixels[i], accuracy: 1e-6)
        }
        // Anti-vacuity: the frames must actually differ on this fixture.
        var framesDiffer = false
        for i in 0..<map.exx.count where map.mask[i] {
            if abs(map.exx[i] - expected.pixels[i]) > 1e-5 { framesDiffer = true }
        }
        XCTAssertTrue(framesDiffer,
                      "fixture must distinguish the frames or this test proves nothing")
        // The wrong-sign frame must ALSO differ from the right one, or the
        // angle chosen here cannot discriminate M3.
        let wrongSign = map.presented(
            in: .scan(rotationRad: -rotation, transposed: false)
        ).component(.exx)
        var signsDiffer = false
        for i in 0..<map.exx.count where map.mask[i] {
            if abs(wrongSign.pixels[i] - expected.pixels[i]) > 1e-5 { signsDiffer = true }
        }
        XCTAssertTrue(signsDiffer, "the pinned angle must discriminate the rotation sign")

        // The burned caption is "the one carrier that survives a screenshot";
        // the reviewer's M5 (drop the frame keys from the caption whitelist)
        // left the suite green — pin the composed caption itself.
        let caption = try XCTUnwrap(
            state.exportedImageProvenanceRecord()["caption"] as? String
        )
        XCTAssertTrue(caption.contains("strain_frame=scan"),
                      "caption must name the frame on its face: \(caption)")
        XCTAssertTrue(caption.contains("qr_rotation_deg=37.2"),
                      "caption must carry the applied angle: \(caption)")
    }

    /// The transpose half of the display wiring: the reviewer's M4 mutation
    /// (display passes transposed: false regardless of calibration) passed
    /// the whole suite when no wiring test covered transposeQR.
    @MainActor
    func testDisplayedStrainComponentHonorsTheTransposeCalibration() throws {
        let state = AppState()
        let map = try XCTUnwrap(Self.syntheticStrainMap())
        state.strain.publish(map)
        let rotation: Float = 30 * .pi / 180
        state.calibration.rotationRad = rotation
        state.calibration.transposeQR = true
        state.showComputedProduct(.strain)

        let image = try XCTUnwrap(state.resultImage)
        let expected = map.presented(
            in: .scan(rotationRad: rotation, transposed: true)
        ).component(.exx)
        for i in 0..<expected.pixels.count where map.mask[i] {
            XCTAssertEqual(image.pixels[i], expected.pixels[i], accuracy: 1e-6)
        }
        // Anti-vacuity: the untransposed presentation must differ, or this
        // fixture cannot see the mutation this test exists to kill.
        let untransposed = map.presented(
            in: .scan(rotationRad: rotation, transposed: false)
        ).component(.exx)
        var transposeMatters = false
        for i in 0..<map.exx.count where map.mask[i] {
            if abs(untransposed.pixels[i] - expected.pixels[i]) > 1e-5 {
                transposeMatters = true
            }
        }
        XCTAssertTrue(transposeMatters,
                      "the fixture must distinguish transposed from untransposed")
    }

    @MainActor
    func testDisplayedStrainStaysDetectorFrameWithoutACalibratedRotation() throws {
        let state = AppState()
        let map = try XCTUnwrap(Self.syntheticStrainMap())
        state.strain.publish(map)
        XCTAssertNil(state.calibration.rotationRad)
        state.showComputedProduct(.strain)

        let image = try XCTUnwrap(state.resultImage)
        let expected = map.component(.exx)
        for i in 0..<expected.pixels.count where map.mask[i] {
            XCTAssertEqual(image.pixels[i], expected.pixels[i], accuracy: 0)
        }
        XCTAssertEqual(state.strainPresentationFrame, .detector)
        // The honest self-labelling is half the fix: a detector-frame figure
        // with no frame token would be the old defect intact (F1.29's trap).
        let caption = try XCTUnwrap(
            state.exportedImageProvenanceRecord()["caption"] as? String
        )
        XCTAssertTrue(caption.contains("strain_frame=detector"),
                      "the detector case must label itself on the figure: \(caption)")
    }

    /// The rotation-change refresh through the one public path that can carry
    /// it: flipping the rotation re-derives the displayed strain (the image is
    /// mathematically invariant under 180°, but the derivation must run — the
    /// same one-rule wiring that covers a genuine angle change). The
    /// `calibrateRotation` and `applySessionCalibration` sites share the rule
    /// but need a CoM field / a sidecar restore to reach; they are
    /// review-pinned (S8 deviations).
    @MainActor
    func testFlippingTheRotationRederivesTheStrainDisplay() throws {
        let state = AppState()
        state.strain.publish(try XCTUnwrap(Self.syntheticStrainMap()))
        state.calibration.rotationRad = .pi / 2
        state.showComputedProduct(.strain)
        let before = state.resultVersion

        state.flipRotation180()

        XCTAssertGreaterThan(state.resultVersion, before,
                             "a rotation change must reach the strain display")
    }

    @MainActor
    func testStrainFrameProvenanceNamesTheFrameAndTheRotation() {
        let state = AppState()
        XCTAssertEqual(state.strainFrameProvenance["strain_frame"], "detector")
        XCTAssertEqual(state.strainFrameProvenance["strain_frame_reason"],
                       "qr_rotation_not_calibrated")
        XCTAssertNil(state.strainFrameProvenance["qr_rotation_rad"])

        state.calibration.rotationRad = -0.6493  // −37.2°
        state.calibration.transposeQR = true
        let scan = state.strainFrameProvenance
        XCTAssertEqual(scan["strain_frame"], "scan")
        XCTAssertEqual(scan["qr_rotation_deg"], "-37.2")
        XCTAssertEqual(scan["qr_transposed"], "true")
        XCTAssertEqual(scan["qr_rotation_rad"], String(Float(-0.6493)))
        XCTAssertNil(scan["strain_frame_reason"])
    }

    /// −64° and transposed, NOT 90° untransposed: the export site is its own
    /// call into `presented(in:)`, so it needs its own sign- and
    /// transpose-discriminating pin (the reviewer's M3/M4 lesson applies here
    /// independently of the display test).
    @MainActor
    func testScientificBundleExportsThePresentedTensorWithFrameProvenance() throws {
        let state = AppState()
        let map = try XCTUnwrap(Self.syntheticStrainMap())
        state.strain.publish(map)
        let rotation: Float = -64 * .pi / 180
        state.calibration.rotationRad = rotation
        state.calibration.transposeQR = true

        let bundle = try XCTUnwrap(state.scientificBundleMaps())
        let exx = try XCTUnwrap(bundle.first { $0.kind == "strain_exx" })
        XCTAssertEqual(exx.provenance["strain_frame"], "scan")
        XCTAssertEqual(exx.provenance["qr_rotation_deg"], "-64.0")
        XCTAssertEqual(exx.provenance["qr_transposed"], "true")

        let expected = map.presented(
            in: .scan(rotationRad: rotation, transposed: true)
        )
        for i in 0..<map.exx.count where map.mask[i] {
            XCTAssertEqual(exx.pixels[i], expected.exx[i], accuracy: 1e-6,
                           "the bundle must carry the same numbers the screen shows")
        }
        // Sign- and transpose-discrimination guards: a wrong-sign or
        // untransposed presentation must differ on this fixture.
        let wrongSign = map.presented(in: .scan(rotationRad: -rotation, transposed: true))
        let untransposed = map.presented(in: .scan(rotationRad: rotation, transposed: false))
        var signMatters = false, transposeMatters = false
        for i in 0..<map.exx.count where map.mask[i] {
            if abs(wrongSign.exx[i] - expected.exx[i]) > 1e-5 { signMatters = true }
            if abs(untransposed.exx[i] - expected.exx[i]) > 1e-5 { transposeMatters = true }
        }
        XCTAssertTrue(signMatters, "the pinned angle must discriminate the rotation sign")
        XCTAssertTrue(transposeMatters, "the fixture must discriminate the transpose")
        // Frame-free diagnostics stay untouched.
        let residual = try XCTUnwrap(bundle.first { $0.kind == "strain_fit_residual" })
        for i in 0..<map.exx.count where map.mask[i] {
            XCTAssertEqual(residual.pixels[i], map.localResidualPixels[i], accuracy: 0)
        }
    }

    // MARK: - Fixture

    /// A 3×2 scan over a heterogeneously strained lattice — anisotropic and
    /// sheared so every tensor component is exercised and the frames are
    /// distinguishable. `rotateInputsBy` applies v' = R(θ)·F·v to every peak
    /// about the origin — exactly py4DSTEM's calibrated-vector transform —
    /// before the fit.
    static func syntheticStrainMap(
        rotateInputsBy angle: Float? = nil,
        transposed: Bool = false,
        dropPosition: Int? = nil
    ) -> StrainMap? {
        let origin = (x: Float(64), y: Float(64))
        func lattice(g1: (Float, Float), g2: (Float, Float)) -> [BraggPeak] {
            let hk: [(Float, Float)] = [
                (1, 0), (-1, 0), (0, 1), (0, -1),
                (1, 1), (-1, -1), (1, -1), (-1, 1),
            ]
            return hk.map { h, k in
                var x = h * g1.0 + k * g2.0
                var y = h * g1.1 + k * g2.1
                if let angle {
                    let a = transposed ? y : x
                    let b = transposed ? x : y
                    let c = cos(angle), s = sin(angle)
                    (x, y) = (c * a - s * b, s * a + c * b)
                }
                return BraggPeak(x: origin.x + x, y: origin.y + y, intensity: 1)
            }
        }
        // Reference-dominated scan (four unstrained positions) plus two
        // distinct strained states: anisotropic tension/compression and shear
        // with a small lattice rotation.
        let unstrained = lattice(g1: (12, 0), g2: (0, 12))
        let tension = lattice(g1: (12.6, 0), g2: (0, 11.4))
        let sheared = lattice(g1: (12, 0.5), g2: (0.4, 12))
        var peaks = [unstrained, unstrained, tension,
                     unstrained, unstrained, sheared]
        if let dropPosition { peaks[dropPosition] = [] }
        return StrainMapping.compute(
            bragg: BraggVectors(scanWidth: 3, scanHeight: 2, peaks: peaks),
            originX: origin.x, originY: origin.y,
            minNumPeaks: 5
        )
    }
}
