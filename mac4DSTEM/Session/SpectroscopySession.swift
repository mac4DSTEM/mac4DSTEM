//
//  SpectroscopySession.swift
//  Role: the one owner of the Spectroscopy room's state (v5.0 WP2, ADR 053–055):
//        the opened EDX spectrum image, the selected step, the element roles,
//        the regions and the quantification method. Held by AppState as
//        `let spectroscopy = SpectroscopySession()`, with no forwarding
//        properties; views read `appState.spectroscopy.…`.
//
//  Nothing here computes a number. The spectrum image is an opaque reference
//  (`SpectrumImageSource`) until the readers of lanes A and C supply one; the
//  room's views (lane V) and the quantification (WP3) read and write this.
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

/// What the shell needs to know about an opened EDX spectrum image: its file,
/// its scan grid and its energy axis. The numbers are the file's own, as read.
package struct SpectrumImageMetadata: Equatable, Sendable {
    package var fileName: String
    package var filePath: String
    /// Scan columns × rows of the spectrum image's own grid (M2: the native
    /// grid, never resampled onto the 4D scan's).
    package var scanWidth: Int
    package var scanHeight: Int
    /// Energy channels per spectrum.
    package var channelCount: Int
    /// The energy axis as the file states it: E(i) = offset + i · dispersion.
    /// Refinement on the pooled spectrum (ADR 054 item 4) is shown beside it,
    /// never written over it.
    package var energyOffsetEV: Double
    package var energyDispersionEV: Double
    /// Real-space pixel size, when the file carries one.
    package var scanPixelSize: Double?
    package var scanPixelUnit: String?

    package nonisolated init(
        fileName: String, filePath: String, scanWidth: Int, scanHeight: Int,
        channelCount: Int, energyOffsetEV: Double, energyDispersionEV: Double,
        scanPixelSize: Double? = nil, scanPixelUnit: String? = nil
    ) {
        self.fileName = fileName
        self.filePath = filePath
        self.scanWidth = scanWidth
        self.scanHeight = scanHeight
        self.channelCount = channelCount
        self.energyOffsetEV = energyOffsetEV
        self.energyDispersionEV = energyDispersionEV
        self.scanPixelSize = scanPixelSize
        self.scanPixelUnit = scanPixelUnit
    }

    package nonisolated var pixelCount: Int { scanWidth * scanHeight }
}

/// An opened EDX spectrum image. The shell holds it as an opaque reference:
/// readers (the Velox sparse store, a GMS DM4 EDS SI) conform and add their
/// own data access; the room's computations ask for what they need through
/// the conforming type, not through this protocol.
package protocol SpectrumImageSource: AnyObject, Sendable {
    nonisolated var metadata: SpectrumImageMetadata { get }
}

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

    package nonisolated init(id: Int, name: String, kind: Kind, pixelCount: Int) {
        self.id = id
        self.name = name
        self.kind = kind
        self.pixelCount = pixelCount
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

    /// Lets go of the spectrum image and everything derived from it.
    package func close() {
        source = nil
        selectedStep = .spectrumImage
        elements = []
        regions = []
        selectedRegionID = nil
    }
}
