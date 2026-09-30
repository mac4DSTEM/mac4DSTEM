//
//  PolishSlot1Tests.swift
//  v4.1 Slot 1, lane P (the polish room). One class per item so a red names its item.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

// MARK: - Item 1: the aperture default on a binned / detector-cropped load (Gate D)

/// Drive 3, shot 52: after Open with Options + detector bin 2 the aperture ring sat in the
/// upper-left quarter of the pattern. The default aperture is built in the VIEW's detector
/// frame, and `activate` handed it to `CalibrationReReference.apply` as if it were a
/// SOURCE-frame position — which the bin rescaled (and a crop translated) a second time.
/// The demo source has a 64 x 64 detector. With `calibrated: false` it has NO pixel metadata at all
/// (`pixelCalibration() == nil`: the `if let pc` block of `activate` is never entered); the drive's
/// file carried Q/R pixel sizes and no origin, which `SizesOnlySource` below reproduces.
@MainActor
final class BinnedApertureDefaultTests: XCTestCase {

    /// A source whose metadata carries pixel sizes and NO origin (no qx0/qy0 mean, no maps) — the
    /// drive's AlMgSi_demo.h5. Patterns are zeros: `activate(runInitialAnalysis: false)` reads none.
    private actor SizesOnlySource: FourDDataSource {
        nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
        func discoverPrimaryDataset() throws -> DatasetDescriptor { DemoFourDDataSource.descriptor }
        func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
            [Float](repeating: 0, count: view.descriptor.qy * view.descriptor.qx)
        }
        func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
            [Float](repeating: 0, count: view.descriptor.rx * view.descriptor.qy * view.descriptor.qx)
        }
        func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
            FourDScanTile(
                yRange: yRange, scanWidth: view.descriptor.rx,
                detectorHeight: view.descriptor.qy, detectorWidth: view.descriptor.qx,
                pixels: [Float](repeating: 0, count: yRange.count * view.descriptor.rx
                                * view.descriptor.qy * view.descriptor.qx))
        }
        func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
        func pixelCalibration() -> PixelCalibration? {
            PixelCalibration(rSize: 0.5, rUnits: "nm", qSize: 0.02, qUnits: "A^-1", qrFlip: false)
        }
    }

    /// The drive's case (finding 7 of the refuter): pixel sizes present, origin absent, detector bin 2.
    /// Mutations it catches: any `fileApertureCenter = <the aperture>` inside the `if let pc` block
    /// (shot 52 exactly: 7.75 on the 32 px view), or a "pixel size present -> seed the centre" edit.
    func testPixelSizesWithoutAnOriginKeepTheViewsMiddleOnABinnedLoad() async throws {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let state = AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults))
        let load = state.beginDatasetLoading("Opening…")
        await state.activate(descriptor: DemoFourDDataSource.descriptor, reader: SizesOnlySource(),
                             specification: LoadSpecification(detectorBin: 2), runInitialAnalysis: false)
        state.finishDatasetLoading(owner: load)

        // Precondition: the metadata block WAS entered — the bin doubled the recorded Q pixel.
        XCTAssertEqual(try XCTUnwrap(state.calibrationSession.calibration.qPixelSize), 0.04, accuracy: 1e-12)
        XCTAssertEqual(state.descriptor?.qx, 32)
        XCTAssertEqual(state.aperture.centerX, 16, "the middle of the 32 px view, not a twice-binned 7.75")
        XCTAssertEqual(state.aperture.centerY, 16)
        XCTAssertEqual(state.aperture.outer, 8)
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .geometricDefault)
        XCTAssertFalse(state.loadedView.invalidatedCalibration.contains { $0.field == .origin },
                       state.loadedView.invalidatedCalibration.map(\.reason).joined(separator: " | "))
    }

    private func openDemo(calibrated: Bool, _ specification: LoadSpecification) async -> AppState {
        let state = AppState()
        await state.openDemoFixture(calibrated: calibrated, specification: specification)
        return state
    }

    /// Mutation it catches: the geometric default is re-referenced like a file-recorded
    /// position (HEAD: binnedCoordinate(16, bin 2) = 7.75 on the 32 px view).
    func testABinnedLoadWithoutAFileOriginKeepsTheViewsMiddleAsItsAperture() async {
        let state = await openDemo(calibrated: false, LoadSpecification(detectorBin: 2))
        XCTAssertEqual(state.descriptor?.qx, 32, "precondition: the view is the binned detector")
        XCTAssertEqual(state.aperture.centerX, 16, "the middle of the 32 px view, not a twice-binned 7.75")
        XCTAssertEqual(state.aperture.centerY, 16)
        XCTAssertEqual(state.aperture.outer, 8, "the radius was always the view's quarter")
    }

    /// Mutation it catches: the crop offset is subtracted from a default that is already
    /// in the cropped frame (HEAD: 16 - 16 = 0, the crop's corner).
    func testACroppedLoadWithoutAFileOriginKeepsTheViewsMiddleAsItsAperture() async {
        let crop = AxisCrop(yOffset: 16, xOffset: 16, height: 32, width: 32)
        let state = await openDemo(calibrated: false, LoadSpecification(detectorCrop: crop))
        XCTAssertEqual(state.descriptor?.qx, 32)
        XCTAssertEqual(state.aperture.centerX, 16)
        XCTAssertEqual(state.aperture.centerY, 16)
    }

    /// A file that never recorded an origin must not be told its beam fell outside the crop.
    /// Mutation it catches: the default is passed to `apply` (HEAD: 8 - 48 lands outside and
    /// a `Beam origin` refusal is appended to the view).
    func testACropFarFromTheMiddleDoesNotInventAnOriginRefusal() async {
        let crop = AxisCrop(yOffset: 48, xOffset: 48, height: 16, width: 16)
        let state = await openDemo(calibrated: false, LoadSpecification(detectorCrop: crop))
        XCTAssertEqual(state.descriptor?.qx, 16)
        XCTAssertFalse(state.loadedView.invalidatedCalibration.contains { $0.field == .origin },
                       "nothing was carried, so nothing was refused: "
                       + state.loadedView.invalidatedCalibration.map(\.reason).joined(separator: " | "))
        XCTAssertEqual(state.aperture.centerX, 8)
        XCTAssertEqual(state.aperture.centerY, 8)
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .geometricDefault)
    }

    /// Control: a file-recorded centre IS a source-frame position and is rebinned
    /// (source 32 -> binned 15.75). Must stay green under the fix: a fix that stops
    /// re-referencing the file's centre fails here.
    func testAFileRecordedCentreIsStillRebinnedIntoTheView() async {
        let state = await openDemo(calibrated: true, LoadSpecification(detectorBin: 2))
        XCTAssertEqual(state.aperture.centerX, 15.75, accuracy: 1e-5)
        XCTAssertEqual(state.aperture.centerY, 15.75, accuracy: 1e-5)
    }

    /// Control: a full-extent view is the identity (qx / 2 = 32, outer = 16).
    func testAFullExtentLoadKeepsTheDefaultAperture() async {
        let state = await openDemo(calibrated: false, .fullExtent)
        XCTAssertEqual(state.aperture.centerX, 32)
        XCTAssertEqual(state.aperture.centerY, 32)
        XCTAssertEqual(state.aperture.outer, 16)
    }

    /// The pure half: no position supplied means no position moved and none refused.
    func testReReferenceWithNoAperturePositionRefusesNothing() throws {
        let source = DemoFourDDataSource.descriptor
        let view = try LoadView(
            source: source,
            specification: LoadSpecification(
                detectorCrop: AxisCrop(yOffset: 48, xOffset: 48, height: 16, width: 16)))
        let outcome = CalibrationReReference.apply(
            view, to: Calibration(), provenance: CalibrationProvenance(), apertureCenter: nil)
        XCTAssertNil(outcome.apertureCenter)
        XCTAssertTrue(outcome.invalidated.isEmpty, outcome.invalidated.map(\.reason).joined(separator: " | "))
    }

    /// The session-sidecar path had the same placeholder: a sidecar with a pixel size and
    /// no origin, restored into a far detector crop, must not refuse an origin it never had.
    /// Mutation it catches: the view-middle placeholder passed to `apply` again.
    func testASessionWithoutAnOriginIsNotRefusedAnOriginOnACrop() throws {
        let specification = LoadSpecification(
            detectorCrop: AxisCrop(yOffset: 48, xOffset: 48, height: 16, width: 16))
        let view = try LoadView(source: DemoFourDDataSource.descriptor, specification: specification)
        let saved = PixelCalibration(rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false)
        let out = try XCTUnwrap(SessionCalibrationTranslation.translate(
            saved: saved, policy: .decide(session: .fullExtent, loaded: specification),
            view: view, descriptor: view.descriptor))
        XCTAssertNil(out.center)
        XCTAssertFalse(out.invalidated.contains { $0.field == .origin },
                       out.invalidated.map(\.reason).joined(separator: " | "))
    }
}

