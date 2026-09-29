//
//  LineageGraphLayout.swift
//  Role: The pure half of the Lineage graph (ADR 047, R9 / phase L3): where each
//        run goes, which edges are drawn, and what state a node is in. No
//        SwiftUI, no AppState — `LineageGraphView` draws what this decides,
//        `LineageGraphLayoutTests` pins it.
//
//  THE LAYOUT (mock: docs/archive/v4/lineage-graph-mock-2026-09-30.html)
//   - COLUMN = the longest path from a root (a node that consumes nothing in
//     the session). Every edge therefore points to a strictly higher column:
//     the picture reads left to right and an edge never runs backward.
//   - ROW: the ACTIVE path takes the top rows, packed; every inactive node
//     (another branch) sits below the last active row. Within a column, the
//     child with the longest downstream chain is placed first, so it inherits
//     its parent's row and the trunk stays a straight line. A node prefers its
//     nearest already-placed input's row and otherwise takes the nearest free
//     row (ties go up). Two nodes never share a (column, row) cell.
//   - v1 nodes (`inputs == nil`: the file never said what they consumed) get NO
//     edge from an input; they are chained in recorded order by ORDER-ONLY
//     connectors, drawn dotted and captioned "Recorded before lineage: order
//     only" — absence is absence, never asserted as a dependency (R7).
//   - An edge already implied by a longer path (Phases read both Disks and Q
//     scale, but Q scale → Disks → Phases says so) is flagged `implied` and is
//     drawn only beside the selected node; only edges spanning more than one
//     column can be implied, so only those are searched.
//
//  Deterministic by construction: arrays and stable tie-breaks only, no
//  iteration over a dictionary or set.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

// MARK: - Layout

