import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// core-data-05 (S22a ride-along): the inspector's excluded-fraction
/// disclosure and the readiness/refusal paths must share ONE policy floor.
/// The retired 0.5% threshold disclosed fractions Gate B measured as inside
/// the robust trim's own false-positive range on clean data.
@MainActor
final class CalibrationDisclosureTests: XCTestCase {

    func testExcludedFractionDisclosureUsesTheSharedPolicyFloor() {
        // 1% sits between the retired 0.5% and the shared 2%: the old
        // threshold disclosed it; the policy says stay quiet.
        XCTAssertFalse(PrepareSettings.disclosesExcludedFraction(0.01))
        // Exactly at the floor: quiet — the policy is strictly-greater,
        // matching Calibration's own readiness use of the constant.
        XCTAssertFalse(PrepareSettings.disclosesExcludedFraction(
            Calibration.excludedFractionDisclosureFloor))
        // Above the floor: disclosed.
        XCTAssertTrue(PrepareSettings.disclosesExcludedFraction(0.03))
    }

    // MARK: - Clear Calibration (open item, 2026-09-14)

    /// Every calibration ready, from a mixture of measurement and import —
    /// the state a user is in when they notice the ellipse fit was wrong.
    private func fullyCalibratedSession() -> CalibrationSession {
        let session = CalibrationSession()
        session.calibration.originProvenance = .fitted
        session.calibration.probeRadius = 5
        session.calibration.ellipseA = 1.03
        session.calibration.ellipseB = 0.97
        session.calibration.ellipseTheta = 0.4
        session.calibration.rotationRad = 0.3
        session.calibration.transposeQR = true
        session.calibration.qPixelSize = 0.012
        session.calibration.qPixelUnits = "Å⁻¹"
        session.calibration.rPixelSize = 0.5
        session.calibration.rPixelUnits = "nm"
        session.provenance = CalibrationProvenance(
            probe: .measuredInApp, ellipse: .measuredInApp, rotation: .measuredInApp,
            qScale: .measuredInApp, rScale: .importedFile
        )
        session.lastEllipseFit = EllipseCalibrationFit(
            centerQX: 64, centerQY: 64, a: 1.03, b: 0.97, theta: 0.4,
            normalizedResidual: 0.02, conicResidual: 0.02, sampleCount: 900,
            occupiedAngularBins: 33, model: .conic, profile: nil,
            profileFallbackReason: nil
        )
        session.acceleratingVoltage = 200
        session.originFitFunction = .parabola
        session.ellipseFitInnerRadius = 22
        session.ellipseFitOuterRadius = 58
        return session
    }

    /// The defect: a measured calibration could not be taken back in the app —
    /// the owner had to reload the file to get "Not set" onto the rows again.
    /// All five rows, by the words the panel prints, not by the fields behind
    /// them: "Not set" is what the row says and what the user reported missing.
    func testClearingTheCalibrationPutsEveryReadinessRowBackToNotSet() {
        let session = fullyCalibratedSession()
        XCTAssertEqual(
            session.readiness.items.map(\.status.displayName),
            ["Measured", "Measured", "Measured", "Measured", "From file"],
            "precondition: this session starts fully calibrated"
        )
        XCTAssertTrue(session.verdict.quantitative)
        XCTAssertTrue(session.hasAnyCalibrationValue)

        session.clear()

        XCTAssertEqual(
            session.readiness.items.map(\.kind),
            CalibrationReadinessKind.allCases,
            "all five rows are still present — cleared, not removed"
        )
        for item in session.readiness.items {
            XCTAssertEqual(item.status, .missing, "\(item.kind.rawValue) is still set")
            XCTAssertEqual(item.status.displayName, "Not set", item.kind.rawValue)
        }
        XCTAssertNil(session.lastEllipseFit, "the fit that produced the ellipse goes with it")
        // The rows cannot see this on their own: with the values gone, every
        // status is `.missing` whatever the provenance says, so dropping the
        // provenance reset would leave "Measured in app" behind with nothing
        // measured — invisible in Prepare, visible in an export's metadata.
        XCTAssertEqual(session.provenance, CalibrationProvenance(),
                       "the sources go with the values")
        XCTAssertFalse(session.hasAnyCalibrationValue, "nothing left for the control to clear")
        XCTAssertFalse(session.verdict.quantitative)
    }

