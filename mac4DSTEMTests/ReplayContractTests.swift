//
//  ReplayContractTests.swift
//  The replay contract (`ReplayContract`) walked row by row against the
//  recording sites' own builders: every key a site writes has a row, the frame
//  map re-expresses it, the parser reads exactly the keys the row says it
//  reads, and the staleness signature compares exactly the keys the row marks
//  compared.
//

import XCTest
import DiffractoCore
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ReplayContractTests: XCTestCase {

    /// One step per kind from the site's own builder, carrying every key that
    /// kind can write (the branch that writes the most keys).
    private func recordedSamples() throws -> [String: [String: String]] {
        let aperture = Aperture(centerX: 31.5, centerY: 30, inner: 3, outer: 9)
        let kernel = try XCTUnwrap(ProbeKernel.synthetic(radius: 4, qy: 32, qx: 32))
        var disk = DiskDetectionParams()
        disk.relativeReferenceMinimumRadiusPx = 3   // non-default, so dropping the key changes the plan
        let gold = CrystalModelLibrary.customCubic(structure: .fcc, latticeA: 4.08, atomicNumber: 79)
        var acom = ReplayStepPlan.ACOMReplayPlan.recordedParameters(
            model: gold, scale: 0.0125, backend: "CPU", scope: .fullScan, quality: .balanced,
            refinesInPlaneAngle: true)
        // Written only for an imported CIF model, which a unit test has no file for.
        acom["material_fingerprint"] = "0123456789abcdef"
        return [
            "virtual_detector": Aperture.replayParameters(shape: VirtualShapeMode.annulus.rawValue, aperture: aperture),
            "dpc": ["origin_reference": "calibrated origins"],
            "disk_detection": disk.replayParameters(kernel: kernel).merging(learnedParameters) { _, new in new },
            "strain": StrainProduct.recordedParameters(
                referenceMaskApplied: false, automaticBasis: false,
                resolvedG1: (x: 10.5, y: 0.5), resolvedG2: (x: -0.5, y: 10),
                inputBasis: (g1: (x: 10, y: 0), g2: (x: 0, y: 10))),
            "acom": acom,
        ]
    }

    /// What `LearnedDetectionSession.replayParameters(for: .learned, ...)` writes
    /// for a fine-tuned model (the branch with every key).
    private let learnedParameters = [
        "detector_class": "learned", "learned_threshold": "0.5",
        "learned_model_sha256": "abc123", "learned_model_origin": "fine_tuned",
        "learned_model_parent_sha256": "def456",
    ]

    private func step(_ kind: String, _ parameters: [String: String]) -> SessionReplayRecord.Step {
        SessionReplayRecord.Step(kind: kind, parameters: parameters, recorded: Date(timeIntervalSince1970: 0))
    }

    func testEveryRecordedKindHasOneRowAndEveryRowARecordingTask() throws {
        let kinds = ReplayContract.entries.map(\.kind)
        XCTAssertEqual(Set(kinds).count, kinds.count, "a kind has two rows")
        let recordedByTasks = Set(AnalysisMode.allCases.compactMap(\.replayKind))
            .subtracting(SessionReplay.lineageOnlyProductKinds)
        XCTAssertEqual(Set(kinds), recordedByTasks,
                       "the contract's kinds and the tasks that record into the recipe differ")
        XCTAssertEqual(Set(try recordedSamples().keys), Set(kinds), "a row has no sample in this test")
    }

    func testEveryWrittenKeyHasARowAndEveryRowIsWritten() throws {
        for (kind, parameters) in try recordedSamples() {
            let entry = try XCTUnwrap(ReplayContract.entry(kind: kind))
            XCTAssertEqual(Set(parameters.keys), Set(entry.keys.keys),
                           "\(kind): the recording site and the contract name different keys")
        }
    }

    func testTheFrameMapReExpressesEveryWrittenStepAndTheResultStillParses() throws {
        for (kind, parameters) in try recordedSamples() {
            for key in parameters.keys {
                XCTAssertEqual(ReplayRecordFrameMap.role(kind: kind, key: key),
                               ReplayContract.entry(kind: kind)?.keys[key]?.role, "\(kind).\(key)")
            }
            let mapped = ReplayRecordFrameMap.map(step(kind, parameters),
                                                  through: .viewToSource(bin: 2, xOffset: 3, yOffset: 5))
            guard case .success(let mappedStep) = mapped else {
                XCTFail("\(kind): the frame map refused a step its site writes: \(mapped)")
                continue
            }
            XCTAssertNoThrow(try ReplayPlanner.parse(mappedStep).get(), "\(kind): the re-referenced step does not parse")
        }
    }

    /// A key the row marks `read` changes the parse when it is dropped, emptied
    /// or garbled; a key marked `notRead` changes nothing.
    func testTheParserReadsExactlyTheKeysTheContractSaysItReads() throws {
        for (kind, parameters) in try recordedSamples() {
            let entry = try XCTUnwrap(ReplayContract.entry(kind: kind))
            let baseline = ReplayPlanner.parse(step(kind, parameters))
            guard case .success(let plan) = baseline else {
                XCTFail("\(kind): the site's own step does not parse: \(baseline)")
                continue
            }
            for (key, contract) in entry.keys {
                var dropped = parameters; dropped[key] = nil
                var emptied = parameters; emptied[key] = ""
                var garbled = parameters; garbled[key] = "#garbled"
                let read = [dropped, emptied, garbled].contains { ReplayPlanner.parse(step(kind, $0)) != baseline }
                XCTAssertEqual(read, contract.replay == .read, "\(kind).\(key): the parser and the contract disagree")
            }
            let readsFrameNumbers = entry.keys.values.contains { $0.replay == .read && $0.role != .invariant }
            XCTAssertEqual(plan.usesDetectorFrameParameters, readsFrameNumbers,
                           "\(kind): the frame gate and the contract's roles disagree")
        }
    }

    /// The builder each task's staleness check runs writes only keys the row
    /// marks compared, and every compared key is one some builder writes.
    func testTheStalenessSignatureComparesExactlyTheContractsComparedKeys() throws {
        let kernel = try XCTUnwrap(ProbeKernel.synthetic(radius: 4, qy: 32, qx: 32))
        let strain = StrainProduct()
        strain.basisMode = .manual
        let gold = CrystalModelLibrary.customCubic(structure: .fcc, latticeA: 4.08, atomicNumber: 79)
        let acom = ReplayStepPlan.ACOMReplayPlan.currentSignatureIfResolved(
            model: gold, scale: 0.0125, backend: "CPU", scope: .fullScan, quality: .balanced,
            refinesInPlaneAngle: true)
        // Written only for an imported CIF model (see `recordedSamples`).
        let notBuildableHere: Set<String> = ["material_fingerprint"]
        for mode in AnalysisMode.allCases {
            guard let kind = mode.replayKind, let entry = ReplayContract.entry(kind: kind) else { continue }
            func signature(kernel: ProbeKernel?) -> [String: String]? {
                ProductWorkflow.settingsSignature(
                    for: mode, virtualDetectorShape: VirtualShapeMode.circle.rawValue,
                    aperture: Aperture(centerX: 16, centerY: 16, inner: 0, outer: 4),
                    dpcOriginReference: "global center", diskKernel: kernel, diskParams: DiskDetectionParams(),
                    learnedDetectorParameters: learnedParameters, strainSignature: strain.currentReplaySignature,
                    acomSignature: acom, diskPeaksProvenance: [:])
            }
            let built = try XCTUnwrap(signature(kernel: kernel), "\(kind): no signature")
            XCTAssertTrue(Set(built.keys).isSubset(of: entry.signatureKeys),
                          "\(kind): the signature compares keys the contract does not: \(Set(built.keys).subtracting(entry.signatureKeys).sorted())")
            XCTAssertEqual(entry.signatureKeys.subtracting(built.keys).subtracting(notBuildableHere), [],
                           "\(kind): the contract marks keys compared that the signature never carries")
            // Peaks restored from a sidecar, before any kernel: judged by their provenance.
            if mode == .disks {
                let fromProvenance = try XCTUnwrap(signature(kernel: nil))
                XCTAssertTrue(Set(fromProvenance.keys).isSubset(of: entry.signatureKeys), "provenance signature")
            }
            XCTAssertEqual(ProductWorkflow.currentReplaySignature(
                for: mode, virtualDetectorShape: VirtualShapeMode.circle.rawValue,
                aperture: Aperture(centerX: 16, centerY: 16, inner: 0, outer: 4),
                dpcOriginReference: "global center", diskKernel: kernel, diskParams: DiskDetectionParams(),
                learnedDetectorParameters: learnedParameters, strainSignature: strain.currentReplaySignature,
                acomSignature: acom, diskPeaksProvenance: [:]), built,
                "\(kind): the contract's filter dropped a key the builder writes")
        }
    }

    /// The titles moved into the table unchanged.
    func testTitlesComeFromTheContract() {
        XCTAssertEqual(ReplayPlanner.title(forKind: "virtual_detector"), "Virtual detector")
        XCTAssertEqual(ReplayPlanner.title(forKind: "dpc"), "DPC")
        XCTAssertEqual(ReplayPlanner.title(forKind: "disk_detection"), "Bragg disk detection")
        XCTAssertEqual(ReplayPlanner.title(forKind: "strain"), "Strain mapping")
        XCTAssertEqual(ReplayPlanner.title(forKind: "acom"), "ACOM orientation mapping")
        XCTAssertEqual(ReplayPlanner.title(forKind: "unknown_kind"), "unknown_kind")
    }
}
