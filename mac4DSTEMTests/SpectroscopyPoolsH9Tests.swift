//
//  SpectroscopyPoolsH9Tests.swift
//  E1 H9 (docs/archive/v5/e1-pooling-preregistration-2026-10-08.md): truth on the simulated joint file
//  References/demo-edx/AlMgSi_4D_EDX.dm4 (tools/demo-edx/run.sh; machine-local, ~254 MB, skipped when absent).
//  (a) GATED: the pool of each phase, through the real chain (GMS joint attach by identity -> phase map published -> catalogue
//      -> mask), equals the sum of `realised_total_eds_counts` of the truth regions with that phase, as integers.
//  (b) REPORTED, no bar: the beta'' pool's fitted Mg and Si nets and their ratio with a Garwood interval, beside the truth's
//      expected Mg/Si line counts. Printed either way (threshold rule).
//

import XCTest
@testable import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM
@testable import SpectroCore

@MainActor
final class SpectroscopyPoolsH9Tests: XCTestCase {
    private var keep: [AppState] = []

    /// Printed, and appended to the file named by `TEST_RUNNER_E1_H9_OUT` when set (the test host's stdout is not in the xcodebuild log).
    private func report(_ line: String) {
        print(line)
        guard let path = ProcessInfo.processInfo.environment["E1_H9_OUT"], let data = (line + "\n").data(using: .utf8) else { return }
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(data); try? h.close() } else { try? data.write(to: URL(fileURLWithPath: path)) }
    }

    func testPoolsEqualTheTruthsRealisedCountsOnTheSimulatedJointFile() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("References/demo-edx")
        let dm4 = root.appendingPathComponent("AlMgSi_4D_EDX.dm4"), truthURL = root.appendingPathComponent("truth_edx.json")
        guard FileManager.default.fileExists(atPath: dm4.path), FileManager.default.fileExists(atPath: truthURL.path) else {
            throw XCTSkip("References/demo-edx is not generated on this machine (tools/demo-edx/run.sh)")
        }
        let truth = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: truthURL)) as? [String: Any])
        let recipes = try XCTUnwrap(truth["recipes"] as? [String: [String: Any]])
        let order = try XCTUnwrap(truth["recipe_names_in_map_order"] as? [String])
        let rmap = try XCTUnwrap(truth["recipe_map"] as? [[Int]])
        let (ny, nx) = (rmap.count, rmap[0].count)
        XCTAssertEqual([nx, ny], [64, 48])
        // The joint attach, by identity: same Experiment ID and scan grid.
        let loaded = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: dm4.path, fourD: GMSFourDIdentity(objectIndex: nil, scanWidth: nx, scanHeight: ny, voltageKV: 200)))
        XCTAssertTrue(loaded.metadata.sameScanAs4DCube, "H9's precondition")
        // The phase map is the truth's: phase per position from the recipe map.
        let phases = ["Al", "beta''", "Q", "vacuum"]
        var map = PhaseMap(width: nx, height: ny, matrixEntryIndex: -1, phaseNames: phases, matrixPhaseIndex: 0)
        for y in 0..<ny { for x in 0..<nx {
            let phase = recipes[order[rmap[y][x]]]!["phase"] as! String
            map.results[y * nx + x].verdict = .indexed
            map.results[y * nx + x].phaseIndex = Int32(try XCTUnwrap(phases.firstIndex(of: phase)))
        } }
        let state = AppState(); keep.append(state)
        state.descriptor = DatasetDescriptor(filePath: dm4.path, datasetPath: "ImageList.4.ImageData.Data", shape: [ny, nx, 128, 128], dtypeDescription: "float32", chunkShape: nil)
        state.openSpectrumImage(loaded)
        state.spectroscopyRoom.autoIDOnOpen?.cancel()
        XCTAssertNotNil(state.spectroscopy.registration)
        state.phaseMapping.publish(map, ranWith: PhaseMappingProduct.RunRecord(
            phaseSignature: "h9", reference: PhaseReferenceSettings(), matching: PhaseVectorSettings(), libraryEntryCount: 1,
            matrixEntryIndex: 0, matrixInPlaneDegrees: .nan, worstChanceMatchPercent: 0, invAngstromPerPixel: 0.01,
            qScaleIsPhysical: false, peakCount: 0,
            calibration: PhaseMappingProduct.CalibrationStamp(calibration: Calibration(), referenceOrigin: (0, 0))))
        await state.spectroscopy.poolTask?.value
        let pools = state.spectroscopy.poolCatalogue.pools
        XCTAssertEqual(pools.map(\.name), phases)
        for (i, phase) in phases.enumerated() {
            let want = recipes.values.filter { ($0["phase"] as? String) == phase }.reduce(0) { $0 + ($1["realised_total_eds_counts"] as! Int) }
            let wantPixels = recipes.values.filter { ($0["phase"] as? String) == phase }.reduce(0) { $0 + ($1["n_pixels"] as! Int) }
            let got = loaded.sum(mask: pools[i].mask).reduce(UInt64(0), &+)
            XCTAssertEqual(Int(got), want, "pool \(phase): counts")
            XCTAssertEqual(pools[i].pixelCount, wantPixels, "pool \(phase): pixels")
            report("H9a \(phase): pool \(got) counts / \(pools[i].pixelCount) px; truth \(want) / \(wantPixels)")
        }
        // (b) reported: the beta'' pool's Mg and Si.
        let b = pools[1]
        let spectrum = loaded.sum(mask: b.mask)
        var method = SpectroscopyQuantifyTests.method(); method.beamEnergyKeV = 200
        let input = PooledQuantificationInput(counts: spectrum, axis: loaded.energyAxis, method: method, metadata: loaded.metadata, regionName: b.name, pixelCount: b.pixelCount)
        do {
            let fit = try PooledQuantifier.run(input, tables: SpectroscopyQuantifyTests.tables)
            let mg = fit.rows.first { $0.element == "Mg" }, si = fit.rows.first { $0.element == "Si" }
            if let mg, let si, si.net > 0 {
                let lo = CountingInterval.garwood(count: mg.net), hi = CountingInterval.garwood(count: si.net)
                let truthMg = recipes.values.filter { ($0["phase"] as? String) == "beta''" }.reduce(0.0) { $0 + (((($1["components_expected_total_counts"]) as? [String: Double])?["Mg_Ka"]) ?? 0) }
                let truthSi = recipes.values.filter { ($0["phase"] as? String) == "beta''" }.reduce(0.0) { $0 + (((($1["components_expected_total_counts"]) as? [String: Double])?["Si_Ka"]) ?? 0) }
                report("H9b beta'' pool: Mg net \(mg.net) [\(lo.lower), \(lo.upper)], Si net \(si.net) [\(hi.lower), \(hi.upper)], Mg/Si \(mg.net / si.net); truth expected Mg_Ka \(truthMg), Si_Ka \(truthSi), ratio \(truthMg / truthSi)")
            } else { report("H9b: no Mg or Si row in the fit: \(fit.rows.map(\.element))") }
        } catch { report("H9b: the fit refused: \(error)") }
    }
}
