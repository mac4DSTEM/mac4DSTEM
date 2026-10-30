//
//  ProductKindModeSwitchTests.swift
//  Lane J (Slot 4½ polish, 2026-10-02): entering a room never shows another room's product (owner card S5 a).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ProductKindModeSwitchTests: XCTestCase {
    private func product(_ kind: String) -> DisplayedProduct {
        DisplayedProduct(
            kind: kind, displayName: kind,
            payload: .scalar(FloatImage(width: 2, height: 2, pixels: [0, 0, 0, 0])), domain: .scan,
            validityMask: nil, qualityFields: [],
            sampling: ProductSampling(row: nil, column: nil, units: nil),
            valueUnits: "x", quantitativeStatus: .relative, provenance: [:], overlays: [])
    }

    private func strainMap() -> StrainMap {
        let z = [Float](repeating: 0, count: 4)
        let diag = StrainFitDiagnostics(
            automaticBasis: false, referenceMaskApplied: false, basisObservationCount: 0, basisSupportCount: 0,
            basisSupportFraction: 0, basisResidualPixels: 0, basisConditionNumber: 1, indexingTolerancePixels: 1,
            localResidualMedianPixels: 0, referenceCandidateCount: 0, referenceRejectedCount: 0)
        return StrainMap(width: 2, height: 2, exx: z, eyy: z, exy: z, theta: z,
                         mask: [true, true, true, true], localG1x: z, localG1y: z, localG2x: z, localG2y: z,
                         localResidualPixels: z, refG1: (x: 1, y: 0), refG2: (x: 0, y: 1),
                         referencePositionCount: 1, indexedFraction: 1, diagnostics: diag)
    }

    /// Mutation: return .strain for "dpc_" kinds (or drop a prefix) -> red.
    func testKindToModeMapping() {
        let cases: [(String, AnalysisMode?)] = [
            ("strain_exx", .strain), ("acom_full_ipf_z", .acom), ("dpc_color", .dpc), ("idpc_phase", .dpc),
            ("parallax_alignment", .ptychography), ("ptychography_object_phase", .singleslicePtychography),
            ("diffraction_groups", .diffractionGroups), ("diffraction_similarity", .diffractionGroups),
            ("phase_map", .phaseMapping), ("precipitate_objects", .phaseMapping),
            ("virtual_detector", nil), ("bragg_vector_map", .disks), ("disk_disagreement", .disks)]
        for (kind, mode) in cases { XCTAssertEqual(AnalysisMode.owning(productKind: kind), mode, kind) }
    }

    /// Mutation: drop the new `.strain` branch -> the DPC wheel stays.
    func testEnteringStrainWithADPCProductAndNoStrainResultClears() {
        let state = AppState()
        state.resultPresentation.publish(product("dpc_color"))
        state.presentProductForEnteredMode(.strain)
        XCTAssertNil(state.resultPresentation.product)
    }

    /// Mutation: skip the "own kind" guard -> a strain product would be re-published/cleared; here it must be the same object.
    func testEnteringStrainWithAStrainProductLeavesItAlone() {
        let state = AppState()
        state.resultPresentation.publish(product("strain_exy"))
        let version = state.resultPresentation.resultVersion
        state.presentProductForEnteredMode(.strain)
        XCTAssertEqual(state.resultPresentation.product?.kind, "strain_exy")
        XCTAssertEqual(state.resultPresentation.resultVersion, version)
    }

    /// Mutation: clear instead of re-showing the strain result -> nil, red.
    func testEnteringStrainWithAForeignProductAndAStrainResultShowsTheStrainMap() {
        let state = AppState()
        state.strain.publish(strainMap())
        state.resultPresentation.publish(product("dpc_color"))
        state.changeMode(.strain)
        XCTAssertEqual(state.resultPresentation.product?.kind, "strain_exx")
    }

    /// Strain computed, Orientation visited (no orientation map: the strain product is cleared), Strain again: the strain
    /// map is shown. The room returned early on an EMPTY pane ("No Result Yet", journey
    /// `CrystalMapsJourney.testStrainSurvivesAnOrientationVisit`), because its guard asked only "is another room's
    /// product on screen?". Mutation: restore the `guard let kind = product?.kind` -> nil, red.
    func testReturningToStrainAfterAnEmptyOrientationVisitShowsTheStrainMap() {
        let state = AppState()
        state.strain.publish(strainMap())
        state.changeMode(.strain)
        XCTAssertEqual(state.resultPresentation.product?.kind, "strain_exx", "precondition: the strain map is shown")
        state.changeMode(.acom)
        XCTAssertNil(state.resultPresentation.product, "precondition: Orientation with no map shows nothing")
        state.changeMode(.strain)
        XCTAssertEqual(state.resultPresentation.product?.kind, "strain_exx")
    }

    /// The same rule for Orientation: an ACOM map held, Strain visited with no strain map, Orientation again.
    func testReturningToOrientationAfterAnEmptyStrainVisitShowsTheOrientationMap() {
        let state = AppState()
        state.acomSession.orientationMap = OrientationMap(width: 2, height: 2)
        state.changeMode(.acom)
        XCTAssertEqual(AnalysisMode.owning(productKind: state.resultPresentation.product?.kind ?? ""), .acom,
                       "precondition: the orientation map is shown")
        state.changeMode(.strain)
        XCTAssertNil(state.resultPresentation.product, "precondition: Strain with no map shows nothing")
        state.changeMode(.acom)
        XCTAssertEqual(AnalysisMode.owning(productKind: state.resultPresentation.product?.kind ?? ""), .acom)
    }

    /// Mutation: drop the `.acom` branch -> the strain product stays.
    func testEnteringOrientationWithAStrainProductAndAnACOMResultShowsACOM() {
        let state = AppState()
        state.acomSession.orientationMap = OrientationMap(width: 2, height: 2)
        state.resultPresentation.publish(product("strain_exx"))
        state.changeMode(.acom)
        XCTAssertEqual(AnalysisMode.owning(productKind: state.resultPresentation.product?.kind ?? ""), .acom)
    }

    /// Mutation: drop the `.ptychography` branch -> the groups map stays.
    func testEnteringParallaxWithAGroupsProductAndNoResultClears() {
        let state = AppState()
        state.resultPresentation.publish(product("diffraction_groups"))
        state.changeMode(.ptychography)
        XCTAssertNil(state.resultPresentation.product)
    }

    /// Mutation: drop the `.singleslicePtychography` branch -> red.
    func testEnteringSingleSliceWithAParallaxProductAndNoResultClears() {
        let state = AppState()
        state.resultPresentation.publish(product("parallax_alignment"))
        state.changeMode(.singleslicePtychography)
        XCTAssertNil(state.resultPresentation.product)
    }

    /// Mutation: drop the `.dpc` branch -> red.
    func testEnteringDPCWithAStrainProductAndNoResultClears() {
        let state = AppState()
        state.resultPresentation.publish(product("strain_exx"))
        state.changeMode(.dpc)
        XCTAssertNil(state.resultPresentation.product)
    }

    /// Mutation: drop the `.disks` branch -> the strain product stays, nothing re-shown -> red.
    /// Round trip: Bragg map, then Strain (cleared), then back to Disks (map returns).
    func testReturningToDisksReShowsTheBraggMapFromHeldVectors() {
        let state = AppState()
        state.descriptor = DatasetDescriptor(
            filePath: "/tmp/example.h5", datasetPath: "/data", shape: [2, 2, 8, 8], dtypeDescription: "float32", chunkShape: nil)
        let peaks = [[BraggPeak(x: 3, y: 4, intensity: 1)], [], [], []]
        state.resultPresentation.setBraggVectors(BraggVectors(scanWidth: 2, scanHeight: 2, peaks: peaks))
        state.changeMode(.disks)
        state.resultPresentation.publish(product("bragg_vector_map"))
        state.changeMode(.strain)
        XCTAssertNil(state.resultPresentation.product)
        state.changeMode(.disks)
        XCTAssertEqual(state.resultPresentation.product?.kind, "bragg_vector_map")
    }

    // MARK: Imaging (the virtual image)

    private func demoState() async -> AppState {
        let state = AppState()
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        await state.openDemoFixture(specification: spec)
        return state
    }

    /// An ACOM preview published its map; entering Imaging kept it on screen under Imaging, because the room had
    /// no branch here. Imaging re-shows the virtual image its last run landed, as it landed (pixels, provenance),
    /// and starts no run. Mutation: drop the `.virtualDetector` branch -> the ACOM map stays, red.
    func testEnteringImagingAfterAnOrientationMapReshowsTheHeldVirtualImage() async throws {
        let state = await demoState()
        state.changeMode(.virtualDetector)
        let outcome = await state.runVirtualDetector()
        XCTAssertEqual(outcome, .published, state.statusText)
        let landed = try XCTUnwrap(state.resultPresentation.product)
        state.resultPresentation.imagingEntryRun = nil
        state.acomSession.orientationMap = OrientationMap(width: 4, height: 4)
        state.changeMode(.acom)
        XCTAssertEqual(AnalysisMode.owning(productKind: state.resultPresentation.product?.kind ?? ""), .acom,
                       "precondition: the orientation map is shown")
        state.changeMode(.virtualDetector)
        await state.resultPresentation.imagingEntryRun?.value
        let shown = try XCTUnwrap(state.resultPresentation.product, "Imaging shows nothing")
        XCTAssertEqual(shown.kind, landed.kind)
        XCTAssertEqual(shown.provenance, landed.provenance)
        guard case .scalar(let landedImage) = landed.payload else { return XCTFail("the virtual image is scalar") }
        XCTAssertEqual(state.resultPresentation.resultImage?.pixels, landedImage.pixels)
        XCTAssertNil(state.resultPresentation.imagingEntryRun, "a held image is re-shown, not re-run")
    }

    /// The same through the room switch (Go to Imaging), from a strain map.
    func testSelectingImagingAfterAStrainMapReshowsTheHeldVirtualImage() async throws {
        let state = await demoState()
        state.changeMode(.virtualDetector)
        _ = await state.runVirtualDetector()
        let landed = try XCTUnwrap(state.resultPresentation.product)
        state.strain.publish(strainMap())
        state.changeMode(.strain)
        state.resultPresentation.publish(product("strain_exx"))
        state.selectWorkspace(.image)
        await state.resultPresentation.imagingEntryRun?.value
        XCTAssertEqual(state.resultPresentation.product?.kind, landed.kind)
    }

    /// Nothing held for this dataset: one run with the live aperture fills the room.
    /// Mutation: clear instead of running -> nil, red.
    func testEnteringImagingWithNothingHeldRunsTheVirtualImageOnce() async throws {
        let state = await demoState()
        state.resultPresentation.holdVirtualImage(nil)
        state.resultPresentation.publish(product("acom_full_ipf_z"))
        state.changeMode(.virtualDetector)
        let run = try XCTUnwrap(state.resultPresentation.imagingEntryRun, "nothing held: Imaging must run once")
        await run.value
        XCTAssertTrue(state.resultPresentation.product?.kind.hasPrefix("virtual_") == true,
                      state.resultPresentation.product?.kind ?? "nil")
    }

    /// A held image for an aperture that is no longer the live one is not shown; the room runs instead.
    /// Mutation: drop the aperture comparison -> the old image is re-shown and no run starts, red.
    func testAHeldImageForAnotherApertureIsNotReshown() async throws {
        let state = await demoState()
        state.changeMode(.virtualDetector)
        _ = await state.runVirtualDetector()
        state.resultPresentation.imagingEntryRun = nil
        state.resultPresentation.publish(product("acom_full_ipf_z"))
        state.aperture.outer += 1
        state.changeMode(.virtualDetector)
        XCTAssertNotNil(state.resultPresentation.imagingEntryRun, "a stale held image must not be re-shown")
        await state.resultPresentation.imagingEntryRun?.value
    }

    /// No dataset and nothing held: another room's map goes, and nothing runs.
    func testEnteringImagingWithoutADatasetClearsAForeignMap() {
        let state = AppState()
        state.resultPresentation.publish(product("acom_full_ipf_z"))
        state.changeMode(.virtualDetector)
        XCTAssertNil(state.resultPresentation.product)
        XCTAssertNil(state.resultPresentation.imagingEntryRun)
    }

    /// No vectors held: entering Disks leaves a foreign product as today (nothing to re-show).
    func testEnteringDisksWithoutVectorsLeavesTheProduct() {
        let state = AppState()
        state.resultPresentation.publish(product("strain_exx"))
        state.changeMode(.disks)
        XCTAssertEqual(state.resultPresentation.product?.kind, "strain_exx")
    }
}
