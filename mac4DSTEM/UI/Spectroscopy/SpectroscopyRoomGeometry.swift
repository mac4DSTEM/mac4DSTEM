import Foundation
import CoreGraphics
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

// The Spectroscopy room's pure geometry (ADR 056): where the map tiles go for the data's own aspect, how a live region is
// hit, moved and resized, and what energy range the spectrum opens on. No SwiftUI, no compute of a number; unit-tested in
// `SpectroscopyRoomGeometryTests`.

// MARK: - The maps grid

/// R6: the ColorMix is ALWAYS the dominant map (the mock's wide-b): at the leading side, at the data's own aspect and as tall
/// as the maps block allows; HAADF and the element tiles sit in a grid beside it, each at the data's aspect (the
/// owner's Velox strip is 215 x 926 px, the GMS demo 64 x 48). Tiles may be small (Velox's are); when they still do not fit
/// the block at the floor, the TILE grid scrolls inside its own area (vertically) and the ColorMix stays put. Only in a
/// genuinely narrow block - no tile column fits beside a ColorMix of at least half the width - the ColorMix goes on top and
/// the tiles form one horizontally scrolling row beneath it. Never a ColorMix shrunk to tile size, never a tile clipped.
nonisolated enum MapGridLayout {
    enum Kind: Equatable { case sideBySide, stacked }
    enum Scroll: Equatable { case none, vertical, horizontal }

    struct Plan: Equatable {
        var kind: Kind
        /// The ColorMix, in the maps block's coordinates (top-left origin).
        var colorMix: CGRect
        /// The container of the tile grid, in the same coordinates (`.zero` with no tiles). It scrolls along `scroll`.
        var tileArea: CGRect
        /// The tiles, relative to the top-left of the tile grid's content (which scrolls inside `tileArea`).
        var tiles: [CGRect]
        var tileContent: CGSize
        var scroll: Scroll
        /// The extent used; the view puts it at the block's top-left.
        var size: CGSize
    }

    static let gap: CGFloat = 8

    /// A tile's long side (the width of landscape data) is never below this: a Velox tile is small, but not a sliver.
    static let minimumTileSide: CGFloat = 96

    /// The ColorMix is at least this many times a tile's area (it is the dominant map).
    static let dominance: CGFloat = 2.5

    /// The ColorMix keeps at least this share of the block's width when the person drags the divider (side-by-side kind).
    static let minimumMixFraction: CGFloat = 0.2

    /// The ColorMix's width fraction after a drag of the vertical divider by `translation` points: the fraction at drag start
    /// plus the cumulative translation over the block width, kept in `minimumMixFraction...1` (the plan clamps it again to
    /// what fits: a tile column and the data's aspect). Cumulative from the start, so a drag is reversible.
    static func mixFraction(afterDrag translation: CGFloat, available: CGFloat, from start: CGFloat) -> CGFloat {
        guard available > 0 else { return start }
        return min(max(start + translation / available, minimumMixFraction), 1)
    }

    /// `aspect` = width / height of the scan; `tileCount` = HAADF + elements (the ColorMix is extra).
    /// `mixFraction` (nil = the rule above: the ColorMix as large as the block allows) is the share of the block's width the
    /// person gave the ColorMix with the divider. It overrides the rule's width, never below `minimumMixFraction` of the width,
    /// never so wide that a tile column of `minimumTileSide` no longer fits beside it or the ColorMix (at the data's aspect) is
    /// taller than the block. It does not apply to the stacked kind (a narrow block has no divider).
    static func plan(tileCount n: Int, aspect: CGFloat, in avail: CGSize, mixFraction: CGFloat? = nil) -> Plan {
        let a = max(aspect, 0.05), g = gap, floorSide = minimumTileSide
        guard avail.width > 0, avail.height > 0 else {
            return Plan(kind: .sideBySide, colorMix: .zero, tileArea: .zero, tiles: [CGRect](repeating: .zero, count: n), tileContent: .zero, scroll: .none, size: .zero)
        }
        if n == 0 {
            let (w, h) = fit(a, avail.width, avail.height)
            return Plan(kind: .sideBySide, colorMix: CGRect(x: 0, y: 0, width: w, height: h), tileArea: .zero, tiles: [], tileContent: .zero, scroll: .none, size: CGSize(width: w, height: h))
        }
        let minTileW = min(floorSide, floorSide * a)        // the narrowest tile whose long side is at the floor
        // The ColorMix as large as the block allows, leaving one tile column beside it.
        var (mw, mh) = fit(a, avail.width, avail.height)
        if avail.width - g - mw < minTileW {
            mw = avail.width - g - minTileW
            // No tile column beside a ColorMix of at least half the width: the narrow case.
            if mw < avail.width / 2 { return stacked(n: n, a: a, avail: avail) }
            mh = mw / a
        }
        if let f = mixFraction {
            // The widest the ColorMix can be: leaves one tile column and keeps the data's aspect inside the block's height.
            let upper = min(avail.width - g - minTileW, fit(a, avail.width, avail.height).0)
            mw = min(max(f * avail.width, minimumMixFraction * avail.width), upper)
            mh = mw / a
        }
        let gw = avail.width - g - mw, gh = avail.height
        // Tile width at which tile area = mix area / dominance; with a dragged divider the person chose the shares, so the
        // tiles fill the column they were given (drive 2026-10-07: a one-column strip beside a shrunk ColorMix otherwise).
        let cap = mixFraction == nil ? (mw * mh / dominance).squareRoot() * a.squareRoot() : .infinity
        func tileWidth(columns c: Int) -> (w: CGFloat, fitsHeight: Bool) {
            let r = (n + c - 1) / c
            let byWidth = (gw - CGFloat(c - 1) * g) / CGFloat(c)
            let byHeight = ((gh - CGFloat(r - 1) * g) / CGFloat(r)) * a
            let w = min(byWidth, byHeight, cap)
            return (w, max(w, w / a) >= floorSide - 0.01)
        }
        // The columns that fit the block without scrolling, the largest tiles first; else the most columns that keep the
        // floor (the least scrolling).
        var best: (c: Int, w: CGFloat)?
        for c in 1...n {
            let t = tileWidth(columns: c)
            if t.fitsHeight, best == nil || t.w > best!.w + 0.01 { best = (c, t.w) }
        }
        var scroll: Scroll = .none
        if best == nil {
            for c in 1...n {
                let byWidth = min((gw - CGFloat(c - 1) * g) / CGFloat(c), cap)
                if max(byWidth, byWidth / a) >= floorSide - 0.01 { best = (c, byWidth) }
            }
            scroll = .vertical
        }
        let c = best?.c ?? 1
        let tw = max(best?.w ?? min(gw, cap), 1)
        let th = tw / a, r = (n + c - 1) / c
        let tiles = (0..<n).map { i in CGRect(x: CGFloat(i % c) * (tw + g), y: CGFloat(i / c) * (th + g), width: tw, height: th) }
        let content = CGSize(width: CGFloat(c) * tw + CGFloat(c - 1) * g, height: CGFloat(r) * th + CGFloat(r - 1) * g)
        let area = CGRect(x: mw + g, y: 0, width: gw, height: gh)
        return Plan(kind: .sideBySide, colorMix: CGRect(x: 0, y: 0, width: mw, height: mh), tileArea: area, tiles: tiles,
                    tileContent: content, scroll: scroll, size: CGSize(width: avail.width, height: avail.height))
    }

    /// Narrow block: the ColorMix across the top (at the data's aspect, at most 65 % of the height unless the tile row
    /// needs less), the tiles in one row beneath it, which scrolls horizontally.
    private static func stacked(n: Int, a: CGFloat, avail: CGSize) -> Plan {
        let g = gap
        let minRow = min(minimumTileSide, minimumTileSide / a)              // the row's least height: a tile at the floor
        let mixMax = max(min(avail.height * 0.65, avail.height - g - minRow), 1)
        let (mw, mh) = fit(a, avail.width, mixMax)
        let rowH = max(min(avail.height - mh - g, mh / dominance.squareRoot()), 1)   // a tile stays well under the ColorMix
        let tw = rowH * a
        let tiles = (0..<n).map { i in CGRect(x: CGFloat(i) * (tw + g), y: 0, width: tw, height: rowH) }
        let content = CGSize(width: CGFloat(n) * tw + CGFloat(n - 1) * g, height: rowH)
        let scrolls = content.width > avail.width + 0.5
        return Plan(kind: .stacked, colorMix: CGRect(x: 0, y: 0, width: mw, height: mh),
                    tileArea: CGRect(x: 0, y: mh + g, width: avail.width, height: rowH), tiles: tiles, tileContent: content,
                    scroll: scrolls ? .horizontal : .none, size: avail)
    }

    private static func fit(_ a: CGFloat, _ w: CGFloat, _ h: CGFloat) -> (CGFloat, CGFloat) {
        a * h <= w ? (a * h, h) : (w, w / a)
    }
}

