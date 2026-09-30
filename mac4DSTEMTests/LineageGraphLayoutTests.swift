//
//  LineageGraphLayoutTests.swift
//  ADR 047, phase L3 — the Lineage graph's pure half: where each run goes
//  (`LineageGraphLayout`), what state it is in and what its detail says
//  (`LineageGraphModel`). No SwiftUI here; the drawing is checked by driving
//  the app at 915 and 1470 pt on the demo cube.
//
//  Every test names the mutation it catches. Break each one before trusting it.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class LineageGraphLayoutTests: XCTestCase {

    typealias Layout = LineageGraphLayout

    private func item(_ id: String, _ inputs: [String]?, active: Bool = true) -> Layout.Item {
        Layout.Item(id: id, inputs: inputs?.map { Layout.Link(step: $0, role: "calibration") }, isActive: active)
    }

    /// The mock's session, reduced: calibrate, detect twice (the first on another
    /// branch, with what was built on it), then strain, phases and objects.
    private var session: [Layout.Item] {
        [
            item("s1", []),                       // origin
            item("s2", ["s1"]),                   // ellipse
            item("s3", ["s2"]),                   // Q scale
            item("s4", ["s3"], active: false),    // disks, other branch
            item("s5", ["s4"], active: false),    // phases, other branch
            item("s6", ["s5"], active: false),    // objects, other branch
            item("s7", ["s3"]),                   // disks, active
            item("s8", ["s7"]),                   // strain
            item("s9", ["s7", "s3"]),             // phases (also reads Q scale)
            item("s10", ["s9"]),                  // objects
            item("s11", ["s10"]),                 // export
        ]
    }

    private func layout(_ items: [Layout.Item]) -> Layout { Layout(items: items) }

    // MARK: - No overlap

    /// Mutation it catches: drop the `occupied` check in `place` (two nodes of a
    /// column take the same row), or place inactive nodes with no minimum row.
    func testNoTwoNodesShareACell() {
        let result = layout(session)
        var cells = Set<String>()
        for placement in result.placements {
            XCTAssertTrue(cells.insert("\(placement.column),\(placement.row)").inserted,
                          "\(placement.id) shares a cell")
        }
        XCTAssertEqual(cells.count, session.count)
    }

    // MARK: - Edges rightward

    /// Mutation it catches: give every node column 0 (or take the column from the
    /// item's index) — an edge then runs sideways or back.
    func testEveryEdgeRunsRightward() {
        let result = layout(session)
        XCTAssertFalse(result.edges.isEmpty)
        for edge in result.edges {
            let from = result.placement(of: edge.from)!, to = result.placement(of: edge.to)!
            XCTAssertLessThan(from.column, to.column, "\(edge.from) -> \(edge.to)")
        }
    }

    /// Mutation it catches: the column as the SHORTEST path from a root
    /// (`min` for `max`), or as `parent + 1` of the first parent seen.
    func testColumnIsTheLongestPathFromTheRoots() {
        // a -> b -> c, and a -> c directly: c is two steps from a, not one.
        let result = layout([item("a", []), item("b", ["a"]), item("c", ["a", "b"])])
        XCTAssertEqual(result.placement(of: "a")?.column, 0)
        XCTAssertEqual(result.placement(of: "b")?.column, 1)
        XCTAssertEqual(result.placement(of: "c")?.column, 2)
        XCTAssertEqual(result.columnCount, 3)
        // The direct edge is implied by the path through b, the others are not.
        XCTAssertEqual(result.edges.first { $0.from == "a" && $0.to == "c" }?.implied, true)
        XCTAssertEqual(result.edges.first { $0.from == "a" && $0.to == "b" }?.implied, false)
        XCTAssertEqual(result.edges.first { $0.from == "b" && $0.to == "c" }?.implied, false)
    }

    /// Mutation it catches: flag every edge spanning two columns as implied
    /// (without asking whether another path reaches it).
    func testALongEdgeWithNoOtherPathIsNotImplied() {
        // a -> b (column 0 -> 1) and a -> d where d is pushed to column 2 by an
        // unrelated chain x -> y -> d: no path from a to d except the direct edge.
        let result = layout([item("a", []), item("b", ["a"]), item("x", []), item("y", ["x"]),
                             item("d", ["a", "y"])])
        XCTAssertEqual(result.placement(of: "d")?.column, 2)
        XCTAssertEqual(result.edges.first { $0.from == "a" && $0.to == "d" }?.implied, false)
    }

    /// Mutation it catches: keep the edge list as recorded without the
    /// `column[from] < column[to]` filter, or let a cycle loop forever.
    func testACycleNeitherHangsNorDrawsABackwardEdge() {
        let result = layout([item("a", ["b"]), item("b", ["a"]), item("c", [])])
        XCTAssertEqual(result.placements.count, 3)
        for edge in result.edges {
            XCTAssertLessThan(result.placement(of: edge.from)!.column, result.placement(of: edge.to)!.column)
        }
        var cells = Set<String>()
        for p in result.placements { XCTAssertTrue(cells.insert("\(p.column),\(p.row)").inserted) }
    }

    /// Mutation it catches: keep an edge whose source is not a node (a dangling
    /// input) or a node that consumes itself.
    func testAnEdgeToNowhereAndASelfEdgeAreDropped() {
        let result = layout([item("a", []), item("b", ["a", "ghost", "b"])])
        XCTAssertEqual(result.edges.map { "\($0.from)>\($0.to)" }, ["a>b"])
    }

    // MARK: - Active path on top

    /// Mutation it catches: one placement pass over all nodes (the inactive
    /// branch is longer and takes row 0), or dropping the `minimumRow` of the
    /// second pass.
    func testTheActivePathTakesTheTopRows() {
        // The inactive branch is the taller one: without the two passes it would
        // take the trunk's row and push the active node down.
        let result = layout([
            item("r", []),
            item("x1", ["r"], active: false), item("x2", ["x1"], active: false),
            item("x3", ["x2"], active: false), item("x4", ["x3"], active: false),
            item("y1", ["r"]), item("y2", ["y1"]),
        ])
        let active = result.placements.filter { ["r", "y1", "y2"].contains($0.id) }.map(\.row)
        let inactive = result.placements.filter { !["r", "y1", "y2"].contains($0.id) }.map(\.row)
        XCTAssertLessThan(active.max()!, inactive.min()!)
        XCTAssertEqual(result.activeRowCount, active.max()! + 1)
        XCTAssertEqual(result.placement(of: "r")?.row, 0)
    }

    func testTheMockSessionHasItsActivePathOnTopAndTheBranchBelow() {
        let result = layout(session)
        let activeIDs = Set(session.filter(\.isActive).map(\.id))
        let activeRows = result.placements.filter { activeIDs.contains($0.id) }.map(\.row)
        let branchRows = result.placements.filter { !activeIDs.contains($0.id) }.map(\.row)
        XCTAssertLessThan(activeRows.max()!, branchRows.min()!)
        // The branch keeps its own row: its chain does not zig-zag.
        XCTAssertEqual(Set(["s4", "s5", "s6"].map { result.placement(of: $0)!.row }).count, 1)
    }

    /// Mutation it catches: order siblings by index only (drop the height
    /// tie-break) — the leaf `e`, recorded first, would take the trunk's row.
    func testTheLongestChainKeepsTheTrunkRow() {
        let result = layout([item("a", []), item("e", ["a"]), item("b", ["a"]),
                             item("c", ["b"]), item("d", ["c"])])
        XCTAssertEqual(["a", "b", "c", "d"].map { result.placement(of: $0)!.row }, [0, 0, 0, 0])
        XCTAssertEqual(result.placement(of: "e")?.row, 1)
    }

    // MARK: - Determinism

    /// Mutation it catches: iterating a `Set` or a `Dictionary` to decide an
    /// order (the layout then differs between constructions and launches).
    func testTheLayoutIsDeterministic() {
        let reference = layout(session)
        for _ in 0..<40 { XCTAssertEqual(layout(session), reference) }
        XCTAssertEqual(reference.placements.map(\.id), session.map(\.id), "placements keep the input order")
    }

    // MARK: - v1

    /// Mutation it catches: treat `inputs == nil` as `[]` (every v1 node a root
    /// in column 0), or infer edges from kinds.
    func testV1NodesAreLaidInRecordedOrderWithOrderOnlyConnectors() {
        let result = layout([item("s1", nil), item("s2", nil), item("s3", nil), item("s4", nil)])
        XCTAssertEqual(result.placements.map(\.column), [0, 1, 2, 3])
        XCTAssertEqual(result.placements.map(\.row), [0, 0, 0, 0])
        XCTAssertEqual(result.edges.count, 3)
        XCTAssertTrue(result.edges.allSatisfy { $0.orderOnly && $0.role == nil })
        XCTAssertEqual(result.edges.map { "\($0.from)>\($0.to)" }, ["s1>s2", "s2>s3", "s3>s4"])
    }

    /// A live run that consumed a v1 node is a real edge; v1 nodes stay chained
    /// by order alone. Mutation it catches: marking every edge order-only when
    /// any v1 node exists.
    func testALiveRunAfterV1NodesKeepsItsRealEdge() {
        let result = layout([item("s1", nil), item("s2", nil), item("s3", ["s2"])])
        XCTAssertEqual(result.edges.first { $0.to == "s2" }?.orderOnly, true)
        let real = result.edges.first { $0.to == "s3" }
        XCTAssertEqual(real?.orderOnly, false)
        XCTAssertEqual(real?.role, "calibration")
        XCTAssertEqual(result.placement(of: "s3")?.column, 2)
    }

    func testAnEmptyLineageLaysOutNothing() {
        let result = layout([])
        XCTAssertTrue(result.placements.isEmpty)
        XCTAssertEqual(result.columnCount, 0)
        XCTAssertEqual(result.rowCount, 0)
        XCTAssertEqual(result.activeRowCount, 0)
    }

    // MARK: - Keyboard neighbours

    /// Mutation it catches: swap left and right, or let up/down leave the column.
    func testArrowKeysMoveAlongEdgesAndColumns() {
        let result = layout(session)
        XCTAssertEqual(result.neighbor(of: "s7", .left), "s3")
        XCTAssertEqual(result.neighbor(of: "s9", .left), "s7", "the nearest input, not the implied Q-scale edge")
        XCTAssertEqual(result.neighbor(of: "s7", .right), "s9", "the nearest-row consumer (strain sits one row lower)")
        XCTAssertNil(result.neighbor(of: "s1", .left), "a root has nothing to its left")
        XCTAssertNil(result.neighbor(of: "s11", .right))
        // s8 (strain) and s9 (phases) share a column, strain on the trunk row.
        let s8 = result.placement(of: "s8")!, s9 = result.placement(of: "s9")!
        XCTAssertEqual(s8.column, s9.column)
        let (upper, lower) = s8.row < s9.row ? ("s8", "s9") : ("s9", "s8")
        XCTAssertEqual(result.neighbor(of: upper, .down), lower)
        XCTAssertEqual(result.neighbor(of: lower, .up), upper)
        XCTAssertNil(result.neighbor(of: upper, .up))
        XCTAssertNil(result.neighbor(of: "nope", .left))
    }

    // MARK: - Metrics

    /// Mutation it catches: a graph shown at any width (the narrow pane then
    /// loses its list), or the threshold moved past the 915-pt window's pane.
    func testTheGraphNeedsWidthAndTheListTakesOverBelowIt() {
        XCTAssertFalse(LineageGraphMetrics.showsGraph(paneWidth: 300))
        XCTAssertFalse(LineageGraphMetrics.showsGraph(paneWidth: LineageGraphMetrics.graphMinimumWidth - 1))
        XCTAssertTrue(LineageGraphMetrics.showsGraph(paneWidth: LineageGraphMetrics.graphMinimumWidth))
    }

    /// Mutation it catches: a content size that ignores the gaps (nodes then
    /// clip at the canvas edge).
    func testContentSizeHoldsTheFarthestNode() {
        let result = layout(session)
        let size = LineageGraphMetrics.contentSize(columns: result.columnCount, rows: result.rowCount)
        for p in result.placements {
            let origin = LineageGraphMetrics.origin(column: p.column, row: p.row)
            XCTAssertLessThanOrEqual(origin.x + LineageGraphMetrics.nodeWidth, size.width)
            XCTAssertLessThanOrEqual(origin.y + LineageGraphMetrics.nodeHeight, size.height)
        }
    }

    // MARK: - The model over a real lineage

    private let frame = SessionLineage.Frame()

    /// s1 origin, s2 ellipse, s3 Q scale, s4 disks (floor 0.50), s5 strain, then
    /// disks again at 0.15: s4 has a child, so s6 is a NEW node; strain is
    /// superseded and s4/s5 are left on another branch.
    private var branched: SessionLineage {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "calibration_origin", parameters: ["method": "friedel"], frame: frame)
        lineage.recordRun(kind: "calibration_ellipse", parameters: ["a_px": "1.0"], frame: frame)
        lineage.recordRun(kind: "calibration_q", parameters: ["q_pixel_size": "0.01"], frame: frame)
        lineage.recordRun(kind: "disk_detection", parameters: ["floor": "0.50", "spacing": "20"], frame: frame)
        lineage.recordRun(kind: "strain", parameters: ["basis": "consensus"], frame: frame)
        lineage.recordRun(kind: "disk_detection", parameters: ["floor": "0.15", "spacing": "20"], frame: frame)
        return lineage
    }

    /// Mutation it catches: state from the node's kind alone, or "active" taken
    /// as "the last node" instead of `activeNodes()`.
    func testStatesFollowTheActivePath() {
        let model = LineageGraphModel(lineage: branched)
        XCTAssertEqual(model.activeIDs, ["s1", "s2", "s3", "s6"])
        XCTAssertEqual(model.state(of: "s6"), .current)
        XCTAssertEqual(model.state(of: "s1"), .current)
        XCTAssertEqual(model.state(of: "s4"), .branch)
        XCTAssertEqual(model.state(of: "s5"), .branch)
        XCTAssertEqual(model.branchNodeCount, 2)
        XCTAssertEqual(model.otherBranchCount(kind: "disk_detection"), 1)
        XCTAssertEqual(model.otherBranchCount(kind: "calibration_origin"), 0)
        // The layout's active flag is the model's.
        let layout = model.layout
        let branchRows = ["s4", "s5"].map { layout.placement(of: $0)!.row }
        XCTAssertGreaterThanOrEqual(branchRows.min()!, layout.activeRowCount)
    }

    /// Mutation it catches: mark stale whenever a product exists, or ignore
    /// the product's kind (a strain map's step would make the disks stale).
    func testAProductFromAnotherRunMakesTheActiveRunStale() {
        let lineage = branched
        XCTAssertEqual(LineageGraphModel(lineage: lineage, productKind: "bragg_vector_map",
                                         productStep: "s4").staleIDs, ["s6"])
        let stale = LineageGraphModel(lineage: lineage, productKind: "bragg_vector_map", productStep: "s4")
        XCTAssertEqual(stale.state(of: "s6"), .stale)
        XCTAssertEqual(stale.state(of: "s4"), .branch, "a branch stays a branch")
        // From the active run: nothing stale. From a file with no step: nothing stale.
        XCTAssertTrue(LineageGraphModel(lineage: lineage, productKind: "bragg_vector_map",
                                        productStep: "s6").staleIDs.isEmpty)
        XCTAssertTrue(LineageGraphModel(lineage: lineage, productKind: "bragg_vector_map",
                                        productStep: nil).staleIDs.isEmpty)
        // A product whose kind has no active run names none.
        XCTAssertTrue(LineageGraphModel(lineage: lineage, productKind: "acom_region_reference",
                                        productStep: "s4").staleIDs.isEmpty)
        // An old strain map does not make the (different-kind) disks stale.
        XCTAssertTrue(LineageGraphModel(lineage: lineage, productKind: "strain_exx",
                                        productStep: "s5").staleIDs.isEmpty)
    }

    /// Mutation it catches: a label without the state word, or with the short title.
    func testAccessibilityLabelNamesStepKindAndState() {
        let lineage = branched
        let stale = LineageGraphModel(lineage: lineage, productKind: "bragg_vector_map", productStep: "s4")
        XCTAssertEqual(stale.accessibilityLabel(for: lineage.node(id: "s6")!), "Step s6, Disk detection, stale")
        XCTAssertEqual(stale.accessibilityLabel(for: lineage.node(id: "s4")!),
                       "Step s4, Disk detection, on another branch")
        XCTAssertEqual(stale.accessibilityLabel(for: lineage.node(id: "s1")!),
                       "Step s1, Origin calibration, current")
    }

    /// Mutation it catches: compare only the keys both runs have (a key that
    /// exists on one side would vanish), or list equal values.
    func testDifferencesListOnlyWhatDiffersWithBothSides() {
        var lineage = branched
        lineage.recordRun(kind: "disk_detection", parameters: ["floor": "0.15", "spacing": "20", "extra": "1"],
                          frame: frame)   // collapses into s6 (no children, no product)
        let old = lineage.node(id: "s4")!, active = lineage.node(id: "s6")!
        XCTAssertEqual(LineageGraphModel.differences(of: old, from: active), [
            LineageGraphModel.Difference(key: "extra", value: nil, activeValue: "1"),
            LineageGraphModel.Difference(key: "floor", value: "0.50", activeValue: "0.15"),
        ])
        XCTAssertTrue(LineageGraphModel.differences(of: active, from: active).isEmpty)
        let model = LineageGraphModel(lineage: lineage)
        XCTAssertEqual(model.activeCounterpart(of: old)?.id, "s6")
        XCTAssertNil(model.activeCounterpart(of: active), "the active run has no other active run of its kind")
    }

    /// Mutation it catches: hide nothing, or hide by kind instead of by the
    /// active path; also an input pointing at a hidden node must not add an edge.
    func testActivePathOnlyHidesTheBranchesAndTheirEdges() {
        let model = LineageGraphModel(lineage: branched, activePathOnly: true)
        XCTAssertEqual(model.nodes.map(\.id), ["s1", "s2", "s3", "s6"])
        XCTAssertEqual(model.layout.placements.map(\.id), ["s1", "s2", "s3", "s6"])
        XCTAssertEqual(model.defaultSelection, "s6")
        XCTAssertEqual(model.layout.activeRowCount, model.layout.rowCount, "nothing is left below the active rows")
        XCTAssertEqual(LineageGraphModel(lineage: branched).nodes.count, 6)
    }

    /// Mutation it catches: the list follows the graph's node order instead of
    /// the record's, or wraps around at either end.
    func testTheNarrowListStepsAlongTheActivePath() {
        let model = LineageGraphModel(lineage: branched)
        XCTAssertEqual(model.activePath.map(\.id), ["s1", "s2", "s3", "s6"])
        XCTAssertEqual(model.activePathNeighbor(of: "s2", offset: 1), "s3")
        XCTAssertEqual(model.activePathNeighbor(of: "s2", offset: -1), "s1")
        XCTAssertNil(model.activePathNeighbor(of: "s1", offset: -1))
        XCTAssertNil(model.activePathNeighbor(of: "s6", offset: 1))
        XCTAssertEqual(model.activePathNeighbor(of: "s5", offset: 1), "s1", "from a branch: the path's start")
    }

    /// A refit of the origin after disks were detected on the first fit is a NEW node that
    /// takes the origin's replay place; the list reads in time order anyway (drive 3).
    /// Mutation it catches: `activePath` back on `activeNodes()` (["s3", "s2"]).
    func testTheNarrowListIsInTimeOrderWhenALaterRefitReplacesAnEarlierKind() {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "calibration_origin", parameters: ["method": "friedel"], frame: frame)
        lineage.recordRun(kind: "disk_detection", parameters: ["floor": "0.50"], frame: frame)
        lineage.recordRun(kind: "calibration_origin", parameters: ["method": "plane"], frame: frame)
        XCTAssertEqual(lineage.activeNodes().map(\.id), ["s3", "s2"], "precondition: the replay order is not time order")
        let model = LineageGraphModel(lineage: lineage)
        XCTAssertEqual(model.activePath.map(\.id), ["s2", "s3"])
        XCTAssertEqual(model.activePathNeighbor(of: "s2", offset: 1), "s3", "the arrow keys follow the list")
    }

    /// Mutation it catches: a caption for every session (a live one must not
    /// claim "order only"), or none for v1.
    func testOnlyV1SessionsDrawOrderOnlyConnectors() {
        XCTAssertFalse(LineageGraphModel(lineage: branched).hasOrderOnlyConnectors)
        let record = SessionReplayRecord(steps: [
            SessionReplayRecord.Step(kind: "disk_detection", parameters: ["floor": "0.5"],
                                     recorded: Date(timeIntervalSince1970: 1)),
            SessionReplayRecord.Step(kind: "strain", parameters: [:], recorded: Date(timeIntervalSince1970: 2)),
        ])
        let v1 = SessionLineage.synthesized(from: record, frame: nil)
        let model = LineageGraphModel(lineage: v1)
        XCTAssertTrue(model.hasOrderOnlyConnectors)
        XCTAssertEqual(model.layout.placements.map(\.column), [0, 1])
        XCTAssertEqual(model.layout.edges.count, 1)
        XCTAssertTrue(model.layout.edges.allSatisfy(\.orderOnly))
        let single = SessionLineage.synthesized(from: SessionReplayRecord(steps: [record.steps[0]]), frame: nil)
        XCTAssertFalse(LineageGraphModel(lineage: single).hasOrderOnlyConnectors, "one node has no connector to caption")
    }

    func testFrameDescriptionSaysWhatTheParametersAreExpressedIn() {
        XCTAssertEqual(LineageGraphModel.frameDescription(nil), "mixed or unknown")
        XCTAssertEqual(LineageGraphModel.frameDescription(SessionLineage.Frame()), "full detector")
        XCTAssertEqual(LineageGraphModel.frameDescription(SessionLineage.Frame(bin: 2)), "bin 2")
        let crop = AxisCrop(yOffset: 4, xOffset: 8, height: 64, width: 32)
        XCTAssertEqual(LineageGraphModel.frameDescription(SessionLineage.Frame(bin: 2, crop: crop)),
                       "bin 2 · crop 32×64")
        XCTAssertEqual(LineageGraphModel.frameDescription(SessionLineage.Frame(bin: 1, crop: crop)), "crop 32×64")
    }

    func testKindVocabularyCoversEveryLineageKindAndToleratesAnUnknownOne() {
        let kinds = ["calibration_origin", "calibration_ellipse", "calibration_q", "disk_detection", "strain",
                     "acom", "phase_mapping", "precipitate_objects", "export", "virtual_detector", "dpc",
                     "diffraction_groups"]
        for kind in kinds {
            XCTAssertNotEqual(LineageKindStyle.symbolName(kind), "circle.dashed", kind)
            XCTAssertFalse(LineageKindStyle.fullTitle(kind).isEmpty, kind)
        }
        XCTAssertEqual(LineageKindStyle.shortTitle("future_kind"), "Future kind")
        XCTAssertEqual(LineageKindStyle.symbolName("future_kind"), "circle.dashed")
        XCTAssertTrue(LineageKindStyle.isSink("export"))
        XCTAssertFalse(LineageKindStyle.isSink("strain"))
    }

    // MARK: - L4: the rewind offer

    /// Mutation it catches: a consequence that omits the products that leave
    /// the path (or says "deleted"), an offer on the run the session is
    /// already at, or one that does not come from the plan the rewind uses.
    func testTheOfferStatesTheConsequenceBeforeTheClick() throws {
        let model = LineageGraphModel(lineage: branched)
        // s4 (disks, floor 0.50) is on another branch; s5 (strain) was built on it.
        guard case .available(let text)? = model.rewindOffer(for: try XCTUnwrap(model.node(id: "s4"))) else {
            return XCTFail("a run on another branch is rewindable")
        }
        XCTAssertTrue(text.contains("Disk detection becomes stale; nothing is deleted."), text)
        XCTAssertTrue(text.contains("The settings of Disk detection, Strain return to the controls."),
                      "the strain built on it comes back with its own settings: \(text)")
        XCTAssertTrue(text.contains("Origin calibration is kept as it is now."),
                      "origin is not restorable and the pane says so: \(text)")
        XCTAssertFalse(text.contains("Ellipse") || text.contains("Q scale"),
                       "an ellipse and a Q scale made before this run stay on the path and are not mentioned: \(text)")
        XCTAssertTrue(text.contains("Nothing recomputes"), text)
        XCTAssertFalse(text.lowercased().contains("delete the"), text)
        XCTAssertNil(model.rewindOffer(for: try XCTUnwrap(model.node(id: "s6"))),
                     "the current run has nothing to rewind to")
    }

    /// Two products leaving the path are both named, in path order.
    /// Mutation it catches: naming only the first kind.
    func testSeveralStaleProductsAreListed() throws {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "disk_detection", parameters: ["a": "1"], frame: frame)   // s1
        lineage.recordRun(kind: "strain", parameters: ["b": "1"], frame: frame)           // s2
        lineage.recordRun(kind: "disk_detection", parameters: ["a": "2"], frame: frame)   // s3
        lineage.recordRun(kind: "strain", parameters: ["b": "1"], frame: frame)           // s4
        lineage.recordRun(kind: "acom", parameters: ["c": "1"], frame: frame)             // s5
        let model = LineageGraphModel(lineage: lineage)
        guard case .available(let text)? = model.rewindOffer(for: try XCTUnwrap(model.node(id: "s1"))) else {
            return XCTFail("rewindable")
        }
        XCTAssertTrue(text.contains("Disk detection, Strain, Orientation map become stale; nothing is deleted."), text)
    }

    /// Mutation it catches: offer a button on a v1 run or an export.
    func testAV1RunAndAnExportGetTheReasonInsteadOfAButton() throws {
        var record = SessionReplayRecord()
        record.record(kind: "disk_detection", parameters: ["a": "1"])
        record.record(kind: "strain", parameters: ["b": "1"])
        let v1 = LineageGraphModel(lineage: SessionLineage.synthesized(from: record, frame: nil))
        for id in ["s1", "s2"] {
            guard case .unavailable(let why)? = v1.rewindOffer(for: try XCTUnwrap(v1.node(id: id))) else {
                return XCTFail("\(id) is v1: no rewind")
            }
            XCTAssertTrue(why.contains("Recorded before lineage"), why)
        }
        var lineage = branched
        lineage.recordRun(kind: "export", parameters: ["format": "png", "file_name": "a.png"], frame: frame)
        let model = LineageGraphModel(lineage: lineage)
        guard case .unavailable(let why)? = model.rewindOffer(for: try XCTUnwrap(model.node(id: "s7"))) else {
            return XCTFail("an export is a sink")
        }
        XCTAssertTrue(why.contains("export"), why)
    }

    /// After a rewind the run whose product is still in memory is another run
    /// than the active one of its kind, and the ACTIVE run reads stale.
    /// Mutation it catches: ignore `producedSteps` (nothing is marked), or
    /// mark a run whose product IS the in-memory one.
    func testTheActiveRunIsStaleWhenTheProductInMemoryCameFromAnotherRun() {
        let model = LineageGraphModel(lineage: branched, producedSteps: ["disk_detection": "s4"])
        XCTAssertEqual(model.state(of: "s6"), .stale, "s6 is the active disks; the peaks in memory are s4's")
        XCTAssertEqual(model.state(of: "s1"), .current)
        let fresh = LineageGraphModel(lineage: branched, producedSteps: ["disk_detection": "s6"])
        XCTAssertEqual(fresh.state(of: "s6"), .current)
    }
}
