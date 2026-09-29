//
//  InspectorWidthBudgetTests.swift
//  Every room's inspector settings must fit the inspector's narrowest column.
//  Gate D, 2026-09-29 (`docs/archive/v4/ai-room-narrow-crash-gateD-2026-09-29.md`):
//  one Phase-mapping row (label + 72-pt field + a fixed-size unit, 332 pt)
//  forced the inspector's minimum to 364 pt, and at a 915-pt window the split
//  view and the inspector invalidated each other until AppKit aborted. A row's
//  label, field and unit are `.fixedSize()`, so a row that does not fit cannot
//  shrink — it can only push the pane's minimum up. This asks each room's
//  settings view for its narrowest width and holds it to the column's.
//

import AppKit
import DSTEMCore
import DSTEMSession
import SwiftUI
import XCTest
@testable import mac4DSTEM

@MainActor
final class InspectorWidthBudgetTests: XCTestCase {

    /// `LayoutPolicy.inspectorWidth.min` (280) less the inspector's own 16-pt
    /// padding on each side (`WorkspaceInspector`'s `.padding()` on the
    /// settings tab). Both are Frozen Shell files; this reads, never edits.
    private let contentBudget: CGFloat = LayoutPolicy.inspectorWidth.min - 2 * 16

    /// The narrowest width the view can be laid out in: proposing 1 pt makes
    /// every compressible part shrink, so what comes back is the sum of the
    /// parts that will not (labels, fields, units).
    private func minimumWidth<V: View>(_ view: V, state: AppState) -> CGFloat {
        let host = NSHostingController(rootView: view.environment(state).environment(state.preferences))
        return host.sizeThatFits(in: CGSize(width: 1, height: 10_000)).width
    }

    private func assertFits(_ name: String, _ width: CGFloat,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(width, 10, "\(name): the probe measured nothing (\(width) pt)", file: file, line: line)
        XCTAssertLessThanOrEqual(
            width, contentBudget,
            "\(name): the settings need \(width) pt; the inspector's narrowest column gives \(contentBudget)",
            file: file, line: line)
    }

    private static let longName = "Al-Mg-Si_precipitate_beta-double-prime_mp-1234567.cif"

    private func runRecord(_ state: AppState) -> PhaseMappingProduct.RunRecord {
        PhaseMappingProduct.RunRecord(
            phaseSignature: state.phaseMapping.phaseSignature,
            reference: state.phaseMapping.reference, matching: state.phaseMapping.matching,
            libraryEntryCount: 1234, matrixEntryIndex: 0, matrixInPlaneDegrees: 12,
            worstChanceMatchPercent: 3.5, invAngstromPerPixel: 0.01,
            qScaleIsPhysical: true, peakCount: 100)
    }

    /// Mutations this must catch: the unit "Å⁻¹ (0 = detector)" back on
    /// "Ignore peaks beyond" (332 pt) — red in every case below; "Direct
    /// matrix up to (vectors)" or "Phase-specific reflections, at least"
    /// restored — red in the known-variants cases.
    func testPhaseMappingSettingsFitTheNarrowestColumn() {
        for rule in [PhaseVectorSettings.ClassificationRule.search, .knownVariants] {
            let state = AppState()
            state.phaseMapping.matching.classificationRule = rule
            assertFits("phase mapping, \(rule), no phases",
                       minimumWidth(PhaseMappingSections(), state: state))
            assertFits("phase mapping, \(rule), no phases, Advanced open",
                       minimumWidth(PhaseMappingSections(advancedExpanded: true), state: state))
        }
    }

