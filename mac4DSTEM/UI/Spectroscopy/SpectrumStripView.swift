import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// The spectrum strip (ADR 056): a header (title, the pins), the Canvas plot on a log axis opening on the listed lines'
/// energy span, and the ±3σ residual strip. No caption: the whole map's curve is named at its end. The layers (Show) live in the
/// settings pane, bound to `model.layers`. A region's spectrum is drawn in the live region's colour (the map outline's). The whole map's spectrum (grey) and each pin's (its own colour) are scaled to the
/// region's counts: a comparison of shapes.
///
/// Interaction follows Velox where pure SwiftUI allows: pinch (and the wheel with ⌃, as
/// macOS synthesises it — `ZoomPan.swift` documents why no AppKit scroll monitor is used)
/// zooms the energy axis about the pointer, drag pans, a vertical drag in the y-axis gutter stretches the counts axis, a
/// horizontal drag in the x-axis row (keV) zooms about where it began (right = in), ⌘-drag draws a zoom box,
/// double-click shows the full range (0 to where 99.5 % of the counts lie, at most 20 keV), Home returns to the lines' span.
/// ⌥-drag reads the counts of an energy range (the range marker; ⎋ or a click clears it; its right-click menu starts with "Zoom
/// to" it); the cursor readout names the lines the
/// energy could be, and a right-click lists them (a listed one adds its element).
/// DEVIATION from Velox: a plain mouse wheel does not zoom (needs an AppKit event
/// monitor); open question for the owner.
struct SpectrumStripView: View {
    @Bindable var model: SpectroscopyRoomModel
    /// Spec 2 D-7: the header's empty area is the room's horizontal divider. The room binds this (the translation so far and
    /// whether the drag ended); the strip itself knows nothing of the maps block.
    var onHeaderDrag: ((CGSize, Bool) -> Void)? = nil
    var onHeaderAdjust: ((AccessibilityAdjustmentDirection) -> Void)? = nil
    var headerValue: String = ""