// MARK: - The room's two bands

/// R5, spec 2 (D-4, D-7): the room is two bands that never scroll as a whole - the maps block on top (the grid alone, about
/// 58 % of the height until the person drags the spectrum's header row) and the spectrum, full width, below it. The ColorMix and
/// the tiles are fitted INSIDE the maps block; when the tiles cannot fit at the floor, the tile grid alone scrolls (`MapGridLayout`).
nonisolated enum SpectroscopyRoomPlan {
    struct Plan: Equatable {
        var mapsHeight: CGFloat
        var bottomHeight: CGFloat
        /// What the grid may use inside the maps block (the block less its padding).
        var gridAvail: CGSize
        var maps: MapGridLayout.Plan
    }

    /// The maps block's share of the height when the person has not dragged the divider (`SpectroscopyRoomModel.mapsFraction` nil).
    static let mapsFraction: CGFloat = 0.58
    /// The spectrum band's height at the DEFAULT split only; a dragged split goes down to its header row (`headerHeight`).
    static let minimumBottomHeight: CGFloat = 220
    static let gridPadding: CGFloat = 8
    /// A maps block shorter than this is treated as 0: nothing is drawn and the spectrum header sits at the top.
    static let minimumMapsHeight: CGFloat = 48

    /// The maps fraction after the spectrum's header row is dragged by `translation` points (the `StatusBar` shape): the
    /// fraction at drag start plus the cumulative translation over the room's height, kept in 0...1 - 0 hides the maps, the top
    /// of the range leaves the spectrum its header row (`bottomFloor`, so the person can always drag it back).
    static func fraction(afterDrag translation: CGFloat, available: CGFloat, from start: CGFloat, bottomFloor: CGFloat = 0) -> CGFloat {
        guard available > 0 else { return start }
        let top = min(max(1 - bottomFloor / available, 0), 1)
        return min(max(start + translation / available, 0), top)
    }

    /// `headerHeight` is the spectrum's header row (plus its rule): the least the bottom band keeps. `mapsFraction` nil = the
    /// default split (`mapsFraction`, the band keeping `minimumBottomHeight`); a value is the person's, clamped to 0...1 with the
    /// bottom band never below `headerHeight`. `mixFraction` goes to `MapGridLayout.plan`.
    static func make(room: CGSize, headerHeight: CGFloat, tileCount n: Int, aspect: CGFloat,
                     mapsFraction given: CGFloat? = nil, mixFraction: CGFloat? = nil) -> Plan {
        var bottom: CGFloat
        if let f = given {
            bottom = min(max(room.height * (1 - min(max(f, 0), 1)), headerHeight), room.height)
        } else {
            bottom = min(max(room.height * (1 - mapsFraction), minimumBottomHeight), room.height)
        }
        var maps = max(room.height - bottom, 0)
        // A maps block under `minimumMapsHeight` shows nothing but clipped tile headers: it is not drawn at all (drive 2026-10-07).
        if maps < minimumMapsHeight { maps = 0; bottom = room.height }
        let avail = CGSize(width: max(room.width - 2 * gridPadding, 0), height: max(maps - 2 * gridPadding, 0))
        let grid = MapGridLayout.plan(tileCount: n, aspect: aspect, in: avail, mixFraction: mixFraction)
        return Plan(mapsHeight: maps, bottomHeight: bottom, gridAvail: avail, maps: grid)
    }
}

