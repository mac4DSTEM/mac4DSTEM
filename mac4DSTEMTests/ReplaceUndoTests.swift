//
//  ReplaceUndoTests.swift
//  UI audit 2026-10-14, A (safety): Import Labels, the Al-Mg-Si preset and the phase minus button replace or
//  remove hand-made work, so each registers its undo with the window's `UndoManager` (`ReplaceUndo`). Driven with
//  a real `UndoManager` and explicit undo groups (the app's `groupsByEvent` closes a group per event).
//
//  Mutations these were broken against (each must turn a test red):
//   1. `register` does not register the redo (drops the recursive call)          -> testUndoThenRedoSwap...
//   2. `importDiskCentreLabels` does not call `ReplaceUndo.register`              -> testImportLabelsUndo...
//   3. `restoreSnapshot` skips the dataset check                                   -> testUndoOfAnImportRefuses...
//   4. `DiskCentreLabelStore.restoreSnapshot` leaves `positions` alone             -> testImportLabelsUndo...
//   5. `restoreList` leaves `classificationRule` alone                             -> testPresetUndo...
//   6. `reinsert` appends instead of inserting at the recorded index               -> testRemovedPhaseComesBack...
//   7. `reinsert` does not clear the promoted matrix                               -> testRemovingTheMatrix...
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ReplaceUndoTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("replace-undo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func manager() -> UndoManager {
        let m = UndoManager()
        m.groupsByEvent = false
        return m
    }

    /// One user action = one undo group.
    private func act(_ m: UndoManager, _ body: () -> Void) {
        m.beginUndoGrouping()
        body()
        m.endUndoGrouping()
    }

    // MARK: - The helper

    func testUndoThenRedoSwapAndNameTheAction() {
        let m = manager()
        let target = NSObject()
        var value = 1
        act(m) {
            value = 2
            ReplaceUndo.register(in: m, target: target, actionName: "Change Value",
                                 before: 1, after: 2) { value = $0; return true }
        }
        XCTAssertTrue(m.canUndo)
        XCTAssertEqual(m.undoActionName, "Change Value")
        m.undo()
        XCTAssertEqual(value, 1)
        XCTAssertTrue(m.canRedo, "an undo registers its redo")
        XCTAssertEqual(m.redoActionName, "Change Value")
        m.redo()
        XCTAssertEqual(value, 2)
        XCTAssertTrue(m.canUndo, "and a redo registers the undo again")
        m.undo()
        XCTAssertEqual(value, 1)
    }

    func testAnUndoThatCannotApplyOffersNoRedo() {
        let m = manager()
        let target = NSObject()
        var applied = 0
        act(m) {
            ReplaceUndo.register(in: m, target: target, actionName: "Refused",
                                 undo: { applied += 1; return false }, redo: { true })
        }
        m.undo()
        XCTAssertEqual(applied, 1)
        XCTAssertFalse(m.canRedo, "nothing was put back, so there is nothing to redo")
    }

    func testNoManagerRegistersNothingAndDoesNotCrash() {
        ReplaceUndo.register(in: nil, target: NSObject(), actionName: "None",
                             undo: { true }, redo: { true })
    }

    // MARK: - Import Labels

    private func labelsFile(for descriptor: DatasetDescriptor, centre: DiskCentreLabelStore.Centre) throws -> URL {
        let source = DiskCentreLabelStore()
        source.reset(filePath: descriptor.filePath, datasetPath: descriptor.datasetPath)
        source.add(centre, ry: 0, rx: 0)
        let url = directory.appendingPathComponent("labels-\(UUID().uuidString).json")
        try source.encodedJSON().write(to: url)
        return url
    }

    private func demoState() async throws -> (AppState, DatasetDescriptor) {
        let state = AppState()
        await state.openDemoFixture(calibrated: true)
        let descriptor = try XCTUnwrap(state.descriptor)
        return (state, descriptor)
    }

    func testImportLabelsUndoPutsTheHandMadeLabelsBackAndRedoImportsAgain() async throws {
        let (state, descriptor) = try await demoState()
        let mine = DiskCentreLabelStore.Centre(row: 9, col: 9)
        let theirs = DiskCentreLabelStore.Centre(row: 2, col: 3)
        state.diskCentreLabels.add(mine, ry: 1, rx: 1)
        let url = try labelsFile(for: descriptor, centre: theirs)
        let m = manager()

        act(m) { state.importDiskCentreLabels(from: url, descriptor: descriptor, undoManager: m) }
        XCTAssertEqual(state.diskCentreLabels.centres(ry: 0, rx: 0), [theirs])
        XCTAssertTrue(state.diskCentreLabels.centres(ry: 1, rx: 1).isEmpty, "the import replaced my label")
        XCTAssertEqual(m.undoActionName, "Import Labels")

        m.undo()
        XCTAssertEqual(state.diskCentreLabels.centres(ry: 1, rx: 1), [mine], "undo brings the hand-made label back")
        XCTAssertTrue(state.diskCentreLabels.centres(ry: 0, rx: 0).isEmpty)

        m.redo()
        XCTAssertEqual(state.diskCentreLabels.centres(ry: 0, rx: 0), [theirs])
        XCTAssertTrue(state.diskCentreLabels.centres(ry: 1, rx: 1).isEmpty)
    }

    func testARefusedImportRegistersNoUndo() async throws {
        let (state, descriptor) = try await demoState()
        state.diskCentreLabels.add(.init(row: 9, col: 9), ry: 1, rx: 1)
        let junk = directory.appendingPathComponent("junk.json")
        try Data("not labels".utf8).write(to: junk)
        let m = manager()
        act(m) { state.importDiskCentreLabels(from: junk, descriptor: descriptor, undoManager: m) }
        XCTAssertNotNil(state.diskCentreLabels.importRefusal)
        // (An empty undo group still reads `canUndo`; every registration here names its action, so no name = none.)
        XCTAssertEqual(m.undoActionName, "", "a refusal changed nothing, so there is nothing to undo")
        XCTAssertEqual(state.diskCentreLabels.centreCount, 1)
    }

    func testUndoOfAnImportRefusesOnceAnotherDatasetIsOpen() async throws {
        let (state, descriptor) = try await demoState()
        state.diskCentreLabels.add(.init(row: 9, col: 9), ry: 1, rx: 1)
        let url = try labelsFile(for: descriptor, centre: .init(row: 2, col: 3))
        let m = manager()
        act(m) { state.importDiskCentreLabels(from: url, descriptor: descriptor, undoManager: m) }

        // The window opens another dataset: the store is rebound to it and starts empty.
        state.diskCentreLabels.reset(filePath: "/elsewhere/other.h5", datasetPath: "/data")
        m.undo()
        XCTAssertEqual(state.diskCentreLabels.centreCount, 0,
                       "the first dataset's labels must not come back onto another dataset")
        XCTAssertEqual(state.diskCentreLabels.filePath, "/elsewhere/other.h5")
        XCTAssertFalse(m.canRedo)
        XCTAssertTrue(state.statusText.contains("cannot be undone"), "the menu offered the undo, so say why it did nothing: \(state.statusText)")
    }

    // MARK: - The Al-Mg-Si preset

    private let betaCIF = """
    data_beta
    _cell_length_a 4.0
    _cell_length_b 5.0
    _cell_length_c 6.0
    _cell_angle_alpha 90
    _cell_angle_beta 90
    _cell_angle_gamma 90
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    Mg1 Mg 0 0 0
    Si1 Si 0.5 0.5 0.5
    """

    func testPresetUndoBringsTheOldPhaseListAndClassifierBack() throws {
        let state = AppState()
        _ = state.phaseMapping.add(CrystalModelLibrary.model(id: "cu_fcc")!)
        _ = state.phaseMapping.add(CrystalModelLibrary.model(id: "fe_bcc")!)
        let before = state.phaseMapping.listSnapshot
        XCTAssertEqual(before.classificationRule, .search, "precondition: the preset will change the classifier")
        let cif = directory.appendingPathComponent("beta.cif")
        try betaCIF.write(to: cif, atomically: true, encoding: .utf8)
        let m = manager()

        act(m) { state.applyAlMgSiPreset(precipitateCIF: cif, undoManager: m) }
        XCTAssertEqual(state.phaseMapping.phases.count, 3)
        XCTAssertEqual(state.phaseMapping.matching.classificationRule, .knownVariants)
        let after = state.phaseMapping.listSnapshot
        XCTAssertEqual(m.undoActionName, "Al–Mg–Si Preset")

        m.undo()
        XCTAssertEqual(state.phaseMapping.listSnapshot, before,
                       "list, classifier and its intensity floor all come back")

        m.redo()
        XCTAssertEqual(state.phaseMapping.listSnapshot, after)
    }

    // MARK: - The phase minus button

    private func threePhases() -> AppState {
        let state = AppState()
        for id in ["al_fcc", "cu_fcc", "fe_bcc"] { _ = state.phaseMapping.add(CrystalModelLibrary.model(id: id)!) }
        return state
    }

    func testRemovedPhaseComesBackWhereItStoodAndAnEditMadeSinceSurvives() {
        let state = threePhases()
        let ids = state.phaseMapping.phases.map(\.slotID)
        let m = manager()

        act(m) { state.removePhaseMappingSlot(slotID: ids[1], undoManager: m) }
        XCTAssertEqual(state.phaseMapping.phases.map(\.slotID), [ids[0], ids[2]])
        XCTAssertEqual(m.undoActionName, "Remove Phase")

        // An edit to another phase after the removal is not part of the undo.
        state.phaseMapping.phases[1].u = 1
        state.phaseMapping.phases[1].v = 1
        state.phaseMapping.phases[1].w = 0

        m.undo()
        XCTAssertEqual(state.phaseMapping.phases.map(\.slotID), ids, "back in its place, not at the end")
        XCTAssertEqual(state.phaseMapping.phases[2].zoneAxis, SIMD3(1, 1, 0), "the later edit stays")

        m.redo()
        XCTAssertEqual(state.phaseMapping.phases.map(\.slotID), [ids[0], ids[2]])
    }

    func testRemovingTheMatrixPromotesAnotherAndUndoMakesTheOriginalTheOnlyMatrix() {
        let state = threePhases()
        let ids = state.phaseMapping.phases.map(\.slotID)
        XCTAssertEqual(state.phaseMapping.phases.map(\.isMatrix), [true, false, false])
        let m = manager()

        act(m) { state.removePhaseMappingSlot(slotID: ids[0], undoManager: m) }
        XCTAssertEqual(state.phaseMapping.phases.map(\.isMatrix), [true, false],
                       "the list never has phases and no matrix")

        m.undo()
        XCTAssertEqual(state.phaseMapping.phases.map(\.slotID), ids)
        XCTAssertEqual(state.phaseMapping.phases.map(\.isMatrix), [true, false, false],
                       "exactly one matrix, and it is the original")
    }

    func testRemovingAnUnknownSlotRegistersNothing() {
        let state = threePhases()
        let m = manager()
        act(m) { state.removePhaseMappingSlot(slotID: UUID(), undoManager: m) }
        XCTAssertEqual(m.undoActionName, "", "nothing was removed, so nothing is registered")
        XCTAssertEqual(state.phaseMapping.phases.count, 3)
    }
}
