import SwiftUI

/// The spectrum strip (ADR 056): a header (title, one "Show" menu), the Canvas plot on a log axis opening on the listed lines'
/// energy span, and the ±3σ residual strip. No caption: the Show menu carries the legend as coloured symbols and the whole
/// map's curve is named at its end. The whole map's spectrum (grey) and each pin's (its own colour) are scaled to the
/// region's counts: a comparison of shapes.
///
/// Interaction follows Velox where pure SwiftUI allows: pinch (and the wheel with ⌃, as
/// macOS synthesises it — `ZoomPan.swift` documents why no AppKit scroll monitor is used)
/// zooms the energy axis about the pointer, drag pans, a vertical drag in the y-axis gutter stretches the counts axis,
/// double-click shows the full range (0 to where 99.5 % of the counts lie, at most 20 keV), Home returns to the lines' span.
/// DEVIATION from Velox: a plain mouse wheel does not zoom (needs an AppKit event
/// monitor); open question for the owner.
struct SpectrumStripView: View {
    @Bindable var model: SpectroscopyRoomModel
    /// Spec 2 D-7: the header's empty area is the room's horizontal divider. The room binds this (the translation so far and
    /// whether the drag ended); the strip itself knows nothing of the maps block.
    var onHeaderDrag: ((CGSize, Bool) -> Void)? = nil

    @State private var dragStart: SpectrumViewport?
    @State private var pinchStart: SpectrumViewport?
    /// The y stretch when a drag that began in the y-axis gutter started (that drag stretches instead of panning).
    @State private var yStart: Double?
    @State private var hover: CGPoint?
    /// Names the label layout left out in the current view; said in the plot's help.
    @State private var hiddenLabels: [String] = []
    @FocusState private var focused: Bool