    /// Mutation: the legend row's label back to `InspectorRow(row.label)`
    /// (fixed size) — red on the 53-character name.
    func testPhaseMappingWithThreePhasesAndALongNamedMapFitsTheNarrowestColumn() async {
        let state = AppState()
        state.phaseMapping.matching.classificationRule = .knownVariants
        let base = CrystalModelLibrary.models[0]
        let long = CrystalModel(id: "long", displayName: Self.longName, crystal: base.crystal,
                                symmetry: base.symmetry, source: .builtIn)
        state.addPhaseMappingSlot(base)
        state.addPhaseMappingSlot(CrystalModelLibrary.models[1])
        state.addPhaseMappingSlot(long)
        assertFits("phase mapping, known variants, 3 phases",
                   minimumWidth(PhaseMappingSections(), state: state))

        var map = PhaseMap(width: 8, height: 8, matrixEntryIndex: 0,
                           phaseNames: state.phaseMapping.phases.map(\.model.displayName),
                           matrixPhaseIndex: 0)
        for i in map.results.indices { map.results[i].verdict = .matrix; map.results[i].phaseIndex = 0 }
        for i in [18, 19, 26, 27] { map.results[i].verdict = .indexed; map.results[i].phaseIndex = 2 }
        state.phaseMapping.publish(map, ranWith: runRecord(state))
        assertFits("phase mapping, known variants, 3 phases + map with a long-named legend",
                   minimumWidth(PhaseMappingSections(), state: state))

        // The Precipitates section, which names each phase again.
        await state.publishPrecipitateClassificationFromPhaseMap()
        XCTAssertNotNil(state.precipitateObjectReport, "the object report never reached the panel")
        assertFits("… + the Precipitates section", minimumWidth(PhaseMappingSections(), state: state))

        // Stale: the phase list moved since the run.
        state.phaseMapping.phases[1].u = 1
        XCTAssertTrue(state.phaseMapping.isStale)
        assertFits("… and stale", minimumWidth(PhaseMappingSections(), state: state))
    }

    /// The Info tab's dataset and product sections with real, long data: a
    /// long file name and dataset path, and a displayed product whose
    /// provenance keys ("minimum_object_area_px", "objects_counted_rule")
    /// are row LABELS. Drive 4 (2026-09-29) aborted on switching to Info at a
    /// 915-pt window. Mutation: `InspectorValueRow`'s label back to
    /// `.fixedSize()` — red.
    func testInfoSectionsWithLongDataFitTheNarrowestColumn() async {
        let state = AppState()
        state.descriptor = DatasetDescriptor(
            filePath: "/Volumes/PL_SSD_2TB/ROI_5/Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712_ellipse-20260925.h5",
            datasetPath: "/4DSTEM_experiment/data/datacubes/datacube_root/datacube/data",
            shape: [171, 171, 128, 128], dtypeDescription: "float32", chunkShape: [1, 1, 128, 128])
        state.addPhaseMappingSlot(CrystalModelLibrary.models[0])
        state.addPhaseMappingSlot(CrystalModelLibrary.models[1])
        var map = PhaseMap(width: 8, height: 8, matrixEntryIndex: 0,
                           phaseNames: state.phaseMapping.phases.map(\.model.displayName),
                           matrixPhaseIndex: 0)
        for i in map.results.indices { map.results[i].verdict = .matrix; map.results[i].phaseIndex = 0 }
        for i in [18, 19, 26, 27] { map.results[i].verdict = .indexed; map.results[i].phaseIndex = 1 }
        state.phaseMapping.publish(map, ranWith: runRecord(state))
        await state.publishPrecipitateClassificationFromPhaseMap()
        state.publishPrecipitateObjectsProduct()
        XCTAssertEqual(state.displayedProduct?.kind, "precipitate_objects", "no product to describe")
        XCTAssertNotNil(state.displayedProduct?.provenance["objects_counted_rule"], "the long provenance key is gone")
        guard let descriptor = state.descriptor else { return XCTFail("no descriptor") }
        assertFits("Info: the dataset", minimumWidth(DatasetInfoSections(descriptor: descriptor), state: state))
        assertFits("Info: the displayed product", minimumWidth(ProductInfoSections(), state: state))
    }

    /// The inspector's live maximum leaves the sidebar (at its maximum) and
    /// both science panes at their floor inside every window from the
    /// minimum up. Drive 4 (2026-09-29): a fixed 460 dragged at 915 pt
    /// aborted. Mutation: `inspectorMaximum` returning `inspectorWidth.max`.
    func testTheInspectorMaximumFollowsTheWindow() {
        let floor = LayoutPolicy.datasetWindowMinimumSize.width
        XCTAssertEqual(LayoutPolicy.inspectorMaximum(windowWidth: floor, navigatorVisible: true),
                       LayoutPolicy.inspectorWidth.min, "at the floor beside the sidebar only the minimum fits")
        XCTAssertEqual(LayoutPolicy.inspectorMaximum(windowWidth: 1470, navigatorVisible: true),
                       LayoutPolicy.inspectorWidth.max, "a wide window keeps the ceiling")
        for width in stride(from: floor, through: 2000, by: 5) {
            for navigator in [true, false] {
                let inspector = LayoutPolicy.inspectorMaximum(windowWidth: width, navigatorVisible: navigator)
                let sidebar = navigator ? LayoutPolicy.sidebarWidth.max + LayoutPolicy.splitColumnDividerAllowance : 0
                XCTAssertGreaterThanOrEqual(inspector, LayoutPolicy.inspectorWidth.min)
                XCTAssertLessThanOrEqual(
                    sidebar + inspector + LayoutPolicy.splitColumnDividerAllowance + LayoutPolicy.scienceMinimum, width,
                    "at \(width) pt (sidebar \(navigator)) the widest inspector overflows the window")
            }
        }
    }