    @State private var dragStart: SpectrumViewport?
    @State private var pinchStart: SpectrumViewport?
    /// The y stretch when a drag that began in the y-axis gutter started (that drag stretches instead of panning).
    @State private var yStart: Double?
    /// The viewport when a drag in the x-axis row began (that drag zooms about its start).
    @State private var zoomStart: SpectrumViewport?
    /// The ⌘-drag's zoom box, keV; nil: none.
    @State private var bandFrom: Double?
    @State private var bandTo: Double?
    /// The pointer over the plot, and where it last was (kept when it leaves, so a right-click menu is built for that energy). A class
    /// the strip never reads: only the hover overlay and the menu observe it, so a pointer move does not redraw the curves.
    @State private var hoverState = SpectrumHoverState()
    /// The per-frame work the curves would repeat (the scaled copies, the sums, the residual), kept while the arrays are the same.
    @State private var drawMemo = SpectrumDrawMemoBox()
    /// The ⌥-drag's energy range, keV (the range marker); nil: none.
    @State private var rangeFrom: Double?
    @State private var rangeTo: Double?
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
        }
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: LayoutPolicy.paneHeaderHeight)
        // The controls sit above this: the empty header is the grab zone (the infobar pattern, `StatusBar`).
        .background {
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { onHeaderDrag?($0.translation, false) }
                    .onEnded { onHeaderDrag?($0.translation, true) })
                .accessibilityElement()
                .focusable()
                .onKeyPress(.upArrow) { onHeaderAdjust?(.decrement); return .handled }
                .onKeyPress(.downArrow) { onHeaderAdjust?(.increment); return .handled }
                .accessibilityLabel("Resize maps and spectrum")
                .accessibilityValue(headerValue)
                .accessibilityAdjustableAction { onHeaderAdjust?($0) }
                .accessibilityIdentifier("spectroscopy.headerDivider")
        }
    }

    private var pinChips: some View {
        HStack(spacing: 6) {
            ForEach(model.pins) { pin in
                Button { model.onUnpin?(pin.id) } label: {
                    HStack(spacing: 3) { Circle().fill(pin.tint).frame(width: PlotMetrics.pinDot, height: PlotMetrics.pinDot); Text(pin.label); Image(systemName: "xmark").font(.caption2) }
                }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                .help("Unpin \(pin.label): \(ResultFormat.counts(Double(pin.pixels))) px")
                // A click removes the pin; VoiceOver would otherwise read the dot, the name and the glyph's "xmark".
                .accessibilityLabel(SpectrumStripLogic.unpinLabel(pin.label))
                // The hint says what happens (Apple); the pixel count is the value.
                .accessibilityHint(SpectrumStripLogic.unpinHint)
                .accessibilityValue("\(ResultFormat.counts(Double(pin.pixels))) pixels")
            }
        }
    }

    // MARK: plot

    private var plot: some View {
        GeometryReader { geo in
            let size = geo.size
            // The marker names' layout is a value of the view, not written back from the draw: what it leaves out is in the help.
            let labelLayout = markerLayout(size)
            accessiblePlot(Canvas { ctx, size in draw(ctx, size, labelLayout) }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .overlay { HoverOverlay(model: model, hover: hoverState, rangeFrom: rangeFrom, rangeTo: rangeTo, bandFrom: bandFrom, bandTo: bandTo).allowsHitTesting(false) })
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { v in drag(v, size, optionHeld: false, commandHeld: false) }
                    .onEnded { _ in endDrag() })
                // ⌥ is what separates the range marker from the pan: this gesture only begins with ⌥ held and then wins.
                .highPriorityGesture(DragGesture(minimumDistance: 2)
                    .onChanged { v in drag(v, size, optionHeld: true, commandHeld: false) }
                    .onEnded { _ in endDrag() }
                    .modifiers(.option))
                // ⌘ draws the zoom box (horizontal only); on release the viewport is its energy span.
                .highPriorityGesture(DragGesture(minimumDistance: 2)
                    .onChanged { v in drag(v, size, optionHeld: false, commandHeld: true) }
                    .onEnded { v in finishBand(v); endDrag() }
                    .modifiers(.command))
                .simultaneousGesture(TapGesture().onEnded { clearRange() })
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
                    case .active(let p): hoverState.point = p; hoverState.lastX = p.x
                    case .ended: hoverState.point = nil
                    }
                }
                .modifier(keyboard)
                .contextMenu { HoverReadingMenu(hover: hoverState) { x in candidateMenu(size, hoverX: x) } }
                .help("Pinch or \u{2303}-wheel: zoom · drag: pan · drag in the counts axis: stretch it\n"
                      + "Drag in the keV row: zoom about where you began (right = in)\n"
                      + "\u{2318}-drag: zoom to a box · \u{2325}-drag: the counts in an energy range (\u{238B} or a click clears it)\n"
                      + "Double-click: the full range · Home: the lines' span\n"
                      + "Right-click: the lines the energy could be (after \u{2325}-drag: Zoom to the range)\n"
                      + "The whole map's spectrum and each pin's are scaled to the region's total counts: a comparison of shapes, not of intensities.\n"
                      + "Residual: (data − model)/√model in σ, clipped at ±3; a tick on the edge marks a clipped channel."
                      + (labelLayout.left.isEmpty ? "" : "\nNames left out where lines crowd: " + labelLayout.left.joined(separator: ", ")))
        }
    }

    /// Focus and the keys: Home and ⎋ as before, and the keyboard's pan and zoom, the same viewport the mouse paths set
    /// (⌘ is left to the menus).
    private var keyboard: some ViewModifier { SpectrumKeys(focused: $focused, perform: perform, reset: resetViewport, escape: escapeKey) }
    private func escapeKey() -> KeyPress.Result { if rangeFrom == nil { return .ignored }; clearRange(); return .handled }

    /// The focus ring and the accessibility element: the plot's label, its changing value and the named view actions.
    private func accessiblePlot<V: View>(_ plot: V) -> some View {
        plot
                // The focus ring (the system one is off, below): a thin inset accent stroke, drawn only while focused, no layout.
                .overlay { if focused { Rectangle().inset(by: 1).stroke(Color.accentColor.opacity(0.7), lineWidth: 1.5).allowsHitTesting(false) } }
                .accessibilityElement()
                .accessibilityLabel(spectrumAccessibility.label)
                .accessibilityValue(spectrumAccessibility.value)
                .accessibilityAction(named: "Zoom in") { perform(.zoomIn) }
                .accessibilityAction(named: "Zoom out") { perform(.zoomOut) }
                .accessibilityAction(named: "Pan left") { perform(.panLeft) }
                .accessibilityAction(named: "Pan right") { perform(.panRight) }
                .accessibilityAction(named: "Show full range") { showFullRange() }
                .accessibilityAction(named: "Reset view") { resetViewport() }
    }

    private func plotWidth(_ size: CGSize) -> CGFloat { size.width - Metrics.left - Metrics.right }

    private func markerLayout(_ size: CGSize) -> MarkerLabelLayout.Result {
        guard SpectrumPlotFit.draws(plotHeight: size.height) else { return MarkerLabelLayout.Result(placed: [], left: []) }
        return SpectrumStripLogic.markerLayout(markers: model.markers, viewport: model.viewport, plotLeft: Metrics.left, plotWidth: plotWidth(size))
    }

    /// The plot's frames: the curves' frame and the residual strip's, nil where nothing is drawn (the floor, or a frame too small).
    static func frames(_ size: CGSize, residual: Bool) -> (main: CGRect, res: CGRect, resH: CGFloat)? {
        guard SpectrumPlotFit.draws(plotHeight: size.height) else { return nil }     // the floor: the header row alone
        let resH = residual ? Metrics.residualHeight : 0
        let main = CGRect(x: Metrics.left, y: Metrics.top,
                          width: size.width - Metrics.left - Metrics.right,
                          height: size.height - Metrics.top - Metrics.axisBand - resH - (residual ? Metrics.gap : 0))
        let res = CGRect(x: main.minX, y: main.maxY + Metrics.gap, width: main.width, height: resH)
        guard main.width > 20, main.height > 20 else { return nil }
        return (main, res, resH)
    }

    /// VoiceOver's description of the plotted data: a stable label, and the changing energy span and axis unit as its value.
    /// Hover readouts remain visual/context-menu feedback and never generate accessibility announcements while the pointer moves.
    private var spectrumAccessibility: (label: String, value: String) {
        SpectrumStripLogic.accessibility(title: model.spectrumTitle, subtitle: model.spectrumSubtitle,
                                         lo: model.viewport.lo, hi: model.viewport.hi,
                                         perPixel: model.layers.perPixel && model.spectrumPixels > 0)
    }

    /// A keyboard or VoiceOver pan/zoom step: the viewport the mouse paths set, and it stays where the person put it (manual).
    private func perform(_ a: SpectrumStripLogic.ViewAction) {
        model.viewport = SpectrumStripLogic.apply(a, to: model.viewport)
        model.viewportIsManual = true
    }

    /// One drag step: the counts axis (it began in the gutter), the pan, or the range marker (⌥), as `SpectrumStripLogic.dragMode` says.
    private func drag(_ v: DragGesture.Value, _ size: CGSize, optionHeld: Bool, commandHeld: Bool) {
        switch SpectrumInteraction.dragMode(optionHeld: optionHeld, commandHeld: commandHeld, startX: v.startLocation.x, startY: v.startLocation.y,
                                            plotLeft: Metrics.left, gutterTop: size.height - Metrics.axisBand) {
        case .stretchY:
            let start = yStart ?? model.viewport.yScale
            yStart = start
            model.viewport.yScale = SpectrumViewport.yScale(from: start, dragDY: Double(v.translation.height))
        case .pan:
            let start = dragStart ?? model.viewport
            dragStart = start
            var vp = start
            vp.pan(byFraction: -Double(v.translation.width / max(plotWidth(size), 1)))
            model.viewport = vp; model.viewportIsManual = true
        case .zoomX:
            let start = zoomStart ?? model.viewport
            zoomStart = start
            var vp = start
            vp.zoom(factor: SpectrumInteraction.zoomFactor(dx: Double(v.translation.width)),
                    anchor: SpectrumStripLogic.anchor(startX: v.startLocation.x, plotLeft: Metrics.left, plotWidth: plotWidth(size)))
            model.viewport = vp; model.viewportIsManual = true
        case .band:
            focused = true
            let r = SpectrumStripLogic.rangeEnergies(startX: v.startLocation.x, endX: v.location.x, plotLeft: Metrics.left, plotWidth: plotWidth(size), viewport: model.viewport)
            bandFrom = r.from; bandTo = r.to
        case .range:
            focused = true
            let r = SpectrumStripLogic.rangeEnergies(startX: v.startLocation.x, endX: v.location.x, plotLeft: Metrics.left, plotWidth: plotWidth(size), viewport: model.viewport)
            rangeFrom = r.from; rangeTo = r.to
        }
    }

    private func endDrag() { dragStart = nil; yStart = nil; zoomStart = nil; bandFrom = nil; bandTo = nil }

    /// The ⌘-drag ended: the viewport is the box's energy span (at least 10 channels); a box under 4 points is a click, not a zoom.
    private func finishBand(_ v: DragGesture.Value) {
        guard abs(v.translation.width) >= 4, let a = bandFrom, let b = bandTo else { return }
        applyWindow(from: a, to: b)
    }

    /// Show the energy window of `a`...`b` (widened to 10 channels, kept inside the domain); the counts axis stays as it is.
    private func applyWindow(from a: Double, to b: Double) {
        guard let w = SpectrumInteraction.bandWindow(from: a, to: b, domain: model.series.domain, channel: model.series.energyStep) else { return }
        model.viewportIsManual = true
        model.viewport.lo = w.lowerBound; model.viewport.hi = w.upperBound
    }

    private func clearRange() { rangeFrom = nil; rangeTo = nil }

    /// The right-click menu at the cursor: every tabulated line the energy could be (it adds the element), the sums and escapes as
    /// information only.
    @ViewBuilder private func candidateMenu(_ size: CGSize, hoverX: CGFloat?) -> some View {
        let f = SpectrumStripLogic.anchor(startX: hoverX ?? Metrics.left, plotLeft: Metrics.left, plotWidth: plotWidth(size))
        let e = model.viewport.energy(atFraction: f)
        let found = SpectrumHover.candidates(at: e, resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV, listed: model.elements.activeZ)
        if let a = rangeFrom, let b = rangeTo, a != b {
            Button(SpectrumInteraction.zoomToRangeTitle(from: a, to: b)) { applyWindow(from: a, to: b) }
            Divider()
        }
        if found.isEmpty {
            Button("No tabulated line within \u{00B1} 1 FWHM") {}.disabled(true)
        } else {
            ForEach(found, id: \.label) { c in
                Button("\(c.label) \u{00B7} \(SpectrumReadout.energy(c.energy)) keV") { model.onPickElement?(c.z) }
                    .disabled(c.kind != .line)
            }
        }
    }

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

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ layout: MarkerLabelLayout.Result) {
        var L = model.layers
        let s = model.series
        if !s.hasModel { L.residual = false }     // no fit: no model curve, no residual strip
        guard let fr = Self.frames(size, residual: L.residual) else { return }
        let main = fr.main, res = fr.res
        let vp = model.viewport
        guard let ch = SpectrumStripLogic.channels(series: s, viewport: vp) else { return }
        let i0 = ch.lowerBound, i1 = ch.upperBound

        // Counts per pixel (Show › Per pixel): the drawn curves and the axis divide by the pooled pixel count; the residual,
        // the fit and every export stay in counts. One raw count is `unit` in the plotted unit (the axis floor).
        let div = SpectrumScale.divisor(perPixel: L.perPixel, pixels: model.spectrumPixels)
        let unit = 1 / div
        // The scaled copies are kept while the arrays and the divisor are the same (a frame is drawn on every drag step).
        let memo = drawMemo
        func scaled(_ key: SpectrumDrawMemo.Key, _ a: [Double]) -> [Double] {
            div == 1 ? a : memo.memo.scaled(key, a, a: div) { SpectrumScale.perPixel(a, pixels: model.spectrumPixels) }
        }
        let data = scaled(.data, s.data), modelCurve = s.hasModel ? scaled(.model, s.model) : [], backgroundCurve = s.hasBackground ? scaled(.background, s.background) : []
        let overlay = s.overlay.map { scaled(.overlay, $0) }
        let role = SpectrumInteraction.curveRole(isLive: model.isLive, selectedRegion: model.selectedRegion)

        // y range over what is visible
        var yMax = unit, yMinPos = Double.infinity
        for i in i0...i1 {
            yMax = max(yMax, data[i]); if s.hasModel { yMax = max(yMax, modelCurve[i]) }
            if data[i] > 0 { yMinPos = min(yMinPos, data[i]) }
        }
        let logRange = SpectrumYRange.log(minPositive: yMinPos, maximum: yMax, unit: unit)
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
            let yStep = AxisTicks.niceStep(lo: 0, hi: yTop, target: 5)
            for v in AxisTicks.linear(lo: 0, hi: yTop, target: 5) {
                let y = Y(v)
                hline(y, main.minX - PlotMetrics.tick, main.minX, axisLine)
                ctx.draw(Text(L.perPixel && div != 1 ? AxisTicks.label(v, step: yStep) : Self.format(v)).font(axisFont).foregroundStyle(axisInk),
                         at: CGPoint(x: main.minX - 16, y: y))
            }
        }
        // y-axis title
        var vctx = ctx
        vctx.translateBy(x: 8, y: main.midY); vctx.rotate(by: .degrees(-90))
        vctx.draw(Text(SpectrumReadout.yAxisTitle(channelEV: Int((s.energyStep * 1000).rounded()), perPixel: div != 1)).font(axisFont).foregroundStyle(axisInk), at: .zero)

        // curves, clipped to the frame
        var clip = ctx; clip.clip(to: Path(main))
        func curve(_ ys: [Double], _ color: Color, width: CGFloat, dash: [CGFloat] = [], within: Range<Int>? = nil) {
            var p = Path()
            // The model and the background exist only where the fit ran (R3): outside it nothing is drawn.
            let lo = max(i0, within?.lowerBound ?? i0), hi = min(i1, (within?.upperBound ?? (i1 + 1)) - 1)
            guard hi > lo else { return }
            // About one point per pixel column, keeping each column's first, lowest, highest and last channel: no peak is lost.
            var first = true
            for i in SpectrumDecimation.channels(ys, range: lo...hi, frame: i0...i1, columns: max(1, Int(main.width))) {
                let pt = CGPoint(x: X(s.energy(i)), y: Y(ys[i]))
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
            }
            clip.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineJoin: .round, dash: dash))
        }
        // The line and background windows of the net maps: faint bands under the curves, no labels.
        if L.windows {
            for b in model.windowBands {
                let x0 = X(b.range.lowerBound), x1 = X(b.range.upperBound)
                let tint = b.kind == .signal ? (b.elementZ.map { model.color($0) } ?? Color.gray) : Color.gray
                clip.fill(Path(CGRect(x: x0, y: main.minY, width: max(x1 - x0, 1), height: main.height)),
                          with: .color(tint.opacity(WindowBandStyle.opacity(b.kind))))
            }
        }
        let total = memo.memo.sum(.total, s.data)
        if s.hasOverlay, let o = overlay {
            curve(o, Color.secondary.opacity(0.7), width: 1)
            // named directly at its right end (the last visible channel), above the curve; never in a caption
            let k = min(i1, o.count - 1)
            let end = CGPoint(x: min(X(s.energy(k)), main.maxX) - 4, y: min(max(Y(o[k]) - 8, main.minY + 8), main.maxY - 8))
            ctx.draw(Text("whole map").font(axisFont).foregroundStyle(axisInk), at: end, anchor: .trailing)
        }
        for pin in model.pins where L.pins && pin.spectrum.count == s.count {
            let t = memo.memo.sum(.pinTotal(pin.id), pin.spectrum)
            if t > 0, total > 0 {
                let k = total / t
                curve(memo.memo.scaled(.pin(pin.id), pin.spectrum, a: k, b: div) { pin.spectrum.map { $0 * k / div } },
                      pin.tint.opacity(SpectrumLayers.pinOpacity), width: SpectrumInteraction.Width.pin)
            }
        }
        if L.spectrum { curve(data, SpectrumInteraction.curveColor(role), width: SpectrumInteraction.Width.spectrum) }
        if L.model, s.hasModel { curve(modelCurve, .blue, width: SpectrumInteraction.Width.model, within: s.fitChannels) }
        if L.background, s.hasBackground { curve(backgroundCurve, .orange.opacity(0.9), width: SpectrumInteraction.Width.background, dash: [2, 3], within: s.fitChannels) }
        // The range marker's band (selection: the accent colour).
        if let a = rangeFrom, let b = rangeTo {
            let x0 = X(min(a, b)), x1 = X(max(a, b))
            clip.fill(Path(CGRect(x: x0, y: main.minY, width: max(x1 - x0, 1), height: main.height)), with: .color(Color.accentColor.opacity(0.15)))
        }
        // The zoom box (⌘-drag): the accent colour, edged, so it reads as a box to zoom into.
        if let a = bandFrom, let b = bandTo {
            let x0 = X(min(a, b)), x1 = X(max(a, b))
            let box = CGRect(x: x0, y: main.minY, width: max(x1 - x0, 1), height: main.height)
            clip.fill(Path(box), with: .color(Color.accentColor.opacity(0.18)))
            clip.stroke(Path(box), with: .color(Color.accentColor.opacity(0.8)), lineWidth: 1)
        }

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
        for m in visible {
            let x = X(m.energy)
            let color = Self.markerColor(m, model: model)
            let t = Text(m.label).font(.system(size: m.kind == .edge ? 10 : SpectrumInteraction.Width.markerLabel, weight: SpectrumStripLogic.isHighlighted(m, highlightedZ: highlightedZ) ? .bold : (m.kind == .line ? .semibold : .regular))).foregroundStyle(color)
            if m.kind == .edge {   // the edge label sits low, by the curve, so it never collides with the line names
                ctx.draw(t, at: CGPoint(x: x + 2, y: main.maxY - 40), anchor: .leading)
            } else if let pl = layout.placed.first(where: { $0.label == m.label }) {
                let y = main.minY + 8 + CGFloat(pl.row) * 12
                ctx.draw(t, at: CGPoint(x: pl.leading ? x + 2 : x - 2, y: y), anchor: pl.leading ? .leading : .trailing)
            }
        }

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
            let r = memo.memo.residual(data: s.data, model: s.model) { s.residual }
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
    }

    /// The edge is grey, a line its element's colour.
    private static func markerColor(_ m: LineMarker, model: SpectroscopyRoomModel) -> Color {
        switch m.kind {
        case .line: return model.color(m.elementZ ?? 0)
        case .edge: return .gray
        }
    }

    /// The cursor guide and readout, in a canvas of their own over the curves: the pointer's moves redraw this and not them.
    private struct HoverOverlay: View {
        var model: SpectroscopyRoomModel
        var hover: SpectrumHoverState
        var rangeFrom: Double?, rangeTo: Double?, bandFrom: Double?, bandTo: Double?

        var body: some View {
            let pointer = hover.point
            Canvas { ctx, size in draw(ctx, size, pointer: pointer) }
        }

        private func draw(_ ctx: GraphicsContext, _ size: CGSize, pointer: CGPoint?) {
            var L = model.layers
            if !model.series.hasModel { L.residual = false }
            guard let main = SpectrumStripView.frames(size, residual: L.residual)?.main,
                  SpectrumStripLogic.channels(series: model.series, viewport: model.viewport) != nil else { return }
            let divisor = SpectrumScale.divisor(perPixel: L.perPixel, pixels: model.spectrumPixels)
            let role = SpectrumInteraction.curveRole(isLive: model.isLive, selectedRegion: model.selectedRegion)
            drawHover(ctx, main, pointer: pointer, divisor: divisor, role: role)
        }

        /// Cursor guide and readout (Velox shows the same): energy, counts, the lines it could be. While a range is marked the
        /// readout is the range's: its energies, counts and share of the region.
        private func drawHover(_ ctx: GraphicsContext, _ main: CGRect, pointer: CGPoint?, divisor: Double, role: SpectrumInteraction.CurveRole) {
            let vp = model.viewport
            func x(of e: Double) -> CGFloat { main.minX + CGFloat(vp.fraction(of: e)) * main.width }
            var parts: [String] = []
            var anchor: CGFloat?
            if let h = pointer, main.contains(CGPoint(x: h.x, y: main.midY)) {
                let f = Double((h.x - main.minX) / main.width)
                if let smp = SpectrumHover.sample(series: model.series, viewport: vp, fraction: f, markers: model.markers,
                                                  resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV, listed: model.elements.activeZ) {
                    var p = Path(); p.move(to: CGPoint(x: h.x, y: main.minY)); p.addLine(to: CGPoint(x: h.x, y: main.maxY))
                    ctx.stroke(p, with: .color(Color.primary.opacity(0.35)), lineWidth: 0.6)
                    parts = SpectrumReadout.parts(smp, divisor: divisor)
                    anchor = h.x
                }
            }
            if let a = rangeFrom, let b = rangeTo {
                let r = SpectrumHover.range(series: model.series, from: a, to: b)
                parts = [SpectrumReadout.rangeText(from: a, to: b, counts: r.counts, fraction: r.fraction, divisor: divisor)]
                anchor = min(max(x(of: max(a, b)), main.minX), main.maxX)
            }
            if let a = bandFrom, let b = bandTo {     // the zoom box's own energies, while it is drawn
                parts = [SpectrumReadout.energy(min(a, b), decimals: 2) + "\u{2013}" + SpectrumReadout.energy(max(a, b), decimals: 2) + " keV"]
                anchor = min(max(x(of: max(a, b)), main.minX), main.maxX)
            }
            guard let ax = anchor, !parts.isEmpty else { return }
            let font = Font.system(size: 10).monospacedDigit()
            // The box grows to the text (at most `SpectrumReadout.widthCap`; trailing names go, with "…").
            let text = SpectrumReadout.fit(parts) { ctx.resolve(Text($0).font(font)).measure(in: CGSize(width: 2000, height: 20)).width + 8 }
            let width = min(ctx.resolve(Text(text).font(font)).measure(in: CGSize(width: 2000, height: 20)).width + 8, SpectrumReadout.widthCap)
            let left = ax < main.midX ? ax + 6 : ax - 6 - width
            let box = CGRect(x: min(max(left, main.minX), max(main.maxX - width, main.minX)), y: main.minY + 18, width: width, height: 16)
            ctx.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(Color(white: 0.5).opacity(0.18)))
            // The energy leads the text; with a region shown it follows the region curve's colour.
            let head = text.components(separatedBy: SpectrumReadout.separator).first ?? text
            let readout = Text("\(Text(head).foregroundStyle(SpectrumInteraction.readoutEnergyColor(role)))\(Text(String(text.dropFirst(head.count))).foregroundStyle(Color.primary))")
            ctx.draw(readout.font(font), at: CGPoint(x: box.minX + 4, y: box.midY), anchor: .leading)
        }
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