// MARK: - Item 2: the drives' presentation list

final class PresentationListTests: XCTestCase {

    // (b) the S23 legend prints grouped counts like the rest of the app.
    /// Mutation it catches: the legend built from the ungrouped interpolation.
    func testTheTrimLegendGroupsDigitsAndMatchesTheCoreSentenceBelowFourDigits() {
        let big = FitOverlays.OriginTrimOverlay(width: 100, height: 100, excluded: 60, runs: [])
        XCTAssertEqual(big.legend, "60 of 10,000 positions excluded by the origin fit\u{2019}s robust trim")
        let small = FitOverlays.OriginTrimOverlay(width: 5, height: 4, excluded: 6, runs: [])
        XCTAssertEqual(small.legend, small.caption, "one sentence: the two cannot drift below 1,000")
    }

    // (c) one axis order, the × glyph, axes named.
    /// Mutation it catches: height-first / (y, x) offsets / ASCII "x" again.
    func testTheCropSummaryReadsWidthByHeightWithTheOffsetsNamed() {
        let specification = LoadSpecification(
            scanCrop: AxisCrop(yOffset: 16, xOffset: 20, height: 64, width: 60),
            detectorCrop: AxisCrop(yOffset: 4, xOffset: 8, height: 32, width: 48),
            detectorBin: 2)
        XCTAssertEqual(specification.provenanceSummary,
                       "scan 60 \u{00D7} 64 at (x 20, y 16), detector 48 \u{00D7} 32 at (x 8, y 4), binned 2\u{00D7}")
        XCTAssertNil(LoadSpecification.fullExtent.provenanceSummary)
    }