// MARK: - The spectrum plot's floor

nonisolated enum SpectrumPlotFit {
    /// The plot area's least height at which axes, the residual strip and labels are drawn; under it the header row alone remains
    /// (a spectrum dragged to its floor was drawn squashed into about 30 pt, drive 2026-10-07).
    static let minimumHeight: CGFloat = 80
    static func draws(plotHeight: CGFloat) -> Bool { plotHeight >= minimumHeight }
}

// MARK: - The live region

nonisolated enum RegionHandle: Equatable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case vertex(Int)
}

nonisolated enum RegionHit: Equatable, Sendable {
    case handle(RegionHandle), inside, outside
}

/// Hit-testing and editing of the one live region, in continuous pixel-grid coordinates (pixel (i, j) covers [i, i+1) x
/// [j, j+1)). Edits land on whole pixel borders: a region is a set of pixels.
nonisolated enum RegionEditing {
    /// `tolerance` is the handle's reach in grid pixels (the view converts its points, which depend on the tile's size).
    static func hit(_ shape: SpectrumRegionShape, at p: PixelPoint, tolerance: Double) -> RegionHit {
        switch shape {
        case .rectangle(let r), .ellipse(let r):
            let x0 = Double(r.x0), x1 = Double(r.x1), y0 = Double(r.y0), y1 = Double(r.y1)
            let mx = (x0 + x1) / 2, my = (y0 + y1) / 2
            let handles: [(RegionHandle, Double, Double)] = [
                (.topLeft, x0, y0), (.topRight, x1, y0), (.bottomRight, x1, y1), (.bottomLeft, x0, y1),
                (.top, mx, y0), (.bottom, mx, y1), (.left, x0, my), (.right, x1, my)]
            // The nearest handle within reach; corners are listed first so they win a tie with an edge midpoint.
            var best: (RegionHandle, Double)?
            for (h, hx, hy) in handles {
                let d = max(abs(p.x - hx), abs(p.y - hy))
                if d <= tolerance, best == nil || d < best!.1 { best = (h, d) }
            }
            if let b = best { return .handle(b.0) }
            return p.x >= x0 && p.x < x1 && p.y >= y0 && p.y < y1 ? .inside : .outside
        case .polygon(let v):
            var best: (Int, Double)?
            for (i, q) in v.enumerated() {
                let d = max(abs(p.x - q.x), abs(p.y - q.y))
                if d <= tolerance, best == nil || d < best!.1 { best = (i, d) }
            }
            if let b = best { return .handle(.vertex(b.0)) }
            return contains(v, p) ? .inside : .outside
        }
    }

    static func contains(_ v: [PixelPoint], _ p: PixelPoint) -> Bool {
        guard v.count >= 3 else { return false }
        var inside = false
        var j = v.count - 1
        for i in 0..<v.count {
            let a = v[j], b = v[i]
            if (a.y > p.y) != (b.y > p.y), p.x < a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x) { inside.toggle() }
            j = i
        }
        return inside
    }

    /// The shape shifted by whole pixels, kept inside the grid (it stops at the edge, it never changes size).
    static func moved(_ shape: SpectrumRegionShape, dx: Int, dy: Int, grid: (w: Int, h: Int)) -> SpectrumRegionShape {
        func shift(_ r: PixelRect) -> PixelRect {
            let ddx = min(max(dx, -r.x0), grid.w - r.x1), ddy = min(max(dy, -r.y0), grid.h - r.y1)
            return PixelRect(x0: r.x0 + ddx, y0: r.y0 + ddy, x1: r.x1 + ddx, y1: r.y1 + ddy)
        }
        switch shape {
        case .rectangle(let r): return .rectangle(shift(r))
        case .ellipse(let r): return .ellipse(shift(r))
        case .polygon(let v):
            let b = shape.bounds
            let ddx = Double(min(max(dx, -b.x0), grid.w - b.x1)), ddy = Double(min(max(dy, -b.y0), grid.h - b.y1))
            return .polygon(v.map { PixelPoint(x: $0.x + ddx, y: $0.y + ddy) })
        }
    }

    /// The rectangle two points of a drag span: both end pixels included, clamped to the grid; nil off the grid.
    static func drawnRect(from a: PixelPoint, to b: PixelPoint, grid: (w: Int, h: Int)) -> PixelRect? {
        guard grid.w > 0, grid.h > 0 else { return nil }
        func px(_ q: PixelPoint) -> (x: Int, y: Int) { (min(max(Int(q.x), 0), grid.w - 1), min(max(Int(q.y), 0), grid.h - 1)) }
        return PixelRect.spanning(px(a), px(b), nx: grid.w, ny: grid.h)
    }

    /// A rectangle with one handle dragged to `p` (rounded to a pixel border, kept in the grid, at least one pixel across;
    /// dragging an edge past the opposite one flips it).
    static func resized(_ r: PixelRect, handle: RegionHandle, to p: PixelPoint, grid: (w: Int, h: Int)) -> PixelRect {
        var x0 = r.x0, x1 = r.x1, y0 = r.y0, y1 = r.y1
        let px = min(max(Int(p.x.rounded()), 0), grid.w), py = min(max(Int(p.y.rounded()), 0), grid.h)
        switch handle {
        case .topLeft: x0 = px; y0 = py
        case .top: y0 = py
        case .topRight: x1 = px; y0 = py
        case .right: x1 = px
        case .bottomRight: x1 = px; y1 = py
        case .bottom: y1 = py
        case .bottomLeft: x0 = px; y1 = py
        case .left: x0 = px
        case .vertex: break
        }
        var out = PixelRect(x0: min(x0, x1), y0: min(y0, y1), x1: max(x0, x1), y1: max(y0, y1))
        if out.width < 1 { out.x1 = min(out.x0 + 1, grid.w); out.x0 = out.x1 - 1 }
        if out.height < 1 { out.y1 = min(out.y0 + 1, grid.h); out.y0 = out.y1 - 1 }
        return out
    }

    /// A polygon with one vertex dragged to `p` (kept in the grid).
    static func movedVertex(_ v: [PixelPoint], index: Int, to p: PixelPoint, grid: (w: Int, h: Int)) -> [PixelPoint] {
        guard v.indices.contains(index) else { return v }
        var out = v
        out[index] = PixelPoint(x: min(max(p.x, 0), Double(grid.w)), y: min(max(p.y, 0), Double(grid.h)))
        return out
    }

    /// The shape with `handle` dragged to `p`.
    static func edited(_ shape: SpectrumRegionShape, handle: RegionHandle, to p: PixelPoint, grid: (w: Int, h: Int)) -> SpectrumRegionShape {
        switch shape {
        case .rectangle(let r): return .rectangle(resized(r, handle: handle, to: p, grid: grid))
        case .ellipse(let r): return .ellipse(resized(r, handle: handle, to: p, grid: grid))
        case .polygon(let v):
            if case .vertex(let i) = handle { return .polygon(movedVertex(v, index: i, to: p, grid: grid)) }
            return shape
        }
    }
}

