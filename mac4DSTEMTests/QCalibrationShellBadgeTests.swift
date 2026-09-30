import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane Q (v4.1 Slot 1, 2026-09-30), the Q calibration's shell-ratio badge.
///
/// The decision, in the owner's words (ADR 050, "Q calibration picks the wrong
/// ring"): say "unchecked" when the ratio cannot confirm the ring assignment.
/// What ships is the THRESHOLD-FREE half — the state `.notSelfChecked` reads
/// "Shell ratio unchecked — <reason>" on the Q readiness row and on Prepare's
/// "Q shell check" row; the row keeps `.ready(.measuredInApp)` (a caveat, not a
/// refusal). The "disagrees" half was measured on the app's own path and did
/// not separate (`KnownCrystalQCalibration`, note 5), so a MEASURED ratio —
/// however far from the crystal's — is never worded "unchecked": its numbers are
/// shown and the reader judges. Both halves are pinned here; the second pin is
/// what would catch a threshold slipped in without its derivation.
@MainActor
final class QCalibrationShellBadgeTests: XCTestCase {

    private static let reason = "only one shell is detectable"
    private static let probeRadius: Float = 4.5

    // MARK: - The wording (Core)

    func testAnUncheckedShellCheckCarriesTheSharedWording() {
        XCTAssertEqual(
            QCalibrationShellCheck.notSelfChecked(Self.reason).uncheckedNote,
            "Shell ratio unchecked — only one shell is detectable"
        )
    }

    /// No threshold ships: a measured ratio is not "unchecked" at 0.1 % apart,
    /// at the demo cube's 22 %, or at 50 %. Break it by returning a note above
    /// any `mismatch` line.
    func testAMeasuredShellCheckIsNeverWordedUnchecked() {
        for observed in [1.1547 * 1.001, 1.4129, 1.1547 * 1.5] {
            let check = QCalibrationShellCheck.measured(
                observedRatio: observed, expectedRatio: 1.1547, positions: 7650)
            XCTAssertNil(check.uncheckedNote,
                         "a measured ratio shows its numbers, it is not 'unchecked' (observed \(observed))")
        }
    }

    // MARK: - The Q readiness row (Core/Data)

    private func qItem(size: Double, provenance: CalibrationValueProvenance?,
                       caveat: CalibrationProvenance.QShellCaveat?) throws -> CalibrationReadinessItem {
        var calibration = Calibration()
        calibration.qPixelSize = size
        calibration.qPixelUnits = "Å⁻¹"
        var state = CalibrationProvenance()
        state.qScale = provenance
        state.qShellCaveat = caveat
        let report = CalibrationReadinessReport.make(calibration: calibration, provenance: state)
        return try XCTUnwrap(report.items.first { $0.kind == .qScale })
    }

    private var caveat: CalibrationProvenance.QShellCaveat {
        .init(pixelSize: 0.0125, text: "Shell ratio unchecked — \(Self.reason)")
    }

    /// The verdict is untouched — the row is still ready and still "Measured in
    /// app" — and the detail names what was not checked. Break it by deleting
    /// the `qDetail +=` line in `CalibrationReadinessReport.make`.
    func testTheQRowStaysReadyAndNamesWhatWasNotChecked() throws {
        let item = try qItem(size: 0.0125, provenance: .measuredInApp, caveat: caveat)
        XCTAssertEqual(item.status, .ready(.measuredInApp),
                       "unchecked is a caveat on a used scale, never a refusal")
        XCTAssertTrue(item.detail.contains("0.0125"), "the value stays on the row: \(item.detail)")
        XCTAssertTrue(item.detail.contains("Shell ratio unchecked — only one shell is detectable"),
                      "the row must say what was not checked: \(item.detail)")
        XCTAssertFalse(
            try qItem(size: 0.0125, provenance: .measuredInApp, caveat: nil).detail.contains("unchecked"),
            "no caveat, no words")
    }

    /// A caveat describes ONE value from ONE measurement. Typed over (manual),
    /// restored (sidecar), rewound to another number, or an import all leave it
    /// behind in the provenance record; none may show it. Break each guard in
    /// turn: drop `provenance.qScale == .measuredInApp` (manual/sidecar go
    /// red), drop `caveat.pixelSize == size` (the changed value goes red).
    func testTheCaveatNeverDescribesAnotherValue() throws {
        for (provenance, size, why) in [
            (CalibrationValueProvenance.manual, 0.0125, "a typed scale"),
            (.sessionSidecar, 0.0125, "a restored scale"),
            (.importedFile, 0.0125, "an imported scale"),
            (.measuredInApp, 0.02, "a measured scale that is not the one the caveat was made for"),
        ] {
            let item = try qItem(size: size, provenance: provenance, caveat: caveat)
            XCTAssertFalse(item.detail.contains("unchecked"), "\(why) must not carry it: \(item.detail)")
        }
    }

    // MARK: - Prepare's "Q shell check" row (Session)

