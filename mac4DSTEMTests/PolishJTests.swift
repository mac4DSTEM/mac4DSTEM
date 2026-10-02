//
//  PolishJTests.swift
//  Lane J (Slot 4½ polish, 2026-10-02): entering a room never shows another room's product (owner card S5 a).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PolishJTests: XCTestCase {
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

    /// No vectors held: entering Disks leaves a foreign product as today (nothing to re-show).
    func testEnteringDisksWithoutVectorsLeavesTheProduct() {
        let state = AppState()
        state.resultPresentation.publish(product("strain_exx"))
        state.changeMode(.disks)
        XCTAssertEqual(state.resultPresentation.product?.kind, "strain_exx")
    }
}