    // (d) human labels, the raw key stays in the help.
    /// Mutation it catches: the raw key shown; the phase-count keys left raw.
    func testProvenanceKeysReadAsLabels() {
        XCTAssertEqual(ProvenanceKeyLabel.text("analysis_mode"), "Analysis mode")
        XCTAssertEqual(ProvenanceKeyLabel.text("quantitative_status"), "Quantitative status")
        XCTAssertEqual(ProvenanceKeyLabel.text("method"), "Method")
        XCTAssertEqual(ProvenanceKeyLabel.text("count_0_Aluminium (FCC)"), "Positions: Aluminium (FCC)")
        XCTAssertEqual(ProvenanceKeyLabel.text("count_2_beta_double_prime_Mg5Si6 [0 0 1]"),
                       "Positions: beta_double_prime_Mg5Si6 [0 0 1]", "a phase keeps its own spelling")
        XCTAssertEqual(ProvenanceKeyLabel.text("count_not_indexed"), "Positions: not indexed")
        XCTAssertEqual(ProvenanceKeyLabel.text("count_no_peaks"), "Positions: no peaks")
        XCTAssertEqual(ProvenanceKeyLabel.text("count_x"), "Count x", "no index, no phase: the generic label")
    }

    // (f) px stays with its number.
    /// Mutation it catches: the text returned unchanged (the "px" wraps alone again).
    func testAUnitStaysWithItsNumber() {
        let nbsp = "\u{00A0}"
        XCTAssertEqual(
            CalibrationReadinessRow.keepingUnitsWithNumbers(
                "Origin: Measured · Probe: 6.93 px (Measured in app) · Fit RMS 0.001819 px"),
            "Origin: Measured · Probe: 6.93\(nbsp)px (Measured in app) · Fit RMS 0.001819\(nbsp)px")
        XCTAssertEqual(CalibrationReadinessRow.keepingUnitsWithNumbers("0.024 Å⁻¹/px"), "0.024 Å⁻¹/px")
        XCTAssertEqual(CalibrationReadinessRow.keepingUnitsWithNumbers("a 12.5 · b 11 · θ 3.0°"),
                       "a 12.5 · b 11 · θ 3.0°")
    }
}