    /// What a clear must NOT take. The voltage is an acquisition fact, not a
    /// measurement of this dataset, and the fit settings are how the next
    /// measurement will be made — re-entering them is the friction the clear
    /// exists to remove. `AppState.activate` also reads the voltage off the
    /// file *before* it resets the calibration, so a `clear()` that took the
    /// voltage would silently discard imported metadata on every open.
    func testClearingKeepsTheVoltageAndTheFitSettings() {
        let session = fullyCalibratedSession()
        session.clear()
        XCTAssertEqual(session.acceleratingVoltage, 200)
        XCTAssertTrue(session.hasUsableVoltage)
        XCTAssertEqual(session.originFitFunction, .parabola)
        XCTAssertEqual(session.ellipseFitInnerRadius, 22)
        XCTAssertEqual(session.ellipseFitOuterRadius, 58)
    }

    /// `.unusable` — an origin and probe that are present but failed the fit
    /// gate — is exactly the state a user clears, so the control must be
    /// offered for it. Reading `hasAnyCalibrationValue` off `isReady` would
    /// have hidden the button in the one case it was asked for.
    func testAnOriginThatFailedItsFitGateStillCountsAsSomethingToClear() {
        let session = CalibrationSession()
        session.calibration.originProvenance = .fitted
        session.calibration.probeRadius = 2
        session.calibration.origin = OriginMaps(
            width: 2, height: 2,
            measuredX: [0, 0, 0, 0], measuredY: [0, 0, 0, 0],
            fittedX: [9, 9, 9, 9], fittedY: [9, 9, 9, 9],
            excludedFraction: 0, robustResidual: nil
        )
        session.provenance.probe = .measuredInApp
        XCTAssertEqual(session.readiness.items[0].status, .unusable)
        XCTAssertFalse(session.readiness.items[0].status.isReady)
        XCTAssertTrue(session.hasAnyCalibrationValue)

        session.clear()
        XCTAssertEqual(session.readiness.items[0].status, .missing)
        XCTAssertFalse(session.hasAnyCalibrationValue)
    }

    // MARK: - Origin validity mask (v3.1, ADR 033)

    /// The mechanical carry: `OriginMaps.init` must STORE the mask it is handed,
    /// verbatim. This pins the initializer assignment ONLY — break-first M1
    /// (`self.originValidity = nil` in the init, `Calibration.swift`) turns it
    /// red. It deliberately does NOT claim to cover the two production
    /// constructors in `OriginCalibration` (tiledRun/run) — those are Metal-bound
    /// and pinned end-to-end in `ProbeSizeTests`
    /// (`testTiledRunCarriesTheOriginValidityMask`,
    /// `testResidentCubeRunCarriesTheOriginValidityMask`), where reverting the
    /// `originValidity: fitted.kept` lines actually goes red.
    func testOriginMapsStoresTheValidityMaskVerbatim() throws {
        let mask = [true, false, true, true, false, true]
        let maps = OriginMaps(
            width: 3, height: 2, measuredX: nil, measuredY: nil,
            fittedX: [Float](repeating: 0, count: 6), fittedY: [Float](repeating: 0, count: 6),
            originValidity: mask)
        XCTAssertEqual(maps.originValidity, mask)
    }

    /// The nil contract: an imported / file / session origin has no trim history,
    /// so the mask is `nil` — not an invented all-`true` array — exactly as
    /// `excludedFraction` is `nil` there. Both entry points: the direct
    /// constructor default and the py4DSTEM `appOriginMaps` bridge. Break-first M2
    /// (the bridge invents an all-`true` mask) turns the bridge assertion red.
    func testAnImportedOriginCarriesNoValidityMask() throws {
        let direct = OriginMaps(
            width: 2, height: 2, measuredX: nil, measuredY: nil,
            fittedX: [1, 1, 1, 1], fittedY: [2, 2, 2, 2])
        XCTAssertNil(direct.originValidity, "no trim history → no mask")
        XCTAssertNil(direct.excludedFraction, "precondition: this is the no-trim path")

        let pixel = PixelOriginMaps(
            shape: [2, 2], fittedQX: [1, 1, 1, 1], fittedQY: [2, 2, 2, 2])
        let bridged = try XCTUnwrap(pixel.appOriginMaps(width: 2, height: 2))
        XCTAssertNil(bridged.originValidity, "the import bridge invents no mask")
    }
}