    private enum PlotMetrics { static let pinDot: CGFloat = 7, tick: CGFloat = 4 }
    private enum Metrics {
        static let left: CGFloat = 46, right: CGFloat = 8, top: CGFloat = 6
        static let axisBand: CGFloat = 20
        static let residualHeight: CGFloat = 46
        static let gap: CGFloat = 4
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            plot
        }
        .accessibilityIdentifier("spectroscopy.spectrum")
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(model.spectrumTitle).fontWeight(.semibold)
                Text("· \(model.spectrumSubtitle)").foregroundStyle(.secondary)
            }.font(.callout).lineLimit(1).truncationMode(.tail)
                .help("Drag to resize the maps and the spectrum")
            Spacer(minLength: 8)
            pinChips
            showMenu
        }
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: LayoutPolicy.paneHeaderHeight)
        // The controls sit above this: the empty header is the grab zone (the infobar pattern, `StatusBar`).
        .background {
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { onHeaderDrag?($0.translation, false) }
                    .onEnded { onHeaderDrag?($0.translation, true) })
        }
    }

    private var showMenu: some View {
        Menu("Show") {
            Toggle(isOn: $model.layers.spectrum) { Self.legendLabel("Spectrum", Color.primary) }
            Toggle(isOn: $model.layers.background) { Self.legendLabel("Background", Color.orange) }
            Toggle(isOn: $model.layers.model) { Self.legendLabel("Model", Color.blue) }
            Toggle(isOn: $model.layers.residual) { Self.legendLabel("Residual", Color.secondary) }
            Toggle(isOn: $model.layers.pins) { Self.legendLabel("Pins", Color.pink) }
            Divider()
            Toggle("Log scale", isOn: $model.layers.log)
        }
        .menuStyle(.button).controlSize(.small).fixedSize()
        .accessibilityIdentifier("spectroscopy.show")
    }

    private var pinChips: some View {
        HStack(spacing: 6) {
            ForEach(model.pins) { pin in
                Button { model.onUnpin?(pin.id) } label: {
                    HStack(spacing: 3) { Circle().fill(pin.tint).frame(width: PlotMetrics.pinDot, height: PlotMetrics.pinDot); Text(pin.label); Image(systemName: "xmark").font(.caption2) }
                }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                .help("Unpin \(pin.label): \(pin.pixels) px")
            }
        }
    }

    /// A Show-menu row led by a symbol in the curve's colour: the legend, so no sentence sits under the plot.
    private static func legendLabel(_ title: String, _ color: Color) -> some View {
        Label { Text(title) } icon: { Image(systemName: "circle.fill").symbolRenderingMode(.palette).foregroundStyle(color) }
    }

    // MARK: plot

    private var plot: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { ctx, size in draw(ctx, size) }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        if v.startLocation.x < Metrics.left {      // began in the y-axis gutter: stretch the counts axis
                            let start = yStart ?? model.viewport.yScale
                            yStart = start
                            model.viewport.yScale = SpectrumViewport.yScale(from: start, dragDY: Double(v.translation.height))
                            return
                        }
                        let start = dragStart ?? model.viewport
                        dragStart = start
                        var vp = start
                        vp.pan(byFraction: -Double(v.translation.width / max(plotWidth(size), 1)))
                        model.viewport = vp; model.viewportIsManual = true
                    }
                    .onEnded { _ in dragStart = nil; yStart = nil })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { g in
                        let start = pinchStart ?? model.viewport
                        pinchStart = start
                        var vp = start
                        vp.zoom(factor: Double(g.magnification), anchor: SpectrumStripLogic.anchor(startX: g.startLocation.x, plotLeft: Metrics.left, plotWidth: plotWidth(size)))
                        model.viewport = vp; model.viewportIsManual = true
                    }
                    .onEnded { _ in pinchStart = nil })
                .onTapGesture(count: 2) { showFullRange() }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): hover = p
                    case .ended: hover = nil
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(.home) { resetViewport(); return .handled }
                .help("Pinch to zoom, drag to pan, drag in the counts axis to stretch it\n"
                      + "Double-click: the full range · Home: the lines' span\n"
                      + "The whole map's spectrum and each pin's are scaled to the region's total counts: a comparison of shapes, not of intensities.\n"
                      + "Residual: (data − model)/√model in σ, clipped at ±3; a tick on the edge marks a clipped channel."
                      + (hiddenLabels.isEmpty ? "" : "\nNames left out where lines crowd: " + hiddenLabels.joined(separator: ", ")))
        }
    }

    private func plotWidth(_ size: CGSize) -> CGFloat { size.width - Metrics.left - Metrics.right }

    /// Double-click: 0 to the energy below which 99.5 % of the counts lie (at most 20 keV), and the counts axis back to auto.
    /// The view stays where the person put it (manual) until Home.
    private func showFullRange() {
        let r = SpectrumStripLogic.fullRange(domain: model.series.domain, minimumSpan: model.viewport.minimumSpan, countsEnergy: SpectrumAutoZoom.countsEnergy(data: model.series.data, energyStart: model.series.energyStart, energyStep: model.series.energyStep))
        model.viewportIsManual = true
        model.viewport.lo = r.lowerBound; model.viewport.hi = r.upperBound; model.viewport.yScale = 1
    }

    /// Home: back to the span of the listed lines (the opening view), which the viewport follows again; the counts axis to auto.
    private func resetViewport() {
        model.viewportIsManual = false
        model.viewport.yScale = 1
        let r = SpectrumAutoZoom.range(markers: model.markers, domain: model.series.domain, minimumSpan: model.viewport.minimumSpan, countsEnergy: SpectrumAutoZoom.countsEnergy(data: model.series.data, energyStart: model.series.energyStart, energyStep: model.series.energyStep), fitEnd: model.fitEndKeV)
        model.viewport.lo = r.lowerBound; model.viewport.hi = r.upperBound
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        var L = model.layers
        let s = model.series
        if !s.hasModel { L.residual = false }     // no fit: no model curve, no residual strip
        let resH = L.residual ? Metrics.residualHeight : 0
        let main = CGRect(x: Metrics.left, y: Metrics.top,
                          width: plotWidth(size),
                          height: size.height - Metrics.top - Metrics.axisBand - resH - (L.residual ? Metrics.gap : 0))
        let res = CGRect(x: main.minX, y: main.maxY + Metrics.gap, width: main.width, height: resH)
        guard main.width > 20, main.height > 20 else { return }
        let vp = model.viewport
        let i0 = max(0, Int(((vp.lo - s.energyStart) / s.energyStep).rounded(.down)))
        let i1 = min(s.count - 1, Int(((vp.hi - s.energyStart) / s.energyStep).rounded(.up)))
        guard i1 > i0 else { return }

        // y range over what is visible
        var yMax = 1.0, yMinPos = Double.infinity
        for i in i0...i1 {
            yMax = max(yMax, s.data[i]); if s.hasModel { yMax = max(yMax, s.model[i]) }
            if s.data[i] > 0 { yMinPos = min(yMinPos, s.data[i]) }
        }
        let logRange = SpectrumYRange.log(minPositive: yMinPos, maximum: yMax)
        let logLo = L.log ? logRange.lo : 0
        let logHi = logRange.hi
        // The y stretch (`viewport.yScale`) divides the automatic top; in log the top decade moves down, never below two times the floor.
        let yTop = vp.scaledTop(yMax * 1.1)
        let logHiDrawn = vp.scaledTop(logHi, floor: logLo * 2)
        func X(_ e: Double) -> CGFloat { main.minX + CGFloat(vp.fraction(of: e)) * main.width }
        func Y(_ v: Double) -> CGFloat {
            if L.log {
                let t = (log10(max(v, logLo)) - log10(logLo)) / max(log10(logHiDrawn) - log10(logLo), 1e-9)
                return main.maxY - CGFloat(t) * main.height
            }
            return main.maxY - CGFloat(v / yTop) * main.height
        }

        // axes: a baseline and a left axis, tick marks, decade lines only (log); no box
        let grid = Color.primary.opacity(0.06), axisInk = Color.secondary, axisLine = Color.primary.opacity(0.25)
        let axisFont = Font.system(size: 10)
        func hline(_ y: CGFloat, _ x0: CGFloat, _ x1: CGFloat, _ c: Color) {
            var p = Path(); p.move(to: CGPoint(x: x0, y: y)); p.addLine(to: CGPoint(x: x1, y: y)); ctx.stroke(p, with: .color(c), lineWidth: 0.5)
        }
        func vline(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ c: Color) {
            var p = Path(); p.move(to: CGPoint(x: x, y: y0)); p.addLine(to: CGPoint(x: x, y: y1)); ctx.stroke(p, with: .color(c), lineWidth: 0.5)
        }
        hline(main.maxY, main.minX, main.maxX, axisLine)
        vline(main.minX, main.minY, main.maxY, axisLine)
        let xTarget = max(3, Int(main.width / 80))
        let xStep = AxisTicks.niceStep(lo: vp.lo, hi: vp.hi, target: xTarget)
        let xTicks = AxisTicks.linear(lo: vp.lo, hi: vp.hi, target: xTarget)
        for e in xTicks { vline(X(e), main.maxY, main.maxY + PlotMetrics.tick, axisLine) }
        // The unit is the axis title, in the left gutter under the counts labels, where no tick label sits.
        let xAxis = AxisTicks.xLabels(ticks: xTicks, x: { X($0) }, step: xStep, unit: "keV", unitTrailing: main.minX - 8)
        let axisY = size.height - Metrics.axisBand / 2 + 3
        for l in xAxis.labels { ctx.draw(Text(l.text).font(axisFont).foregroundStyle(axisInk), at: CGPoint(x: l.x, y: axisY)) }
        ctx.draw(Text(xAxis.unit.text).font(axisFont).foregroundStyle(axisInk), at: CGPoint(x: xAxis.unit.trailing, y: axisY), anchor: .trailing)
        if L.log {
            for e in AxisTicks.logDecades(lo: logLo, hi: logHiDrawn) {
                let y = Y(pow(10, Double(e)))
                hline(y, main.minX, main.maxX, grid)
                ctx.draw(Text("10\(Self.superscript(e))").font(axisFont).foregroundStyle(axisInk),
                         at: CGPoint(x: main.minX - 16, y: y))
            }
        } else {
            for v in AxisTicks.linear(lo: 0, hi: yTop, target: 5) {
                let y = Y(v)
                hline(y, main.minX - PlotMetrics.tick, main.minX, axisLine)
                ctx.draw(Text(Self.format(v)).font(axisFont).foregroundStyle(axisInk),
                         at: CGPoint(x: main.minX - 16, y: y))
            }
        }
        // y-axis title
        var vctx = ctx
        vctx.translateBy(x: 8, y: main.midY); vctx.rotate(by: .degrees(-90))
        vctx.draw(Text("counts / \(Int((s.energyStep * 1000).rounded())) eV").font(axisFont).foregroundStyle(axisInk), at: .zero)

        // curves, clipped to the frame
        var clip = ctx; clip.clip(to: Path(main))
        func curve(_ ys: [Double], _ color: Color, width: CGFloat, dash: [CGFloat] = [], within: Range<Int>? = nil) {
            var p = Path()
            // The model and the background exist only where the fit ran (R3): outside it nothing is drawn.
            let lo = max(i0, within?.lowerBound ?? i0), hi = min(i1, (within?.upperBound ?? (i1 + 1)) - 1)
            guard hi > lo else { return }
            for i in lo...hi {
                let pt = CGPoint(x: X(s.energy(i)), y: Y(ys[i]))
                if i == lo { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            clip.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineJoin: .round, dash: dash))
        }
        let total = s.data.reduce(0, +)
        if s.hasOverlay, let o = s.overlay {
            curve(o, Color.secondary.opacity(0.7), width: 1)
            // named directly at its right end (the last visible channel), above the curve; never in a caption
            let k = min(i1, o.count - 1)
            let end = CGPoint(x: min(X(s.energy(k)), main.maxX) - 4, y: min(max(Y(o[k]) - 8, main.minY + 8), main.maxY - 8))
            ctx.draw(Text("whole map").font(axisFont).foregroundStyle(axisInk), at: end, anchor: .trailing)
        }
        for pin in model.pins where L.pins && pin.spectrum.count == s.count {
            let t = pin.spectrum.reduce(0, +)
            if t > 0, total > 0 { let k = total / t; curve(pin.spectrum.map { $0 * k }, pin.tint.opacity(SpectrumLayers.pinOpacity), width: 1) }
        }
        if L.spectrum { curve(s.data, Color.primary.opacity(0.85), width: 0.9) }
        if L.model, s.hasModel { curve(s.model, .blue, width: 1.8, within: s.fitChannels) }
        if L.background, s.hasBackground { curve(s.background, .orange.opacity(0.9), width: 1, dash: [1, 2], within: s.fitChannels) }

        // line markers: lines first, names staggered into rows by `MarkerLabelLayout`
        // Suspects are not drawn (spec 2 D-3); a highlighted element's lines are thicker and their names bold (D-15).
        let visible = MarkerLabelLayout.inView(model.markers, lo: vp.lo, hi: vp.hi)
        let highlightedZ = model.highlightedZ
        for m in visible {
            let x = X(m.energy)
            let color = Self.markerColor(m, model: model)
            var p = Path(); p.move(to: CGPoint(x: x, y: main.minY)); p.addLine(to: CGPoint(x: x, y: main.maxY))
            ctx.stroke(p, with: .color(color.opacity(0.8)),
                       style: StrokeStyle(lineWidth: SpectrumStripLogic.lineWidth(m, highlightedZ: highlightedZ), dash: m.kind == .edge ? [1, 2] : [4, 3]))
        }
        let layout = MarkerLabelLayout.place(visible.filter { $0.kind != .edge }.map { ($0.label, X($0.energy), $0.priority) }, minX: main.minX, maxX: main.maxX)
        for m in visible {
            let x = X(m.energy)
            let color = Self.markerColor(m, model: model)
            let t = Text(m.label).font(.system(size: m.kind == .edge ? 10 : 11, weight: SpectrumStripLogic.isHighlighted(m, highlightedZ: highlightedZ) ? .bold : (m.kind == .line ? .semibold : .regular))).foregroundStyle(color)
            if m.kind == .edge {   // the edge label sits low, by the curve, so it never collides with the line names
                ctx.draw(t, at: CGPoint(x: x + 2, y: main.maxY - 40), anchor: .leading)
            } else if let pl = layout.placed.first(where: { $0.label == m.label }) {
                let y = main.minY + 8 + CGFloat(pl.row) * 12
                ctx.draw(t, at: CGPoint(x: pl.leading ? x + 2 : x - 2, y: y), anchor: pl.leading ? .leading : .trailing)
            }
        }
        if layout.left != hiddenLabels { DispatchQueue.main.async { hiddenLabels = layout.left } }

        // residual strip: a zero line, the ±3 clip values at the left axis, no red; a clipped channel is a tick on the edge
        if L.residual {
            vline(res.minX, res.minY, res.maxY, axisLine)
            hline(res.maxY, res.minX, res.maxX, axisLine)
            let zero = res.midY
            hline(zero, res.minX, res.maxX, grid)
            ctx.draw(Text("σ").font(axisFont).foregroundStyle(axisInk), at: CGPoint(x: res.minX - 16, y: zero))
            ctx.draw(Text("+3").font(axisFont).foregroundStyle(axisInk), at: CGPoint(x: res.minX - 16, y: res.minY + 6))
            ctx.draw(Text("−3").font(axisFont).foregroundStyle(axisInk), at: CGPoint(x: res.minX - 16, y: res.maxY - 6))
            var rc = ctx; rc.clip(to: Path(res))
            let r = s.residual
            var p = Path()
            let rLo = max(i0, s.fitChannels?.lowerBound ?? i0), rHi = min(i1, (s.fitChannels?.upperBound ?? (i1 + 1)) - 1)
            for i in rLo...max(rLo, rHi) where i <= rHi {
                let v = min(max(r[i], -ResidualNormalisation.frame), ResidualNormalisation.frame)
                let pt = CGPoint(x: X(s.energy(i)), y: zero - CGFloat(v / ResidualNormalisation.frame) * res.height / 2)
                if i == rLo { p.move(to: pt) } else { p.addLine(to: pt) }
                let side = ResidualNormalisation.clipSide(r[i])
                if side != 0 {     // clipped at the frame: a small tick on that edge says so, in the secondary colour
                    let edge = side > 0 ? res.minY : res.maxY, inward: CGFloat = side > 0 ? 1 : -1
                    var t = Path(); t.move(to: CGPoint(x: pt.x, y: edge)); t.addLine(to: CGPoint(x: pt.x, y: edge + inward * PlotMetrics.tick))
                    rc.stroke(t, with: .color(Color.secondary), lineWidth: 1)
                }
            }
            rc.stroke(p, with: .color(Color.primary.opacity(0.6)), lineWidth: 0.8)
        }
        drawHover(ctx, size, main)
    }

    /// The edge is grey, a line its element's colour.
    private static func markerColor(_ m: LineMarker, model: SpectroscopyRoomModel) -> Color {
        switch m.kind {
        case .line: return model.color(m.elementZ ?? 0)
        case .edge: return .gray
        }
    }

    /// Cursor guide and readout (Velox shows the same): energy, counts, nearest line.
    private func drawHover(_ ctx: GraphicsContext, _ size: CGSize, _ main: CGRect) {
        guard let h = hover, main.contains(CGPoint(x: h.x, y: main.midY)) else { return }
        let f = Double((h.x - main.minX) / main.width)
        guard let smp = SpectrumHover.sample(series: model.series, viewport: model.viewport, fraction: f, markers: model.markers) else { return }
        var p = Path(); p.move(to: CGPoint(x: h.x, y: main.minY)); p.addLine(to: CGPoint(x: h.x, y: main.maxY))
        ctx.stroke(p, with: .color(Color.primary.opacity(0.35)), lineWidth: 0.6)
        var text = String(format: "%.3f keV · %@ counts", smp.energy, Self.format(smp.counts))
        if let l = smp.line { text += " · \(l)" }
        let label = Text(text).font(.system(size: 10).monospacedDigit()).foregroundStyle(Color.primary)
        let onRight = h.x < main.midX
        let box = CGRect(x: onRight ? h.x + 6 : h.x - 6 - 190, y: main.minY + 18, width: 190, height: 16)
        ctx.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(Color(white: 0.5).opacity(0.18)))
        ctx.draw(label, at: CGPoint(x: box.minX + 4, y: box.midY), anchor: .leading)
    }

    static func format(_ v: Double) -> String {
        if v >= 10_000 { return String(format: "%.0fk", v / 1000) }
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    static func superscript(_ n: Int) -> String {
        let map: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(n).map { map[$0] ?? $0 })
    }
}

