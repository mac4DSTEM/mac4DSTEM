//
//  MethodTests.swift
//  v5.0 WP3 lane M (prediction M1, first half): the quantification method as a byte-stable value with a hash,
//  and the replay step "quantification" with its input edges and its rewind. Each test names the mutation it
//  catches; each was broken once.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM
@testable import SpectroCore

@MainActor
final class QuantificationMethodTests: XCTestCase {

    private func richMethod() -> QuantificationMethod {
        var m = QuantificationMethod()
        m.estimator = .poissonMaximumLikelihood
        m.background = .wholeRangePolynomial6
        m.elements = [
            .init(symbol: "Mg", role: .quantify, isManual: true),
            .init(symbol: "Si", role: .quantify, isManual: false),
            .init(symbol: "Cu", role: .fitOnly, isManual: false),
        ]
        m.kFactorSource = .typed
        m.kSource = "Williams & Carter, table 4"
        m.kDate = "2026-10-06"
        m.kReference = "Si"
        m.typedK = [.init(element: "Mg", k: 1.12, relativeSigma: 0.1), .init(element: "Si", k: 1)]
        m.absorptionCorrection = false
        m.thickness = .init(nanometres: 55, sigmaNanometres: 5)
        return m
    }

    /// ADR 054's defaults, unchanged by the move into Core.
    /// Mutation: `estimator` default `.poissonMaximumLikelihood`, or `absorptionCorrection` default false — red.
    func testDefaultsAreADR054sAndTheOldNameStillResolves() {
        let m = QuantificationMethod()
        XCTAssertEqual(m.estimator, .leastSquares)
        XCTAssertEqual(m.background, .empiricalWithAlEdge)
        XCTAssertEqual(m.kFactorSource, .computed)
        XCTAssertEqual(QuantificationMethod.KFactorSource.brownPowell, .computed)
        XCTAssertTrue(m.absorptionCorrection)
        XCTAssertNil(m.thickness)
        XCTAssertTrue(m.isComplete, "a computed k needs nothing typed")
        XCTAssertEqual(SpectroscopySession().method, m, "the room's method is this value")
    }

    /// Re-running the phase map or the objects takes the quantification off the active path (the projection is unchanged).
    /// Mutation: drop either `downstreamKinds` entry — red.
    func testRerunningPhasesOrObjectsTakesTheQuantificationOffThePath() {
        for rerun in ["phase_mapping", "precipitate_objects"] {
            let replay = SessionReplay()
            replay.record(kind: "phase_mapping", parameters: ["a": "1"], under: .detectorIdentity)
            replay.record(kind: "precipitate_objects", parameters: ["a": "1"], under: .detectorIdentity)
            SpectroscopySession().recordQuantification(in: replay)
            XCTAssertTrue(replay.lineage.activeNodes().contains { $0.kind == "quantification" })
            replay.record(kind: rerun, parameters: ["a": "2"], under: .detectorIdentity)
            XCTAssertFalse(replay.lineage.activeNodes().contains { $0.kind == "quantification" }, rerun)
            XCTAssertEqual(replay.lineage.nodes.filter { $0.kind == "quantification" }.count, 1, "off the path, not deleted")
        }
    }

    /// The session's element list IS the method's (one copy), and opening a spectrum image still clears it.
    /// Mutation: make `elements` a stored property again — the method's list then stays empty, red.
    func testTheSessionsElementsAreTheMethodsElements() {
        let session = SpectroscopySession()
        session.elements = [SpectroscopyElement(symbol: "Mg", role: .quantify, isManual: true)]
        XCTAssertEqual(session.method.elements.map(\.symbol), ["Mg"])
        session.method.elements.append(.init(symbol: "Si", role: .fitOnly, isManual: false))
        XCTAssertEqual(session.elements.map(\.symbol), ["Mg", "Si"])
    }

    // MARK: - The replay step (ADR 047)