/// The plot's focus and key handling (split out of the plot's long modifier chain, which the type checker would not take).
private struct SpectrumKeys: ViewModifier {
    var focused: FocusState<Bool>.Binding
    var perform: (SpectrumStripLogic.ViewAction) -> Void
    var reset: () -> Void
    var escape: () -> KeyPress.Result
    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused(focused)
            .onKeyPress(.home) { reset(); return .handled }
            .onKeyPress(.escape) { escape() }
            .onKeyPress(.leftArrow, phases: [.down, .repeat]) { _ in perform(.panLeft); return .handled }
            .onKeyPress(.rightArrow, phases: [.down, .repeat]) { _ in perform(.panRight); return .handled }
            .onKeyPress(characters: CharacterSet(charactersIn: "+="), phases: [.down, .repeat]) { press in
                if !SpectrumStripLogic.zoomKeyAccepts(press.modifiers) { return .ignored }
                perform(.zoomIn); return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "-"), phases: [.down, .repeat]) { press in
                if !SpectrumStripLogic.zoomKeyAccepts(press.modifiers) { return .ignored }
                perform(.zoomOut); return .handled
            }
    }
}

/// What a drag on the plot does, by where it began and whether ⌥ is held (the gesture code asks this; nothing else decides).
nonisolated enum SpectrumDragMode: Equatable, Sendable { case pan, stretchY, range, zoomX, band }