/// The strip's pure decisions (spec 2 item 7); the drawing only applies them.
nonisolated enum SpectrumStripLogic {
    /// A marker of the highlighted element (hovered or clicked tile or periodic-table cell).
    static func isHighlighted(_ m: LineMarker, highlightedZ: Int?) -> Bool { highlightedZ != nil && m.elementZ == highlightedZ }
    static func lineWidth(_ m: LineMarker, highlightedZ: Int?) -> CGFloat { isHighlighted(m, highlightedZ: highlightedZ) ? 1.8 : 0.8 }
    /// Double-click: from the axis start to where 99.5 % of the counts lie (floor 2 keV, cap 20 keV): the opening view with no line.
    static func fullRange(domain: ClosedRange<Double>, minimumSpan: Double, countsEnergy: Double?) -> ClosedRange<Double> {
        SpectrumAutoZoom.range(markers: [], domain: domain, minimumSpan: minimumSpan, countsEnergy: countsEnergy)
    }
    /// The pinch anchor: the gesture's start x (in the plot view's own space, the space `draw` lays the frame out in) as a
    /// fraction of the frame's width, clamped to the frame.
    static func anchor(startX: CGFloat, plotLeft: CGFloat, plotWidth: CGFloat) -> Double {
        min(max(Double((startX - plotLeft) / max(plotWidth, 1)), 0), 1)
    }
}

/// The badge `validation:"none"` carries on screen (ADR 054 §3). Orange text on a tint,
/// as the mock draws it; the word is the claim.
struct UnvalidatedBadge: View {
    var body: some View {
        Text("unvalidated")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .accessibilityLabel("unvalidated")
    }
}

#Preview("Spectrum strip") {
    SpectrumStripView(model: .fixture).frame(width: 640, height: 300)
}