    /// The sidebar steps aside before the science panes fall under their
    /// comfortable width; with the inspector hidden it never has to at the
    /// window's minimum. Mutation: `navigatorFits` always true.
    func testTheSidebarStepsAsideBeforeThePanesGetCramped() {
        let needed = LayoutPolicy.sidebarWidth.ideal + LayoutPolicy.inspectorWidth.ideal
            + 2 * LayoutPolicy.splitColumnDividerAllowance
            + 2 * LayoutPolicy.sciencePaneComfortable + LayoutPolicy.sciencePaneDividerWidth
        XCTAssertTrue(LayoutPolicy.navigatorFits(windowWidth: needed, inspectorVisible: true))
        XCTAssertFalse(LayoutPolicy.navigatorFits(windowWidth: needed - 1, inspectorVisible: true))
        XCTAssertFalse(LayoutPolicy.navigatorFits(windowWidth: LayoutPolicy.datasetWindowMinimumSize.width,
                                                  inspectorVisible: true), "915 pt with the inspector: step aside")
        XCTAssertTrue(LayoutPolicy.navigatorFits(windowWidth: LayoutPolicy.datasetWindowMinimumSize.width,
                                                 inspectorVisible: false), "915 pt without it: room enough")
    }

    /// The width collapse is not the user's intent: showing the sidebar on a
    /// narrow window keeps it shown, hiding it records the intent, and the
    /// Show/Hide label follows what is on screen. Mutations: `navigatorIsVisible`
    /// ignoring the collapse; `toggleNavigator` not clearing it.
    func testShowingToolsOnANarrowWindowKeepsThemShown() {
        let navigation = WorkspaceNavigation()
        navigation.showToolsPane = true
        navigation.navigatorCollapsedForWidth = true
        XCTAssertFalse(navigation.navigatorIsVisible, "a narrow window hides the sidebar")
        XCTAssertTrue(navigation.showToolsPane, "…without touching the user's intent")
        navigation.toggleNavigator()
        XCTAssertTrue(navigation.navigatorIsVisible, "Show Tools on a narrow window shows it")
        XCTAssertFalse(navigation.navigatorCollapsedForWidth)
        navigation.toggleNavigator()
        XCTAssertFalse(navigation.navigatorIsVisible)
        XCTAssertFalse(navigation.showToolsPane, "Hide Tools records the intent")
    }

    /// The other rooms' settings views, hosted the same way. They are hosted
    /// with no dataset, so a row that only exists once data is loaded is not
    /// measured here; what renders is held to the same column.
    private func room<V: View>(_ name: String, _ mode: AnalysisMode?, _ view: V) {
        let state = AppState()
        if let mode { state.navigation.analysisMode = mode }
        assertFits(name, minimumWidth(view, state: state))
    }
    func testPrepareSettingsFitTheNarrowestColumn() { room("Prepare", nil, PrepareSettings()) }
    func testImagingSettingsFit() { room("Imaging", .virtualDetector, ImagingSettings()) }
    func testDiskDetectionSettingsFit() { room("Map / Disks", .disks, MapSettings()) }
    func testStrainSettingsFit() { room("Map / Strain", .strain, MapSettings()) }
    func testACOMSettingsFit() { room("Map / ACOM", .acom, MapSettings()) }
    func testDPCSettingsFit() { room("Reconstruct / DPC", .dpc, PhaseSettings()) }
    func testSingleslicePtychographySettingsFit() { room("Reconstruct / Single-slice", .singleslicePtychography, PhaseSettings()) }
    func testParallaxSettingsFit() { room("Reconstruct / Parallax", .ptychography, PhaseSettings()) }
    func testDiffractionGroupsSettingsFit() { room("AI / Diffraction groups", .diffractionGroups, AIAnalysisSettings()) }
    func testResultsSettingsFit() { room("Results", nil, ResultsSettings()) }
}
