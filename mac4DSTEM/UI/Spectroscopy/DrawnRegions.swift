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

/// The drawn regions as MacEMUI's `SpectralRegionSet` (the Regions list and the outline overlay read it): the shapes, names, colours and
/// flags are the room's, the set is built from them, and an edit of the set comes back through `apply`.
extension SpectroscopyRoomModel {
    /// The colour of the `n`-th drawn region ever made: the live region's purple first, then the shared palette.
    static func regionTint(issued n: Int) -> Color { n == 0 ? liveRegionColor : RegionPalette.color(at: n - 1).color }

    /// A drawn region's id as the set's UUID, and back: 8 fixed bytes then the id, so the mapping needs no table.
    static func regionUUID(_ id: Int) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 0x4D; bytes[1] = 0x45; bytes[2] = 0x52; bytes[3] = 0x47   // "MERG": marks the mapping
        for i in 0..<8 { bytes[8 + i] = UInt8((UInt64(bitPattern: Int64(id)) >> UInt64(8 * (7 - i))) & 0xFF) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func regionID(_ uuid: UUID) -> Int? {
        let u = uuid.uuid
        guard u.0 == 0x4D, u.1 == 0x45, u.2 == 0x52, u.3 == 0x47 else { return nil }
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

    /// Every drawn region, in the order they were drawn; the selected one is the set's selection.
    var regionSet: SpectralRegionSet {
        SpectralRegionSet(regions: regions.compactMap(setRegion), selectedID: selectedRegion.map(Self.regionUUID))
    }

    /// The shown drawn regions other than the selected one: what the map outlines in their own colours beside the live region.
    var otherRegionSet: SpectralRegionSet {
        SpectralRegionSet(regions: regions.filter { $0.id != selectedRegion }.compactMap(setRegion).filter(\.isVisible))
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
        for region in old.regions where !kept.contains(region.id) { if let id = Self.regionID(region.id) { onRemoveRegion?(id) } }
        for region in new.regions {
            guard let id = Self.regionID(region.id), var style = regionStyles[id] else { continue }
            let named = region.name == regions.first(where: { $0.id == id })?.name ? nil : region.name
            let tint = RegionColor(style.tint, resolvedIn: EnvironmentValues()) == region.color ? style.tint : region.color.color
            if style.name != named || style.tint != tint || style.isVisible != region.isVisible {
                style.name = named; style.tint = tint; style.isVisible = region.isVisible
                regionStyles[id] = style
            }
        }
        if new.selectedID != old.selectedID, let uuid = new.selectedID, let id = Self.regionID(uuid), regions.contains(where: { $0.id == id }) {
            selectedRegion = id
        }
    }
}
