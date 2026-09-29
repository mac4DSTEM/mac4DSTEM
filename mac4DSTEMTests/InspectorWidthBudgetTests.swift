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
