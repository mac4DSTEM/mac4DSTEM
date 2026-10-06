import Foundation
import CoreGraphics
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

// The Spectroscopy room's pure geometry (ADR 056): where the map tiles go for the data's own aspect, how a live region is
// hit, moved and resized, and what energy range the spectrum opens on. No SwiftUI, no compute of a number; unit-tested in
// `SpectroscopyRoomGeometryTests`.

// MARK: - The maps grid

/// The ColorMix is large and the other tiles (HAADF, one per element) sit beside it, every tile keeping the data's aspect
/// (the owner's Velox strip is 215 x 926 px, the GMS demo 64 x 48): the arrangement is the one that uses the most area of
/// the room that is given (the geometric mean of the ColorMix's and a tile's areas), so a tall sliver of a scan gives a row of tall tiles and a 4:3 scan the mock's 2 x 3 block.
nonisolated enum MapGridLayout {
    struct Arrangement: Equatable {
        var colorMix: CGRect
        var tiles: [CGRect]
        /// The extent actually used; the rects are relative to its top-left, the view centres it in what it was given.
        var size: CGSize
    }

    static let gap: CGFloat = 8

    /// R4c: a tile is never smaller than this on its long side (the width of landscape data): below it the arrangement
    /// hands over to the stacked layout (the room scrolls) rather than shrink tiles to slivers beside a huge ColorMix.
    static let minimumTileSide: CGFloat = 150

    /// R5: the maps block is a bounded region (`avail`). The side-by-side arrangement whose tiles stay at or above the floor
    /// (the best-scoring one that does, so a window that is a little too small for five columns takes four); when none does,
    /// the stacked arrangement, which is taller than `avail` and so scrolls inside the block (`scrolls`) - never the room.
    static func layout(tileCount n: Int, aspect: CGFloat, in avail: CGSize, maxColorMixHeight: CGFloat) -> (arrangement: Arrangement, stacked: Bool) {
        if let a = arrange(tileCount: n, aspect: aspect, in: avail, minimumSide: minimumTileSide) { return (a, false) }
        return (stacked(tileCount: n, aspect: aspect, width: avail.width, maxColorMixHeight: maxColorMixHeight, columns: stackedColumns(aspect: aspect, width: avail.width, tileCount: n)), true)
    }

    /// As many tile columns as keep a tile's long side at the floor (at least two while there are two tiles to share a row).
    static func stackedColumns(aspect: CGFloat, width: CGFloat, tileCount n: Int) -> Int {
        let a = max(aspect, 0.05)
        var c = max(min(n, 2), 1)
        while c < n {
            let tw = (width - CGFloat(c) * gap) / CGFloat(c + 1)    // the width one more column would leave each tile
            if max(tw, tw / a) < minimumTileSide { break }
            c += 1
        }
        return c
    }

    /// `aspect` = width / height of the scan; `tileCount` = HAADF + elements + proposals (the ColorMix is extra).
    static func arrange(tileCount n: Int, aspect: CGFloat, in avail: CGSize) -> Arrangement {
        arrange(tileCount: n, aspect: aspect, in: avail, minimumSide: 0) ?? fallback(tileCount: n, aspect: aspect, in: avail)
    }

    /// nil when no column count keeps every tile's long side at `minimumSide`.
    private static func arrange(tileCount n: Int, aspect: CGFloat, in avail: CGSize, minimumSide: CGFloat) -> Arrangement? {
        let a = max(aspect, 0.05), g = gap
        guard avail.width > 0, avail.height > 0 else { return Arrangement(colorMix: .zero, tiles: [CGRect](repeating: .zero, count: n), size: .zero) }
        if n == 0 {
            let (w, h) = fit(a, avail.width, avail.height)
            return Arrangement(colorMix: CGRect(x: 0, y: 0, width: w, height: h), tiles: [], size: CGSize(width: w, height: h))
        }
        var best: (score: CGFloat, c: Int, tw: CGFloat, mw: CGFloat, mh: CGFloat)?
        for c in 1...n {
            let r = (n + c - 1) / c
            let twHeight = ((avail.height - CGFloat(r - 1) * g) / CGFloat(r)) * a
            let twWidth = (avail.width - CGFloat(c) * g) / CGFloat(c + 1)     // the ColorMix is at least one tile wide
            let tw = min(twHeight, twWidth)
            guard tw > 1, max(tw, tw / a) >= minimumSide else { continue }
            var mw = min(a * avail.height, avail.width - CGFloat(c) * (tw + g))
            var mh = mw / a
            if mh > avail.height { mh = avail.height; mw = mh * a }
            guard mw >= tw - 0.5 else { continue }
            let th = tw / a
            // Geometric mean of the two sizes: the ColorMix and a tile each count, so a huge ColorMix beside slivers loses.
            let score = (mw * mh).squareRoot() * (tw * th).squareRoot()
            if best == nil || score > best!.score { best = (score, c, tw, mw, mh) }
        }
        guard let b = best else { return nil }
        return place(c: b.c, n: n, tw: b.tw, a: a, mw: b.mw, mh: b.mh, avail: avail)
    }

    /// Too small for the rule: one column, whatever fits.
    private static func fallback(tileCount n: Int, aspect: CGFloat, in avail: CGSize) -> Arrangement {
        let a = max(aspect, 0.05), g = gap
        let tw = max(((avail.height - CGFloat(n - 1) * g) / CGFloat(n)) * a, 1)
        return place(c: 1, n: n, tw: tw, a: a, mw: max(avail.width - tw - g, 1), mh: max((avail.width - tw - g) / a, 1), avail: avail)
    }

    private static func place(c: Int, n: Int, tw: CGFloat, a: CGFloat, mw: CGFloat, mh: CGFloat, avail: CGSize) -> Arrangement {
        let g = gap, th = tw / a, r = (n + c - 1) / c
        let blockW = mw + g + CGFloat(c) * tw + CGFloat(c - 1) * g
        let blockH = max(mh, CGFloat(r) * th + CGFloat(r - 1) * g)
        let x0: CGFloat = 0     // R5: the view centres the block in its frame; an offset here pushed it right of that frame
        let tiles = (0..<n).map { i in
            CGRect(x: x0 + mw + g + CGFloat(i % c) * (tw + g), y: CGFloat(i / c) * (th + g), width: tw, height: th)
        }
        return Arrangement(colorMix: CGRect(x: x0, y: 0, width: mw, height: mh), tiles: tiles, size: CGSize(width: blockW, height: blockH))
    }

    /// Narrow windows: the ColorMix across the full width (at most `maxColorMixHeight` tall), the tiles two across beneath it.
    static func stacked(tileCount n: Int, aspect: CGFloat, width: CGFloat, maxColorMixHeight: CGFloat, columns: Int = 2) -> Arrangement {
        let a = max(aspect, 0.05), g = gap
        let (mw, mh) = fit(a, width, maxColorMixHeight)
        var rects: [CGRect] = []
        let tw = (width - CGFloat(columns - 1) * g) / CGFloat(columns), th = tw / a
        for i in 0..<n {
            rects.append(CGRect(x: CGFloat(i % columns) * (tw + g), y: mh + g + CGFloat(i / columns) * (th + g), width: tw, height: th))
        }
        let rows = (n + columns - 1) / columns
        return Arrangement(colorMix: CGRect(x: (width - mw) / 2, y: 0, width: mw, height: mh), tiles: rects,
                           size: CGSize(width: width, height: mh + (n > 0 ? g + CGFloat(rows) * th + CGFloat(rows - 1) * g : 0)))
    }

    private static func fit(_ a: CGFloat, _ w: CGFloat, _ h: CGFloat) -> (CGFloat, CGFloat) {
        a * h <= w ? (a * h, h) : (w, w / a)
    }
}

