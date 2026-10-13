//
//  E1PoolRecording.swift
//  E1 (docs/archive/v5/e1-pooling-preregistration-2026-10-08.md), H7: "no existing number moves". This file is the RECORDING
//  COMMAND. Run on the build BEFORE the E1 code, it writes the Spectroscopy room's outputs for the two registered images
//  (`--demo-spectrum-fixture`'s `DemoSpectrumImageSource` and `demo-edx-tiny.dm4`) for the whole map and for one drawn rectangle:
//  the spectrum, the maps' counts, the fit's results CSV and method JSON, the footers, the lineage step's parameters and the
//  Spectrum CSV. Run on the E1 build, `testOutputsAreByteIdenticalToTheRecording` compares every byte against
//  docs/archive/v5/e1-results-2026-10-12/ (the recorded files); `SpectroscopyPoolsTests` runs the same recorder with a 4D
//  product present and a pool in the picker.
//
//  Record (from a copy of the pre-E1 commit 0a1a8106 with only this file added):
//    TEST_RUNNER_E1_RECORD_DIR=<dir> xcodebuild test ... -only-testing:mac4DSTEMTests/E1PoolRecordingTests CODE_SIGNING_ALLOWED=NO
//

import XCTest
@testable import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
enum E1Recording {
    enum Scenario: String, CaseIterable { case demoSpectrumFixture = "demo-spectrum-fixture", demoEdxTiny = "demo-edx-tiny" }
    enum Which: String, CaseIterable { case whole, drawn }

    static func image(_ s: Scenario) throws -> LoadedSpectrumImage {
        switch s {
        case .demoSpectrumFixture: return DemoSpectrumImageSource.make()
        case .demoEdxTiny: return try SpectroscopyQuantifyTests.image()
        }
    }

    private static func elements(_ s: Scenario) -> (quantify: [Int], fitOnly: [Int]) {
        switch s {
        case .demoSpectrumFixture: return ([13, 12, 14], [])
        case .demoEdxTiny: return ([13, 12, 14, 29], [8, 31])
        }
    }

    private static func rectangle(_ s: Scenario) -> SpectrumRegionShape {
        switch s {
        case .demoSpectrumFixture: return .rectangle(PixelRect(x0: 8, y0: 8, x1: 24, y1: 24))
        case .demoEdxTiny: return .rectangle(PixelRect(x0: 1, y0: 1, x1: 4, y1: 3))
        }
    }

    /// Opens the image, picks the elements, selects the region, runs the Quantify verb and writes down what the room shows.
    /// `prepare` runs after the open and before anything is picked (the E1 tests put a 4D product and its pools there).
    static func output(_ s: Scenario, _ which: Which, prepare: (AppState) async -> Void = { _ in }) async throws -> String {
        let state = AppState()
        defer { _ = state }
        let loaded = try image(s)
        state.openSpectrumImage(loaded)
        let c = state.spectroscopyRoom
        c.autoIDOnOpen?.cancel()
        await prepare(state)
        let e = elements(s)
        for z in e.quantify { c.model.elements.set(z, .quantify) }
        for z in e.fitOnly { c.model.elements.set(z, .fitOnly) }
        c.elementsChanged()
        if loaded.metadata.beamEnergyKeV == nil { c.model.quantify.beamEnergy = 200; c.quantifySettingsChanged() }
        if which == .drawn { c.editRegion(rectangle(s), final: true) }
        await c.lastRefresh?.value
        state.navigation.workspaceArea = .spectroscopy
        await state.runPrimaryWorkspaceTask()
        await c.checkTask?.value
        await c.lastRefresh?.value
        let m = c.model
        let region = state.spectroscopy.regions.first { $0.id == state.spectroscopy.selectedRegionID }
        var out: [String] = []
        out.append("# E1 H7 recording: \(s.rawValue), \(which.rawValue); region \(region?.name ?? "?") (\(region?.kind.rawValue ?? "?"), \(region?.pixelCount ?? -1) px)")
        out.append("== spectrum (counts per channel)")
        out.append(m.series.data.map { String(format: "%.0f", $0) }.joined(separator: " "))
        out.append("== maps (net counts per pixel, per tile)")
        for t in m.tiles { out.append("z\(t.z) \(t.width)x\(t.height): " + t.counts.map { String(format: "%.17g", $0) }.joined(separator: " ")) }
        out.append("== fit: hasFit \(m.hasFit), failure \(m.fitFailure ?? "none"), validation \(m.validation ?? "nil")")
        out.append("== results csv"); out.append(m.export.csv ?? "(none)")
        out.append("== method json"); out.append(m.export.methodJSON ?? "(none)")
        out.append("== results footer"); out.append(m.resultsFooter)
        out.append("== fit footer"); out.append(m.fitFooter)
        out.append("== warnings"); out.append(m.fitWarnings.map { "\($0.detail)" }.joined(separator: "\n"))
        out.append("== lineage parameters (last quantification step)")
        if let step = state.replay.lineage.nodes.last(where: { $0.kind == "quantification" }) {
            out.append(step.parameters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
        } else { out.append("(no step)") }
        out.append("== spectrum csv")
        out.append(SpectrumCSV.text(m.series, imageName: loaded.metadata.fileName, regionName: region?.name ?? "Whole map"))
        return out.joined(separator: "\n") + "\n"
    }

    static func fileName(_ s: Scenario, _ w: Which) -> String { "\(s.rawValue)-\(w.rawValue).txt" }

    static var recordedDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/archive/v5/e1-results-2026-10-12")
    }
}

@MainActor
final class E1PoolRecordingTests: XCTestCase {
    /// With `TEST_RUNNER_E1_RECORD_DIR` set the test records; without it, it compares every recorded file byte for byte.
    /// Mutation (H7's own): any change to the whole-map or drawn-region path of the room (a pool path that dilates the drawn mask,
    /// a changed lineage key) - red on the file it moves.
    func testOutputsAreByteIdenticalToTheRecording() async throws {
        let record = ProcessInfo.processInfo.environment["E1_RECORD_DIR"]
        for s in E1Recording.Scenario.allCases {
            for w in E1Recording.Which.allCases {
                let text = try await E1Recording.output(s, w)
                let name = E1Recording.fileName(s, w)
                if let record {
                    try FileManager.default.createDirectory(atPath: record, withIntermediateDirectories: true)
                    try text.write(toFile: record + "/" + name, atomically: true, encoding: .utf8)
                } else {
                    let recorded = try String(contentsOf: E1Recording.recordedDirectory.appendingPathComponent(name), encoding: .utf8)
                    XCTAssertEqual(text, recorded, "\(name) moved")
                }
            }
        }
    }
}
