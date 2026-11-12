import XCTest
import DiffractoCore
import DiffractoOrientation
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// mac4DSTEM#184: Map Phases with the orientations found from the structures. The numerics are DiffractoKit's
/// (`mapFromStructures`, its own planted test); here: what the phase list asks for, the map in the list's order, and the
/// run on the simulated demo when it is on this machine.
@MainActor
final class PhaseMappingFromStructuresTests: XCTestCase {

    private func model(_ id: String) throws -> CrystalModel { try XCTUnwrap(CrystalModelLibrary.model(id: id)) }

    /// A new list finds its orientations from the structures: no zone axis is asked for, [0 0 0] is no refusal, and the
    /// same structure twice is one (a second copy has nothing to add). Typed zones keep their own rules.
    func testAStructuresListAsksForNoZoneAxis() throws {
        let product = PhaseMappingProduct()
        XCTAssertEqual(product.orientationSource, .structures)
        let al = try model("al_fcc"), si = try model("si_diamond")
        product.add(al); product.add(si)
        XCTAssertNil(product.runRefusal)
        product.phases[1].u = 0; product.phases[1].v = 0; product.phases[1].w = 0
        XCTAssertNil(product.runRefusal, "a zone axis is not read in a structures run")
        product.add(si)
        XCTAssertEqual(product.runRefusal?.contains("twice"), true)
        product.orientationSource = .typedZones
        XCTAssertEqual(product.runRefusal, "A zone axis of [0 0 0] names no direction.")
    }

    /// Changing where the orientations come from makes a finished map stale, and the preset is a typed-zones setup.
    func testTheSourceIsPartOfTheRunsIdentity() throws {
        let product = PhaseMappingProduct()
        let al = try model("al_fcc"), si = try model("si_diamond")
        product.add(al); product.add(si)
        let structures = product.phaseSignature
        product.orientationSource = .typedZones
        XCTAssertNotEqual(product.phaseSignature, structures)
        product.orientationSource = .structures
        product.applyAlMgSiPreset(precipitate: si)
        XCTAssertEqual(product.orientationSource, .typedZones)
    }

    /// The kit numbers the matrix 0 and the candidates after it; the list may hold the matrix anywhere. The map handed on
    /// carries the list's positions: matrix at its slot, each candidate at its own, runner-up too, the rest untouched.
    func testTheMapCarriesTheListsPositions() throws {
        var kit = PhaseMap(width: 4, height: 1, matrixEntryIndex: -1, phaseNames: ["M", "A", "B"], matrixPhaseIndex: 0)
        kit.results[0].verdict = .matrix; kit.results[0].phaseIndex = 0
        kit.results[1].verdict = .indexed; kit.results[1].phaseIndex = 1; kit.results[1].runnerUpPhaseIndex = 2; kit.results[1].matchedCount = 7
        kit.results[2].verdict = .indexed; kit.results[2].phaseIndex = 2
        kit.results[3].verdict = .notIndexed
        // The list: A, M (matrix), B.
        let map = try XCTUnwrap(PhaseMappingProduct.mapInListOrder(kit, slotNames: ["A", "M", "B"], matrixSlot: 1, candidateSlots: [0, 2]))
        XCTAssertEqual(map.phaseNames, ["A", "M", "B"])
        XCTAssertEqual(map.matrixPhaseIndex, 1)
        XCTAssertEqual(map.results.map(\.phaseIndex), [1, 0, 2, -1])
        XCTAssertEqual(map.results[1].runnerUpPhaseIndex, 2)
        XCTAssertEqual(map.results[1].matchedCount, 7)
        XCTAssertEqual(map.results.map(\.verdict), [.matrix, .indexed, .indexed, .notIndexed])
        XCTAssertEqual(map.phaseCounts, [1, 1, 1])
        XCTAssertNil(PhaseMappingProduct.mapInListOrder(kit, slotNames: ["A", "M"], matrixSlot: 1, candidateSlots: [0, 2]))
        XCTAssertNil(PhaseMappingProduct.mapInListOrder(kit, slotNames: ["A", "M", "B"], matrixSlot: 1, candidateSlots: [0]))
    }

    /// The words on what a run learned.
    func testTheLearnedRelationshipLines() {
        XCTAssertEqual(AppState.learnedRelationshipLines(names: ["beta"], relationships: [[]]),
                       ["beta: no relationship to the matrix learned (too few strong positions)"])
    }