// MARK: - The spectrum's opening range

nonisolated enum SpectrumAutoZoom {
    /// The energy below which `fraction` of the counts lie (nil without counts): where an opening view with no line ends.
    static func countsEnergy(data: [Double], energyStart: Double, energyStep: Double, fraction: Double = 0.995) -> Double? {
        let total = data.reduce(0) { $0 + max($1, 0) }
        guard total > 0 else { return nil }
        var run = 0.0
        for (i, d) in data.enumerated() {
            run += max(d, 0)
            if run >= fraction * total { return energyStart + Double(i) * energyStep }
        }
        return energyStart + Double(data.count - 1) * energyStep
    }

    /// The energy span the listed lines occupy with room to read their names, inside the axis;
    /// without a line, up to the energy below which 99.5 % of the counts lie (floor 2 keV, cap 20 keV: the first 20 keV an
    /// EDX spectrum is read in, a Velox axis runs to 80), or those 20 keV when the counts are not known. Never narrower
    /// than `minimumSpan`. A line above the view's ceiling does not stretch it (the person can still zoom out): the ceiling is
    /// the fit range's end when it is known (`fitEnd`), else the counts energy (floor 2 keV), else none.
    static func range(markers: [LineMarker], domain: ClosedRange<Double>, minimumSpan: Double, countsEnergy: Double? = nil, fitEnd: Double? = nil) -> ClosedRange<Double> {
        let ceiling = fitEnd ?? countsEnergy.map { max(2, $0) } ?? .infinity
        let energies = markers.filter { $0.kind == .line }.map(\.energy).filter { $0 <= ceiling }
        guard let lo = energies.min(), let hi = energies.max() else {
            let end = min(20, max(2, countsEnergy ?? 20))
            let top = min(domain.upperBound, max(end, domain.lowerBound + minimumSpan))
            return domain.lowerBound...top
        }
        var a = max(domain.lowerBound, lo - 0.4)
        var b = min(domain.upperBound, max(hi * 1.1, hi + 0.6))
        let need = max(minimumSpan, 1)
        if b - a < need {
            let mid = (a + b) / 2
            a = max(domain.lowerBound, mid - need / 2); b = min(domain.upperBound, a + need)
            a = max(domain.lowerBound, b - need)
        }
        return a...b
    }
}