nonisolated struct LineageGraphLayout: Equatable {

    /// One consumed run, by node id, with the role the edge was recorded under.
    nonisolated struct Link: Equatable {
        let step: String
        let role: String
    }

    /// One node as the layout sees it. `inputs == nil` is a v1 node.
    nonisolated struct Item: Equatable {
        let id: String
        let inputs: [Link]?
        let isActive: Bool
    }

    nonisolated struct Placement: Equatable {
        let id: String
        let column: Int
        let row: Int
    }

    nonisolated struct Edge: Equatable {
        let from: String
        let to: String
        /// The recorded role (`peaks`, `calibration`, …); nil for an order-only connector.
        let role: String?
        /// A v1 connector: the recorded ORDER of two runs, not a consumption.
        let orderOnly: Bool
        /// Another path already connects `from` to `to`.
        let implied: Bool
    }

    nonisolated enum Direction { case left, right, up, down }

    /// In the order the items were given.
    let placements: [Placement]
    let edges: [Edge]
    let columnCount: Int
    let rowCount: Int
    /// Rows `0..<activeRowCount` hold the active path; inactive nodes are below.
    let activeRowCount: Int

    private let indexByID: [String: Int]

    func placement(of id: String) -> Placement? {
        indexByID[id].map { placements[$0] }
    }

    // MARK: Building

    init(items: [Item]) {
        // Ids are unique in a validated lineage; a repeat here is ignored
        // rather than allowed to make two nodes one.
        var unique: [Item] = []
        var index: [String: Int] = [:]
        for item in items where index[item.id] == nil {
            index[item.id] = unique.count
            unique.append(item)
        }
        let n = unique.count

        // Edges, in item order. Parents are indices into `unique`.
        struct RawEdge { let from: Int; let to: Int; let role: String?; let orderOnly: Bool }
        var raw: [RawEdge] = []
        var lastV1: Int?
        for (i, item) in unique.enumerated() {
            if let inputs = item.inputs {
                var seen = Set<String>()
                for link in inputs {
                    guard let j = index[link.step], j != i, seen.insert(link.step).inserted else { continue }
                    raw.append(RawEdge(from: j, to: i, role: link.role, orderOnly: false))
                }
            } else {
                if let previous = lastV1 {
                    raw.append(RawEdge(from: previous, to: i, role: nil, orderOnly: true))
                }
                lastV1 = i
            }
        }

        // Columns: longest path from a root (Kahn's algorithm, FIFO, index order).
        var children = [[Int]](repeating: [], count: n)
        var parents = [[Int]](repeating: [], count: n)
        var inDegree = [Int](repeating: 0, count: n)
        for edge in raw {
            children[edge.from].append(edge.to)
            parents[edge.to].append(edge.from)
            inDegree[edge.to] += 1
        }
        var column = [Int](repeating: 0, count: n)
        var order: [Int] = []
        var remaining = inDegree
        for i in 0..<n where remaining[i] == 0 { order.append(i) }
        var cursor = 0
        while cursor < order.count {
            let u = order[cursor]
            cursor += 1
            for v in children[u] {
                column[v] = max(column[v], column[u] + 1)
                remaining[v] -= 1
                if remaining[v] == 0 { order.append(v) }
            }
        }
        // A cycle never validates (R8), but if one arrives its members keep
        // whatever column they reached and the edges that would run backward
        // are dropped below — the layout still holds its invariants.

        // Height: the longest chain below a node, so the trunk keeps its row.
        var height = [Int](repeating: 0, count: n)
        for u in order.reversed() {
            for v in children[u] where column[v] > column[u] {
                height[u] = max(height[u], height[v] + 1)
            }
        }

        // Rows: active first (rows from 0), then the rest below them.
        var row = [Int](repeating: -1, count: n)
        var occupied: [Set<Int>] = []
        func ensureColumn(_ c: Int) { while occupied.count <= c { occupied.append([]) } }

        let sequence = (0..<n).sorted {
            if column[$0] != column[$1] { return column[$0] < column[$1] }
            if height[$0] != height[$1] { return height[$0] > height[$1] }
            return $0 < $1
        }
        func place(_ u: Int, minimumRow: Int) {
            ensureColumn(column[u])
            // The nearest already-placed input (highest column, first recorded).
            var preferred = minimumRow
            var best = -1
            for p in parents[u] where row[p] >= 0 && column[p] < column[u] && column[p] > best {
                best = column[p]
                preferred = row[p]
            }
            let want = max(minimumRow, preferred)
            var chosen = want
            if occupied[column[u]].contains(want) {
                var distance = 1
                while true {
                    let up = want - distance
                    if up >= minimumRow, !occupied[column[u]].contains(up) { chosen = up; break }
                    let down = want + distance
                    if !occupied[column[u]].contains(down) { chosen = down; break }
                    distance += 1
                }
            }
            occupied[column[u]].insert(chosen)
            row[u] = chosen
        }
        for u in sequence where unique[u].isActive { place(u, minimumRow: 0) }
        let activeRows = (row.max() ?? -1) + 1
        for u in sequence where !unique[u].isActive { place(u, minimumRow: activeRows) }

        // Edges that run rightward only; implied ones flagged.
        var kept: [Edge] = []
        for edge in raw where column[edge.from] < column[edge.to] {
            var implied = false
            if column[edge.to] - column[edge.from] > 1 {
                // Reachable from `from` without using this edge?
                var visited = [Bool](repeating: false, count: n)
                var stack = children[edge.from].filter { $0 != edge.to && column[$0] < column[edge.to] }
                while let u = stack.popLast(), !implied {
                    if visited[u] { continue }
                    visited[u] = true
                    for v in children[u] where column[v] > column[u] {
                        if v == edge.to { implied = true; break }
                        if column[v] < column[edge.to] { stack.append(v) }
                    }
                }
            }
            kept.append(Edge(from: unique[edge.from].id, to: unique[edge.to].id,
                             role: edge.role, orderOnly: edge.orderOnly, implied: implied))
        }

        self.indexByID = index
        self.placements = (0..<n).map { Placement(id: unique[$0].id, column: column[$0], row: row[$0]) }
        self.edges = kept
        self.columnCount = n == 0 ? 0 : (column.max() ?? 0) + 1
        self.rowCount = n == 0 ? 0 : (row.max() ?? 0) + 1
        self.activeRowCount = activeRows
    }

    // MARK: Keyboard navigation

    /// The node an arrow key moves to from `id`, or nil at an edge of the graph.
    /// Left = the nearest-row input, right = the nearest-row consumer, up / down
    /// = the next node in the same column. Deterministic (ties go to the earlier item).
    func neighbor(of id: String, _ direction: Direction) -> String? {
        guard let here = placement(of: id) else { return nil }
        switch direction {
        case .up, .down:
            var best: Placement?
            for other in placements where other.column == here.column && other.id != id {
                let delta = other.row - here.row
                guard direction == .down ? delta > 0 : delta < 0 else { continue }
                if best == nil || abs(delta) < abs(best!.row - here.row) { best = other }
            }
            return best?.id
        case .left, .right:
            var best: Placement?
            for edge in edges {
                let otherID: String
                if direction == .left, edge.to == id { otherID = edge.from }
                else if direction == .right, edge.from == id { otherID = edge.to }
                else { continue }
                guard let other = placement(of: otherID) else { continue }
                if best == nil { best = other; continue }
                let current = best!
                let nearer = abs(other.row - here.row) < abs(current.row - here.row)
                let sameRowCloserColumn = abs(other.row - here.row) == abs(current.row - here.row)
                    && abs(other.column - here.column) < abs(current.column - here.column)
                if nearer || sameRowCloserColumn { best = other }
            }
            return best?.id
        }
    }
}

