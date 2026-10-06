//
//  SpectroscopySession.swift
//  Role: the one owner of the Spectroscopy room's state (v5.0 WP2, ADR 053–055):
//        the opened EDX spectrum image, the selected step, the element roles,
//        the regions and the quantification method. Held by AppState as
//        `let spectroscopy = SpectroscopySession()`, with no forwarding
//        properties; views read `appState.spectroscopy.…`.
//
//  Nothing here computes a number. The spectrum image is a `SpectrumImageSource`
//  (Core), supplied by the Velox and GMS readers; the room's controller computes
//  from it and the quantification (WP3) will read and write this.
//
//  Why its own owner and not AppState: a spectrum image is a second kind of
//  document in the window (ADR 053 item 3, M2 item 4), independent of the 4D
//  cube — a window may hold either or both — so none of the 4D owners
//  (`DatasetSession`, `LoadedView`, `CalibrationSession`) is its home.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation

// MARK: - The spectrum image, as the room sees it

// `SpectrumImageMetadata` and `SpectrumImageSource` moved to Core (`Core/Spectroscopy/SpectrumImageSource.swift`,
// v5.0 WP2 R2): one protocol now carries the counts, the energy axis and the file's own metadata, so the session's
// opaque reference and Core's compute protocol are the same thing.

// MARK: - The room's five steps (ADR 054 item 8)

package enum SpectroscopyStep: String, CaseIterable, Identifiable, Sendable {
    case spectrumImage
    case elementsAndMaps
    case regions
    case quantify
    case export

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .spectrumImage: "Spectrum image"
        case .elementsAndMaps: "Elements & maps"
        case .regions: "Regions"
        case .quantify: "Quantify"
        case .export: "Export"
        }
    }

    package var systemImage: String {
        switch self {
        case .spectrumImage: "square.grid.3x3"
        case .elementsAndMaps: "circle.circle"
        case .regions: "square.dashed"
        case .quantify: "sum"
        case .export: "square.and.arrow.up"
        }
    }
}

// MARK: - Elements

/// An element's role in the fit (ADR 054 item 6) and the element row itself: the types live with the
/// method (`QuantificationMethod`, Core), because the element states are part of what a replay step
/// records. These names are the room's.
package typealias SpectroscopyElementRole = QuantificationMethod.ElementRole
package typealias SpectroscopyElement = QuantificationMethod.ElementState

// MARK: - Regions

package struct SpectroscopyRegion: Equatable, Identifiable, Sendable {
    package enum Kind: String, Sendable {
        /// Every pixel of the spectrum image.
        case wholeMap
        /// Drawn on the map.
        case drawn
        /// From a phase map of the linked 4D scan (M2: transported masks).
        case phase
        /// One precipitate object of the linked 4D scan.
        case object
    }

    package var id: Int
    package var name: String
    package var kind: Kind
    package var pixelCount: Int
    /// The drawn shape on the spectrum image's grid; nil for the whole map (and for regions transported from the 4D scan).
    package var shape: SpectrumRegionShape?

    package nonisolated init(id: Int, name: String, kind: Kind, pixelCount: Int, shape: SpectrumRegionShape? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.pixelCount = pixelCount
        self.shape = shape
    }
}

// MARK: - The quantification method (ADR 054 items 1-3, 9)

/// The method value is Core's (`QuantificationMethod`): Codable, byte-stable, hashed, recorded as the
/// replay step "quantification". Defaults are ADR 054's, unchanged by the move.
package typealias SpectroscopyQuantificationMethod = QuantificationMethod

// MARK: - The owner

@Observable
@MainActor
package final class SpectroscopySession {

    package nonisolated init() {}

    /// The opened spectrum image; nil when the window holds none.
    package private(set) var source: (any SpectrumImageSource)?

    /// The step the sidebar has selected and the inspector shows.
    package var selectedStep: SpectroscopyStep = .spectrumImage

    /// The element roles live in the method (they are part of what a quantification step records);
    /// this is the same list, so there is one copy.
    package var elements: [SpectroscopyElement] {
        get { method.elements }
        set { method.elements = newValue }
    }

    package var regions: [SpectroscopyRegion] = []
    /// The region the spectrum and the results describe.
    package var selectedRegionID: Int?

    package var method = SpectroscopyQuantificationMethod()

    package var metadata: SpectrumImageMetadata? { source?.metadata }

    /// Takes a spectrum image as this window's, and starts the room over on it:
    /// the first step, no elements yet (the proposer runs on open, WP3), and the
    /// whole map as the one region. The method is kept — it is the user's
    /// choice, not a property of the file (as `DiffractionGroupsProduct`
    /// keeps its run controls across datasets).
    package func open(_ source: any SpectrumImageSource) {
        self.source = source
        selectedStep = .spectrumImage
        elements = []
        let whole = SpectroscopyRegion(id: 0, name: "Whole map", kind: .wholeMap,
                                       pixelCount: source.metadata.pixelCount)
        regions = [whole]
        selectedRegionID = whole.id
    }

    /// Adds a drawn region and selects it. The pixel count is the mask's; a shape that holds no pixel adds nothing.
    @discardableResult
    package func addDrawnRegion(_ shape: SpectrumRegionShape) -> SpectroscopyRegion? {
        guard let source else { return nil }
        let count = shape.mask(nx: source.nx, ny: source.ny).reduce(0) { $0 + ($1 ? 1 : 0) }
        guard count > 0 else { return nil }
        let id = (regions.map(\.id).max() ?? -1) + 1
        let n = regions.filter { $0.kind == .drawn }.count + 1
        let region = SpectroscopyRegion(id: id, name: "Region \(n)", kind: .drawn, pixelCount: count, shape: shape)
        regions.append(region)
        selectedRegionID = id
        return region
    }

    /// Removes a drawn region (never the whole map); the whole map becomes the selection if it was the removed one.
    package func removeRegion(id: Int) {
        guard let r = regions.first(where: { $0.id == id }), r.kind != .wholeMap else { return }
        regions.removeAll { $0.id == id }
        if selectedRegionID == id { selectedRegionID = regions.first?.id }
    }

    /// The mask of a region on the open spectrum image: nil (every pixel) for the whole map.
    package func mask(of region: SpectroscopyRegion) -> PixelMask? {
        guard let source, let shape = region.shape else { return nil }
        return shape.mask(nx: source.nx, ny: source.ny)
    }

    /// Lets go of the spectrum image and everything derived from it.
    package func close() {
        source = nil
        selectedStep = .spectrumImage
        elements = []
        regions = []
        selectedRegionID = nil
    }
}
