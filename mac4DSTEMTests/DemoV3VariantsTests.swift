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
    /// - all six end-on needles get their planted variant (1, 4, 5, 5, 8, 1), direction [001], every pixel agreeing, no alternative;
    ///   typed zones manage three;
    /// - the three needles in the foil plane get their direction and the PAIR of variants that share it: H1 "2 or 3" (planted 3), H2
    ///   "6 or 7" (planted 7), V1 "9 or 11" (planted 9). The two variants of a pair predict the same spots within the detector's reach, so
    ///   the pattern cannot decide between them (DiffractoKit#107); before, one of the two was shown by the fall of a tie;
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
        let structureRun = ObjectVariantJoin.StructureRun(
            run: run, crystals: state.phaseMapping.phases.map(\.model.structure), candidateIndex: [nil, 0],
            reachInvAngstrom: try XCTUnwrap(state.phaseMapping.lastRun?.libraryKMaxInvAngstrom), pairRadiusInvAngstrom: state.phaseMapping.matching.pairRadiusInvAngstrom,
            excitationSlabs: [0, PhaseMappingProduct.structuresExcitationSlabDefault])
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
                         + (a.map { $0.isAssigned ? "variant \($0.variantText), \($0.directionName ?? "?"), \(String(format: "%.2f", $0.angleDegrees ?? -1)) deg, agreement \(String(format: "%.2f", $0.agreement))"
                                                  : "\($0.status), angle \(String(format: "%.2f", $0.angleDegrees ?? -1))" } ?? "no value"))
            guard let a, a.isAssigned else { continue }
            assigned[p.name] = a
            // Right when the planted variant is the one shown or one of the alternatives shown with it.
            let shown = [a.variant].compactMap { $0 } + (a.alternatives ?? [])
            if !(p.variant.map(shown.contains) ?? false) { wrong.append("\(p.name): variant \(a.variantText), planted \(p.variant.map(String.init) ?? "none")") }
        }
        for l in lines { print("DEMO V3 VARIANTS FROM STRUCTURES | " + l) }
        XCTAssertEqual(wrong, [], "a precipitate was given a variant it was not planted as: \(lines)")
        for (name, variant, direction) in [("E1", 1, "[001]"), ("E2", 4, "[001]"), ("E3", 5, "[001]"), ("E4", 8, "[001]"), ("E5", 1, "[001]"), ("E6", 5, "[001]")] {
            let a = try XCTUnwrap(assigned[name], "\(name) is not assigned: \(lines)")
            XCTAssertEqual(a.variant, variant, name)
            XCTAssertNil(a.alternatives, "\(name): an end-on needle is told apart")
            XCTAssertEqual(a.directionName, direction, name)
            XCTAssertLessThan(try XCTUnwrap(a.angleDegrees), 3, name)
        }
        for (name, text, direction) in [("H1", "2 or 3", "[010]"), ("H2", "6 or 7", "[010]"), ("V1", "9 or 11", "[100]")] {
            let a = try XCTUnwrap(assigned[name], "\(name) is not assigned: \(lines)")
            XCTAssertEqual(a.variantText, text, name)
            XCTAssertEqual(a.directionName, direction, name)
            XCTAssertEqual(a.agreement, 1, accuracy: 1e-9, "\(name): the pair is one choice, so every position agrees")
        }
        XCTAssertNil(assigned["Q1"]); XCTAssertNil(assigned["Q2"])

        // What the legend, the object table and the CSV say (seen on screen in the PR 253 check, pinned here).
        let report = PrecipitateObjectReport.make(
            objects: objects, phaseNames: map.phaseNames, matrixPhaseIndex: map.matrixPhaseIndex, pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1,
            variantJoin: outcome.result, variantSettings: VariantSettings(), endOnDirection: outcome.endOnDirection,
            variantDirections: outcome.habitFamilies, variantDefaultToleranceDegrees: outcome.defaultToleranceDegrees)
        let variantRows = (report.variantGroups ?? []).filter { $0.kind == .variant }
        let titles = variantRows.map(\.title)
        for title in ["Variant 2 or 3", "Variant 6 or 7", "Variant 9 or 11"] { XCTAssertTrue(titles.contains(title), "\(title) is not a legend row: \(titles)") }
        // The other half of a pair has no row of its own; a variant nobody has (10, 12) keeps its row with 0 objects.
        XCTAssertEqual(variantRows.map(\.index), [1, 2, 4, 5, 6, 8, 9, 10, 12], "\(titles)")
        let summary = try XCTUnwrap(report.variantSummary)
        XCTAssertTrue(summary.contains("the learned relationship's distance to the named one, plus 3"), summary)
        XCTAssertFalse(summary.contains("library"), summary)
        let texts = Set(report.rows.map(\.variantText))
        XCTAssertTrue(texts.isSuperset(of: ["1", "4", "5", "8", "2 or 3", "6 or 7", "9 or 11"]), "\(texts)")
        let csv = report.csv()
        XCTAssertTrue(csv.contains("6 or 7"), "the CSV does not carry the pair")
        XCTAssertTrue(csv.contains("# variant 6 or 7: 1 counted of 1"), "the CSV's legend line does not name the pair")
        XCTAssertTrue(csv.contains("found at each position from the structures"), "the CSV names the wrong source")
        XCTAssertFalse(csv.contains("library"), "the CSV speaks of a library a structures run does not have")
        try? csv.write(toFile: NSTemporaryDirectory() + "demo-v3-variants-from-structures.csv", atomically: true, encoding: .utf8)
    }
}