// MARK: - Drawing metrics

/// Sizes in points. The pane is a fixed-size canvas inside a scroll view, so
/// these are the graph's own units; the pane scrolls, it does not scale.
nonisolated enum LineageGraphMetrics {
    static let nodeWidth: Double = 108
    static let nodeHeight: Double = 40
    static let columnGap: Double = 26
    static let rowGap: Double = 8
    static let margin: Double = 12
    /// A kind symbol's column in a node box / list row, and in the detail's input rows.
    static let symbolWidth: Double = 16
    static let inputSymbolWidth: Double = 14
    /// The expanded provenance disclosure under the graph.
    static let provenanceMaxHeight: Double = 120

    /// The narrowest pane that shows the graph beside its detail column; below
    /// it the pane lists the active path instead (ADR 047 L2's fallback).
    static let graphMinimumWidth: Double = 560
    static let detailColumnWidth: Double = 244

    static func showsGraph(paneWidth: Double) -> Bool { paneWidth >= graphMinimumWidth }

    static func origin(column: Int, row: Int) -> (x: Double, y: Double) {
        (margin + Double(column) * (nodeWidth + columnGap),
         margin + Double(row) * (nodeHeight + rowGap))
    }

    static func contentSize(columns: Int, rows: Int) -> (width: Double, height: Double) {
        (2 * margin + Double(max(columns, 1)) * nodeWidth + Double(max(columns - 1, 0)) * columnGap,
         2 * margin + Double(max(rows, 1)) * nodeHeight + Double(max(rows - 1, 0)) * rowGap)
    }
}

// MARK: - Node vocabulary

/// How a node is standing relative to the session as it is now (by symbol,
/// never by colouring the box — the mock's rule).
nonisolated enum LineageNodeState: Equatable {
    /// On the active path, and the product shown (if any) came from this run.
    case current
    /// On the active path, but the product shown came from another run.
    case stale
    /// Not on the active path: kept, dimmed, and (from L4) rewindable.
    case branch

    var symbolName: String {
        switch self {
        case .current: "checkmark.circle.fill"
        case .stale: "exclamationmark.triangle.fill"
        case .branch: "arrow.triangle.branch"
        }
    }

    /// The word VoiceOver and the detail caption use.
    var phrase: String {
        switch self {
        case .current: "current"
        case .stale: "stale"
        case .branch: "on another branch"
        }
    }
}

