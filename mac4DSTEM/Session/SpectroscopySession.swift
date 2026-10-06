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

/// An element's role in the fit (ADR 054 item 6): quantified, fitted only (its
/// lines are modelled so they do not leak into neighbours, but it gets no
/// at%), or off.
package enum SpectroscopyElementRole: String, CaseIterable, Sendable {
    case quantify
    case fitOnly
    case off
}

package struct SpectroscopyElement: Equatable, Identifiable, Sendable {
    /// The element symbol, e.g. "Mg".
    package var symbol: String
    package var role: SpectroscopyElementRole
    /// Picked by the user. The proposer never drops a manual pick (owner,
    /// ADR 054 "The mock's first review").
    package var isManual: Bool

    package var id: String { symbol }

    package nonisolated init(symbol: String, role: SpectroscopyElementRole, isManual: Bool) {
        self.symbol = symbol
        self.role = role
        self.isManual = isManual
    }
}

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

// MARK: - The quantification method (ADR 054 items 1–3, 9)

package struct SpectroscopyQuantificationMethod: Equatable, Sendable {
    /// Item 1: least squares, unweighted, is the named default; Poisson
    /// maximum likelihood sits under Expert.
    package enum Estimator: String, CaseIterable, Sendable {
        /// Least squares, unweighted.
        case leastSquares
        case poissonMaximumLikelihood
    }

    /// Item 2: a fitted whole-spectrum empirical continuum with the Al K-edge
    /// step (Velox's "Empirical") by default.
    package enum Background: String, CaseIterable, Sendable {
        case empiricalWithAlEdge
        /// eXSpy's whole-range sixth-order polynomial, the parity path, under Expert.
        case wholeRangePolynomial6
    }

    /// Item 3: a computed Brown-Powell k, or a typed k with its source. No ζ in
    /// the menu.
    package enum KFactorSource: String, CaseIterable, Sendable {
        case brownPowell
        case typed
    }

    /// Item 9: typed ± σ now, in nanometres.
    package struct Thickness: Equatable, Sendable {
        package var nanometres: Double
        package var sigmaNanometres: Double

        package nonisolated init(nanometres: Double, sigmaNanometres: Double) {
            self.nanometres = nanometres
            self.sigmaNanometres = sigmaNanometres
        }
    }

    package var estimator: Estimator = .leastSquares
    package var background: Background = .empiricalWithAlEdge
    package var kFactorSource: KFactorSource = .brownPowell
    /// ADR 053 item 5: four-detector weighted transmission (solid-angle-weighted
    /// mean), badged; on by default, and refused (by the quantification, not
    /// here) when geometry or tilt is unknown.
    package var absorptionCorrection = true
    /// Unset until the user types one: no thickness is assumed.
    package var thickness: Thickness?

    package nonisolated init() {}
}

// MARK: - The owner

@Observable
@MainActor
package final class SpectroscopySession {

    package nonisolated init() {}

    /// The opened spectrum image; nil when the window holds none.
    package private(set) var source: (any SpectrumImageSource)?

    /// The step the sidebar has selected and the inspector shows.
    package var selectedStep: SpectroscopyStep = .spectrumImage

    package var elements: [SpectroscopyElement] = []

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
