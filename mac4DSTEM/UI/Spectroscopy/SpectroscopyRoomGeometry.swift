import Foundation
import CoreGraphics
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import SpectroCore
import SpectroEDX
#endif

// The Spectroscopy room's pure geometry (ADR 056): how a live region is moved and resized (hit-testing and the tile layout are MacEMUI's
// since the corrected room, 2026-10-22), and what energy range the spectrum opens on. No SwiftUI, no compute of a number; unit-tested in
// `SpectroscopyRoomGeometryTests`.

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

/// Editing of the one live region (move, resize, draw), in continuous pixel-grid coordinates (pixel (i, j) covers [i, i+1) x
/// [j, j+1)). Edits land on whole pixel borders: a region is a set of pixels.
nonisolated enum RegionEditing {
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

// MARK: - The live region typed

/// The live region's extent as numbers (x, y, width, height in scan pixels), and a typed value as an edit. A rectangle or an
/// ellipse is typed; a polygon is read only (its corners are the drag's). Every edit goes through `RegionEditing`, so a typed
/// value obeys the drag's rules: whole pixel borders, kept in the grid, at least one pixel across, a move stops at the edge.
nonisolated enum RegionExtent {
    enum Field: CaseIterable, Sendable { case x, y, width, height }

    /// The extent shown: the shape's bounding rectangle.
    static func values(_ shape: SpectrumRegionShape) -> (x: Int, y: Int, width: Int, height: Int) {
        let b = shape.bounds
        return (b.x0, b.y0, b.width, b.height)
    }

    static func value(_ shape: SpectrumRegionShape, _ field: Field) -> Int {
        let v = values(shape)
        switch field { case .x: return v.x; case .y: return v.y; case .width: return v.width; case .height: return v.height }
    }

    /// Only a rectangle and an ellipse have a typed extent.
    static func isEditable(_ shape: SpectrumRegionShape) -> Bool {
        switch shape { case .rectangle, .ellipse: true; case .polygon: false }
    }

    /// The shape after `field` is typed as `value`; nil when the field is not editable or the typed value changes nothing.
    /// x and y move the region (its size stays; it stops at the grid's edge), width and height move the right and bottom edges.
    static func edited(_ shape: SpectrumRegionShape, _ field: Field, to value: Int, grid: (w: Int, h: Int)) -> SpectrumRegionShape? {
        guard isEditable(shape), grid.w > 0, grid.h > 0 else { return nil }
        let b = shape.bounds
        let out: SpectrumRegionShape
        switch field {
        case .x: out = RegionEditing.moved(shape, dx: value - b.x0, dy: 0, grid: grid)
        case .y: out = RegionEditing.moved(shape, dx: 0, dy: value - b.y0, grid: grid)
        case .width:
            out = RegionEditing.edited(shape, handle: .right, to: PixelPoint(x: Double(b.x0 + max(value, 1)), y: 0), grid: grid)
        case .height:
            out = RegionEditing.edited(shape, handle: .bottom, to: PixelPoint(x: 0, y: Double(b.y0 + max(value, 1))), grid: grid)
        }
        return out == shape ? nil : out
    }
}

// MARK: - The drawn outline of a region

/// A region's outline on a map as one path, in a space of `cellWidth` x `cellHeight` per grid pixel (y down, as the map is
/// drawn). The live region and the pins on the exported maps and figures
/// (`FigureRendering`) all stroke this one path.
nonisolated enum RegionOutline {
    static func path(_ shape: SpectrumRegionShape, cellWidth cw: CGFloat, cellHeight ch: CGFloat) -> CGPath {
        func rect(_ r: PixelRect) -> CGRect {
            CGRect(x: CGFloat(r.x0) * cw, y: CGFloat(r.y0) * ch, width: CGFloat(r.width) * cw, height: CGFloat(r.height) * ch)
        }
        switch shape {
        case .rectangle(let r): return CGPath(rect: rect(r), transform: nil)
        case .ellipse(let r): return CGPath(ellipseIn: rect(r), transform: nil)
        case .polygon(let v):
            let path = CGMutablePath()
            for (i, q) in v.enumerated() {
                let p = CGPoint(x: CGFloat(q.x) * cw, y: CGFloat(q.y) * ch)
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            path.closeSubpath()
            return path
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