    private func estimate(_ check: QCalibrationShellCheck) -> QCalibrationEstimate {
        QCalibrationEstimate(
            invAngstromPerPixel: 0.0125, observedRadiusPixels: 10, referenceRadiusInvAngstrom: 0.125,
            medianAbsoluteDeviationPixels: 0.1, sampleCount: 5, secondShellRadiusPixels: nil,
            shellCheck: check, sameShellPeaksPerPosition: 1)
    }

    /// Break it by reverting `selfCheckSummary` to "Not self-checked — …".
    func testThePrepareLineUsesTheSharedWordingAndAMeasuredLineKeepsItsNumbers() {
        let run = QCalibrationRun()
        run.record(estimate(.notSelfChecked(Self.reason)))
        XCTAssertEqual(run.selfCheckSummary, "Shell ratio unchecked — only one shell is detectable")

        run.record(estimate(.measured(observedRatio: 1.4129, expectedRatio: 1.1547, positions: 7650)))
        let summary = run.selfCheckSummary ?? ""
        XCTAssertTrue(summary.contains("1.413") && summary.contains("1.155") && summary.contains("22.4%"),
                      "the mismatch number stays visible: \(summary)")
        XCTAssertTrue(summary.contains("7650 positions"), summary)
        XCTAssertFalse(summary.contains("unchecked"), summary)
    }

    // MARK: - The app path (AppState.calibrateQFromCrystal)

    private func stateReadyToCalibrateQ() async throws -> AppState {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.navigation.analysisMode = .disks
        await state.runDiskDetection()
        XCTAssertGreaterThan(try XCTUnwrap(state.resultPresentation.braggVectors).totalPeakCount, 0)
        let scan = state.descriptor.map { max($0.rx, $0.ry) } ?? 12
        let centre = Float(state.descriptor.map { $0.qx } ?? 64) / 2
        let count = scan * scan
        let signs = (0..<count).map { Float($0 % 2 == 0 ? 1 : -1) }
        state.calibrationSession.calibration.originProvenance = .fitted
        state.calibrationSession.calibration.probeRadius = Self.probeRadius
        state.calibrationSession.calibration.origin = OriginMaps(
            width: scan, height: scan,
            measuredX: signs.map { centre + $0 * Self.probeRadius * 0.2 },
            measuredY: [Float](repeating: centre, count: count),
            fittedX: [Float](repeating: centre, count: count),
            fittedY: [Float](repeating: centre, count: count))
        return state
    }

    /// A crystal with ONE allowed shell inside kMax 2.5 (simple cubic, a = 0.5 Å:
    /// {100} at 2.0 Å⁻¹, {110} at 2.83) cannot be checked. The app stamps the
    /// scale `.measuredInApp` AND the Q row says so. Break it by deleting the
    /// `qShellCaveat` assignment in `calibrateQFromCrystal`.
    func testACrystalWithOneShellLeavesAnUncheckedCaveatOnTheQRow() async throws {
        let state = try await stateReadyToCalibrateQ()
        state.acomSession.customStructure = .sc
        state.acomSession.customLatticeA = 0.5
        state.acomSession.customZ = 13
        state.acomSession.modelSelection = .customCubic
        XCTAssertNotNil(state.resolvedACOMModel, "the one-shell model must resolve")

        await state.calibrateQFromCrystal()

        guard case .notSelfChecked? = state.qCalibration.shellCheck else {
            return XCTFail("one allowed shell must report .notSelfChecked: \(state.statusText)")
        }
        XCTAssertEqual(state.calibrationSession.provenance.qScale, .measuredInApp)
        let item = try XCTUnwrap(state.calibrationSession.readiness.items.first { $0.kind == .qScale })
        XCTAssertEqual(item.status, .ready(.measuredInApp))
        XCTAssertTrue(item.detail.contains("Shell ratio unchecked — this crystal has only one allowed shell"),
                      "the Q row must say what was not checked: \(item.detail)")
        XCTAssertTrue(state.statusText.contains("shell ratio unchecked"), state.statusText)
    }

    /// The other half, through the app: the demo cube's pattern read against gold
    /// disagrees by ~24 % (the existing pin in `QCalibrationOriginGateTests`).
    /// The numbers reach the Prepare line; NO caveat reaches the Q row. Break it
    /// by making `calibrateQFromCrystal` set a caveat when `mismatch > 0.1`.
    func testAMeasuredRatioThatDisagreesByFarCarriesNoCaveat() async throws {
        let state = try await stateReadyToCalibrateQ()
        state.acomSession.modelSelection = .library("au_fcc")
        XCTAssertNotNil(state.resolvedACOMModel)

        await state.calibrateQFromCrystal()

        let mismatch = try XCTUnwrap(state.qCalibration.shellCheck?.mismatch,
                                     "two shells must give a measured ratio: \(state.statusText)")
        XCTAssertGreaterThan(mismatch, 0.15, "the fixture must disagree for this test to mean anything")
        XCTAssertNil(state.calibrationSession.provenance.qShellCaveat)
        let item = try XCTUnwrap(state.calibrationSession.readiness.items.first { $0.kind == .qScale })
        XCTAssertFalse(item.detail.contains("unchecked"), item.detail)
        XCTAssertTrue((state.qCalibration.selfCheckSummary ?? "").contains("predicted"))
    }
}
