//
//  PolishCPanesTests.swift
//  Polish C (2026-09-30 morning), from the night's drives: the annulus centre
//  handle at inner radius 0, restored unit spellings, the opening image, and
//  the pattern readout after a promote. Each test names the mutation it catches.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Drive 2A: the inner-radius handle sits exactly on the centre handle at
/// radius 0 and took its drag. It is parked, not hidden: dragging it is the
/// only way to raise the inner radius again from 0.
final class ApertureHandleRulesTests: XCTestCase {
    /// Mutation it catches: no parking (offset = inner, back on the centre at
    /// 0), or `min` instead of `max` (parked handle pulled back in, or a real
    /// radius above the minimum dragged down to it).
    func testTheInnerHandleIsParkedOneDiameterOutAndNeverInsideTheRadius() {
        // Radius 0, or smaller than a handle: parked at the minimum.
        XCTAssertEqual(ApertureHandleRules.innerHandleOffset(inner: 0, minimum: 3), 3)
        XCTAssertEqual(ApertureHandleRules.innerHandleOffset(inner: 1, minimum: 3), 3)
        // A real radius is drawn where it is.
        XCTAssertEqual(ApertureHandleRules.innerHandleOffset(inner: 3, minimum: 3), 3)
        XCTAssertEqual(ApertureHandleRules.innerHandleOffset(inner: 12.5, minimum: 3), 12.5)
    }
}

/// Drives 2A/2B: a restored or file-read scale printed "A^-1" while a live one
/// read "Å⁻¹". One formatter at the display boundary; nothing stored changes.
final class UnitDisplayLabelTests: XCTestCase {
    /// Mutation it catches: `displayLabel` returns its input unchanged; or a
    /// canonical spelling / an unrecognised one is altered.
    func testAsciiSpellingsReadCanonicalAndUnknownOnesPassThrough() {
        XCTAssertEqual(CalibrationUnitConversion.displayLabel("A^-1"), "Å⁻¹")
        XCTAssertEqual(CalibrationUnitConversion.displayLabel("1/A"), "Å⁻¹")
        XCTAssertEqual(CalibrationUnitConversion.displayLabel("Å⁻¹"), "Å⁻¹")
        XCTAssertEqual(CalibrationUnitConversion.displayLabel("1/nm"), "nm⁻¹")
        XCTAssertEqual(CalibrationUnitConversion.displayLabel("A"), "Å")
        XCTAssertEqual(CalibrationUnitConversion.displayLabel("nm"), "nm")
        XCTAssertEqual(CalibrationUnitConversion.displayLabel("mrad"), "mrad")
        XCTAssertEqual(CalibrationUnitConversion.displayLabel("px"), "px")
        XCTAssertEqual(CalibrationUnitConversion.displayLabel("furlongs"), "furlongs",
                       "a spelling nobody recognises is shown, not guessed")
        XCTAssertEqual(CalibrationUnitConversion.displayLabel(nil), "")
    }

    /// The scale bar's boundary. Mutation it catches: `footerSampling` (or the
    /// diffraction bar's call site) passing the raw label through.
    func testTheFooterScaleBarLabelIsNormalised() {
        let sampling = ScaleBar.footerSampling(row: 0.012, column: 0.012, units: "A^-1", swapsAxes: false)
        XCTAssertEqual(sampling.label, "Å⁻¹")
        XCTAssertEqual(sampling.perPixel, 0.012)
    }

    /// Info › Product › Sampling (the one wording authority). Mutation it
    /// catches: `sampling` printing the stored spelling.
    func testTheSamplingLineReadsCanonical() {
        XCTAssertEqual(SessionResultPresentation.sampling(row: 0.012, column: 0.012, units: "A^-1"),
                       "sampling 0.012 Å⁻¹/px")
        XCTAssertEqual(SessionResultPresentation.sampling(row: 2, column: 2, units: nil),
                       "sampling 2 px/px")
    }