/// The strip's pure decisions (spec 2 item 7); the drawing only applies them.
nonisolated enum SpectrumStripLogic {
    /// A drag that began in the counts gutter stretches the axis (⌥ or not); in the frame ⌥ selects an energy range and a plain
    /// drag pans.
    static func dragMode(optionHeld: Bool, startX: CGFloat, plotLeft: CGFloat) -> SpectrumDragMode {
        if startX < plotLeft { return .stretchY }
        return optionHeld ? .range : .pan
    }
    /// The range's two energies from a drag's x positions (the plot view's own space), each clamped to the frame.
    static func rangeEnergies(startX: CGFloat, endX: CGFloat, plotLeft: CGFloat, plotWidth: CGFloat, viewport: SpectrumViewport) -> (from: Double, to: Double) {
        (viewport.energy(atFraction: anchor(startX: startX, plotLeft: plotLeft, plotWidth: plotWidth)),
         viewport.energy(atFraction: anchor(startX: endX, plotLeft: plotLeft, plotWidth: plotWidth)))
    }
    /// What the keyboard (arrows, + and -) and VoiceOver's named actions do to the energy window.
    enum ViewAction: Equatable, Sendable { case zoomIn, zoomOut, panLeft, panRight }
    /// One step zooms by this factor about the window's centre, or pans by this fraction of the visible width.
    static let zoomStep = 1.5, panStep = 0.2
    static func apply(_ a: ViewAction, to viewport: SpectrumViewport) -> SpectrumViewport {
        var vp = viewport
        switch a {
        case .zoomIn: vp.zoom(factor: zoomStep, anchor: 0.5)
        case .zoomOut: vp.zoom(factor: 1 / zoomStep, anchor: 0.5)
        case .panLeft: vp.pan(byFraction: -panStep)
        case .panRight: vp.pan(byFraction: panStep)
        }
        return vp
    }
    /// The plot's accessibility label (stable while the view moves) and value (the energy span and the counts unit).
    static func accessibility(title: String, subtitle: String, lo: Double, hi: Double, perPixel: Bool, locale: Locale = .current) -> (label: String, value: String) {
        let label = subtitle.isEmpty ? title : "\(title), \(subtitle)"
        let unit = perPixel ? "counts per pixel" : "counts"
        return (label, "Energy from \(SpectrumReadout.energy(lo, locale: locale)) to \(SpectrumReadout.energy(hi, locale: locale)) keV. Y axis in \(unit).")
    }
    /// The first and last channel the viewport shows (the curves' index range); nil when under two channels are visible.
    static func channels(series s: SpectrumSeries, viewport vp: SpectrumViewport) -> ClosedRange<Int>? {
        let i0 = max(0, Int(((vp.lo - s.energyStart) / s.energyStep).rounded(.down)))
        let i1 = min(s.count - 1, Int(((vp.hi - s.energyStart) / s.energyStep).rounded(.up)))
        return i1 > i0 ? i0...i1 : nil
    }
    /// Where the line-marker names go for this viewport and plot width (the plot frame starts at `plotLeft`): the names of the
    /// markers in view, edges apart (the edge label sits low, by the curve), staggered by `MarkerLabelLayout`. Nothing under a 20 pt frame.
    static func markerLayout(markers: [LineMarker], viewport vp: SpectrumViewport, plotLeft: CGFloat, plotWidth: CGFloat) -> MarkerLabelLayout.Result {
        guard plotWidth > 20 else { return MarkerLabelLayout.Result(placed: [], left: []) }
        let visible = MarkerLabelLayout.inView(markers, lo: vp.lo, hi: vp.hi).filter { $0.kind != .edge }
        return MarkerLabelLayout.place(visible.map { ($0.label, plotLeft + CGFloat(vp.fraction(of: $0.energy)) * plotWidth, $0.priority) },
                                       minX: plotLeft, maxX: plotLeft + plotWidth)
    }
    /// Whether a +/=/- press zooms: not with ⌘, ⌃ or ⌥ held (those belong to the window's zoom and to the system; the key then
    /// passes on); ⇧ is allowed because some layouts type "+" with it.
    static func zoomKeyAccepts(_ modifiers: EventModifiers) -> Bool {
        modifiers.intersection([.command, .control, .option]).isEmpty
    }
    /// A pin chip's button removes the pin; its spoken name says so.
    static func unpinLabel(_ pinLabel: String) -> String { "Unpin \(pinLabel)" }
    static let unpinHint = "Removes the pin"
    /// A marker of the highlighted element (hovered or clicked tile or periodic-table cell).
    static func isHighlighted(_ m: LineMarker, highlightedZ: Int?) -> Bool { highlightedZ != nil && m.elementZ == highlightedZ }
    static func lineWidth(_ m: LineMarker, highlightedZ: Int?) -> CGFloat { isHighlighted(m, highlightedZ: highlightedZ) ? SpectrumInteraction.Width.markerHighlighted : SpectrumInteraction.Width.marker }
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

/// Which channels of a curve to stroke when the spectrum has far more channels than the plot has pixel columns: per column the
/// first, the lowest, the highest and the last, in channel order, so a one-channel peak or dip is never dropped and the line
/// looks as the full one does.
nonisolated enum SpectrumDecimation {
    /// `range` is the curve's channels, `frame` the channels the plot shows (they set the columns), `columns` the plot's width in
    /// points. With at most twice as many channels as columns every channel of `range` is returned.
    static func channels(_ ys: [Double], range: ClosedRange<Int>, frame: ClosedRange<Int>, columns: Int) -> [Int] {
        guard columns > 0, frame.upperBound - frame.lowerBound > 2 * columns else { return Array(range) }
        let span = frame.upperBound - frame.lowerBound + 1
        func column(_ i: Int) -> Int { (i - frame.lowerBound) * columns / span }
        var out: [Int] = []
        out.reserveCapacity(min(range.count, 4 * columns + 4))
        var i = range.lowerBound
        while i <= range.upperBound {
            let c = column(i)
            let first = i
            var last = i, lo = i, hi = i
            var j = i + 1
            while j <= range.upperBound, column(j) == c {
                if ys[j] < ys[lo] { lo = j }
                if ys[j] > ys[hi] { hi = j }
                last = j; j += 1
            }
            var prev = Int.min
            for k in [first, min(lo, hi), max(lo, hi), last] where k != prev { out.append(k); prev = k }
            i = j
        }
        return out
    }
}

/// What a frame of the strip would otherwise compute again: the per-pixel copies of the curves, the totals, the residual.
/// Each is kept while its source arrays (and the numbers it was made with) are the same; Swift compares two arrays of one
/// buffer in constant time, so the unchanged case costs next to nothing.
nonisolated struct SpectrumDrawMemo {
    enum Key: Hashable, Sendable { case data, model, background, overlay, total, residual, pin(Int), pinTotal(Int) }
    private struct Entry { var source: [Double]; var other: [Double]; var a: Double; var b: Double; var value: [Double] }
    private var entries: [Key: Entry] = [:]
    private var sums: [Key: (source: [Double], value: Double)] = [:]
    /// How many times a value was computed (not served from the memo).
    private(set) var computed = 0

    mutating func scaled(_ key: Key, _ source: [Double], other: [Double] = [], a: Double = 1, b: Double = 1, compute: () -> [Double]) -> [Double] {
        if let e = entries[key], e.a == a, e.b == b, e.source == source, e.other == other { return e.value }
        let v = compute()
        computed += 1
        entries[key] = Entry(source: source, other: other, a: a, b: b, value: v)
        return v
    }
    mutating func sum(_ key: Key, _ source: [Double]) -> Double {
        if let e = sums[key], e.source == source { return e.value }
        let v = source.reduce(0, +)
        computed += 1
        sums[key] = (source, v)
        return v
    }
    mutating func residual(data: [Double], model: [Double], compute: () -> [Double]) -> [Double] {
        scaled(.residual, data, other: model, compute: compute)
    }
}
@MainActor final class SpectrumDrawMemoBox { var memo = SpectrumDrawMemo() }

/// The pointer over the plot. Only the hover overlay and the right-click menu read it.
@MainActor @Observable final class SpectrumHoverState {
    var point: CGPoint?
    var lastX: CGFloat?
}

/// The right-click menu's content, built from the pointer's last x; reading it here (not in the strip) keeps the pointer's moves
/// from re-evaluating the strip.
private struct HoverReadingMenu<Content: View>: View {
    var hover: SpectrumHoverState
    @ViewBuilder var content: (CGFloat?) -> Content
    var body: some View { content(hover.lastX) }
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
