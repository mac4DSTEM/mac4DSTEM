//
//  FCRow25VirtualDetectorOrderingTests.swift
//  Cloud review row 25 (Gate D): a quiet (live-drag) virtual-detector run for
//  aperture A that lands AFTER the commit run for aperture B overwrote B's image
//  and recorded aperture A as the last recipe step.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class FCRow25VirtualDetectorOrderingTests: XCTestCase {

    private final class Gate { var entered = false; var released = false }

    override func tearDown() async throws {
        AppState.virtualDetectorBeforeLanding = nil
    }

    /// Mutation it catches: a quiet run that lands (publishes and records)
    /// whatever aperture it started with, even when the live aperture has moved on.
    func testStaleQuietRunDoesNotOverwriteTheCommitRun() async throws {
        let state = AppState()
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        await state.openDemoFixture(specification: spec)
        state.navigation.analysisMode = .virtualDetector
        state.resultPresentation.virtualShape = .circle

        let gate = Gate()
        defer { gate.released = true }
        AppState.virtualDetectorBeforeLanding = { quiet, ap in
            guard quiet, ap.outer == 5 else { return }
            gate.entered = true
            while !gate.released { await Task.yield() }
        }
        // Aperture A: a quiet drag run, held back before it lands.
        state.aperture = Aperture(centerX: 32, centerY: 32, inner: 0, outer: 5)
        let quietA = Task { await state.runVirtualDetector(quiet: true) }
        while !gate.entered { await Task.yield() }

        // Aperture B: the commit run lands first.
        state.aperture = Aperture(centerX: 32, centerY: 32, inner: 0, outer: 9)
        let committed = await state.runVirtualDetector()
        XCTAssertEqual(committed, .published, state.statusText)
        let imageB = try XCTUnwrap(state.scanNavigationImage).pixels

        gate.released = true
        let quietOutcome = await quietA.value
        XCTAssertEqual(quietOutcome, .cancelled, "the stale quiet run must be dropped, not landed")

        XCTAssertEqual(try XCTUnwrap(state.scanNavigationImage).pixels, imageB,
                       "the stale quiet run overwrote the committed image")
        let steps = state.replay.record.steps.filter { $0.kind == "virtual_detector" }
        XCTAssertEqual(steps.last?.parameters["outer"], "9.0",
                       "the recipe's last virtual_detector step must be the commit's aperture: \(steps.map(\.parameters))")

        // A quiet run at the LIVE aperture still lands (quiet runs are not dropped wholesale).
        let quietLive = await state.runVirtualDetector(quiet: true)
        XCTAssertEqual(quietLive, .published, "a quiet run for the live aperture must land")
        XCTAssertEqual(state.replay.record.steps.last { $0.kind == "virtual_detector" }?.parameters["outer"], "9.0")
    }
}
