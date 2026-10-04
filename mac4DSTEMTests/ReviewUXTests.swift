//
//  ReviewUXTests.swift
//  Lane F (Slot 4¾ pre-release review, 2026-10-02): first-run UX and claims on exports
//  (findings e2, e3, e6, e7, e9, b2, b3). Each test names the mutation that turns it red.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ReviewUXTests: XCTestCase {

    // MARK: - e2: Add Phase › From CIF adds the model it parsed, never `.last`

    private func cif(name: String, a: Double) -> String {
        """
        data_\(name)
        _cell_length_a \(a)
        _cell_length_b \(a)
        _cell_length_c \(a)
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        X1 Al 0.0 0.0 0.0
        X2 Al 0.5 0.5 0.0
        X3 Al 0.5 0.0 0.5
        X4 Al 0.0 0.5 0.5
        """
    }

    private func write(_ text: String, named baseName: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-ux-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(baseName).cif")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A refusal returns nil, so the caller adds nothing.
    /// Mutation: `return acomSession.importedCrystalModels.last` in the catch -> returns the earlier model.
    func testARefusedCIFImportReturnsNilAndLeavesTheListAlone() throws {
        let state = AppState()
        let good = try XCTUnwrap(state.importCrystalModel(from: try write(cif(name: "Al", a: 4.05), named: "Al")))
        XCTAssertEqual(good.id, "imported_Al")
        // Two data_ blocks: a shipped refusal (CIFMultiBlockTests).
        let refused = try write(cif(name: "a", a: 4.0) + "\n" + cif(name: "b", a: 5.0), named: "two")
        XCTAssertNil(state.importCrystalModel(from: refused))
        XCTAssertEqual(state.acomSession.importedCrystalModels.map(\.id), ["imported_Al"])
        XCTAssertNotNil(state.errorMessage, "the refusal still reaches the modal")
    }

    /// Re-importing an edited CIF replaces index 0 in place; the returned model is that one, not the list's last.
    /// Mutation: `return acomSession.importedCrystalModels.last` on success -> the other model (red).
    func testReimportingAnEditedCIFReturnsThatModelNotTheLastOne() throws {
        let state = AppState()
        _ = state.importCrystalModel(from: try write(cif(name: "Al", a: 4.05), named: "Al"))
        let other = try XCTUnwrap(state.importCrystalModel(from: try write(cif(name: "Beta", a: 6.0), named: "Beta")))
        XCTAssertEqual(state.acomSession.importedCrystalModels.last?.id, other.id)

        let again = try XCTUnwrap(state.importCrystalModel(from: try write(cif(name: "Al", a: 4.10), named: "Al")))
        XCTAssertEqual(again.id, "imported_Al", "the replaced model, not `.last`")
        XCTAssertNotEqual(again.id, state.acomSession.importedCrystalModels.last?.id)
        XCTAssertEqual(state.acomSession.importedCrystalModels.count, 2)
        // What the view does with the result: add exactly it.
        state.addPhaseMappingSlot(again)
        XCTAssertEqual(state.phaseMapping.phases.map(\.model.id), ["imported_Al"])
    }

    // MARK: - e3: an offline Materials Project fetch is one plain line

    private struct ThrowingTransport: MaterialsProjectTransport {
        let error: Error
        func data(for request: URLRequest) async throws -> (Data, URLResponse) { throw error }
    }

    /// Mutation: restore `String(describing: error)` in describeFetchError -> the NSURLErrorDomain dump.
    func testAnOfflineFetchIsAPlainSentence() async {
        let state = AppState(materialsProject: MaterialsProjectSettings(store: InMemoryAPIKeyStore(initial: "k")))
        let outcome = await state.fetchMaterialsProject(
            materialID: "mp-134", expectation: PhaseExpectation(formula: "Al", spaceGroupNumber: 225),
            transport: ThrowingTransport(error: URLError(.notConnectedToInternet)))
        guard case .failure(let message) = outcome else { return XCTFail("expected .failure, got \(outcome)") }
        XCTAssertFalse(message.contains("NSURLErrorDomain"), message)
        XCTAssertFalse(message.contains("UserInfo"), message)
        XCTAssertTrue(message.contains("materialsproject.org"), message)
    }

    /// The other network codes share the line; an unmapped URLError uses its localized text, not a dump.
    /// Mutations: drop `.timedOut` from the case list -> no "materialsproject.org" (red); `String(describing:)` as the URLError fallback -> the dump (red).
    func testOtherNetworkCodesAndTheLocalizedFallback() {
        for code in [URLError.Code.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost] {
            XCTAssertTrue(AppState.describeFetchError(URLError(code)).contains("materialsproject.org"), "\(code)")
        }
        // A system URLError carries NSLocalizedDescription; a bare synthetic one only the generic
        // "(NSURLErrorDomain error -1011.)" text, which is not the production shape.
        let sentence = "The server returned a bad response."
        let other = AppState.describeFetchError(URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: sentence]))
        XCTAssertEqual(other, sentence)
    }

    // MARK: - e6: ⌘R follows readiness; a refused run says why

    /// Phase mapping with no phase: the menu predicate is false (the toolbar's Map Phases is disabled for the same reason).
    /// Mutation: drop the readiness `guard` in canRunPrimaryWorkspaceTask -> true (red).
    func testRunCurrentTaskIsDisabledWhenTheTasksRequirementsAreUnmet() async {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.navigation.workspaceArea = .map
        state.navigation.analysisMode = .phaseMapping
        XCTAssertNotNil(state.phaseMapping.runRefusal, "premise: no phase added")
        XCTAssertTrue(state.hasPrimaryWorkspaceTask, "Map Phases has a verb in this room")
        XCTAssertFalse(state.canRunPrimaryWorkspaceTask)
    }

    /// Results has no verb; Image (Group Patterns) needs only the cube — the virtual detector has no verb since the
    /// owner's card Q7 a (`FinalPolishFTests`). Mutation: drop `hasPrimaryWorkspaceTask` from the guard -> Results true.
    func testRunCurrentTaskNeedsAVerbAndADataset() async {
        let state = AppState()
        XCTAssertFalse(state.canRunPrimaryWorkspaceTask, "no dataset")
        await state.openDemoFixture(calibrated: false)
        state.navigation.workspaceArea = .image
        state.navigation.analysisMode = .diffractionGroups
        XCTAssertTrue(state.canRunPrimaryWorkspaceTask)
        state.navigation.workspaceArea = .results
        XCTAssertFalse(state.hasPrimaryWorkspaceTask)
        XCTAssertFalse(state.canRunPrimaryWorkspaceTask)
    }

    /// A programmatic run that is refused puts the reason in the status line (it used to return it unseen).
    /// Mutation: drop the `statusText = reason` line -> statusText unchanged (red).
    func testARefusedPrimaryRunPutsItsReasonInTheStatusLine() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.navigation.workspaceArea = .map
        state.navigation.analysisMode = .phaseMapping
        let refusal = try XCTUnwrap(state.phaseMapping.runRefusal)
        state.statusText = "before"
        await state.runPrimaryWorkspaceTask()
        XCTAssertEqual(state.statusText, refusal)
    }

    /// Refuter fix round: a run that reports its own failure (`presentComputeFailure` -> "Error: <detail>") keeps that
    /// line; the primary action's `.failed(reason)` fallback must not overwrite it with the bare reason.
    /// Mutation: restore the unconditional `statusText = reason` -> red (the "Error: " marker is lost).
    func testAFailedPrimaryRunKeepsItsOwnErrorLine() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.navigation.workspaceArea = .braggDisks
        state.diskDetection.diskParams.corrPower = 5   // invalid: must be within 0...1
        state.statusText = "before"
        await state.runPrimaryWorkspaceTask()
        XCTAssertTrue(state.statusText.hasPrefix("Error: "), state.statusText)
    }

    // MARK: - e9: the controls live in the inspector, not "the tools panel"

    /// Mutation: restore "…in the tools panel." in the diskSettings item -> red.
    func testTheDiskSettingsRequirementPointsAtTheInspector() throws {
        let items = ProductWorkflow.prerequisiteItems(
            for: .disks, readiness: ProductWorkflowReadiness(hasValidDiskDetectionSettings: false))
        let item = try XCTUnwrap(items.first { $0.id == "diskSettings" })
        guard case .taskPanel(let hint) = item.resolution else { return XCTFail("taskPanel") }
        XCTAssertFalse(hint.contains("tools panel"), hint)
        XCTAssertTrue(hint.contains("inspector"), hint)
    }

    /// The frozen toolbar's ACOM help is a private string, so this reads the source: no user-facing string may say "tools panel".
    /// Mutation: restore the old ACOM help text -> red.
    func testNoUserFacingStringInUIOrAppSaysToolsPanel() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for relative in ["mac4DSTEM/UI/WorkspaceView.swift", "mac4DSTEM/App/ProductWorkflow.swift"] {
            let url = root.appendingPathComponent(relative)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw XCTSkip("source tree not beside the tests: \(url.path)")
            }
            for line in text.split(separator: "\n") where line.contains("\"") && line.localizedCaseInsensitiveContains("tools panel") {
                // A string literal naming it; comments (//) are history, not UI.
                if !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    XCTFail("\(relative): \(line)")
                }
            }
        }
    }

    // MARK: - e7: single-slice ptychography's empty state names its own task

    /// Mutation: share the case again with `.ptychography` -> the single-slice line says "parallax" (red).
    func testSingleSliceEmptyStateNamesReconstructObjectNotParallax() {
        let text = RealSpacePane.pendingInstruction(for: .singleslicePtychography)
        XCTAssertTrue(text.contains("Reconstruct Object"), text)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("parallax"), text)
        XCTAssertTrue(RealSpacePane.pendingInstruction(for: .ptychography).contains("parallax"))
    }

    // MARK: - b2: an unvalidated product says so on the face of the exported PNG

    private func scalar() -> ProductPayload {
        .scalar(FloatImage(width: 2, height: 2, pixels: [0, 1, 2, 3]))
    }

    /// Mutation: delete the `validation == "none"` append in publicationCaption -> red.
    func testTheCaptionBurnsUnvalidatedForAValidationNoneProduct() {
        let state = AppState()
        state.publishProduct(kind: "phase_map", displayName: "Phase map", valueUnits: "phase_index", payload: scalar(),
                             extraProvenance: ["validation": "none"])
        XCTAssertTrue(state.publicationCaption.localizedCaseInsensitiveContains("unvalidated"), state.publicationCaption)
    }

    /// A product with no such key carries no noise. Mutation: append unconditionally -> red.
    func testTheCaptionOfAnOrdinaryProductSaysNothingOfValidation() {
        let state = AppState()
        state.publishProduct(kind: "t", displayName: "t", valueUnits: "rad", payload: scalar())
        XCTAssertFalse(state.publicationCaption.localizedCaseInsensitiveContains("unvalidated"), state.publicationCaption)
    }

    // MARK: - b3: DPC vector products name their frame

    private func stateWithDPC(rotationRad: Float?) async throws -> AppState {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        let d = try XCTUnwrap(state.descriptor)
        state.comField = [Float](repeating: 0.25, count: 2 * d.rx * d.ry)
        state.navigation.workspaceArea = .reconstruct
        state.navigation.analysisMode = .dpc
        state.dpc.dpcDisplay = .angle
        state.calibrationSession.calibration.rotationRad = rotationRad
        return state
    }

    /// Mutation: drop `extraProvenance: frameKeys` from publishProduct in applyDPCDisplay -> both nil (red).
    func testDPCAngleWithoutARotationIsLabelledDetectorFrame() async throws {
        let state = try await stateWithDPC(rotationRad: nil)
        XCTAssertNil(state.applyDPCDisplay())
        let provenance = try XCTUnwrap(state.resultPresentation.product).provenance
        XCTAssertEqual(provenance["dpc_frame"], "detector")
        XCTAssertEqual(provenance["dpc_frame_reason"], "qr_rotation_not_calibrated")
        XCTAssertNil(provenance["qr_rotation_deg"])
        XCTAssertTrue(state.publicationCaption.contains("dpc_frame=detector"), state.publicationCaption)
    }

    /// 0.5 rad in the app's sign is -28.6 deg in py4DSTEM's (ADR 040) — the sign, not only the key, is pinned.
    /// Mutation: drop the negation (use +rotation) -> "28.6" (red); or drop "dpc_frame" from the caption keys -> caption check red.
    func testDPCAngleWithARotationIsLabelledScanFrameInPy4DSTEMSign() async throws {
        let state = try await stateWithDPC(rotationRad: 0.5)
        XCTAssertNil(state.applyDPCDisplay())
        let provenance = try XCTUnwrap(state.resultPresentation.product).provenance
        XCTAssertEqual(provenance["dpc_frame"], "scan")
        XCTAssertEqual(provenance["qr_rotation_deg"], "-28.6")
        XCTAssertEqual(provenance["qr_rotation_convention"], RQRotationConvention.marker)
        XCTAssertNil(provenance["dpc_frame_reason"])
        XCTAssertTrue(state.publicationCaption.contains("dpc_frame=scan"), state.publicationCaption)
    }

    /// The magnitude and colour wheel carry it too. Mutation: pass the keys for .angle only -> red.
    func testDPCMagnitudeAndColourWheelCarryTheFrameToo() async throws {
        let state = try await stateWithDPC(rotationRad: nil)
        state.dpc.dpcDisplay = .magnitude
        XCTAssertNil(state.applyDPCDisplay())
        XCTAssertEqual(state.resultPresentation.product?.kind, "dpc_magnitude")
        XCTAssertEqual(state.resultPresentation.product?.provenance["dpc_frame"], "detector")
        state.dpc.dpcDisplay = .colorWheel
        XCTAssertNil(state.applyDPCDisplay())
        XCTAssertEqual(state.resultPresentation.product?.kind, "dpc_color")
        XCTAssertEqual(state.resultPresentation.product?.provenance["dpc_frame"], "detector")
    }
}
