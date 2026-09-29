//
//  SessionLineageSidecarTests.swift
//  ADR 047, phase L1 — the lineage through the PRODUCTION writer and reader:
//  schema 7, R5 (the attribute), R6 (the record beside it), R7 (v1 files open
//  read-only), R8 (hostile attributes refuse by name).
//
//  THE v6 FIXTURE. The ADR asks for a committed fixture from the v4.0.0 tag;
//  none is committed (building the tag costs a second DerivedData on a disk
//  that is tight), so `makeV6Sidecar` builds the same thing: the current
//  writer, handed a plain record with NO lineage — exactly the attribute set
//  a schema-6 writer produced — with the schema stamp then patched to "6".
//  What is not covered by that construction is byte-level identity with a
//  file the old binary wrote; the attribute set is, and the reader's only
//  input is the attribute set.
//
//  Every test names the mutation it catches. Break each one before trusting it.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class SessionLineageSidecarTests: XCTestCase {

    private var workDirectory: URL!
    private let lineageName = SessionSidecarFormat.lineageAttribute

    override func setUpWithError() throws {
        _ = BraggVectorEMDWriter.takeLineageOmission()   // drain what another test left
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionLineageSidecarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private var calibration: PixelCalibration {
        PixelCalibration(rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false)
    }

    private var binned: LoadSpecification { LoadSpecification(detectorBin: 2) }

    private func url(_ name: String) -> URL {
        workDirectory.appendingPathComponent("\(name).mac4dstem.h5")
    }

    private func date(_ index: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(index)) }

    /// origin → disks → strain → (re-detect: a branch) → strain again, plus an
    /// imported-phase ACOM: enough edges, one branch, one external.
    private func sampleLineage() -> SessionLineage {
        let frame = SessionLineage.Frame(bin: 2, crop: nil)
        var lineage = SessionLineage()
        lineage.recordRun(kind: "calibration_origin", parameters: ["fit_function": "Plane"], frame: frame, at: date(1))
        lineage.recordRun(kind: "disk_detection", parameters: ["sigma_cc": "2.0"], frame: frame, at: date(2))
        lineage.recordRun(kind: "strain", parameters: ["basis_mode": "consensus"], frame: frame, at: date(3))
        lineage.recordRun(kind: "disk_detection", parameters: ["sigma_cc": "3.5"], frame: frame, at: date(4))
        lineage.recordRun(kind: "strain", parameters: ["basis_mode": "consensus"], frame: frame, at: date(5))
        lineage.recordRun(kind: "acom", parameters: ["material": "imported_theta", "material_fingerprint": "00ff"],
                          frame: frame, at: date(6))
        return lineage
    }

    private func attached(_ lineage: SessionLineage) -> SessionReplayRecord {
        SessionReplayRecord(steps: lineage.projection().steps, lineage: lineage)
    }

    private func save(_ record: SessionReplayRecord?, to url: URL,
                      specification: LoadSpecification? = nil) throws {
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 32, qHeight: 32, to: url,
            loadSpecification: specification, replayRecord: record)
    }

    /// A schema-6 sidecar as v4.0.0 wrote it: a record, no lineage, stamp "6".
    private func makeV6Sidecar(at url: URL) throws -> SessionReplayRecord {
        var record = SessionReplayRecord()
        record.record(kind: "disk_detection", parameters: ["sigma_cc": "2.0"], at: date(10))
        record.record(kind: "strain", parameters: ["basis_mode": "automatic"], at: date(11))
        try save(record, to: url, specification: binned)
        try SidecarPatcher.write(.variableString("6"), named: SessionSidecarFormat.schemaAttribute, into: url)
        return record
    }

    private func expectRefusal(_ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try BraggVectorEMDWriter.loadSession(from: url), file: file, line: line) { error in
            guard case BraggVectorEMDWriter.WriterError.malformedAttribute(let name) = error else {
                return XCTFail("Expected malformedAttribute, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(name, "mac4dstem_lineage", file: file, line: line)
        }
    }

    // MARK: - Schema 7 and the round trip

    /// Mutation it catches: leave `currentSchema` at 6; write no lineage
    /// attribute; decode a different graph than was written; re-encode with
    /// different bytes after the trip.
    func testTheLineageRoundTripsThroughTheSidecarByteIdentically() throws {
        XCTAssertEqual(SessionSidecarFormat.currentSchema, 7)
        let lineage = sampleLineage()
        let first = url("first")
        try save(attached(lineage), to: first, specification: binned)
        let snapshot = try BraggVectorEMDWriter.loadSession(from: first)
        XCTAssertEqual(snapshot.lineage, lineage)
        XCTAssertNil(snapshot.lineageNote)
        XCTAssertEqual(snapshot.lineage?.nodes.map(\.source), Array(repeating: "live", count: 6))
        XCTAssertEqual(snapshot.replayRecord, lineage.projection(), "R6: the record beside it is its projection")
        XCTAssertEqual(snapshot.replayRecord?.steps.map(\.kind), ["disk_detection", "strain", "acom"])
        let original = try XCTUnwrap(lineage.jsonString)
        XCTAssertEqual(snapshot.lineage?.jsonString, original)

        // Save what was read, read again: the same bytes.
        let second = url("second")
        try save(snapshot.lineage.map(attached), to: second, specification: binned)
        XCTAssertEqual(try BraggVectorEMDWriter.loadSession(from: second).lineage?.jsonString, original)
    }

    /// Mutation it catches: raise the marker with the lineage (v4.0.0 would
    /// refuse every session), or stop writing the record beside the lineage.
    func testTheMinimumReaderMarkerDidNotMoveWithTheLineage() throws {
        let lineage = sampleLineage()
        let full = url("full"), cropped = url("cropped")
        try save(attached(lineage), to: full)
        try save(attached(lineage), to: cropped, specification: binned)
        XCTAssertNoThrow(try BraggVectorEMDWriter.loadSession(from: full, supportedSchema: 5),
                         "full extent: marker 5, as before schema 7")
        XCTAssertNoThrow(try BraggVectorEMDWriter.loadSession(from: cropped, supportedSchema: 6),
                         "reduced view: marker 6, as before schema 7")
        XCTAssertThrowsError(try BraggVectorEMDWriter.loadSession(from: cropped, supportedSchema: 5))
    }

    /// Mutation it catches: preserve nothing when the caller has no record —
    /// a colleague's calibration save would erase the graph.
    func testASaveThatSaysNothingKeepsTheLineageAndOneWithoutALineageDropsTheStaleOne() throws {
        let lineage = sampleLineage()
        let target = url("keep")
        try save(attached(lineage), to: target)
        try save(nil, to: target)
        XCTAssertEqual(try BraggVectorEMDWriter.loadSession(from: target).lineage, lineage,
                       "nil record: the file's lineage survives, like its recipe")

        // A caller that predates the lineage hands a plain record: the file's
        // graph would be stale against it, so it is not carried — the file
        // reads as v1 again rather than assert a chain the record disowns.
        var plain = SessionReplayRecord()
        plain.record(kind: "dpc", parameters: ["origin_reference": "global center"], at: date(20))
        try save(plain, to: target)
        let snapshot = try BraggVectorEMDWriter.loadSession(from: target)
        XCTAssertEqual(snapshot.lineage?.nodes.map(\.kind), ["dpc"])
        XCTAssertEqual(snapshot.lineage?.nodes.map(\.source), ["v1"])
        XCTAssertNil(snapshot.lineageNote, "no lineage attribute is not a disagreement")
    }

    /// A session whose only runs were calibrations: no replayable step, but a graph.
    /// Mutation it catches: write `{"steps":[]}` beside it (an asserted empty
    /// recipe), or drop the lineage because the recipe is empty.
    func testACalibrationOnlyLineageIsSavedWithoutAnAssertedEmptyRecipe() throws {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "calibration_origin", parameters: ["fit_function": "Plane"],
                          frame: SessionLineage.Frame(), at: date(1))
        let target = url("calibration-only")
        try save(attached(lineage), to: target)
        let snapshot = try BraggVectorEMDWriter.loadSession(from: target)
        XCTAssertNil(snapshot.replayRecord, "absence is absence: no recipe was recorded")
        XCTAssertEqual(snapshot.lineage, lineage)
    }

    // MARK: - R7: v1 sidecars open read-only

    /// Mutation it catches: infer edges when synthesizing (`inputs` non-nil),
    /// write during load (bytes change), or drop the frame the specification
    /// gave the record.
    func testAV6SidecarOpensWithTheLineageSynthesizedInputsAbsentAndTheFileUntouched() throws {
        let target = url("v6")
        let record = try makeV6Sidecar(at: target)
        let before = try Data(contentsOf: target)
        let modified = try FileManager.default.attributesOfItem(atPath: target.path)[.modificationDate] as? Date

        let snapshot = try BraggVectorEMDWriter.loadSession(from: target)
        _ = try BraggVectorEMDWriter.loadSession(from: target)   // and again: still a pure read

        XCTAssertEqual(snapshot.replayRecord, record)
        let lineage = try XCTUnwrap(snapshot.lineage)
        XCTAssertEqual(lineage.nodes.map(\.id), ["s1", "s2"])
        XCTAssertEqual(lineage.nodes.map(\.kind), ["disk_detection", "strain"])
        XCTAssertEqual(lineage.nodes.map(\.source), ["v1", "v1"])
        XCTAssertEqual(lineage.nodes.map(\.inputs), [nil, nil], "unknown, not a chain")
        XCTAssertEqual(lineage.nodes.map(\.frame),
                       Array(repeating: Optional(SessionLineage.Frame(bin: 2, crop: nil)), count: 2))
        XCTAssertEqual(lineage.projection(), record)
        XCTAssertNil(snapshot.lineageNote)
        XCTAssertEqual(try Data(contentsOf: target), before, "opening never rewrites the file (the F1 rule)")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: target.path)[.modificationDate] as? Date, modified)
    }

    /// Mutation it catches: `adopt` ignoring the synthesized graph, or a save
    /// that re-derives the nodes as live.
    @MainActor
    func testTheFirstSaveAfterOpeningAV1FileWritesV7WithThoseNodesStillMarkedV1() throws {
        let target = url("v6-resave")
        _ = try makeV6Sidecar(at: target)
        let snapshot = try BraggVectorEMDWriter.loadSession(from: target)
        let replay = SessionReplay()
        replay.adopt(snapshot.replayRecord, lineage: snapshot.lineage, recordedOn: .detectorReduced(bin: 2, crop: nil))
        let id = replay.record(kind: "virtual_detector", parameters: ["outer": "6"],
                               under: .detectorReduced(bin: 2, crop: nil))
        XCTAssertEqual(id, "s3")
        try save(replay.recordForSaving, to: target, specification: binned)

        let reread = try BraggVectorEMDWriter.loadSession(from: target)
        XCTAssertEqual(reread.lineage?.nodes.map(\.source), ["v1", "v1", "live"])
        XCTAssertEqual(reread.lineage?.nodes.map(\.id), ["s1", "s2", "s3"])
        XCTAssertEqual(reread.lineage?.nodes.map(\.inputs), [nil, nil, []])
        XCTAssertEqual(reread.replayRecord?.steps.map(\.kind), ["disk_detection", "strain", "virtual_detector"])
    }

    /// R7's other clause: both attributes present and disagreeing is a foreign
    /// or hand-edited file. Read as v1, with a named note, never merged.
    /// Mutation it catches: skip the projection comparison (the lineage would
    /// be trusted over the record a replay actually runs).
    func testALineageThatDisagreesWithItsRecordIsReadAsV1WithANote() throws {
        let target = url("disagree")
        try save(attached(sampleLineage()), to: target, specification: binned)
        var other = SessionReplayRecord()
        other.record(kind: "dpc", parameters: ["origin_reference": "global center"], at: date(30))
        try SidecarPatcher.write(.variableString(try XCTUnwrap(other.jsonString)),
                                 named: SessionSidecarFormat.replayRecordAttribute, into: target)
        let snapshot = try BraggVectorEMDWriter.loadSession(from: target)
        XCTAssertNotNil(snapshot.lineageNote)
        XCTAssertEqual(snapshot.replayRecord, other, "the record is what a replay runs")
        XCTAssertEqual(snapshot.lineage?.nodes.map(\.kind), ["dpc"], "nothing of the disagreeing graph is merged")
        XCTAssertEqual(snapshot.lineage?.nodes.map(\.source), ["v1"])
    }

    // MARK: - Old readers

    /// A v7 file read as a schema-6 reader reads it: everything a v4.0.0 build
    /// restored still restores. `supportedSchema: 6` is the reader that
    /// predates the attribute — it never looks at it, which the synthesized v1
    /// nodes (not the file's `live` ones) prove.
    /// Mutation it catches: read the lineage regardless of `supportedSchema`;
    /// raise the marker; make the direct result readers depend on the lineage.
    func testAV7FileReadByTheSchema6PathStillRestoresEverything() throws {
        let lineage = sampleLineage()
        let target = url("v7-for-v6")
        let map = ScalarResultMap(width: 16, height: 8, pixels: (0..<128).map(Float.init),
                                  kind: "virtual_detector", displayName: "VD", valueUnits: "counts")
        try BraggVectorEMDWriter.mergeResultMap(
            map, vectors: nil, qWidth: 32, qHeight: 32, calibration: calibration, to: target,
            loadSpecification: binned, replayRecord: attached(lineage))

        let asV7 = try BraggVectorEMDWriter.loadSession(from: target)
        XCTAssertEqual(asV7.lineage?.nodes.map(\.source), Array(repeating: "live", count: 6))

        let asV6 = try BraggVectorEMDWriter.loadSession(from: target, supportedSchema: 6)
        XCTAssertEqual(asV6.replayRecord, lineage.projection(), "the linear record is still the recipe")
        XCTAssertEqual(asV6.loadSpecification, binned)
        XCTAssertEqual(asV6.inventory.results.count, 1)
        XCTAssertEqual(asV6.lineage?.nodes.map(\.source), ["v1", "v1", "v1"], "the attribute was not consulted")
        let id = try XCTUnwrap(asV6.inventory.results.first?.id)
        XCTAssertEqual(try BraggVectorEMDWriter.loadResultMap(id: id, from: target, supportedSchema: 6)?.pixels,
                       map.pixels)

        // And an attribute this reader cannot make sense of cannot brick it.
        try SidecarPatcher.write(.double(2.5), named: lineageName, into: target)
        XCTAssertNoThrow(try BraggVectorEMDWriter.loadSession(from: target, supportedSchema: 6))
    }

    // MARK: - R8: hostile attributes refuse by name

    private func writeValidV7(_ name: String) throws -> URL {
        let target = url(name)
        try save(attached(sampleLineage()), to: target, specification: binned)
        return target
    }

    /// Mutation it catches: delete the single-element guard (an array read into
    /// one pointer — the D003 overrun), the string-class check (a number),
    /// the 4 MiB cap (valid JSON padded with blanks still decodes), the
    /// input-existence check, or the cycle check — each goes red alone.
    func testHostileLineageAttributesRefuseByName() throws {
        // An array of strings.
        var target = try writeValidV7("hostile-array")
        try SidecarPatcher.write(.fixedStrings(["{}", "[]"], size: 4), named: lineageName, into: target)
        expectRefusal(target)

        // A number.
        target = try writeValidV7("hostile-number")
        try SidecarPatcher.write(.double(2.5), named: lineageName, into: target)
        expectRefusal(target)

        // Over 4 MiB: a VALID lineage padded with blanks, so only the cap trips.
        target = try writeValidV7("hostile-large")
        let valid = try XCTUnwrap(sampleLineage().jsonString)
        try SidecarPatcher.write(
            .variableString(valid + String(repeating: " ", count: SessionLineage.maximumJSONBytes)),
            named: lineageName, into: target)
        expectRefusal(target)

        // A dangling input id.
        target = try writeValidV7("hostile-dangling")
        try SidecarPatcher.write(
            .variableString(valid.replacingOccurrences(of: "\"step\":\"s2\"", with: "\"step\":\"s99\"")),
            named: lineageName, into: target)
        expectRefusal(target)

        // A cycle: s2 (disk detection, no peaks input) made to consume s3, which consumes s2.
        target = try writeValidV7("hostile-cycle")
        let cyclic = lineageJSON(nodes: [
            nodeJSON(id: "s1", inputs: ["s2"]), nodeJSON(id: "s2", inputs: ["s1"]),
        ])
        try SidecarPatcher.write(.variableString(cyclic), named: lineageName, into: target)
        expectRefusal(target)

        // Undecodable text, and a hostile next_id (Int.max: the next run would trap).
        target = try writeValidV7("hostile-text")
        try SidecarPatcher.write(.variableString("not json"), named: lineageName, into: target)
        expectRefusal(target)
        target = try writeValidV7("hostile-next-id")
        try SidecarPatcher.write(
            .variableString(valid.replacingOccurrences(of: "\"next_id\":7", with: "\"next_id\":\(Int.max)")),
            named: lineageName, into: target)
        expectRefusal(target)

        // The control: the untouched neighbour of every case above opens.
        XCTAssertNoThrow(try BraggVectorEMDWriter.loadSession(from: try writeValidV7("control")))
    }

    /// Mutation it catches: remove the `catch malformedAttribute` in the
    /// preserve path — a hostile attribute on a file this save is about to
    /// rewrite (and cannot carry forward) would block the save.
    func testASaveOverAnUnreadableLineageIsNotBlockedAndDoesNotCarryItForward() throws {
        let target = try writeValidV7("unreadable")
        try SidecarPatcher.write(.double(2.5), named: lineageName, into: target)
        XCTAssertNoThrow(try save(nil, to: target, specification: binned))
        let snapshot = try BraggVectorEMDWriter.loadSession(from: target)
        XCTAssertNotNil(snapshot.replayRecord, "the recipe was preserved")
        XCTAssertEqual(snapshot.lineage?.nodes.map(\.source), Array(repeating: "v1", count: 3),
                       "the hostile attribute is gone; the graph is the v1 synthesis")
    }

    // MARK: - Gate B fixes: what the writer will not write

    /// A lineage this build's own reader would refuse (2 001 nodes) must not be
    /// written: the file has to stay openable. The recipe is written, the
    /// lineage is omitted, and the omission is reported.
    /// Mutation it catches: write the lineage without `SessionLineage.writable`
    /// — the next `loadSession` throws `malformedAttribute`.
    func testALineageTheReaderWouldRefuseIsOmittedAndReported() throws {
        let nodes = (1...2_001).map { nodeJSON(id: "s\($0)", kind: "kind_\($0)") }
        let oversized = try JSONDecoder.lineage.decode(
            SessionLineage.self, from: Data(lineageJSON(nodes: nodes, nextID: 3_000).utf8))
        XCTAssertEqual(oversized.nodes.count, 2_001, "precondition: decoded without validation")
        XCTAssertEqual(oversized.projection().steps.count, 2_001, "unknown kinds are recipe steps")
        let target = url("oversized")
        try save(attached(oversized), to: target)
        let snapshot = try BraggVectorEMDWriter.loadSession(from: target)   // must not throw
        XCTAssertNotNil(BraggVectorEMDWriter.takeLineageOmission())
        XCTAssertEqual(snapshot.replayRecord?.steps.count, 2_001, "the recipe is written")
        XCTAssertNil(snapshot.lineageNote)
        XCTAssertTrue(snapshot.lineage?.nodes.allSatisfy { $0.source == "v1" } ?? false,
                      "no lineage attribute: the graph is the in-memory v1 synthesis")
    }

    /// A lineage STRING carried forward from the file on a save that says
    /// nothing is checked like any other. Mutation it catches: carry it
    /// forward unchecked — the file is then unreadable to this very build.
    func testAnInvalidLineageStringIsNotCarriedForwardByASaveWithNoRecord() throws {
        let target = try writeValidV7("carry")
        let valid = try XCTUnwrap(sampleLineage().jsonString)
        try SidecarPatcher.write(
            .variableString(valid.replacingOccurrences(of: "\"step\":\"s2\"", with: "\"step\":\"s99\"")),
            named: lineageName, into: target)
        try save(nil, to: target, specification: binned)
        XCTAssertNotNil(BraggVectorEMDWriter.takeLineageOmission())
        let snapshot = try BraggVectorEMDWriter.loadSession(from: target)   // must not throw
        XCTAssertEqual(snapshot.lineage?.nodes.map(\.source), ["v1", "v1", "v1"])
        XCTAssertNotNil(snapshot.replayRecord, "the recipe was carried forward")
    }

    /// A calibration-only session saved over a file that has a recipe: the
    /// recipe stays, the lineage (which projects to nothing) is not written
    /// beside it, and the next open does not read a disagreement.
    /// Mutation it catches: drop the projection == record comparison in
    /// `writable` — the file then reads with a note and the lineage is lost.
    func testACalibrationOnlySaveOverARecipeKeepsTheRecipeAndOmitsTheLineage() throws {
        let target = url("cal-over-recipe")
        var plain = SessionReplayRecord()
        plain.record(kind: "dpc", parameters: ["origin_reference": "global center"], at: date(20))
        try save(plain, to: target)
        var calibrationOnly = SessionLineage()
        calibrationOnly.recordRun(kind: "calibration_origin", parameters: ["fit_function": "Plane"],
                                  frame: SessionLineage.Frame(), at: date(21))
        try save(attached(calibrationOnly), to: target)
        XCTAssertNotNil(BraggVectorEMDWriter.takeLineageOmission())
        let snapshot = try BraggVectorEMDWriter.loadSession(from: target)
        XCTAssertEqual(snapshot.replayRecord, plain, "the colleague's recipe is untouched")
        XCTAssertNil(snapshot.lineageNote, "no disagreement is ever written")
        XCTAssertEqual(snapshot.lineage?.nodes.map(\.kind), ["dpc"])
    }

    /// The agreeing writes report nothing. Mutation it catches: an omission
    /// note that is never cleared (the next good save would log a stale reason).
    func testAWriteThatKeepsTheLineageReportsNoOmission() throws {
        try save(attached(sampleLineage()), to: url("clean"), specification: binned)
        XCTAssertNil(BraggVectorEMDWriter.takeLineageOmission())
    }

    // MARK: - Gate B fixes: a newer lineage is a note, not a refusal

    /// The file's minimum-reader marker says this build can read it, so a
    /// lineage version it does not know cannot refuse the sidecar.
    /// Mutation it catches: refuse on `unsupportedVersion` (the pre-fix reader),
    /// or decode the future nodes before the version is known.
    func testANewerLineageVersionReadsAsV1WithANoteAndTheRecipeRestores() throws {
        let target = try writeValidV7("future")
        let future = "{\"version\":3,\"graph\":{\"vertices\":[1,2,3]},\"nodes\":\"reshaped\"}"
        try SidecarPatcher.write(.variableString(future), named: lineageName, into: target)
        let snapshot = try BraggVectorEMDWriter.loadSession(from: target)   // must not throw
        let note = try XCTUnwrap(snapshot.lineageNote)
        XCTAssertTrue(note.contains("version 3"), note)
        XCTAssertEqual(snapshot.replayRecord, sampleLineage().projection(), "the recipe restores")
        XCTAssertEqual(snapshot.lineage?.nodes.map(\.source), ["v1", "v1", "v1"])
        XCTAssertNil(snapshot.lineage?.nodes.first?.inputs)

        // And a save over it replaces it, saying so — it is not carried unchecked.
        try save(nil, to: target, specification: binned)
        XCTAssertNotNil(BraggVectorEMDWriter.takeLineageOmission())
        XCTAssertNil(try BraggVectorEMDWriter.loadSession(from: target).lineageNote)
    }

    private func nodeJSON(id: String, inputs: [String] = [], kind: String = "strain") -> String {
        let edges = inputs.map { "{\"role\":\"peaks\",\"step\":\"\($0)\"}" }.joined(separator: ",")
        return "{\"external\":[],\"id\":\"\(id)\",\"inputs\":[\(edges)],\"kind\":\"\(kind)\",\"parameters\":{},\"recorded\":1,\"source\":\"live\"}"
    }

    private func lineageJSON(nodes: [String], nextID: Int = 100, version: Int = 2) -> String {
        "{\"head\":null,\"next_id\":\(nextID),\"nodes\":[\(nodes.joined(separator: ","))],\"version\":\(version)}"
    }
}

private extension JSONDecoder {
    /// The decoder `SessionLineage` uses, WITHOUT its validation — to build the
    /// over-cap graph a hostile or future file could hold.
    static var lineage: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
