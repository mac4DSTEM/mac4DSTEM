//
//  LineageGraphView.swift
//  Role: The run graph in the bottom Lineage pane (ADR 047, R9 / phase L3;
//        mock: docs/archive/v4/lineage-graph-mock-2026-09-30.html). Layered
//        left to right; one `Button` per run; edges on a `Canvas` beneath them;
//        the selected run's record in a trailing column INSIDE the pane. SwiftUI
//        only. Presentation only — where things go is `LineageGraphLayout`, the
//        lineage itself is read, never written.
//
//  States are drawn by SYMBOL, never by colouring the box: a green check
//  (current), an orange triangle and a dashed border (stale — its settings are
//  active but the product on screen came from another run), a branch glyph and
//  a dimmed box (kept, on another branch). The accent colour marks only the
//  selection and the edges touching it. A run recorded before lineage existed
//  (v1) has no recorded inputs: its connectors are dotted and captioned
//  "Recorded before lineage: order only".
//
//  Narrow pane (below `LineageGraphMetrics.graphMinimumWidth`): the graph gives
//  way to a list of the active path with the same detail beneath it. No
//  "Rewind to Here" yet — rewind is L4 (Gate D); no dead control is shown.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct LineageGraphView: View {
    let model: LineageGraphModel

    @State private var selectedID: String?
    @State private var scrollPosition = ScrollPosition()
    @State private var visibleRect = CGRect.zero
    @FocusState private var isFocused: Bool

    /// The chosen run, or the one recorded last when nothing (valid) is chosen.
    private var selected: SessionLineage.Node? {
        if let selectedID, let node = model.nodes.first(where: { $0.id == selectedID }) { return node }
        return model.defaultSelection.flatMap { id in model.nodes.first { $0.id == id } }
    }

    var body: some View {
        GeometryReader { proxy in
            if model.nodes.isEmpty {
                Text("No steps recorded yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(LayoutPolicy.infobarHorizontalPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if LineageGraphMetrics.showsGraph(paneWidth: proxy.size.width) {
                HStack(spacing: 0) {
                    graphColumn
                    Divider()
                    ScrollView {
                        detail(for: selected)
                            .padding(LayoutPolicy.infobarHorizontalPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: LineageGraphMetrics.detailColumnWidth)
                }
            } else {
                narrowList
            }
        }
        .accessibilityIdentifier("bottomWorkspace.lineage.graph")
    }

    // MARK: - Graph

    private var graphColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.hasOrderOnlyConnectors {
                Text("Recorded before lineage: order only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
                    .padding(.top, 6)
            }
            ScrollView([.horizontal, .vertical]) {
                graphCanvas
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGRect.self, of: { $0.visibleRect }) { _, rect in
                visibleRect = rect
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(phases: .down) { handleArrowKey($0, inGraph: true) }
        .onChange(of: selected?.id) { _, id in reveal(id) }
    }

    private var graphCanvas: some View {
        let size = LineageGraphMetrics.contentSize(columns: model.layout.columnCount,
                                                   rows: model.layout.rowCount)
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                drawEdges(into: &context)
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            ForEach(model.nodes, id: \.id) { node in
                nodeButton(node)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func nodeButton(_ node: SessionLineage.Node) -> some View {
        let placement = model.layout.placement(of: node.id)
        let origin = LineageGraphMetrics.origin(column: placement?.column ?? 0, row: placement?.row ?? 0)
        let isSelected = node.id == selected?.id
        return Button {
            selectedID = node.id
            isFocused = true
        } label: {
            LineageNodeBox(node: node, state: model.state(of: node.id), isSelected: isSelected,
                           subtitle: LineageGraphModel.subtitle(of: node))
        }
        .buttonStyle(.plain)
        .frame(width: LineageGraphMetrics.nodeWidth, height: LineageGraphMetrics.nodeHeight)
        .offset(x: origin.x, y: origin.y)
        .accessibilityLabel(model.accessibilityLabel(for: node))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("bottomWorkspace.lineage.node.\(node.id)")
    }

    /// Input edges, right-pointing curves from a node's trailing edge to the
    /// next node's leading edge. An implied edge is drawn only beside the
    /// selection; the edges touching the selection take the accent colour.
    private func drawEdges(into context: inout GraphicsContext) {
        let layout = model.layout
        let selectedID = selected?.id
        let w = CGFloat(LineageGraphMetrics.nodeWidth), h = CGFloat(LineageGraphMetrics.nodeHeight)
        let bend = CGFloat(LineageGraphMetrics.columnGap * 0.6)
        for edge in layout.edges {
            guard let a = layout.placement(of: edge.from), let b = layout.placement(of: edge.to) else { continue }
            let touchesSelection = edge.from == selectedID || edge.to == selectedID
            if edge.implied && !touchesSelection { continue }
            let from = LineageGraphMetrics.origin(column: a.column, row: a.row)
            let to = LineageGraphMetrics.origin(column: b.column, row: b.row)
            let start = CGPoint(x: CGFloat(from.x) + w, y: CGFloat(from.y) + h / 2)
            let end = CGPoint(x: CGFloat(to.x), y: CGFloat(to.y) + h / 2)
            var path = Path()
            path.move(to: start)
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x + bend, y: start.y),
                          control2: CGPoint(x: end.x - bend, y: end.y))
            let dimmed = !model.activeIDs.contains(edge.from) || !model.activeIDs.contains(edge.to)
            let color: Color = touchesSelection ? .accentColor : Color.secondary.opacity(dimmed ? 0.35 : 0.65)
            if edge.orderOnly {
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [1, 4]))
            } else {
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: touchesSelection ? 2 : 1.2, lineCap: .round))
                var head = Path()
                head.move(to: end)
                head.addLine(to: CGPoint(x: end.x - 6, y: end.y - 3.5))
                head.addLine(to: CGPoint(x: end.x - 6, y: end.y + 3.5))
                head.closeSubpath()
                context.fill(head, with: .color(color))
            }
        }
    }

    // MARK: - Keyboard and scrolling

    private func handleArrowKey(_ press: KeyPress, inGraph: Bool) -> KeyPress.Result {
        guard let current = selected?.id else { return .ignored }
        let next: String?
        if inGraph {
            let direction: LineageGraphLayout.Direction
            switch press.key {
            case .leftArrow: direction = .left
            case .rightArrow: direction = .right
            case .upArrow: direction = .up
            case .downArrow: direction = .down
            default: return .ignored
            }
            next = model.layout.neighbor(of: current, direction)
        } else {
            switch press.key {
            case .upArrow, .leftArrow: next = model.activePathNeighbor(of: current, offset: -1)
            case .downArrow, .rightArrow: next = model.activePathNeighbor(of: current, offset: 1)
            default: return .ignored
            }
        }
        // At an edge of the graph the key is consumed, not passed up: the scan
        // position's arrow-key stepping must not fire from here.
        if let next { selectedID = next }
        return .handled
    }

    /// Scroll the chosen node into view if it is not (a plain arrow key must
    /// never leave the selection off-screen).
    private func reveal(_ id: String?) {
        guard let id, let placement = model.layout.placement(of: id), visibleRect.width > 0 else { return }
        let origin = LineageGraphMetrics.origin(column: placement.column, row: placement.row)
        let pad = CGFloat(LineageGraphMetrics.margin)
        let node = CGRect(x: origin.x, y: origin.y,
                          width: LineageGraphMetrics.nodeWidth, height: LineageGraphMetrics.nodeHeight)
        var x = visibleRect.minX, y = visibleRect.minY
        if node.minX - pad < visibleRect.minX { x = max(0, node.minX - pad) }
        else if node.maxX + pad > visibleRect.maxX { x = node.maxX + pad - visibleRect.width }
        if node.minY - pad < visibleRect.minY { y = max(0, node.minY - pad) }
        else if node.maxY + pad > visibleRect.maxY { y = node.maxY + pad - visibleRect.height }
        if x != visibleRect.minX || y != visibleRect.minY {
            scrollPosition.scrollTo(x: x, y: y)
        }
    }

    // MARK: - Narrow pane: the active path as a list

    private var narrowList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.activePath, id: \.id) { node in
                    listRow(node)
                }
                if model.branchNodeCount > 0 {
                    Text("\(model.branchNodeCount) run\(model.branchNodeCount == 1 ? "" : "s") on other branches — widen the pane to see the graph.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
                        .padding(.vertical, 6)
                }
                Divider()
                detail(for: selected)
                    .padding(LayoutPolicy.infobarHorizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(phases: .down) { handleArrowKey($0, inGraph: false) }
    }

    private func listRow(_ node: SessionLineage.Node) -> some View {
        let state = model.state(of: node.id)
        let isSelected = node.id == selected?.id
        let others = model.otherBranchCount(kind: node.kind)
        return Button {
            selectedID = node.id
            isFocused = true
        } label: {
            HStack(spacing: LayoutPolicy.inspectorRowSpacing) {
                Image(systemName: LineageKindStyle.symbolName(node.kind))
                    .foregroundStyle(.secondary)
                    .frame(width: LineageGraphMetrics.symbolWidth)
                Text("\(node.id) · \(LineageKindStyle.fullTitle(node.kind))")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if others > 0 {
                    Text("\(others) other")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                LineageStateSymbol(state: state)
            }
            .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { if isSelected { Rectangle().fill(Color.secondary.opacity(0.15)) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.accessibilityLabel(for: node))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("bottomWorkspace.lineage.node.\(node.id)")
    }

    // MARK: - Detail

    private static let recordedFormat: Date.FormatStyle = .dateTime.month(.abbreviated).day().hour().minute()

    @ViewBuilder
    private func detail(for node: SessionLineage.Node?) -> some View {
        if let node {
            let state = model.state(of: node.id)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: LineageKindStyle.symbolName(node.kind))
                        .foregroundStyle(.secondary)
                    Text(LineageKindStyle.fullTitle(node.kind))
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text("\(node.id) · \(state.phrase) · \(node.recorded.formatted(Self.recordedFormat))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)

                differences(of: node)

                DetailSection("Parameters") {
                    LineageDetailRow(label: "Frame", value: LineageGraphModel.frameDescription(node.frame))
                    ForEach(node.parameters.sorted { $0.key < $1.key }, id: \.key) { entry in
                        LineageDetailRow(label: LineageKindStyle.humanised(entry.key), value: entry.value)
                    }
                    if node.parameters.isEmpty {
                        Text("No parameters recorded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DetailSection("Inputs") { inputs(of: node) }

                DetailSection("Record") {
                    LineageDetailRow(label: "Product", value: node.product ?? "Not saved", mono: false)
                    LineageDetailRow(label: "Recorded", value: node.recorded.formatted(Self.recordedFormat), mono: false)
                    if node.source == "v1" {
                        LineageDetailRow(label: "Source", value: "Before lineage", mono: false)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("bottomWorkspace.lineage.detail")
        } else {
            Text("Select a run to see its record.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// For a run on another branch: what differs from the active run of its kind.
    @ViewBuilder
    private func differences(of node: SessionLineage.Node) -> some View {
        if model.state(of: node.id) == .branch, let active = model.activeCounterpart(of: node) {
            let rows = LineageGraphModel.differences(of: node, from: active)
            if !rows.isEmpty {
                DetailSection("Differs from the active path") {
                    ForEach(rows, id: \.key) { row in
                        VStack(alignment: .trailing, spacing: 0) {
                            LineageDetailRow(label: LineageKindStyle.humanised(row.key), value: row.value ?? "—")
                            Text("now \(row.activeValue ?? "—")")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inputs(of node: SessionLineage.Node) -> some View {
        if let inputs = node.inputs {
            ForEach(Array(inputs.enumerated()), id: \.offset) { _, input in
                if let upstream = model.node(id: input.step) {
                    let navigable = model.nodes.contains { $0.id == upstream.id }
                    Button {
                        selectedID = upstream.id
                        isFocused = true
                    } label: {
                        HStack(spacing: LayoutPolicy.inspectorRowSpacing) {
                            Image(systemName: LineageKindStyle.symbolName(upstream.kind))
                                .foregroundStyle(.secondary)
                                .frame(width: LineageGraphMetrics.inputSymbolWidth)
                            Text(LineageKindStyle.shortTitle(upstream.kind))
                                .font(.caption)
                            Spacer(minLength: 4)
                            Text(upstream.id)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!navigable)
                    .help("\(LineageKindStyle.fullTitle(upstream.kind)) — \(input.role)")
                    .accessibilityLabel("Input \(upstream.id), \(LineageKindStyle.fullTitle(upstream.kind)), \(input.role)")
                }
            }
            ForEach(node.external, id: \.fingerprint) { file in
                LineageDetailRow(label: file.name, value: String(file.fingerprint.prefix(12)))
            }
            if inputs.isEmpty && node.external.isEmpty {
                Text("Consumes nothing in this session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Recorded before lineage: order only")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(node.external, id: \.fingerprint) { file in
                LineageDetailRow(label: file.name, value: String(file.fingerprint.prefix(12)))
            }
        }
    }
}

// MARK: - Pieces

/// One run: kind symbol and "s5 · Disks", the state symbol at the corner.
private struct LineageNodeBox: View {
    let node: SessionLineage.Node
    let state: LineageNodeState
    let isSelected: Bool
    let subtitle: String?

    var body: some View {
        let radius = CGFloat(LineageKindStyle.isSink(node.kind) ? LineageGraphMetrics.nodeHeight / 2 : 8)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: LineageKindStyle.symbolName(node.kind))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: LineageGraphMetrics.symbolWidth)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(node.id) · \(LineageKindStyle.shortTitle(node.kind))")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 9)
        .padding(.trailing, 14)
        .frame(width: LineageGraphMetrics.nodeWidth, height: LineageGraphMetrics.nodeHeight)
        .background(shape.fill(.background))
        .overlay {
            if isSelected {
                shape.strokeBorder(Color.accentColor, lineWidth: 2)
            } else {
                shape.strokeBorder(.tertiary,
                                   style: StrokeStyle(lineWidth: 1, dash: state == .stale ? [4, 3] : []))
            }
        }
        .overlay(alignment: .topTrailing) {
            LineageStateSymbol(state: state)
                .font(.system(size: 10))
                .padding(.top, 4)
                .padding(.trailing, LineageKindStyle.isSink(node.kind) ? 10 : 5)
        }
        .opacity(state == .branch ? 0.55 : 1)
        .contentShape(shape)
    }
}

/// The state symbol — the only place a status colour appears.
private struct LineageStateSymbol: View {
    let state: LineageNodeState

    var body: some View {
        Image(systemName: state.symbolName)
            .foregroundStyle(color)
            .accessibilityHidden(true)   // the node's own label carries the state
    }

    private var color: Color {
        switch state {
        case .current: .green
        case .stale: .orange
        case .branch: .secondary
        }
    }
}

/// A titled group in the detail column: flat, no card (the inspector rule).
private struct DetailSection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(.top, 10)
    }
}

/// Label at the leading edge, value at the trailing edge (the owner's rule),
/// one line each; a long value truncates in the middle and is the row's help.
private struct LineageDetailRow: View {
    let label: String
    let value: String
    var mono = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(value)
                .font(mono ? .caption.monospaced() : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
        }
        .help("\(label): \(value)")
    }
}