    private static var references: URL {
        if let root = ProcessInfo.processInfo.environment["MACEM_REFERENCES"] { return URL(fileURLWithPath: root).appendingPathComponent("mac4DSTEM") }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("References")
    }
    private struct Precipitate: Decodable { let name: String; let kind: String; let pixels_y_x: [[Int]] }
    private struct Truth: Decodable { let grain_label_map: [[Int]]; let precipitates: [Precipitate] }

    /// The app's own run on the simulated Al-Mg-Si demo, version 3 (skipped when the file is not on this machine): open,
    /// origin, disks, aluminium and the beta'' CIF added as two phases with no zone typed, Map Phases. Every one of the
    /// nine planted beta'' precipitates gets positions and the run says it learned a relationship. Typed zones on the
    /// same file miss the needle H2 and label a whole grain of 696 positions.
    ///
    /// KNOWN, DiffractoKit#103: positions on a grain boundary can be called beta'' (one column of 24 here, or none, or
    /// two, depending on the slab). Whatever is called outside the planted precipitates must lie on a grain boundary
    /// (a position with a neighbour of another grain) and be at most two such columns; nothing inside a grain.
    func testTheDemoIsMappedFromItsTwoStructures() async throws {
        let folder = Self.references.appendingPathComponent("demo-edx-v3")
        let file = folder.appendingPathComponent("AlMgSi_4D_EDX.dm4")
        let cif = Self.references.appendingPathComponent("crystal-structures/beta_double_prime_Mg5Si6.cif")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: file.path) && FileManager.default.fileExists(atPath: cif.path),
                          "demo-edx-v3 or the beta'' CIF is not on this machine")
        let truth = try JSONDecoder().decode(Truth.self, from: Data(contentsOf: folder.appendingPathComponent("truth_edx.json")))
        let width = truth.grain_label_map[0].count

        let state = AppState()
        await state.openFileAsync(url: file)
        _ = try XCTUnwrap(state.descriptor, state.statusText)
        await state.calibrateOrigin()
        state.navigation.analysisMode = .disks
        _ = await state.runDiskDetection()
        let beta = try CIFModelImport.crystalModel(from: try String(contentsOf: cif, encoding: .utf8), fileBaseName: "beta_double_prime_Mg5Si6")
        state.phaseMapping.add(try model("al_fcc"))
        state.phaseMapping.add(beta)
        XCTAssertEqual(state.phaseMapping.orientationSource, .structures)
        state.navigation.analysisMode = .phaseMapping
        let outcome = await state.runPhaseMapping()
        XCTAssertEqual(outcome, .published, state.statusText)
        let map = try XCTUnwrap(state.phaseMapping.map, state.statusText)
        let run = try XCTUnwrap(state.phaseMapping.lastRun)
        XCTAssertEqual(run.orientationSource, .structures)
        XCTAssertNotNil(state.phaseMapping.lastStructureRun)
        XCTAssertNil(state.phaseMapping.lastLibrary)
        XCTAssertEqual(run.learnedRelationships.count, 1)
        XCTAssertTrue(run.learnedRelationships[0].contains("learned from"), run.learnedRelationships[0])
        print("STRUCTURES DEMO | \(state.statusText) | \(run.learnedRelationships)")

        var planted = Set<Int>()
        for p in truth.precipitates {
            let pixels = p.pixels_y_x.map { $0[0] * width + $0[1] }
            planted.formUnion(pixels)
            guard p.kind != "other_phase" && !p.name.hasPrefix("Q") else { continue }
            let called = pixels.filter { map.results[$0].verdict == .indexed && map.results[$0].phaseIndex == 1 }.count
            XCTAssertGreaterThan(called, 0, "planted \(p.name) has no beta'' position")
        }
        let outside = map.results.indices.filter { !planted.contains($0) && map.results[$0].verdict == .indexed }
        let height = truth.grain_label_map.count
        func onBoundary(_ i: Int) -> Bool {
            let x = i % width, y = i / width, grain = truth.grain_label_map[y][x]
            for dy in -1...1 { for dx in -1...1 {
                let xx = x + dx, yy = y + dy
                if xx >= 0, yy >= 0, xx < width, yy < height, truth.grain_label_map[yy][xx] != grain { return true }
            } }
            return false
        }
        let insideAGrain = outside.filter { !onBoundary($0) }
        XCTAssertEqual(insideAGrain.count, 0, "positions inside a grain, outside every planted precipitate, called a phase: "
                       + insideAGrain.prefix(12).map { "(\($0 % width),\($0 / width))" }.joined(separator: " ") + "; \(state.statusText)")
        XCTAssertLessThanOrEqual(outside.count, 48, "more than two grain boundary columns called a phase (DiffractoKit#103); \(state.statusText)")
    }
}