/// The names and symbols of run kinds. An unknown kind (a newer build's) is an
/// ordinary node with a neutral symbol and its own kind string humanised.
nonisolated enum LineageKindStyle {
    static func shortTitle(_ kind: String) -> String {
        switch kind {
        case "calibration_origin": "Origin"
        case "calibration_ellipse": "Ellipse"
        case "calibration_q": "Q scale"
        case "disk_detection": "Disks"
        case "strain": "Strain"
        case "acom": "ACOM"
        case "phase_mapping": "Phases"
        case "precipitate_objects": "Objects"
        case "export": "Export"
        case "virtual_detector": "Virtual"
        case "dpc": "DPC"
        case "diffraction_groups": "Groups"
        default: humanised(kind)
        }
    }

    static func fullTitle(_ kind: String) -> String {
        switch kind {
        case "calibration_origin": "Origin calibration"
        case "calibration_ellipse": "Ellipse calibration"
        case "calibration_q": "Q-scale calibration"
        case "disk_detection": "Disk detection"
        case "strain": "Strain mapping"
        case "acom": "ACOM orientation mapping"
        case "phase_mapping": "Phase mapping"
        case "precipitate_objects": "Precipitate objects"
        case "export": "Export"
        case "virtual_detector": "Virtual detector"
        case "dpc": "Differential phase contrast"
        case "diffraction_groups": "Diffraction groups"
        default: humanised(kind)
        }
    }

    static func symbolName(_ kind: String) -> String {
        switch kind {
        case "calibration_origin": "scope"
        case "calibration_ellipse": "oval"
        case "calibration_q": "ruler"
        case "disk_detection": "circle.grid.3x3"
        case "strain": "arrow.left.and.right"
        case "acom": "cube"
        case "phase_mapping": "circle.lefthalf.filled"
        case "precipitate_objects": "capsule"
        case "export": "square.and.arrow.up"
        case "virtual_detector": "viewfinder.circle"
        case "dpc": "arrow.up.and.down.and.arrow.left.and.right"
        case "diffraction_groups": "rectangle.3.group"
        default: "circle.dashed"
        }
    }

    /// An export is a sink: its box is a capsule, not a rounded rectangle.
    static func isSink(_ kind: String) -> Bool { kind == "export" }

    /// `some_new_kind` → `Some new kind`.
    static func humanised(_ key: String) -> String {
        let spaced = key.replacingOccurrences(of: "_", with: " ")
        guard let first = spaced.first else { return spaced }
        return first.uppercased() + spaced.dropFirst()
    }
}

// MARK: - Model