// MARK: - Item 3 (A1): a centre drag parks the file's recorded centre

@MainActor
final class ApertureDragParksTheFilesCentreTests: XCTestCase {

    private func drag(_ state: AppState, to x: Float, _ y: Float) {
        var raw = state.aperture
        raw.centerX = x; raw.centerY = y
        state.updateAperture(raw)
    }

    /// The demo file records both a mean (32, 32) and fitted maps. Mutation it catches: the
    /// drag destroys the recorded mean (HEAD); Restore puts the maps back but not the mean.
    func testARestoreAfterADragReturnsTheFilesRecordedCentreAndMaps() async throws {
        let state = AppState()
        await state.openDemoFixture()
        let calibration = state.calibrationSession.calibration
        XCTAssertEqual(calibration.recordedOriginX, 32, "precondition: the file recorded a centre")
        XCTAssertEqual(calibration.recordedOriginY, 32)
        XCTAssertNotNil(calibration.origin)

        drag(state, to: 40, 41)
        XCTAssertNil(state.calibrationSession.calibration.recordedOriginX, "live origin follows the drag")
        let parked = try XCTUnwrap(state.calibrationSession.parkedRecordedOrigin, "the file's centre is parked")
        XCTAssertEqual(parked.x, 32); XCTAssertEqual(parked.y, 32)
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .manual)
        XCTAssertTrue(state.canRestoreFittedOrigin)
        XCTAssertEqual(state.setAsideOriginProvenance, .fileMaps)
        XCTAssertEqual(CalibrationReadinessRow.originReplacedDetail(displaced: state.setAsideOriginProvenance),
                       "Aperture center replaced the file's origin.")

        // More ticks of the same drag must not overwrite the parked centre with the dragged one.
        drag(state, to: 41, 42)
        XCTAssertEqual(state.calibrationSession.parkedRecordedOrigin, parked)

        state.restoreFittedOrigin()
        XCTAssertEqual(state.calibrationSession.calibration.recordedOriginX, 32)
        XCTAssertEqual(state.calibrationSession.calibration.recordedOriginY, 32)
        XCTAssertNotNil(state.calibrationSession.calibration.origin)
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .fileMaps)
        XCTAssertEqual(state.aperture.centerX, 32)
        XCTAssertEqual(state.aperture.centerY, 32)
        XCTAssertFalse(state.canRestoreFittedOrigin)
        XCTAssertNil(state.calibrationSession.parkedRecordedOrigin)
    }

    /// A file with only a recorded mean (no fitted maps) had NOTHING to restore before: the drag
    /// destroyed its only origin. Mutation it catches: Restore requires set-aside maps.
    func testAFileWithOnlyARecordedMeanCanBeRestoredToo() {
        let state = AppState()
        state.calibrationSession.calibration.recordedOriginX = 31.5
        state.calibrationSession.calibration.recordedOriginY = 30.5
        state.calibrationSession.calibration.originProvenance = .fileMean
        state.aperture = Aperture(centerX: 31.5, centerY: 30.5, inner: 0, outer: 16)

        drag(state, to: 40, 41)
        XCTAssertTrue(state.canRestoreFittedOrigin, "the drag set the file's centre aside, so Restore is offered")
        XCTAssertEqual(state.setAsideOriginProvenance, .fileMean)
        XCTAssertNil(state.supersededFittedOrigin, "there were no maps to set aside")
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .manual)
        XCTAssertTrue(state.replay.lineage.nodes.isEmpty, "no fit was displaced, so no lineage node")

        state.restoreFittedOrigin()
        XCTAssertEqual(state.calibrationSession.calibration.recordedOriginX, 31.5)
        XCTAssertEqual(state.calibrationSession.calibration.recordedOriginY, 30.5)
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .fileMean)
        XCTAssertEqual(state.aperture.centerX, 31.5)
        XCTAssertEqual(state.aperture.centerY, 30.5)
        XCTAssertFalse(state.canRestoreFittedOrigin)
    }

    /// Control: no recorded centre, nothing parked, nothing to restore (the existing
    /// `testACentreDragWithNoFitSetAsideRecordsNoNode` contract).
    func testADragWithNoRecordedCentreParksNothing() {
        let state = AppState()
        state.aperture = Aperture(centerX: 60, centerY: 60, inner: 0, outer: 20)
        drag(state, to: 61, 62)
        XCTAssertNil(state.calibrationSession.parkedRecordedOrigin)
        XCTAssertFalse(state.canRestoreFittedOrigin)
        state.restoreFittedOrigin()   // a no-op, not a crash
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .manual)
    }

    /// Clearing the calibration drops the parked centre with everything else.
    func testClearCalibrationDropsTheParkedCentre() {
        let state = AppState()
        state.calibrationSession.calibration.recordedOriginX = 31.5
        state.calibrationSession.calibration.recordedOriginY = 30.5
        state.calibrationSession.calibration.originProvenance = .fileMean
        state.aperture = Aperture(centerX: 31.5, centerY: 30.5, inner: 0, outer: 16)
        drag(state, to: 40, 41)
        XCTAssertNotNil(state.calibrationSession.parkedRecordedOrigin)
        state.clearCalibration()
        XCTAssertNil(state.calibrationSession.parkedRecordedOrigin)
        XCTAssertFalse(state.canRestoreFittedOrigin)
    }
}

