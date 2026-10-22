import SwiftUI
import ShellSpectroscopy
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import SpectroCore
import SpectroEDX
#endif

/// How a drawn region looks in the room. The session's region holds the shape and the pixel count only.
struct DrawnRegionStyle: Equatable {
    var tint: Color
    var isVisible = true
    /// A name the person typed in the Regions list; nil: the session's own ("Region 2").
    var name: String?
}

/// A line drawn on the maps: what the Profile tab plots the element maps along. Scan pixels as the regions are (continuous, pixel i covers
/// [i, i+1)); no spectrum is pooled from it.
struct ProfileLine: Identifiable, Equatable {
    var id: Int
    var from: PixelPoint
    var to: PixelPoint
    var name: String
    var tint: Color
    var isVisible = true
}

/// The drawn regions as MacEMUI's `SpectralRegionSet` (the Regions list and the outline overlay read it): the shapes, names, colours and
/// flags are the room's, the set is built from them, and an edit of the set comes back through `apply`.
extension SpectroscopyRoomModel {
    /// The colour of the `n`-th drawn region ever made: the live region's purple first, then the shared palette.
    static func regionTint(issued n: Int) -> Color { n == 0 ? liveRegionColor : RegionPalette.color(at: n - 1).color }

    /// A drawn region's id as the set's UUID, and back: 8 fixed bytes then the id, so the mapping needs no table.
    static func regionUUID(_ id: Int) -> UUID { uuid(id, marker: (0x4D, 0x45, 0x52, 0x47)) }   // "MERG"
    static func lineUUID(_ id: Int) -> UUID { uuid(id, marker: (0x4C, 0x49, 0x4E, 0x45)) }   // "LINE"

