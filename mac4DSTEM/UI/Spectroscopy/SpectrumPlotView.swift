import SwiftUI

/// The spectrum pane: a header (title, layer toggles that fold into one "Show" menu when
/// narrow), the Canvas plot, the ±3σ residual strip, and the fit footer.
///
/// Interaction follows Velox where pure SwiftUI allows: pinch (and the wheel with ⌃, as
/// macOS synthesises it — `ZoomPan.swift` documents why no AppKit scroll monitor is used)
/// zooms the energy axis about the pointer, drag pans, double-click or Home resets.
/// DEVIATION from Velox: a plain mouse wheel does not zoom (needs an AppKit event
/// monitor); open question for the owner.
struct SpectrumPlotView: View {
    @Bindable var model: SpectroscopyRoomModel
    var narrow: Bool

    @State private var dragStart: SpectrumViewport?
    @State private var pinchStart: SpectrumViewport?
    @State private var hover: CGPoint?
    @FocusState private var focused: Bool

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
            Divider()
            footer
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 8) {
            (Text(model.spectrumTitle).fontWeight(.semibold)
             + Text(" · ").foregroundStyle(.secondary)
             + Text(model.spectrumSubtitle).foregroundStyle(.secondary))
                .font(.callout).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if narrow { showMenu } else { chips }
        }
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: LayoutPolicy.paneHeaderHeight)
    }

    private var chips: some View {
        HStack(spacing: 4) {
            chip("Spectrum", \.spectrum); chip("Background", \.background); chip("Model", \.model)
            chip("Residual", \.residual); chip("Overlay", \.overlay); chip("Log", \.log)
        }
    }

    private func chip(_ title: String, _ key: WritableKeyPath<SpectrumLayers, Bool>) -> some View {
        let on = model.layers[keyPath: key]
        return Button { model.layers[keyPath: key].toggle() } label: {
            Text(title).font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .background(Capsule().fill(on ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05)))
                .overlay(Capsule().strokeBorder(on ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.15)))
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    private var showMenu: some View {
        Menu("Show") {
            Toggle("Spectrum", isOn: $model.layers.spectrum)
            Toggle("Background", isOn: $model.layers.background)
            Toggle("Model", isOn: $model.layers.model)
            Toggle("Residual", isOn: $model.layers.residual)
            Toggle("Overlay", isOn: $model.layers.overlay)
            Divider()
            Toggle("Log scale", isOn: $model.layers.log)
        }
        .menuStyle(.button).controlSize(.small).fixedSize()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(model.series.hasModel ? model.fitFooter : (model.isLive ? "no fit yet · Quantify fits the selected region" : "no fit yet")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if model.series.hasModel && model.unvalidated { UnvalidatedBadge() }
        }
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: 26)
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
                        let start = dragStart ?? model.viewport
                        dragStart = start
                        var vp = start
                        vp.pan(byFraction: -Double(v.translation.width / max(plotWidth(size), 1)))
                        model.viewport = vp
                    }
                    .onEnded { _ in dragStart = nil })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { g in
                        let start = pinchStart ?? model.viewport
                        pinchStart = start
                        var vp = start
                        let a = Double((g.startLocation.x - Metrics.left) / max(plotWidth(size), 1))
                        vp.zoom(factor: Double(g.magnification), anchor: min(max(a, 0), 1))
                        model.viewport = vp
                    }
                    .onEnded { _ in pinchStart = nil })
                .onTapGesture(count: 2) { model.viewport.reset() }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): hover = p
                    case .ended: hover = nil
                    }
                }
                .focusable()
                .focused($focused)
                .onKeyPress(.home) { model.viewport.reset(); return .handled }
                .help("Pinch to zoom, drag to pan, double-click or Home to reset")
        }
    }

    private func plotWidth(_ size: CGSize) -> CGFloat { size.width - Metrics.left - Metrics.right }

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
        let yTop = L.log ? logHi : yMax * 1.1
        func X(_ e: Double) -> CGFloat { main.minX + CGFloat(vp.fraction(of: e)) * main.width }
        func Y(_ v: Double) -> CGFloat {
            if L.log {
                let t = (log10(max(v, logLo)) - log10(logLo)) / max(log10(logHi) - log10(logLo), 1e-9)
                return main.maxY - CGFloat(t) * main.height
            }
            return main.maxY - CGFloat(v / yTop) * main.height
        }

        // frame + grid
        let grid = Color.primary.opacity(0.08), axisInk = Color.secondary
        ctx.stroke(Path(main), with: .color(Color.primary.opacity(0.25)), lineWidth: 0.5)
        let xTarget = max(3, Int(main.width / 80))
        let xStep = AxisTicks.niceStep(lo: vp.lo, hi: vp.hi, target: xTarget)
        for e in AxisTicks.linear(lo: vp.lo, hi: vp.hi, target: xTarget) {
            var p = Path(); p.move(to: CGPoint(x: X(e), y: main.minY)); p.addLine(to: CGPoint(x: X(e), y: main.maxY))
            ctx.stroke(p, with: .color(grid), lineWidth: 0.5)
            let at = CGPoint(x: X(e), y: size.height - Metrics.axisBand / 2 + 1)
            ctx.draw(Text(AxisTicks.label(e, step: xStep)).font(.system(size: 9)).foregroundStyle(axisInk), at: at)
        }
        ctx.draw(Text("keV").font(.system(size: 9)).foregroundStyle(axisInk),
                 at: CGPoint(x: main.maxX - 8, y: size.height - Metrics.axisBand / 2 + 1))
        if L.log {
            for e in AxisTicks.logDecades(lo: logLo, hi: logHi) {
                let y = Y(pow(10, Double(e)))
                var p = Path(); p.move(to: CGPoint(x: main.minX, y: y)); p.addLine(to: CGPoint(x: main.maxX, y: y))
                ctx.stroke(p, with: .color(grid), lineWidth: 0.5)
                ctx.draw(Text("10\(Self.superscript(e))").font(.system(size: 9)).foregroundStyle(axisInk),
                         at: CGPoint(x: main.minX - 16, y: y))
            }
        } else {
            for v in AxisTicks.linear(lo: 0, hi: yTop, target: 5) {
                let y = Y(v)
                var p = Path(); p.move(to: CGPoint(x: main.minX, y: y)); p.addLine(to: CGPoint(x: main.maxX, y: y))
                ctx.stroke(p, with: .color(grid), lineWidth: 0.5)
                ctx.draw(Text(Self.format(v)).font(.system(size: 9)).foregroundStyle(axisInk),
                         at: CGPoint(x: main.minX - 16, y: y))
            }
        }
        // y-axis title
        var vctx = ctx
        vctx.translateBy(x: 8, y: main.midY); vctx.rotate(by: .degrees(-90))
        vctx.draw(Text("counts / \(Int((s.energyStep * 1000).rounded())) eV").font(.system(size: 9)).foregroundStyle(axisInk), at: .zero)

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
        if L.overlay, s.hasOverlay, let o = s.overlay { curve(o, .gray, width: 1.2, dash: [4, 3]) }
        if L.spectrum { curve(s.data, Color.primary.opacity(0.45), width: 0.8) }
        if L.model, s.hasModel { curve(s.model, .blue, width: 1.8, within: s.fitChannels) }
        if L.background, s.hasBackground { curve(s.background, .orange.opacity(0.9), width: 1, dash: [1, 2], within: s.fitChannels) }
        if !s.hasModel {
            ctx.draw(Text("no fit yet").font(.callout).foregroundStyle(.secondary), at: CGPoint(x: main.midX, y: main.midY - 20))
        }

        // line markers
        for m in model.markers where m.energy >= vp.lo && m.energy <= vp.hi {
            let x = X(m.energy)
            let grey = m.kind != .line
            let color: Color = grey ? .gray : ElementPalette.color(m.elementZ ?? 0)
            var p = Path(); p.move(to: CGPoint(x: x, y: main.minY)); p.addLine(to: CGPoint(x: x, y: main.maxY))
            ctx.stroke(p, with: .color(color.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 0.8, dash: m.kind == .edge ? [1, 2] : [4, 3]))
            var t = Text(m.label).font(.system(size: m.kind == .edge ? 9 : 10, weight: m.kind == .line ? .semibold : .regular)).foregroundStyle(color)
            if m.kind == .suspect { t = t.italic() }
            // the edge label sits low, by the curve, so it never collides with the line names
            ctx.draw(t, at: CGPoint(x: x + 2, y: m.kind == .edge ? main.maxY - 40 : main.minY + 8), anchor: .leading)
        }

        // residual strip
        if L.residual {
            ctx.stroke(Path(res), with: .color(Color.primary.opacity(0.25)), lineWidth: 0.5)
            let zero = res.midY
            var z = Path(); z.move(to: CGPoint(x: res.minX, y: zero)); z.addLine(to: CGPoint(x: res.maxX, y: zero))
            ctx.stroke(z, with: .color(grid), lineWidth: 0.5)
            ctx.draw(Text("res σ").font(.system(size: 9)).foregroundStyle(axisInk), at: CGPoint(x: res.minX - 16, y: zero))
            ctx.draw(Text("±3").font(.system(size: 8)).foregroundStyle(axisInk), at: CGPoint(x: res.maxX - 8, y: res.minY + 6))
            var rc = ctx; rc.clip(to: Path(res))
            let r = s.residual
            var p = Path()
            let rLo = max(i0, s.fitChannels?.lowerBound ?? i0), rHi = min(i1, (s.fitChannels?.upperBound ?? (i1 + 1)) - 1)
            for i in rLo...max(rLo, rHi) where i <= rHi {
                let v = min(max(r[i], -ResidualNormalisation.frame), ResidualNormalisation.frame)
                let pt = CGPoint(x: X(s.energy(i)), y: zero - CGFloat(v / ResidualNormalisation.frame) * res.height / 2)
                if i == rLo { p.move(to: pt) } else { p.addLine(to: pt) }
                if ResidualNormalisation.isClipped(r[i]) {     // clipped at the frame: a red dot says so
                    rc.fill(Path(ellipseIn: CGRect(x: pt.x - 1.8, y: pt.y - 1.8, width: 3.6, height: 3.6)), with: .color(.red))
                }
            }
            rc.stroke(p, with: .color(Color.primary.opacity(0.6)), lineWidth: 0.8)
        }
        drawHover(ctx, size, main)
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

#Preview("Spectrum, wide") {
    SpectrumPlotView(model: .fixture, narrow: false).frame(width: 760, height: 300)
}
#Preview("Spectrum, narrow") {
    SpectrumPlotView(model: .fixture, narrow: true).frame(width: 520, height: 300)
}
