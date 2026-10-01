//
//  FC2ReplayProvenanceTests.swift
//  Lane FC2 (Gate D, F-C items 1 and 3):
//  (1) a virtual-detector run published while another mode is current took that
//      mode's provenance (source_product=bragg_vector_map under .disks);
//  (3) a commit run landing after a NEWER quiet drag overwrote the drag's image.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class FC2ReplayProvenanceTests: XCTestCase {

    private final class Gate { var entered = false; var released = false }

    override func tearDown() async throws {
        AppState.virtualDetectorBeforeLanding = nil
    }

    private func openedState() async -> AppState {
        let state = AppState()
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        await state.openDemoFixture(specification: spec)
        return state
    }

    /// Mutation it catches: the VD publish merging the CURRENT mode's metadata
    /// (publishProduct default) again -- source_product=bragg_vector_map returns.
    func testReplayedVirtualDetectorStepCarriesItsOwnProvenanceWhateverTheMode() async throws {
        let state = await openedState()
        state.navigation.analysisMode = .virtualDetector
        state.resultPresentation.virtualShape = .circle
        state.aperture = Aperture(centerX: 32, centerY: 32, inner: 0, outer: 9)
        let recorded = await state.runVirtualDetector()
        XCTAssertEqual(recorded, .published, state.statusText)
        XCTAssertEqual(state.replay.record.steps.map(\.kind), ["virtual_detector"])

        // The executor never switches mode: replay under Bragg Disks.
        state.navigation.analysisMode = .disks
        let replayed = await state.runVirtualDetector(replaying: true)
        XCTAssertEqual(replayed, .published, state.statusText)

        let provenance = try XCTUnwrap(state.resultPresentation.product).provenance
        XCTAssertNil(provenance["source_product"], "replayed VD step carried source_product=\(provenance["source_product"] ?? "")")
        XCTAssertNil(provenance["coordinate_space"])
        XCTAssertEqual(provenance["analysis_mode"], AnalysisMode.virtualDetector.rawValue)
        XCTAssertEqual(provenance["virtual_shape"], VirtualShapeMode.circle.rawValue)
    }

    /// Mutation it catches: a commit run that lands whatever it started with,
    /// although a newer (quiet drag) run has already landed.
    func testOlderCommitRunDoesNotOverwriteANewerQuietDrag() async throws {
        let state = await openedState()
        state.navigation.analysisMode = .virtualDetector
        state.resultPresentation.virtualShape = .circle

        let gate = Gate()
        defer { gate.released = true }
        AppState.virtualDetectorBeforeLanding = { quiet, ap in
            guard !quiet, ap.outer == 9 else { return }
            gate.entered = true
            while !gate.released { await Task.yield() }
        }
        // Commit run for aperture B, held back before it lands.
        state.aperture = Aperture(centerX: 32, centerY: 32, inner: 0, outer: 9)
        let commit = Task { await state.runVirtualDetector() }
        while !gate.entered { await Task.yield() }

        // A newer drag moves the aperture; its quiet run lands first.
        state.aperture = Aperture(centerX: 32, centerY: 32, inner: 0, outer: 5)
        let drag = await state.runVirtualDetector(quiet: true)
        XCTAssertEqual(drag, .published)
        let imageDrag = try XCTUnwrap(state.scanNavigationImage).pixels

        gate.released = true
        let commitOutcome = await commit.value
        XCTAssertEqual(commitOutcome, .cancelled, "the older commit run must be dropped")
        XCTAssertEqual(try XCTUnwrap(state.scanNavigationImage).pixels, imageDrag,
                       "the older commit run overwrote the newer drag's image")
        XCTAssertEqual(state.replay.record.steps.last { $0.kind == "virtual_detector" }?.parameters["outer"], "5.0")
    }
}