    /// P2: the step records with its input edges, stays out of the linear projection, survives JSON byte for
    /// byte, and a rewind restores the method.
    /// Mutations: remove "quantification" from `lineageOnlyKinds` (the projection then carries it, red); drop its
    /// `inputPolicy` row (no edges, red); drop `parameters["method_hash"]` (restore refuses, red).
    func testTheQuantificationStepRecordsEdgesRoundTripsAndRewinds() throws {
        let replay = SessionReplay()
        let phases = replay.record(kind: "phase_mapping", parameters: ["phases": "Al,Q"], under: .detectorIdentity)
        let objects = replay.record(kind: "precipitate_objects", parameters: ["min_area": "4"], under: .detectorIdentity)
        let session = SpectroscopySession()
        session.method = richMethod()
        let registration = RegistrationRecordM2(matrix: [-0.5, 0, 32.75, 0, 0.5, 0.75], source: .simulatorTruth,
                                                sourceNote: "truth_edx_regmismatch.json",
                                                scanWidth: 64, scanHeight: 48, spectrumWidth: 32, spectrumHeight: 24)
        let first = session.recordQuantification(in: replay, registration: registration, regionKind: "phase", regionName: "Q")

        let node = try XCTUnwrap(replay.lineage.node(id: first))
        XCTAssertEqual(node.kind, "quantification")
        XCTAssertEqual(node.inputs, [.init(step: phases, role: "phases"), .init(step: objects, role: "objects")])
        XCTAssertEqual(node.parameters["registration_source"], "simulatorTruth")
        XCTAssertFalse(replay.record.steps.contains { $0.kind == "quantification" },
                       "an older build's linear record never carries it")

        // Same inputs, other method, no children, no product: collapses into the one node (R3).
        session.method.estimator = .leastSquares
        let second = session.recordQuantification(in: replay, registration: registration, regionKind: "phase", regionName: "Q")
        XCTAssertEqual(second, first)
        XCTAssertEqual(replay.lineage.nodes.filter { $0.kind == "quantification" }.count, 1)

        // The lineage as a file: byte-identical re-encode.
        let json = try XCTUnwrap(replay.lineage.jsonString)
        let parsed = try XCTUnwrap(SessionLineage.parse(json))
        XCTAssertEqual(parsed.jsonString, json)
        XCTAssertEqual(parsed.node(id: first)?.parameters, replay.lineage.node(id: first)?.parameters)

        // Branch: a different method after saving the product is a new node; rewind to the first restores it.
        replay.markProduct(step: first, as: "quant_table_1")
        let methodAtFirst = session.method
        session.method.thickness = .init(nanometres: 80, sigmaNanometres: 8)
        let third = session.recordQuantification(in: replay, registration: registration, regionKind: "phase", regionName: "Q")
        XCTAssertNotEqual(third, first)
        let plan = try replay.lineage.rewindPlan(to: first).get()
        XCTAssertTrue(plan.restore.contains(first))
        replay.apply(plan)
        let restored = session.restoreQuantification(parameters: try XCTUnwrap(replay.lineage.node(id: first)).parameters)
        XCTAssertNotNil(restored)
        XCTAssertEqual(session.method, methodAtFirst, "rewind restores the method")
        XCTAssertEqual(session.method.hash, methodAtFirst.hash)
        XCTAssertEqual(restored?.registration, registration)
    }

    /// A step whose JSON no longer matches its hash, or with no method, restores nothing.
    /// Mutation: skip the hash comparison in `QuantificationStep.init?(parameters:)` — red.
    func testARestoreRefusesATamperedStep() {
        let step = QuantificationStep(method: richMethod())
        var p = step.parameters
        XCTAssertNotNil(QuantificationStep(parameters: p))
        p["method_hash"] = String(repeating: "0", count: 64)
        XCTAssertNil(QuantificationStep(parameters: p))
        XCTAssertNil(QuantificationStep(parameters: ["region_kind": "wholeMap"]))
        let session = SpectroscopySession()
        XCTAssertNil(session.restoreQuantification(parameters: p))
        XCTAssertEqual(session.method, QuantificationMethod(), "a refused restore changes nothing")
    }
}
