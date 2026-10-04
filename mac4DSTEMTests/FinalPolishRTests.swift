//
//  FinalPolishRTests.swift
//  Lane R (Slot 4⅞ polish, 2026-10-04): a room shows its own result on entry.
//  P4a — the opening pass is Prepare's pass (the virtual image), whatever task is remembered; a task
//        belonging to the destination room is presented on entry through `selectWorkspace` as it is
//        through `changeMode`.
//  P4b — Diffraction groups re-shows its own map from the retained result and the settings it ran with.
//  Each test names the mutation it catches.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class FinalPolishRTests: XCTestCase {

    // MARK: - Fixtures

    private func stub(_ kind: String) -> DisplayedProduct {
        DisplayedProduct(
            kind: kind, displayName: kind,
            payload: .scalar(FloatImage(width: 2, height: 2, pixels: [0, 0, 0, 0])), domain: .scan,
            validityMask: nil, qualityFields: [],
            sampling: ProductSampling(row: nil, column: nil, units: nil),
            valueUnits: "x", quantitativeStatus: .relative, provenance: [:], overlays: [])
    }

    private func strainMap(width: Int, height: Int) -> StrainMap {
        let n = width * height
        let z = [Float](repeating: 0, count: n)
        let diag = StrainFitDiagnostics(
            automaticBasis: false, referenceMaskApplied: false, basisObservationCount: 0, basisSupportCount: 0,
            basisSupportFraction: 0, basisResidualPixels: 0, basisConditionNumber: 1, indexingTolerancePixels: 1,
            localResidualMedianPixels: 0, referenceCandidateCount: 0, referenceRejectedCount: 0)
        return StrainMap(width: width, height: height, exx: z, eyy: z, exy: z, theta: z,
                         mask: [Bool](repeating: true, count: n), localG1x: z, localG1y: z, localG2x: z, localG2y: z,
                         localResidualPixels: z, refG1: (x: 1, y: 0), refG2: (x: 0, y: 1),
                         referencePositionCount: 1, indexedFraction: 1, diagnostics: diag)
    }

    /// A 2 × 2 grouping with one component and two groups (groupCount = centroids / components = 2).
    private func groupsResult() -> DiffractionEmbedding.Result {
        DiffractionEmbedding.Result(
            scanWidth: 2, scanHeight: 2, coordinates: [0, 1, 1, 0], mean: [0], basis: [1],
            explainedVariance: [0.5], groupOf: [0, 1, 1, 0], groupCentroids: [0, 1])
    }

    private var groupsSettings: DiffractionEmbedding.Settings {
        DiffractionEmbedding.Settings(binnedSize: 8, components: 4, groups: 3, seed: 7)
    }

    /// A state holding a grouping result and a foreign product on screen under Prepare.
    private func stateWithGroupsResultAndForeignProduct(_ foreign: String) -> AppState {
        let state = AppState()
        state.diffractionGroups.publish(groupsResult(), ranWith: groupsSettings)
        state.resultPresentation.publish(stub(foreign))
        return state
    }

    private var smallCrop: LoadSpecification {
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        return spec
    }

    // MARK: - P4a: the opening pass is Prepare's pass

    /// The reproducing observation (HEAD): a cube opened while DPC is the remembered task ran the whole-scan CoM
    /// pass and put the DPC product in Prepare. Real open path.
    /// Mutation it catches: `runOpeningAnalysis` calling `runCurrentAnalysis()` (the remembered task's pass).
    func testACubeOpenedUnderTheDPCTaskShowsTheVirtualImageAndRunsNoDPC() async throws {
        let state = AppState()
        state.navigation.analysisMode = .dpc
        await state.openDemoFixture()

        XCTAssertEqual(state.navigation.workspaceArea, .prepare)
        XCTAssertEqual(state.navigation.analysisMode, .dpc, "the remembered task is kept")
        let kind = try XCTUnwrap(state.resultPresentation.product?.kind, state.statusText)
        XCTAssertTrue(kind.hasPrefix("virtual_"), "Prepare shows the virtual image, not \(kind)")
        XCTAssertTrue(state.comField == nil, "no whole-scan DPC pass at open")
    }

    /// Restored Bragg vectors under the Disks task put a detector-domain map and the SCAN inset into Prepare.
    /// Mutation it catches: the opening pass re-showing the Bragg map for the remembered Disks task.
    func testOpeningUnderBraggDisksWithHeldVectorsShowsTheVirtualImage() async throws {
        let state = AppState()
        await state.openDemoFixture()
        let d = try XCTUnwrap(state.descriptor)
        let peaks = [[BraggPeak(x: 3, y: 4, intensity: 1)]] + [[BraggPeak]](repeating: [], count: d.rx * d.ry - 1)
        state.resultPresentation.setBraggVectors(BraggVectors(scanWidth: d.rx, scanHeight: d.ry, peaks: peaks))
        state.navigation.analysisMode = .disks

        await state.runOpeningAnalysis()

        let product = try XCTUnwrap(state.resultPresentation.product)
        XCTAssertTrue(product.kind.hasPrefix("virtual_"), "Prepare shows the virtual image, not \(product.kind)")
        XCTAssertEqual(product.domain, .scan)
        XCTAssertEqual(state.navigation.analysisMode, .disks, "the remembered task is kept")
        XCTAssertNotNil(state.resultPresentation.braggVectors, "nothing held is dropped")
    }

    /// A strain map a sidecar restored is not shown in Prepare at open.
    /// Mutation it catches: the opening pass re-showing the strain map for the remembered Strain task.
    func testOpeningUnderStrainWithAHeldMapShowsTheVirtualImage() async throws {
        let state = AppState()
        await state.openDemoFixture()
        let d = try XCTUnwrap(state.descriptor)
        state.strain.publish(strainMap(width: d.rx, height: d.ry))
        state.navigation.analysisMode = .strain

        await state.runOpeningAnalysis()

        let kind = try XCTUnwrap(state.resultPresentation.product?.kind)
        XCTAssertTrue(kind.hasPrefix("virtual_"), "Prepare shows the virtual image, not \(kind)")
        XCTAssertNotNil(state.strain.map, "nothing held is dropped")
    }

    /// The promote's re-establishing pass is the same pass.
    /// Mutation it catches: `runOpeningAnalysis` running the remembered DPC task on the promoted view.
    func testAPromoteUnderTheDPCTaskReEstablishesTheVirtualImageAndRunsNoDPC() async throws {
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 2, xOffset: 3, height: 6, width: 6)
        let state = AppState()
        await state.openDemoFixture(specification: spec)
        state.navigation.analysisMode = .dpc

        await state.promoteToFullExtent()

        XCTAssertTrue(state.loadedView.isFullExtent, "precondition: the promote ran")
        let kind = try XCTUnwrap(state.resultPresentation.product?.kind, state.statusText)
        XCTAssertTrue(kind.hasPrefix("virtual_"), "Prepare shows the virtual image, not \(kind)")
        XCTAssertTrue(state.comField == nil, "no whole-scan DPC pass on the promoted view")
        XCTAssertEqual(state.navigation.analysisMode, .dpc, "the remembered task is kept")
    }

    // MARK: - selectWorkspace presents the entered room

    /// Mutation it catches: dropping the new `else if` branch of `selectWorkspace` (the virtual image stays under Crystal Maps).
    func testSelectingTheRoomOfTheCurrentTaskReShowsItsOwnResult() {
        let state = AppState()
        state.strain.publish(strainMap(width: 2, height: 2))
        state.navigation.analysisMode = .strain
        state.navigation.workspaceArea = .prepare
        state.resultPresentation.publish(stub("virtual_annulus"))

        state.selectWorkspace(.map)

        XCTAssertEqual(state.navigation.workspaceArea, .map)
        XCTAssertEqual(state.resultPresentation.product?.kind, "strain_exx")
    }

    /// No result of its own: the other room's product is cleared, as `changeMode` does.
    /// Mutation it catches: dropping the new `else if` branch.
    func testSelectingTheRoomOfTheCurrentTaskWithoutAResultClearsTheForeignProduct() {
        let state = AppState()
        state.navigation.analysisMode = .acom
        state.navigation.workspaceArea = .prepare
        state.resultPresentation.publish(stub("virtual_annulus"))

        state.selectWorkspace(.map)

        XCTAssertNil(state.resultPresentation.product)
    }

    /// The call is idempotent: the room's own product is the same object afterwards.
    /// Mutation it catches: a selectWorkspace that re-publishes (or clears) an own product.
    func testSelectingTheRoomAgainLeavesItsOwnProductAlone() {
        let state = AppState()
        state.strain.publish(strainMap(width: 2, height: 2))
        state.navigation.analysisMode = .strain
        state.navigation.workspaceArea = .map
        state.resultPresentation.publish(stub("strain_exy"))
        let version = state.resultPresentation.resultVersion

        state.selectWorkspace(.map)

        XCTAssertEqual(state.resultPresentation.product?.kind, "strain_exy")
        XCTAssertEqual(state.resultPresentation.resultVersion, version)
    }

    /// Prepare and Results own no task: presenting "the current task" there would re-show a map in Prepare.
    /// Mutation it catches: the `!area.analysisModes.isEmpty` condition dropped.
    func testSelectingATasklessRoomPresentsNothing() {
        let state = AppState()
        state.strain.publish(strainMap(width: 2, height: 2))
        state.navigation.analysisMode = .strain
        state.navigation.workspaceArea = .map
        state.resultPresentation.publish(stub("virtual_annulus"))
        let version = state.resultPresentation.resultVersion

        state.selectWorkspace(.prepare)
        XCTAssertEqual(state.resultPresentation.product?.kind, "virtual_annulus")
        state.selectWorkspace(.results)
        XCTAssertEqual(state.resultPresentation.product?.kind, "virtual_annulus")
        XCTAssertEqual(state.resultPresentation.resultVersion, version)
    }

    /// Imaging under the Diffraction groups task re-shows the grouping map (P4b through the menu path).
    /// Mutation it catches: either new branch dropped (selectWorkspace's, or the groups republish).
    func testSelectingImagingUnderTheGroupsTaskReShowsTheGroupMap() {
        let state = stateWithGroupsResultAndForeignProduct("virtual_annulus")
        state.navigation.analysisMode = .diffractionGroups
        state.navigation.workspaceArea = .prepare

        state.selectWorkspace(.image)

        XCTAssertEqual(state.resultPresentation.product?.kind, "diffraction_groups")
    }

    /// Imaging under the virtual-detector task leaves the virtual image (its own product has no owner).
    /// Mutation it catches: a clear-everything-foreign rule reaching the virtual detector's room.
    func testSelectingImagingUnderTheVirtualDetectorTaskLeavesTheImage() {
        let state = AppState()
        state.navigation.analysisMode = .virtualDetector
        state.navigation.workspaceArea = .prepare
        state.resultPresentation.publish(stub("virtual_annulus"))

        state.selectWorkspace(.image)

        XCTAssertEqual(state.resultPresentation.product?.kind, "virtual_annulus")
    }

    // MARK: - Fix round: the room's own virtual image survives entering the room

    /// The refuter's reproducing observation: a cube opened under the remembered Diffraction groups task shows the
    /// virtual image in Prepare; entering Imaging from the sidebar must not clear it — it is Imaging's own image and
    /// nothing re-shows it (`presentProductForEnteredMode` has no `.virtualDetector` case). Real open path.
    /// Mutation it catches: the groups branch's no-result clear not sparing a `virtual_` product.
    func testImagingEnteredFromTheSidebarUnderTheGroupsTaskAfterOpenKeepsTheVirtualImage() async throws {
        let state = AppState()
        state.navigation.analysisMode = .diffractionGroups
        await state.openDemoFixture()
        let before = try XCTUnwrap(state.resultPresentation.product?.kind, state.statusText)
        XCTAssertTrue(before.hasPrefix("virtual_"), "precondition: Prepare shows the virtual image, not \(before)")

        state.selectWorkspace(.image)

        XCTAssertEqual(state.navigation.workspaceArea, .image)
        XCTAssertEqual(state.navigation.analysisMode, .diffractionGroups, "the remembered task is kept")
        XCTAssertEqual(state.resultPresentation.product?.kind, before, "Imaging's own image survives entering Imaging")
        state.selectWorkspace(.prepare)
        XCTAssertEqual(state.resultPresentation.product?.kind, before, "and Prepare still has its image")
    }

    /// Entering Diffraction groups with no result clears another room's map (owner card S5 (2)) but not the virtual
    /// image, which is the Imaging room's own (the task picker's Virtual detector -> Group Patterns, the menu path).
    /// Mutations it catches: the clear sparing every product (the strain map stays); sparing none (the image goes).
    func testEnteringDiffractionGroupsWithoutAResultClearsAForeignMapButNotTheVirtualImage() {
        let strain = AppState()
        strain.resultPresentation.publish(stub("strain_exx"))
        strain.changeMode(.diffractionGroups)
        XCTAssertNil(strain.resultPresentation.product, "a strain map is another room's: cleared")

        let image = AppState()
        image.resultPresentation.publish(stub("virtual_annulus"))
        let version = image.resultPresentation.resultVersion
        image.changeMode(.diffractionGroups)
        XCTAssertEqual(image.resultPresentation.product?.kind, "virtual_annulus")
        XCTAssertEqual(image.resultPresentation.resultVersion, version, "untouched")
    }

    /// A four-component fixture, so the explained-variance sum can tell its first three components from its first
    /// two or four (the one-component fixture above cannot), and the republished pixels are pinned to the group
    /// indices (the round-trip test compares the republish with the run — both from the same function).
    /// Mutations it catches: `prefix(3)` -> `prefix(2)` ("75.0") / `prefix(4)` ("93.8"); the payload a zero map.
    func testTheRepublishedGroupMapSumsThreeComponentsAndCarriesTheGroupIndices() throws {
        let state = AppState()
        let result = DiffractionEmbedding.Result(
            scanWidth: 2, scanHeight: 2, coordinates: [Float](repeating: 0, count: 16), mean: [0],
            basis: [1, 1, 1, 1], explainedVariance: [0.5, 0.25, 0.125, 0.0625],
            groupOf: [0, 1, 1, 0], groupCentroids: [Float](repeating: 0, count: 8))
        state.diffractionGroups.publish(
            result, ranWith: DiffractionEmbedding.Settings(binnedSize: 8, components: 4, groups: 2, seed: 7))
        state.resultPresentation.publish(stub("strain_exx"))

        state.changeMode(.diffractionGroups)

        let product = try XCTUnwrap(state.resultPresentation.product)
        XCTAssertEqual(product.kind, "diffraction_groups")
        XCTAssertEqual(product.provenance["explained_variance_first3_percent"], "87.5")
        XCTAssertEqual(product.provenance["components"], "4")
        guard case .scalar(let image) = product.payload else { return XCTFail("scalar payload expected") }
        XCTAssertEqual(image.pixels, [0, 1, 1, 0], "the group indices, not another map of the same size")
    }

    // MARK: - P4b: Diffraction groups re-shows its own map

    /// Strain on screen after a grouping run: entering Diffraction groups shows the group map, named for the run,
    /// categorical, on the viridis map (a Strain map left RdBu on the shared colormap).
    /// Mutations it catches: the `.diffractionGroups` branch a no-op (the strain product stays); the `.viridis`
    /// assignment dropped (RdBu on a categorical map).
    func testEnteringDiffractionGroupsWithAResultReShowsTheGroupMap() throws {
        let state = stateWithGroupsResultAndForeignProduct("strain_exx")
        state.resultPresentation.resultColormap = .rdbu

        state.changeMode(.diffractionGroups)

        let product = try XCTUnwrap(state.resultPresentation.product)
        XCTAssertEqual(product.kind, "diffraction_groups")
        XCTAssertEqual(product.displayName, DiffractionGroupsProduct.groupMapDisplayName(groups: 2))
        XCTAssertEqual(product.domain, .scan)
        XCTAssertEqual(product.valueUnits, "group")
        XCTAssertEqual(product.provenance["quantitative_status"], "categorical")
        XCTAssertEqual(state.resultPresentation.resultColormap, .viridis)
        XCTAssertEqual(product.payload.dimensions.width, 2)
        XCTAssertEqual(product.payload.dimensions.height, 2)
    }

    /// The republished provenance names the settings the RESULT was computed with, not the panel's live ones.
    /// Mutation it catches: the republish reading `diffractionGroups.settings` instead of `lastRunSettings`.
    func testTheRepublishedGroupMapNamesTheSettingsTheResultRanWith() throws {
        let state = stateWithGroupsResultAndForeignProduct("strain_exx")
        state.diffractionGroups.settings.seed = 99            // edited since the run
        state.diffractionGroups.settings.binnedSize = 32

        state.changeMode(.diffractionGroups)

        let provenance = try XCTUnwrap(state.resultPresentation.product?.provenance)
        XCTAssertEqual(provenance["binned_size"], "8")
        XCTAssertEqual(provenance["seed"], "7")
        XCTAssertEqual(provenance["components"], "1", "the ACTUAL component count of the result")
        XCTAssertEqual(provenance["groups"], "2", "the ACTUAL group count of the result")
        XCTAssertEqual(provenance["explained_variance_first3_percent"], "50.0")
        XCTAssertEqual(provenance["analysis_mode"], AnalysisMode.diffractionGroups.rawValue)
    }

    /// A grouping or similarity map already on screen is left alone (the same guard as the phase-mapping branch):
    /// entering the room must not overwrite a similarity map with the group map.
    /// Mutation it catches: the own-kind guard dropped (the similarity map is replaced, the version bumps).
    func testEnteringDiffractionGroupsLeavesAGroupOrSimilarityMapAlone() {
        for kind in ["diffraction_similarity", "diffraction_groups"] {
            let state = stateWithGroupsResultAndForeignProduct(kind)
            let version = state.resultPresentation.resultVersion

            state.changeMode(.diffractionGroups)

            XCTAssertEqual(state.resultPresentation.product?.kind, kind, kind)
            XCTAssertEqual(state.resultPresentation.resultVersion, version, "\(kind): untouched")
        }
    }

    /// Through the real run on the demo cube: the republish after a room round trip equals what the run published,
    /// key for key (lineage_step included), and the run itself now leaves the viridis map.
    /// Mutations it catches: a republish that builds its provenance differently from the run's; the `.viridis`
    /// assignment dropped (the run after a Strain map left RdBu); no republish at all (nil after the round trip).
    func testTheRepublishAfterARoomRoundTripEqualsTheRunsOwnPublish() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: smallCrop)
        state.navigation.analysisMode = .diffractionGroups
        state.resultPresentation.resultColormap = .rdbu       // what a Strain run leaves behind

        let outcome = await state.runDiffractionGroups()
        XCTAssertEqual(outcome, .published, state.statusText)
        let original = try XCTUnwrap(state.resultPresentation.product)
        XCTAssertEqual(original.kind, "diffraction_groups")
        XCTAssertEqual(state.resultPresentation.resultColormap, .viridis, "the run leaves the categorical map on viridis")
        XCTAssertNotNil(original.provenance["lineage_step"], "precondition: the run named its node")

        state.changeMode(.strain)                              // no strain result: the room clears the groups map
        XCTAssertNil(state.resultPresentation.product, "precondition: the other room dropped it")
        state.diffractionGroups.settings.seed += 1             // the panel moved on; the result did not
        state.changeMode(.diffractionGroups)

        let again = try XCTUnwrap(state.resultPresentation.product, "the group map is back on re-entry")
        XCTAssertEqual(again.kind, original.kind)
        XCTAssertEqual(again.displayName, original.displayName)
        XCTAssertEqual(again.provenance, original.provenance)
        XCTAssertEqual(again.sampling.units, original.sampling.units)
        XCTAssertEqual(again.sampling.row, original.sampling.row)
        guard case .scalar(let a) = again.payload, case .scalar(let o) = original.payload else {
            return XCTFail("scalar payloads expected")
        }
        XCTAssertEqual(a.pixels, o.pixels, "the same group indices")
    }
}
