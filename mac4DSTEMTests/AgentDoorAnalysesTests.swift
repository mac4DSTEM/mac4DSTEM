//
//  AgentDoorAnalysesTests.swift
//  The agent door's Strain, ACOM, Diffraction groups, Imaging and Reconstruction settings (AgentDoorAnalyses.swift, AgentDoorImaging.swift,
//  issues #224-#227), asked
//  through a real door over MCP: each tool writes the fields it is given and no other, answers in the same words it takes, and
//  says so in the Output.
//

import XCTest
import DSTEMCore
import DSTEMSession
import DiffractoOrientation
import ShellAgentDoor
@testable import mac4DSTEM

@MainActor
final class AgentDoorAnalysesTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private var root: URL!
    private let session = URLSession(configuration: .ephemeral)

    private static func cif(_ name: String, _ a: Double, _ b: Double, _ c: Double, _ atoms: String) -> String {
        """
        data_\(name)
        _cell_length_a \(a)
        _cell_length_b \(b)
        _cell_length_c \(c)
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        \(atoms)
        """
    }

    override func setUp() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("agent-analyses-\(UUID().uuidString)")
        root = scratch.appendingPathComponent("Agent")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.cif("gold", 4.078, 4.078, 4.078, "Au1 Au 0.0 0.0 0.0\nAu2 Au 0.5 0.5 0.0\nAu3 Au 0.5 0.0 0.5\nAu4 Au 0.0 0.5 0.5")
            .write(to: root.appendingPathComponent("gold.cif"), atomically: true, encoding: .utf8)
        try Self.cif("ortho", 5, 6, 7, "Fe1 Fe 0 0 0")
            .write(to: root.appendingPathComponent("ortho.cif"), atomically: true, encoding: .utf8)
        try "not a cif".write(to: root.appendingPathComponent("broken.cif"), atomically: true, encoding: .utf8)

        defaultsSuite = "agent-door-analyses-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.analysisTools + Mac4DSTEMAgentDoor.imagingTools
                      + Mac4DSTEMAgentDoor.precipitateTools + Mac4DSTEMAgentDoor.preprocessTools + Mac4DSTEMAgentDoor.resultTools)
        door.setEnabled(true)
        for _ in 0..<250 where door.status == .starting { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening = door.status else { return XCTFail("the door did not open: \(String(describing: door.status))") }
        Mac4DSTEMAgentDoor.folder.use(folder: root)
    }

    override func tearDown() async throws {
        Mac4DSTEMAgentDoor.folder.use(folder: nil)
        Mac4DSTEMAgentDoor.savesAllowed = false
        door?.setEnabled(false)
        door = nil
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        if let root { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    }

    private func call(_ name: String, _ arguments: [String: Any] = [:]) async throws -> (refused: Bool, text: String) {
        guard case .listening(let port) = door.status else { throw XCTSkip("door not open") }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/mcp")))
        request.httpMethod = "POST"
        request.setValue("Bearer \(door.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments],
        ])
        let (data, _) = try await session.data(for: request)
        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(answer["result"] as? [String: Any])
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        return (result["isError"] as? Bool ?? true, text)
    }

    private func enrolledState() -> AppState {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        door.runsAllowed = true
        return state
    }

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    /// Mutation: set_strain writes the wrong field, or a field not given moves - red.
    func testStrainFollowsTheAgent() async throws {
        let state = enrolledState()
        let set = try await call("set_strain", ["reference": "selectedRegion", "basis": "manual", "g1_x": 12.5, "component": "theta"])
        XCTAssertFalse(set.refused, set.text)
        XCTAssertEqual(state.strain.referenceMode, .selectedRegion)
        XCTAssertEqual(state.strain.basisMode, .manual)
        XCTAssertEqual(state.strain.g1X, 12.5, accuracy: 1e-6)
        XCTAssertEqual(state.strain.g2Y, 10, accuracy: 1e-6, "a field not given is left alone")
        XCTAssertEqual(state.strain.component, .theta)
        let answer = try object(set.text)
        XCTAssertEqual(answer["reference"] as? String, "selectedRegion", "the answer uses the words the call takes")
        XCTAssertTrue(answer["last_run"] is NSNull)
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains("An agent set Strain:") })
        let wrong = try await call("set_strain", ["component": "εxx"])
        XCTAssertTrue(wrong.refused, "a display name is not a choice")
        withExtendedLifetime(state) {}
    }

    /// Mutation: set_acom ignores a field, cannot clear the gate, or adds a CIF from outside the folder - red.
    func testACOMFollowsTheAgent() async throws {
        let state = enrolledState()
        let set = try await call("set_acom", ["phase_cif": "gold.cif", "scope": "fullScan", "quality": "best", "engine": "cpu",
                                              "refine_in_plane": true, "reliability_threshold": 0.4])
        XCTAssertFalse(set.refused, set.text)
        let acom = state.acomSession
        XCTAssertEqual(acom.scope, .fullScan)
        XCTAssertEqual(acom.quality, .best)
        XCTAssertEqual(acom.backend, .cpu)
        XCTAssertTrue(acom.refinesInPlaneAngle)
        XCTAssertEqual(try XCTUnwrap(acom.reliabilityThreshold), 0.4, accuracy: 1e-6)
        XCTAssertEqual(state.resolvedACOMModel?.displayName.isEmpty, false, "the CIF is ACOM's phase model")
        XCTAssertEqual(try object(set.text)["scope"] as? String, "fullScan")

        let cleared = try await call("set_acom", ["clear_reliability_threshold": true])
        XCTAssertFalse(cleared.refused, cleared.text)
        XCTAssertNil(acom.reliabilityThreshold)
        let outside = try await call("set_acom", ["phase_cif": "../gold.cif"])
        XCTAssertTrue(outside.refused)
        withExtendedLifetime(state) {}
    }

    /// Mutation: set_diffraction_groups writes the wrong field; find_similar_patterns runs with no grouping - red.
    func testDiffractionGroupsFollowTheAgent() async throws {
        let state = enrolledState()
        let set = try await call("set_diffraction_groups", ["binned_size": "32", "groups": 7])
        XCTAssertFalse(set.refused, set.text)
        XCTAssertEqual(state.diffractionGroups.settings.binnedSize, 32)
        XCTAssertEqual(state.diffractionGroups.settings.groups, 7)
        let tooMany = try await call("set_diffraction_groups", ["groups": 99])
        XCTAssertTrue(tooMany.refused)
        let similar = try await call("find_similar_patterns")
        XCTAssertTrue(similar.refused)
        XCTAssertTrue(similar.text.contains("no grouping"), similar.text)
        withExtendedLifetime(state) {}
    }

    /// Mutation: the detector's numbers skip the typed path, or set_imaging writes the wrong field - red.
    func testTheVirtualDetectorAndTheImagingViewFollowTheAgent() async throws {
        let state = enrolledState()
        await state.openDemoFixture()
        let set = try await call("set_virtual_detector", ["shape": "annulus", "center_x": 30, "center_y": 31, "inner": 4, "outer": 9])
        XCTAssertFalse(set.refused, set.text)
        XCTAssertEqual(state.resultPresentation.virtualShape, .annulus)
        XCTAssertEqual(Double(state.aperture.inner), 4, accuracy: 0.51)
        XCTAssertEqual(Double(state.aperture.outer), 9, accuracy: 0.51)
        let detector = try XCTUnwrap(try object(set.text)["detector"] as? [String: Any])
        XCTAssertEqual(detector["shape"] as? String, "annulus")

        let view = try await call("set_imaging", ["direction": "region", "region_shape": "circle", "region_radius": 3])
        XCTAssertFalse(view.refused, view.text)
        XCTAssertEqual(state.activePane, .realSpace)
        XCTAssertEqual(state.realSpaceShape, .circle)
        XCTAssertEqual(state.realSpaceRadius, 3, accuracy: 1e-6)
        withExtendedLifetime(state) {}
    }

    /// Mutation: set_reconstruction writes the wrong field, or a stage runs without what it needs - red.
    func testReconstructionFieldsAndStepsFollowTheAgent() async throws {
        let state = enrolledState()
        let set = try await call("set_reconstruction", ["ptycho_iterations": 12, "ptycho_pure_phase": true,
                                                        "parallax_kde_sigma_px": 0.25, "dpc_display": "angle"])
        XCTAssertFalse(set.refused, set.text)
        XCTAssertEqual(state.ptychography.iterations, 12)
        XCTAssertTrue(state.ptychography.purePhaseObject)
        XCTAssertEqual(state.phaseContrast.parallaxKDESigmaPixels, 0.25, accuracy: 1e-12)
        XCTAssertEqual(state.dpc.dpcDisplay, .angle)
        XCTAssertEqual(state.ptychography.stepSize, 0.5, accuracy: 1e-6, "a field not given is left alone")
        XCTAssertEqual(try object(set.text)["ptycho_iterations"] as? Int, 12)

        let noData = try await call("run_reconstruction_step", ["step": "use_parallax_fit"])
        XCTAssertTrue(noData.refused, "no dataset")
        await state.openDemoFixture()
        let noFit = try await call("run_reconstruction_step", ["step": "use_parallax_fit"])
        XCTAssertTrue(noFit.refused)
        XCTAssertTrue(noFit.text.contains("no parallax aberration fit"), noFit.text)
        withExtendedLifetime(state) {}
    }

    private func publishFixtureMap(_ state: AppState) async {
        var map = PhaseMap(width: 6, height: 6, matrixEntryIndex: 0, phaseNames: ["Al", "T1"], matrixPhaseIndex: 0)
        for i in map.results.indices { map.results[i].verdict = .matrix; map.results[i].phaseIndex = 0 }
        for (r, c) in [(1, 1), (1, 2), (2, 1), (2, 2)] { map.results[r * 6 + c].verdict = .indexed; map.results[r * 6 + c].phaseIndex = 1 }
        state.phaseMapping.publish(map, ranWith: PhaseMappingProduct.RunRecord(
            phaseSignature: "fixture", reference: PhaseReferenceSettings(), matching: PhaseVectorSettings(), libraryEntryCount: 1,
            matrixEntryIndex: 0, matrixInPlaneDegrees: .nan, worstChanceMatchPercent: 0, invAngstromPerPixel: 0.01,
            qScaleIsPhysical: false, peakCount: 0,
            calibration: PhaseMappingProduct.CalibrationStamp(calibration: Calibration(), referenceOrigin: (0, 0))))
        await state.publishPrecipitateClassificationFromPhaseMap()
    }

    /// Mutation: set_precipitates runs without a map, writes the wrong field, or the CSV replaces a file - red.
    func testPrecipitatesFollowTheAgentAndTheCSVIsANewFile() async throws {
        let state = enrolledState()
        let early = try await call("set_precipitates", ["labels": true])
        XCTAssertTrue(early.refused, "no phase map yet")
        await publishFixtureMap(state)
        let set = try await call("set_precipitates", ["labels": true, "on_panes": true, "minimum_size_px": 3,
                                                      "thickness_nm": 80, "thickness_source": "CBED fringes", "show": "objects"])
        XCTAssertFalse(set.refused, set.text)
        XCTAssertTrue(state.precipitateOverlay.labels)
        XCTAssertTrue(state.precipitateOverlay.onPanes)
        XCTAssertEqual(state.precipitateClassification.minimumObjectAreaPx, 3)
        XCTAssertEqual(try XCTUnwrap(state.precipitateThickness?.nanometres), 80, accuracy: 1e-12)
        XCTAssertEqual(state.precipitateThickness?.source, "CBED fringes")
        let cleared = try await call("set_precipitates", ["clear_thickness": true])
        XCTAssertFalse(cleared.refused, cleared.text)
        XCTAssertNil(state.precipitateThickness)

        let off = try await call("export_precipitates_csv", ["name": "objects"])
        XCTAssertTrue(off.refused, "saving is off")
        Mac4DSTEMAgentDoor.savesAllowed = true
        let saved = try await call("export_precipitates_csv", ["name": "objects"])
        XCTAssertFalse(saved.refused, saved.text)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("objects.csv").path))
        let again = try await call("export_precipitates_csv", ["name": "objects"])
        XCTAssertTrue(again.refused, "never replaced")
        withExtendedLifetime(state) {}
    }

    /// Mutation: preprocess writes without being told where, replaces a file, or ignores the binning - red.
    func testPreprocessingWritesANewReducedCopyWhereItIsTold() async throws {
        let state = enrolledState()
        let none = try await call("preprocess", ["detector_bin": 2, "name": "binned"])
        XCTAssertTrue(none.refused, "no dataset")
        await state.openDemoFixture()
        let nowhere = try await call("preprocess", ["detector_bin": 2])
        XCTAssertTrue(nowhere.refused)
        XCTAssertTrue(nowhere.text.contains("Say where"), nowhere.text)
        let off = try await call("preprocess", ["detector_bin": 2, "name": "binned"])
        XCTAssertTrue(off.refused, "saving is off")
        let tooBig = try await call("preprocess", ["scan_width": 100_000, "name": "binned"])
        XCTAssertTrue(tooBig.refused, "a crop that does not fit")

        Mac4DSTEMAgentDoor.savesAllowed = true
        let started = try await call("preprocess", ["detector_bin": 2, "name": "binned"])
        XCTAssertFalse(started.refused, started.text)
        XCTAssertEqual(try object(started.text)["detector_bin"] as? Int, 2)
        XCTAssertEqual(try object(started.text)["writing"] as? String, "binned.h5")
        for _ in 0..<600 where state.isBusy { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("binned.h5").path),
                      "\(state.activityLog.messages.suffix(3))")
        let again = try await call("preprocess", ["detector_bin": 2, "name": "binned"])
        XCTAssertTrue(again.refused, "never replaced")

        let nothingPending = try await call("set_open_options", ["detector_bin": 2, "action": "load"])
        XCTAssertTrue(nothingPending.refused)
        withExtendedLifetime(state) {}
    }

    /// Mutation: export_result writes outside the rules (saving off, a replaced file, an unknown panel), the quality toggle does not
    /// follow, or a comparison loads a result the session does not have - red.
    func testResultsAreExportedComparedAndKeptAsTold() async throws {
        let state = enrolledState()
        await state.openDemoFixture()
        let off = try await call("export_result", ["what": "figure", "figure_panels": "pattern", "name": "fig"])
        XCTAssertTrue(off.refused, "saving is off")
        Mac4DSTEMAgentDoor.savesAllowed = true
        let unknown = try await call("export_result", ["what": "figure", "figure_panels": "nothing", "name": "fig"])
        XCTAssertTrue(unknown.refused, unknown.text)
        let figure = try await call("export_result", ["what": "figure", "figure_panels": "pattern", "figure_format": "png",
                                                      "name": "fig"])
        XCTAssertFalse(figure.refused, figure.text)
        XCTAssertEqual(state.preferences.figureFormat, .png)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("fig.png").path))
        let again = try await call("export_result", ["what": "figure", "figure_panels": "pattern", "figure_format": "png",
                                                     "name": "fig"])
        XCTAssertTrue(again.refused, "never replaced")

        let none = try await call("show_quality_field", ["show": true])
        XCTAssertTrue(none.refused, "the demo's view carries no quality field: \(none.text)")
        XCTAssertFalse(state.resultPresentation.inspectQualityField)
        let hidden = try await call("show_quality_field", ["show": false])
        XCTAssertFalse(hidden.refused, hidden.text)

        let missing = try await call("compare_results", ["a": "no such result"])
        XCTAssertTrue(missing.refused, missing.text)
        let rewind = try await call("rewind_lineage", ["step": "no such step"])
        XCTAssertTrue(rewind.refused, rewind.text)
        withExtendedLifetime(state) {}
    }
}