/// The lineage as the pane shows it: the layout, each node's state, and the
/// small derived facts the detail column needs.
nonisolated struct LineageGraphModel {

    /// Shown nodes, in recorded (id) order.
    let nodes: [SessionLineage.Node]
    let layout: LineageGraphLayout
    let activeIDs: Set<String>
    let staleIDs: Set<String>
    /// The whole lineage, for inputs that point at a node the filter hid.
    let lineage: SessionLineage

    /// - Parameters:
    ///   - productKind / productStep: the displayed product's kind and its
    ///     provenance `lineage_step`, if it has one. A product that names a run
    ///     other than the active run of its kind makes that active run stale.
    ///   - activePathOnly: hide the nodes on other branches.
    init(lineage: SessionLineage, productKind: String? = nil, productStep: String? = nil,
         activePathOnly: Bool = false) {
        let active = lineage.activeNodes()
        let activeIDs = Set(active.map(\.id))
        self.lineage = lineage
        self.activeIDs = activeIDs
        self.staleIDs = Self.staleSteps(active: active, productKind: productKind, productStep: productStep)
        let shown = activePathOnly ? lineage.nodes.filter { activeIDs.contains($0.id) } : lineage.nodes
        self.nodes = shown
        self.layout = LineageGraphLayout(items: shown.map { node in
            LineageGraphLayout.Item(
                id: node.id,
                inputs: node.inputs?.map { LineageGraphLayout.Link(step: $0.step, role: $0.role) },
                isActive: activeIDs.contains(node.id))
        })
    }

    /// The active run of the displayed product's kind is stale when the product
    /// names a different run. Nothing names a run yet in files written before
    /// the product carries `lineage_step`; then nothing is stale.
    static func staleSteps(active: [SessionLineage.Node], productKind: String?,
                           productStep: String?) -> Set<String> {
        guard let productKind, let productStep,
              let kind = SessionLineage.lineageKind(forProductKind: productKind),
              let current = active.first(where: { $0.kind == kind }),
              current.id != productStep else { return [] }
        return [current.id]
    }

    func state(of id: String) -> LineageNodeState {
        if !activeIDs.contains(id) { return .branch }
        return staleIDs.contains(id) ? .stale : .current
    }

    func node(id: String) -> SessionLineage.Node? { nodes.first { $0.id == id } ?? lineage.node(id: id) }

    /// The selection when nothing is chosen: the run recorded last, if shown.
    var defaultSelection: String? {
        if let head = lineage.head, nodes.contains(where: { $0.id == head }) { return head }
        return nodes.last?.id
    }

    /// The active path in the record's order — the list the narrow pane shows.
    var activePath: [SessionLineage.Node] { lineage.activeNodes() }

    /// The next (`offset` 1) or previous (-1) run on the active path — the
    /// narrow list's arrow keys. From a run that is not on the path: its start
    /// (forward) or its end (backward).
    func activePathNeighbor(of id: String, offset: Int) -> String? {
        let path = activePath
        guard let index = path.firstIndex(where: { $0.id == id }) else {
            return (offset > 0 ? path.first : path.last)?.id
        }
        let target = index + offset
        return path.indices.contains(target) ? path[target].id : nil
    }

    /// Runs of this kind that are not on the active path.
    func otherBranchCount(kind: String) -> Int {
        lineage.nodes.filter { $0.kind == kind && !activeIDs.contains($0.id) }.count
    }

    var branchNodeCount: Int { lineage.nodes.filter { !activeIDs.contains($0.id) }.count }

    /// True when the picture draws an order-only connector, so it must be captioned.
    var hasOrderOnlyConnectors: Bool { layout.edges.contains { $0.orderOnly } }

    /// The active run of `node`'s kind, when `node` is not it.
    func activeCounterpart(of node: SessionLineage.Node) -> SessionLineage.Node? {
        lineage.activeNodes().first { $0.kind == node.kind && $0.id != node.id }
    }

    // MARK: Detail

    /// One parameter that differs between a node and the active run of its kind.
    nonisolated struct Difference: Equatable {
        let key: String
        /// This node's value; nil when the key is absent here.
        let value: String?
        /// The active run's value; nil when the key is absent there.
        let activeValue: String?
    }

    static func differences(of node: SessionLineage.Node, from active: SessionLineage.Node) -> [Difference] {
        let keys = Set(node.parameters.keys).union(active.parameters.keys).sorted()
        return keys.compactMap { key in
            let mine = node.parameters[key], theirs = active.parameters[key]
            return mine == theirs ? nil : Difference(key: key, value: mine, activeValue: theirs)
        }
    }

    /// The frame a run's pixel-valued parameters are in, in words.
    static func frameDescription(_ frame: SessionLineage.Frame?) -> String {
        guard let frame else { return "mixed or unknown" }
        if frame.bin == 1 && frame.crop == nil { return "full detector" }
        var text = frame.bin == 1 ? "" : "bin \(frame.bin)"
        if let crop = frame.crop {
            text += (text.isEmpty ? "" : " · ") + "crop \(crop.width)×\(crop.height)"
        }
        return text
    }

    /// A second line for the box, only where the node's own record has a
    /// short, meaningful word for it.
    static func subtitle(of node: SessionLineage.Node) -> String? {
        switch node.kind {
        case "export": node.parameters["format"]
        case "acom": node.parameters["material"]
        default: nil
        }
    }

    /// "Step s5, Disk detection, stale" — the node button's accessibility label.
    func accessibilityLabel(for node: SessionLineage.Node) -> String {
        "Step \(node.id), \(LineageKindStyle.fullTitle(node.kind)), \(state(of: node.id).phrase)"
    }
}
