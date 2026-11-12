//
//  DemoV3VariantsTests.swift
//  Role: Count variants on the simulated Al-Mg-Si demo, version 3 (mac4DSTEM#115). Version 2 planted beta'' at the matrix's in-plane
//        angle plus 0 or 90 degrees, which is no variant of the Andersen 1998 relationship, so every object came out unassigned.
//        Version 3 plants each precipitate as one of the twelve variants (`truth_edx.json`: `precipitates[].variant`, in DiffractoKit's
//        order). The test runs the app's own steps (open, origin, disks, the Al-Mg-Si preset, Map Phases, objects, Count variants at
//        default settings) and compares each planted precipitate's object with its planted variant.
//  Gate:  real files, outside the repo (References/demo-edx-v3/AlMgSi_4D_EDX.dm4, 254 MB, and the beta'' CIF): skipped when they are
//        not there. `MACEM_REFERENCES` names the folder that holds `mac4DSTEM/`; otherwise the repo's own `References`.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class DemoV3VariantsTests: XCTestCase {
    private static var references: URL {
        if let root = ProcessInfo.processInfo.environment["MACEM_REFERENCES"] { return URL(fileURLWithPath: root).appendingPathComponent("mac4DSTEM") }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("References")
    }
    private struct Precipitate: Decodable { let name: String; let kind: String; let pixels_y_x: [[Int]]; let variant: Int? }
    private struct Truth: Decodable { let grain_label_map: [[Int]]; let precipitates: [Precipitate] }

    /// What Count variants says of every planted precipitate, measured 2026-11-11:
    /// - E1 and E5 (end-on, planted variant 1) and E4 (variant 8): assigned their planted variant, direction [001], every pixel agreeing,
    ///   0.31 degrees from the variant. On version 2 none of the six end-on needles was assigned.
    /// - No precipitate is assigned a variant other than its planted one.
    /// - Not assigned, and not this file's fault: E2 (variant 4), E3 and E6 (variant 5) are "ambiguous", the entry the phase map chose
    ///   for them lies about 27 degrees from every variant (#197); the needles in the foil plane H1 and V1 are objects of the preset's
    ///   second phase entry and get no value, and H2 has no object (#198). The two regions of another phase (Q1, Q2) have no variant.
    func testCountVariantsGivesThePlantedVariants() async throws {
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
        state.applyAlMgSiPreset(precipitateCIF: cif)
        state.navigation.analysisMode = .phaseMapping
        _ = await state.runPhaseMapping()
        let map = try XCTUnwrap(state.phaseMapping.map, state.statusText)
        let labeled = PhaseMapObjectsBridge.labeledMap(from: map)
        let objects = PrecipitateSegmentation.classObjects(labels: labeled.labels, width: map.width, height: map.height, roles: labeled.roles,
                                                           pixelSize: nil, pixelUnit: nil)
        let outcome = ObjectVariantJoin.run(objects: objects, map: map, library: state.phaseMapping.lastLibrary,
                                            matrixEntryIndex: state.phaseMapping.lastRun?.matrixEntryIndex, settings: VariantSettings())
        XCTAssertNil(outcome.result.unavailable)

        // Each planted precipitate: the object that holds most of its pixels, and that object's assignment.
        let all = objects.classes.flatMap(\.objects)
        var assigned: [String: VariantAssignment] = [:], wrong: [String] = [], lines: [String] = []
        for p in truth.precipitates {
            let pixels = Set(p.pixels_y_x.map { $0[0] * width + $0[1] })
            guard let object = all.max(by: { a, b in a.pixelIndices.filter(pixels.contains).count < b.pixelIndices.filter(pixels.contains).count }),
                  object.pixelIndices.contains(where: pixels.contains) else {
                lines.append("\(p.name) (planted variant \(p.variant.map(String.init) ?? "-")): no object")
                continue
            }
            let a = outcome.result.perObject[object.id]
            lines.append("\(p.name) (planted variant \(p.variant.map(String.init) ?? "-")): object \(object.id), \(object.area) px: "
                         + (a.map { $0.isAssigned ? "variant \($0.variant ?? 0), \($0.directionName ?? "?")" : "\($0.status)" } ?? "no value"))
            guard let a, a.isAssigned else { continue }
            assigned[p.name] = a
            if a.variant != p.variant { wrong.append("\(p.name): variant \(a.variant ?? 0), planted \(p.variant.map(String.init) ?? "none")") }
        }
        for l in lines { print("DEMO V3 VARIANTS | " + l) }
        XCTAssertEqual(wrong, [], "a precipitate was given a variant it was not planted as")
        for (name, variant) in [("E1", 1), ("E4", 8), ("E5", 1)] {
            let a = try XCTUnwrap(assigned[name], "\(name) is not assigned: \(lines)")
            XCTAssertEqual(a.variant, variant, name)
            XCTAssertEqual(a.directionName, "[001]", name)
            XCTAssertEqual(a.agreement, 1, accuracy: 1e-9, name)
            XCTAssertLessThan(try XCTUnwrap(a.angleDegrees), 1, name)
        }
    }

    /// The same file with the orientations found from the structures (mac4DSTEM#184) and the variants read from them (#245): aluminium and
    /// the beta'' CIF as two phases, no zone typed, Map Phases, Count variants at default settings. Measured 2026-11-12:
    /// - all six end-on needles get their planted variant (1, 4, 5, 5, 8, 1), direction [001], every pixel agreeing; typed zones manage three;
    /// - the in-plane needles H1 (variant 3, [010]) and V1 (variant 9, [100]) get theirs; typed zones give them no value;
    /// - KNOWN, DiffractoKit#107: H2, planted as variant 7, is given variant 6, the mirror variant with the same needle direction [010];
    /// - the two regions of the crystal turned 45 degrees (Q1, Q2) are not assigned.
    func testCountVariantsFromTheStructures() async throws {
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
        state.phaseMapping.add(try XCTUnwrap(CrystalModelLibrary.model(id: "al_fcc")))
        state.phaseMapping.add(beta)
        state.navigation.analysisMode = .phaseMapping
        _ = await state.runPhaseMapping()
        let map = try XCTUnwrap(state.phaseMapping.map, state.statusText)
        let run = try XCTUnwrap(state.phaseMapping.lastStructureRun)
        let labeled = PhaseMapObjectsBridge.labeledMap(from: map)
        let objects = PrecipitateSegmentation.classObjects(labels: labeled.labels, width: map.width, height: map.height, roles: labeled.roles,
                                                           pixelSize: nil, pixelUnit: nil)
        let structureRun = ObjectVariantJoin.StructureRun(run: run, crystals: state.phaseMapping.phases.map(\.model.structure), candidateIndex: [nil, 0])
        let outcome = ObjectVariantJoin.run(objects: objects, map: map, library: nil, matrixEntryIndex: nil, settings: VariantSettings(),
                                            structureRun: structureRun)
        XCTAssertNil(outcome.result.unavailable)

        let all = objects.classes.flatMap(\.objects)
        var assigned: [String: VariantAssignment] = [:], wrong: [String] = [], lines: [String] = [state.statusText]
        for p in truth.precipitates {
            let pixels = Set(p.pixels_y_x.map { $0[0] * width + $0[1] })
            guard let object = all.max(by: { a, b in a.pixelIndices.filter(pixels.contains).count < b.pixelIndices.filter(pixels.contains).count }),
                  object.pixelIndices.contains(where: pixels.contains) else {
                lines.append("\(p.name) (planted variant \(p.variant.map(String.init) ?? "-")): no object")
                continue
            }
            let a = outcome.result.perObject[object.id]
            lines.append("\(p.name) (planted variant \(p.variant.map(String.init) ?? "-")): object \(object.id), \(object.area) px: "
                         + (a.map { $0.isAssigned ? "variant \($0.variant ?? 0), \($0.directionName ?? "?"), \(String(format: "%.2f", $0.angleDegrees ?? -1)) deg, agreement \(String(format: "%.2f", $0.agreement))"
                                                  : "\($0.status), angle \(String(format: "%.2f", $0.angleDegrees ?? -1))" } ?? "no value"))
            guard let a, a.isAssigned else { continue }
            assigned[p.name] = a
            if a.variant != p.variant { wrong.append("\(p.name): variant \(a.variant ?? 0), planted \(p.variant.map(String.init) ?? "none")") }
        }
        for l in lines { print("DEMO V3 VARIANTS FROM STRUCTURES | " + l) }
        XCTAssertEqual(wrong.filter { !$0.hasPrefix("H2:") }, [], "a precipitate was given a variant it was not planted as: \(lines)")
        for (name, variant, direction) in [("E1", 1, "[001]"), ("E2", 4, "[001]"), ("E3", 5, "[001]"), ("E4", 8, "[001]"), ("E5", 1, "[001]"),
                                           ("E6", 5, "[001]"), ("H1", 3, "[010]"), ("V1", 9, "[100]")] {
            let a = try XCTUnwrap(assigned[name], "\(name) is not assigned: \(lines)")
            XCTAssertEqual(a.variant, variant, name)
            XCTAssertEqual(a.directionName, direction, name)
            XCTAssertLessThan(try XCTUnwrap(a.angleDegrees), 3, name)
        }
        // DiffractoKit#107: the needle direction of H2 is right, its variant is the mirror one. Turn this round when it is fixed.
        let h2 = try XCTUnwrap(assigned["H2"], "H2 is not assigned: \(lines)")
        XCTAssertEqual(h2.directionName, "[010]")
        XCTAssertEqual(h2.variant, 6, "H2's variant changed: if it is 7 now, DiffractoKit#107 is fixed and this line goes")
        XCTAssertNil(assigned["Q1"]); XCTAssertNil(assigned["Q2"])
    }
}