// MARK: - Item 5 (A3): an imported CIF named like a built-in model

/// The card's residual ("the library-first resolver shadows an imported CIF with the same stem as
/// a built-in id") does not reproduce: an imported model's id is `imported_<stem>`
/// (`CIFImport`), so no stem can equal a built-in id, and `resolveMaterial`'s library-first order
/// can never reach an import. This pins the invariant that makes the order harmless.
final class ImportedModelNamedLikeABuiltInTests: XCTestCase {
    private let cif = """
    data_al
    _cell_length_a 4.05
    _cell_length_b 4.05
    _cell_length_c 4.05
    _cell_angle_alpha 90
    _cell_angle_beta 90
    _cell_angle_gamma 90
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    Al1 Al 0.0 0.0 0.0
    Al2 Al 0.5 0.5 0.0
    Al3 Al 0.5 0.0 0.5
    Al4 Al 0.0 0.5 0.5
    """

    /// Mutation it catches: `CIFImport` dropping the `imported_` prefix (the import then
    /// takes the built-in's id and the library-first resolver returns the built-in).
    func testAnImportedCIFWithABuiltInsStemKeepsItsOwnIdAndResolvesAsImported() throws {
        let imported = try CIFImport.crystalModel(from: cif, fileBaseName: "al_fcc")
        XCTAssertNotNil(CrystalModelLibrary.model(id: "al_fcc"), "precondition: the built-in exists")
        XCTAssertNotEqual(imported.id, "al_fcc", "an import never takes a built-in's id")
        let session = ReplayStepPlan.ACOMReplayPlan.SessionMaterials(
            importedIDs: [imported.id], importedFingerprints: [imported.id: imported.contentFingerprint],
            customStructure: .fcc, customLatticeA: 1, customZ: 6)
        var recordedOnImport = ReplayStepPlan.ACOMReplayPlan(
            materialID: imported.id, latticeA: nil, scaleInvAngstromPerPixel: 0.0125,
            scope: .fullScan, quality: .balanced)
        recordedOnImport.materialFingerprint = imported.contentFingerprint
        XCTAssertEqual(recordedOnImport.resolveMaterial(in: session), .imported(imported.id))
        let recordedOnLibrary = ReplayStepPlan.ACOMReplayPlan(
            materialID: "al_fcc", latticeA: nil, scaleInvAngstromPerPixel: 0.0125,
            scope: .fullScan, quality: .balanced)
        XCTAssertEqual(recordedOnLibrary.resolveMaterial(in: session), .library("al_fcc"),
                       "the built-in's own recipes are unaffected by an import of the same stem")
    }
}
