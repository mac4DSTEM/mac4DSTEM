//
//  PrecipitateTableHighlightTests.swift
//  A selected row of the object table outlines its object on the map: the
//  pure outline (`PrecipitateHighlight`), and the wiring that keeps it from
//  ever drawing on another run's or another window's map or reaching a
//  published product (`AppState.precipitateHighlightOutline(for:)`).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PrecipitateTableHighlightTests: XCTestCase {

    /// 5 wide × 3 high. Class 1: a single pixel at (0, 2). Class 2: a 2 × 2
    /// block at columns 3–4, rows 0–1. Matrix elsewhere.
    ///   0 0 0 2 2
    ///   0 0 0 2 2
    ///   1 0 0 0 0
    private func classMap() -> PrecipitateSegmentation.ClassMapObjects {
        var labels = [Int32](repeating: 0, count: 15)
        labels[2 * 5 + 0] = 1
        for (x, y) in [(3, 0), (4, 0), (3, 1), (4, 1)] { labels[y * 5 + x] = 2 }
        return PrecipitateSegmentation.classObjects(
            labels: labels, width: 5, height: 3,
            roles: .init(precipitateClasses: [1, 2], matrix: [0], notIndexed: []),
            pixelSize: nil, pixelUnit: nil)
    }

    private func objectID(label: Int32, in objects: PrecipitateSegmentation.ClassMapObjects) -> Int {
        objects.classes.first { $0.label == label }!.objects[0].id
    }

    private func publishObjectsPicture(_ state: AppState) {
        state.publishProduct(kind: "precipitate_objects", displayName: "Precipitate Objects",
                             valueUnits: "phase",
                             payload: .scalar(FloatImage(width: 5, height: 3,
                                                         pixels: [Float](repeating: 0, count: 15))),
                             domain: .scan)
    }

    /// (a) The pixel set and the outline of the selected object are exactly
    /// that object's. Break-first: `ids.contains(object.id)` → `true` in
    /// `pixels` adds the other object and goes red.
    func testHighlightCoversExactlyTheSelectedObject() {
        let objects = classMap()
        let block = objectID(label: 2, in: objects), single = objectID(label: 1, in: objects)
        XCTAssertNotEqual(block, single, "test precondition: ids are distinct across classes")

        XCTAssertEqual(PrecipitateHighlight.pixels(objects: objects, ids: [block]), [3, 4, 8, 9])
        XCTAssertEqual(PrecipitateHighlight.pixels(objects: objects, ids: [single]), [10])
        XCTAssertTrue(PrecipitateHighlight.pixels(objects: objects, ids: [999]).isEmpty)

        // A 2 × 2 block has 8 boundary edges, all on x ∈ {3, 5} or y ∈ {0, 2}
        // (the scan edge counts as a boundary); a lone pixel has 4.
        let blockEdges = PrecipitateHighlight.outline(objects: objects, ids: [block])
        XCTAssertEqual(blockEdges.count, 8)
        XCTAssertEqual(Set(blockEdges), [
            .init(x0: 3, y0: 0, x1: 3, y1: 1), .init(x0: 3, y0: 1, x1: 3, y1: 2),
            .init(x0: 5, y0: 0, x1: 5, y1: 1), .init(x0: 5, y0: 1, x1: 5, y1: 2),
            .init(x0: 3, y0: 0, x1: 4, y1: 0), .init(x0: 4, y0: 0, x1: 5, y1: 0),
            .init(x0: 3, y0: 2, x1: 4, y1: 2), .init(x0: 4, y0: 2, x1: 5, y1: 2),
        ])
        XCTAssertEqual(Set(PrecipitateHighlight.outline(objects: objects, ids: [single])), [
            .init(x0: 0, y0: 2, x1: 0, y1: 3), .init(x0: 1, y0: 2, x1: 1, y1: 3),
            .init(x0: 0, y0: 2, x1: 1, y1: 2), .init(x0: 0, y0: 3, x1: 1, y1: 3),
        ])
        // Both selected: two disjoint outlines, 12 edges.
        XCTAssertEqual(PrecipitateHighlight.outline(objects: objects, ids: [block, single]).count, 12)
    }

    /// (b) One relay, two windows. Break-first mutations (logs a4-mut-*):
    /// the match ignoring `sourceID` (B goes red); the outline built from every
    /// object instead of the selection; the kind gate dropped; `publish`
    /// keeping its old `sourceID` (the re-run assertion goes red).
    func testTheRelayHighlightsOnlyTheRunItCameFromAndNeverRepublishes() {
        let a = AppState(), b = AppState(), other = AppState()
        let resultA = classMap()
        a.precipitateClassification.publish(resultA)
        b.precipitateClassification.publish(classMap())
        other.precipitateClassification.publish(classMap())
        publishObjectsPicture(a); publishObjectsPicture(b)     // `other` shows no objects picture
        let id = objectID(label: 2, in: resultA)
        let sourceA = try! XCTUnwrap(a.precipitateClassification.sourceID)
        XCTAssertNotEqual(sourceA, b.precipitateClassification.sourceID)

        let relay = PrecipitateTableSelection()
        let productBefore = a.displayedProduct
        let versionBefore = a.displayedResultVersion
        relay.select([id], of: sourceA)

        let edges = a.precipitateHighlightOutline(for: relay)
        XCTAssertEqual(Set(edges), Set(PrecipitateHighlight.outline(objects: resultA, ids: [id])),
                       "the selected object's outline, and only that")
        XCTAssertEqual(edges.count, 8)
        XCTAssertTrue(b.precipitateHighlightOutline(for: relay).isEmpty,
                      "another window's run, however alike, never highlights")
        XCTAssertTrue(other.precipitateHighlightOutline(for: relay).isEmpty)
        XCTAssertEqual(a.displayedResultVersion, versionBefore, "the highlight is not a re-published product")
        XCTAssertEqual(a.displayedProduct?.kind, productBefore?.kind)

        // Only while the objects picture is what the pane shows.
        a.publishProduct(kind: "virtual_annulus", displayName: "Virtual detector · Annulus",
                         valueUnits: "intensity",
                         payload: .scalar(FloatImage(width: 5, height: 3, pixels: [Float](repeating: 0, count: 15))),
                         domain: .scan)
        XCTAssertTrue(a.precipitateHighlightOutline(for: relay).isEmpty)
        publishObjectsPicture(a)
        XCTAssertFalse(a.precipitateHighlightOutline(for: relay).isEmpty)

        // A re-run mints a new sourceID: the open table's selection is stale.
        a.precipitateClassification.publish(classMap())
        XCTAssertNotEqual(a.precipitateClassification.sourceID, sourceA)
        XCTAssertTrue(a.precipitateHighlightOutline(for: relay).isEmpty)

        // Cleared with the dataset: nothing matches, and a nil relay never matches nil.
        a.precipitateClassification.clear()
        XCTAssertNil(a.precipitateClassification.sourceID)
        relay.select([id], of: nil)
        XCTAssertTrue(a.precipitateHighlightOutline(for: relay).isEmpty)
    }

    /// The table closing clears only its own selection.
    func testRelayClearsOnlyWhatTheClosingTableWrote() {
        let relay = PrecipitateTableSelection()
        let mine = UUID(), newer = UUID()
        relay.select([1], of: newer)
        relay.clear(ifOwnedBy: mine)
        XCTAssertEqual(relay.objectIDs, [1], "a newer table's selection survives an older table closing")
        relay.clear(ifOwnedBy: newer)
        XCTAssertTrue(relay.objectIDs.isEmpty)
        XCTAssertNil(relay.sourceID)
    }

    /// The report carries its source through the snapshot's Codable round trip,
    /// and a snapshot written before the field existed still decodes (no source).
    func testReportSourceIDSurvivesCodableAndOldSnapshotsDecode() throws {
        let source = UUID()
        let report = PrecipitateObjectReport.make(
            objects: classMap(), phaseNames: ["Al", "A", "B"], matrixPhaseIndex: 0,
            pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1, sourceID: source)
        let data = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(PrecipitateObjectReport.self, from: data).sourceID, source)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "sourceID")
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(PrecipitateObjectReport.self, from: old).sourceID)
    }
}