    private static func uuid(_ id: Int, marker: (UInt8, UInt8, UInt8, UInt8)) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = marker.0; bytes[1] = marker.1; bytes[2] = marker.2; bytes[3] = marker.3
        for i in 0..<8 { bytes[8 + i] = UInt8((UInt64(bitPattern: Int64(id)) >> UInt64(8 * (7 - i))) & 0xFF) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func regionID(_ uuid: UUID) -> Int? {
        let u = uuid.uuid
        guard u.0 == 0x4D, u.1 == 0x45, u.2 == 0x52, u.3 == 0x47 else { return nil }
        return id(of: u)
    }

    static func lineID(_ uuid: UUID) -> Int? {
        let u = uuid.uuid
        guard u.0 == 0x4C, u.1 == 0x49, u.2 == 0x4E, u.3 == 0x45 else { return nil }
        return id(of: u)
    }

    private static func id(of u: uuid_t) -> Int {
        let b = [u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
        return Int(Int64(bitPattern: b.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }))
    }

    static func geometry(of shape: SpectrumRegionShape) -> RegionGeometry {
        switch shape {
        case .rectangle(let r): .rectangle(x0: Double(r.x0), y0: Double(r.y0), x1: Double(r.x1), y1: Double(r.y1))
        case .ellipse(let r): .ellipse(x0: Double(r.x0), y0: Double(r.y0), x1: Double(r.x1), y1: Double(r.y1))
        case .polygon(let v): .polygon(v.map { RegionPoint(x: $0.x, y: $0.y) })
        }
    }

    /// The colour of drawn region `id`: its style's, the live region's purple for one without a style.
    func regionColor(_ id: Int?) -> Color { id.flatMap { regionStyles[$0]?.tint } ?? Self.liveRegionColor }
    /// The selected region's colour: its outline, its curve and its capsule. The purple while the whole map or a pool is selected.
    var liveColor: Color { regionColor(selectedRegion) }
    /// The name the list and the spectrum's title show for a region.
    func regionName(_ id: Int) -> String { regionStyles[id]?.name ?? regions.first { $0.id == id }?.name ?? "Region" }

    private func setRegion(_ r: RegionSummary) -> SpectralRegion? {
        guard r.isDrawn, let shape = drawnShapes[r.id] else { return nil }
        let style = regionStyles[r.id]
        return SpectralRegion(id: Self.regionUUID(r.id), name: regionName(r.id),
                              color: RegionColor(style?.tint ?? Self.liveRegionColor, resolvedIn: EnvironmentValues()),
                              isVisible: style?.isVisible ?? true, geometry: Self.geometry(of: shape))
    }

    private func setLine(_ l: ProfileLine) -> SpectralRegion {
        SpectralRegion(id: Self.lineUUID(l.id), name: l.name, color: RegionColor(l.tint, resolvedIn: EnvironmentValues()), isVisible: l.isVisible,
                       geometry: .line(RegionPoint(x: l.from.x, y: l.from.y), RegionPoint(x: l.to.x, y: l.to.y)))
    }

    /// Every drawn region, then every line, in the order they were drawn; the selected one is the set's selection.
    var regionSet: SpectralRegionSet {
        SpectralRegionSet(regions: regions.compactMap(setRegion) + lines.map(setLine),
                          selectedID: selectedLine.map(Self.lineUUID) ?? selectedRegion.map(Self.regionUUID))
    }

    /// A line drawn on the ColorMix: named "Line n", in the next palette colour, selected, and the lower block shows its profile.
    func addLine(from: PixelPoint, to: PixelPoint) {
        linesIssued += 1
        let id = (lines.map(\.id).max() ?? -1) + 1
        lines.append(ProfileLine(id: id, from: from, to: to, name: "Line \(linesIssued)", tint: RegionPalette.color(at: regionsIssued + linesIssued - 1).color))
        selectedLine = id
        pane = .profile
    }

    /// The views the lower block offers: the profile only while a line is drawn.
    var availablePanes: [SpectrumPane] { [.spectrum] + (lines.isEmpty ? [] : [.profile]) + (tiles.isEmpty ? [] : [.table]) }
    var shownPane: SpectrumPane { availablePanes.contains(pane) ? pane : .spectrum }

    /// The profile of every mixed element map along the selected line (the first line when none is selected), each in its map's own unit and
    /// in the element's colour; the maps ImagoCore's `LineProfile` samples. Empty without a line or a map.
    /// The maps the Profile and Table tabs read: the ColorMix's elements (all of them when none is mixed), each in its own unit
    /// (the raw counts or percent when the tile has them, else the 0...1 values times their scale; the hover chip's rule).
    var tabMaps: [(tile: MapTile, values: [Float])] {
        let shown = tiles.filter { mixed.contains($0.z) }
        return (shown.isEmpty ? tiles : shown).map { t in
            (t, t.counts.count == t.values.count ? t.counts.map { Float($0) } : t.values.map { $0 * t.scale })
        }
    }

    var profileSeries: [ProfileSeries] {
        guard let line = lines.first(where: { $0.id == selectedLine }) ?? lines.first else { return [] }
        return tabMaps.compactMap { (t, values) in
            guard let p = MapProfile.along(values: values, width: t.width, height: t.height, from: (line.from.x, line.from.y), to: (line.to.x, line.to.y),
                                           pixelSize: scanPixel?.size, unit: scanPixel?.unit) else { return nil }
            let spacing = p.positions.count > 1 ? p.positions[1] - p.positions[0] : 1
            return ProfileSeries(id: PeriodicLayout.symbol(t.z), name: t.lineLabel ?? PeriodicLayout.symbol(t.z),
                                 color: RegionColor(color(t.z), resolvedIn: EnvironmentValues()), values: p.samples, spacing: spacing)
        }
    }
    /// "Profile · Line 1": what the lower block's header says on the Profile tab.
    var profileTitle: String {
        guard let line = lines.first(where: { $0.id == selectedLine }) ?? lines.first else { return "Profile" }
        // the length is the kit's (the last sample's distance), in the scan's unit
        let length = profileSeries.first?.length
        let text = length.map { " \u{00B7} " + $0.formatted(.number.precision(.significantDigits(1...3)).locale(Locale(identifier: "en_US"))) + " " + profileUnit } ?? ""
        return "Profile \u{00B7} \(line.name)" + text
    }
    /// The unit of the profile's distance: the scan's, else pixels.
    /// (The kit calibrates an axis only with a positive size and a unit; the label follows the same rule.)
    var profileUnit: String { scanPixel.flatMap { $0.size > 0 && $0.size.isFinite && !$0.unit.isEmpty ? $0.unit : nil } ?? "px" }

    /// The shown drawn regions other than the selected one: what the map outlines in their own colours beside the live region.
    var otherRegionSet: SpectralRegionSet {
        SpectralRegionSet(regions: (regions.filter { $0.id != selectedRegion }.compactMap(setRegion) + lines.map(setLine)).filter(\.isVisible),
                          selectedID: selectedLine.map(Self.lineUUID))
    }

    /// The spectra of the other shown drawn regions, as the Pins layer draws them (ids offset so they never meet a pin's).
    var regionOverlays: [PinnedRegion] {
        regions.compactMap { r in
            guard r.isDrawn, r.id != selectedRegion, regionStyles[r.id]?.isVisible != false,
                  let spectrum = regionCurves[r.id], let shape = drawnShapes[r.id] else { return nil }
            return PinnedRegion(id: Self.regionOverlayBase + r.id, label: regionName(r.id), tint: regionColor(r.id), shape: shape,
                                pixels: r.pixels, spectrum: spectrum, sourceRegion: nil)
        }
    }
    static let regionOverlayBase = 10_000

    /// An edit of the Regions list: names, colours and flags are kept here; a delete goes to the controller; a new selection
    /// selects the region (the room follows through `selectedRegion`).
    func apply(_ new: SpectralRegionSet) {
        let old = regionSet
        let kept = Set(new.regions.map(\.id))
        for region in old.regions where !kept.contains(region.id) {
            if let id = Self.regionID(region.id) { onRemoveRegion?(id) }
            else if let id = Self.lineID(region.id) { lines.removeAll { $0.id == id }; if selectedLine == id { selectedLine = nil } }
        }
        for region in new.regions {
            if let id = Self.lineID(region.id), let i = lines.firstIndex(where: { $0.id == id }) {
                lines[i].name = region.name
                lines[i].isVisible = region.isVisible
                let current = RegionColor(lines[i].tint, resolvedIn: EnvironmentValues())
                if current != region.color { lines[i].tint = region.color.color }
                continue
            }
            guard let id = Self.regionID(region.id), var style = regionStyles[id] else { continue }
            let named = region.name == regions.first(where: { $0.id == id })?.name ? nil : region.name
            let tint = RegionColor(style.tint, resolvedIn: EnvironmentValues()) == region.color ? style.tint : region.color.color
            if style.name != named || style.tint != tint || style.isVisible != region.isVisible {
                style.name = named; style.tint = tint; style.isVisible = region.isVisible
                regionStyles[id] = style
            }
        }
        if new.selectedID != old.selectedID, let uuid = new.selectedID {
            if let id = Self.lineID(uuid), lines.contains(where: { $0.id == id }) { selectedLine = id; pane = .profile }
            else if let id = Self.regionID(uuid), regions.contains(where: { $0.id == id }) { selectedLine = nil; pane = .spectrum; selectedRegion = id }
        }
    }
}