// MARK: - The room's two bands

/// R5: the room is two bands that never scroll as a whole - the maps block on top (about 58 % of the height, as in the mock)
/// and the spectrum + quantification row below it, which keeps at least `minimumBottomHeight`. The ColorMix and the tiles
/// are fitted INSIDE the maps block (scaled down to the tile floor); when they cannot fit, the block alone scrolls.
nonisolated enum SpectroscopyRoomPlan {
    struct Plan: Equatable {
        var mapsHeight: CGFloat
        var bottomHeight: CGFloat
        /// What the grid may use inside the maps block (the block less its header and padding).
        var gridAvail: CGSize
        var arrangement: MapGridLayout.Arrangement
        /// The arrangement is taller than `gridAvail`: the maps block scrolls.
        var scrolls: Bool
        var quantWidth: CGFloat
    }

    static let mapsFraction: CGFloat = 0.58
    static let minimumBottomHeight: CGFloat = 220
    static let gridPadding: CGFloat = 8
    static let quantWidth: (min: CGFloat, fraction: CGFloat, max: CGFloat) = (300, 0.36, 420)

    static func make(room: CGSize, headerHeight: CGFloat, tileCount n: Int, aspect: CGFloat) -> Plan {
        let bottom = min(max(room.height * (1 - mapsFraction), minimumBottomHeight), room.height)
        let maps = max(room.height - bottom, 0)
        let avail = CGSize(width: max(room.width - 2 * gridPadding, 0), height: max(maps - headerHeight - 2 * gridPadding, 0))
        let l = MapGridLayout.layout(tileCount: n, aspect: aspect, in: avail, maxColorMixHeight: avail.height * 0.7)
        // Half the width at most, so the spectrum keeps the other half in a small window.
        let quant = min(min(max(room.width * quantWidth.fraction, quantWidth.min), quantWidth.max), room.width / 2)
        return Plan(mapsHeight: maps, bottomHeight: bottom, gridAvail: avail, arrangement: l.arrangement,
                    scrolls: l.arrangement.size.height > avail.height + 0.5, quantWidth: quant)
    }
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
    /// The energy span the listed lines occupy with room to read their names, inside the axis; without a line, the first 20
    /// keV an EDX spectrum is read in (a Velox axis runs to 80 keV). Never narrower than `minimumSpan`.
    static func range(markers: [LineMarker], domain: ClosedRange<Double>, minimumSpan: Double) -> ClosedRange<Double> {
        let energies = markers.filter { $0.kind == .line }.map(\.energy)
        guard let lo = energies.min(), let hi = energies.max() else {
            let top = min(domain.upperBound, max(20, domain.lowerBound + minimumSpan))
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