    /// The Prepare readiness detail ("From file 0.012 A^-1/px") and the stored
    /// value: the row reads canonical while `qPixelUnits` keeps the file's
    /// spelling. Mutation it catches: the detail using the raw spelling, or the
    /// display fix writing the canonical one back into the stored calibration.
    func testTheReadinessDetailReadsCanonicalAndTheStoredUnitIsUntouched() throws {
        var calibration = Calibration()
        calibration.qPixelSize = 0.012
        calibration.qPixelUnits = "A^-1"
        calibration.rPixelSize = 0.5
        calibration.rPixelUnits = "nm"
        let report = CalibrationReadinessReport.make(
            calibration: calibration, provenance: CalibrationProvenance())
        let q = try XCTUnwrap(report.items.first { $0.kind == .qScale })
        XCTAssertEqual(q.detail, "\(CalibrationUnitConversion.displayNumber(0.012)) Å⁻¹/px")  // the reader's locale (0,012 in de_DE)
        XCTAssertEqual(calibration.qPixelUnits, "A^-1", "display boundary only")
        XCTAssertEqual(calibration.diffractionScaleBar.unitLabel, "A^-1",
                       "the Core value passes through; the pane normalises it")
    }
}

/// Drives 1 and 2B.
@MainActor
final class OpeningAnalysisTests: XCTestCase {
    /// Mutation it catches: any of the three conditions dropped.
    func testTheVirtualImageIsOnlyForAnEmptyPrepareUnderAnotherTask() {
        XCTAssertTrue(OpeningAnalysis.needsVirtualImage(
            hasProduct: false, area: .prepare, mode: .phaseMapping))
        XCTAssertFalse(OpeningAnalysis.needsVirtualImage(
            hasProduct: true, area: .prepare, mode: .phaseMapping), "an image already shows")
        XCTAssertFalse(OpeningAnalysis.needsVirtualImage(
            hasProduct: false, area: .map, mode: .phaseMapping), "a task's own room keeps its empty state")
        XCTAssertFalse(OpeningAnalysis.needsVirtualImage(
            hasProduct: false, area: .prepare, mode: .virtualDetector), "it already tried")
    }

    /// Mutation it catches: the position restated at the origin, with no
    /// image, or never.
    func testThePatternReadoutIsRestoredOnlyOffTheOriginWithAnImage() {
        XCTAssertTrue(OpeningAnalysis.restoresPatternReadout(selected: ScanPos(x: 41, y: 36), hasProduct: true))
        XCTAssertFalse(OpeningAnalysis.restoresPatternReadout(selected: ScanPos(x: 0, y: 0), hasProduct: true))
        XCTAssertFalse(OpeningAnalysis.restoresPatternReadout(selected: ScanPos(x: 41, y: 36), hasProduct: false))
        XCTAssertEqual(OpeningAnalysis.patternReadout(ScanPos(x: 41, y: 36)), "Pattern x 41, y 36")
    }

    /// Drive 1, shots 52-54: a cube opened after a phase-map session titled
    /// its pane "Phase map (0 candidates)" over "No Result Yet". Through the
    /// real open path. Mutation it catches: `activate` running only
    /// `runCurrentAnalysis` (the stale task's no-op).
    func testACubeOpenedUnderAStaleTaskShowsItsVirtualImage() async {
        let state = AppState()
        state.navigation.analysisMode = .phaseMapping
        await state.openDemoFixture()

        XCTAssertNotNil(state.resultPresentation.product, "Prepare must have an image to show")
        XCTAssertFalse(state.displayedResultName.hasPrefix("Phase map"),
                       "the title was \(state.displayedResultName)")
        XCTAssertTrue(state.displayedResultName.hasPrefix("Virtual detector"),
                      "the title was \(state.displayedResultName)")
    }

    /// Drive 2B: after promote the footer said "Virtual detector ✓ …" and the
    /// selected position was readable only from the marker. Mutation it
    /// catches: promote ending on the analysis line.
    func testThePromoteFooterStatesTheCarriedPosition() async {
        let state = AppState()
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 2, xOffset: 3, height: 6, width: 6)
        await state.openDemoFixture(specification: spec)
        state.selectedScan = ScanPos(x: 4, y: 1)

        await state.promoteToFullExtent()

        XCTAssertEqual(state.selectedScan, ScanPos(x: 7, y: 3), "precondition: the position was carried")
        XCTAssertEqual(state.statusText, "Pattern x 7, y 3")
    }
}
