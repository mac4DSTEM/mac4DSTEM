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
import SpectroCore
import SpectroEDX

// MARK: - The spectrum image, as the room sees it

// `SpectrumImageMetadata` and `SpectrumImageSource` moved to Core (`Core/Spectroscopy/SpectrumImageSource.swift`, SpectroKit's since S4,
// v5.0 WP2 R2): one protocol now carries the counts, the energy axis and the file's own metadata, so the session's
// opaque reference and Core's compute protocol are the same thing.

// MARK: - The room's tools (ADR 056)

/// The tools the Spectroscopy room lists under its sidebar row, as the other rooms list theirs. One today; EELS is the
/// next (ADR 056). The room is one window, so a tool is a whole workspace, not a step.
package enum SpectroscopyTool: String, CaseIterable, Identifiable, Sendable {
    case edx

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .edx: "EDS"
        }
    }

    package var systemImage: String {
        switch self {
        case .edx: "waveform.path.ecg"
        }
    }
}

// MARK: - Elements

/// The element row: the type lives with the method (`QuantificationMethod`, Core), because the element
/// states are part of what a replay step records. This name is the room's.
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
        /// One diffraction group of the linked 4D scan (E1).
        case group
        /// The positions of the linked 4D scan the phase matcher did not index (E1, card E4 a).
        case notIndexed

        /// A pool of the 4D scan: its mask is the catalogue's, never nil.
        package var isPool: Bool { self == .phase || self == .group || self == .notIndexed }
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

    /// The tool the sidebar has selected.
    package var selectedTool: SpectroscopyTool = .edx

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

    /// The registration of this spectrum image to the window's 4D scan, when the app states one (E1): the identity of a GMS
    /// joint attach, "same scan, identity; no lag check". Owner: this session; the window sets it at attach. Nil: no pool.
    package var registration: RegistrationRecordM2?
    /// The 4D file the registration was stated for: another cube in the window does not inherit the claim.
    package var registeredCubePath: String?
    /// The pools of the 4D scan the window offers beside the drawn regions (E1); the regions of kind phase, group and
    /// notIndexed in `regions` are exactly these.
    package private(set) var poolCatalogue = PoolCatalogue()
    /// The newest pool request; a build that lands for an older one is dropped (the window bumps it).
    package var poolRequest = 0
    /// The build in flight, so a newer request can cancel it.
    package var poolTask: Task<Void, Never>?

    package var metadata: SpectrumImageMetadata? { source?.metadata }

    /// Takes a spectrum image as this window's, and starts the room over on it:
    /// no elements yet (the proposer runs on open, WP3), and the
    /// whole map as the one region. The method is kept — it is the user's
    /// choice, not a property of the file (as `DiffractionGroupsProduct`
    /// keeps its run controls across datasets).
    package func open(_ source: any SpectrumImageSource) {
        self.source = source
        selectedTool = .edx
        elements = []
        let whole = SpectroscopyRegion(id: 0, name: "Whole map", kind: .wholeMap,
                                       pixelCount: source.metadata.pixelCount)
        regions = [whole]
        selectedRegionID = whole.id
        registration = nil; registeredCubePath = nil
        poolCatalogue = PoolCatalogue()
        poolTask?.cancel(); poolTask = nil
        poolRequest += 1
    }

    /// What `applyPools` changed, for the room: pools whose content changed or vanished must lose their cached spectra,
    /// pins and Auto ID outcome (H8).
    package struct PoolChange: Equatable {
        /// Region ids of pools that were shown before and are now different or gone.
        package var stale: Set<Int> = []
        /// Their names (an Auto ID outcome names its region).
        package var staleNames: Set<String> = []
        /// The sentence when the selected pool's source vanished and the selection moved to the whole map.
        package var selectionSentence: String?
        package var isEmpty: Bool { stale.isEmpty && selectionSentence == nil }
    }

    /// Replaces the pool regions with `catalogue`'s. A pool that is the same as before is left alone; one that changed or
    /// vanished is reported in the change. If the selected pool vanished the whole map is selected, with a sentence.
    @discardableResult
    package func applyPools(_ catalogue: PoolCatalogue) -> PoolChange {
        var change = PoolChange()
        let fresh = Dictionary(uniqueKeysWithValues: catalogue.pools.map { ($0.id, $0) })
        for old in poolCatalogue.pools where fresh[old.id] != old {
            change.stale.insert(old.id); change.staleNames.insert(old.name)
        }
        if let selected = selectedRegionID, let gone = poolCatalogue.pools.first(where: { $0.id == selected }), fresh[selected] == nil {
            change.selectionSentence = "The pool \u{201C}\(gone.name)\u{201D} is gone: the 4D product it came from was replaced or cleared. Showing the whole map."
            selectedRegionID = regions.first { $0.kind == .wholeMap }?.id
        }
        regions.removeAll { $0.kind.isPool }
        poolCatalogue = catalogue
        for pool in catalogue.pools {
            let kind: SpectroscopyRegion.Kind = pool.kind == .phase ? .phase : pool.kind == .group ? .group : .notIndexed
            regions.append(SpectroscopyRegion(id: pool.id, name: pool.name, kind: kind, pixelCount: pool.pixelCount))
        }
        return change
    }

    /// The registration a region's spectrum went through: the session's for a pool, none for the whole map and a drawn region.
    package func registration(of region: SpectroscopyRegion) -> RegistrationRecordM2? {
        region.kind.isPool ? registration : nil
    }

    /// Adds a drawn region and selects it. The pixel count is the mask's; a shape that holds no pixel adds nothing.
    @discardableResult
    package func addDrawnRegion(_ shape: SpectrumRegionShape) -> SpectroscopyRegion? {
        guard let source else { return nil }
        let count = shape.mask(nx: source.nx, ny: source.ny).reduce(0) { $0 + ($1 ? 1 : 0) }
        guard count > 0 else { return nil }
        let id = (regions.filter { !$0.kind.isPool }.map(\.id).max() ?? -1) + 1   // pool ids sit above every drawn one
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
    /// A pool's mask is the catalogue's and is never nil (nil means every pixel): a pool that is not there sums nothing.
    package func mask(of region: SpectroscopyRegion) -> PixelMask? {
        guard let source else { return nil }
        if region.kind.isPool {
            return poolCatalogue.pools.first { $0.id == region.id }?.mask ?? PixelMask(repeating: false, count: source.nx * source.ny)
        }
        guard let shape = region.shape else { return nil }
        return shape.mask(nx: source.nx, ny: source.ny)
    }

    /// Lets go of the spectrum image and everything derived from it.
    package func close() {
        poolTask?.cancel(); poolTask = nil
        poolRequest += 1
        registration = nil; registeredCubePath = nil
        poolCatalogue = PoolCatalogue()
        source = nil
        selectedTool = .edx
        elements = []
        regions = []
        selectedRegionID = nil
    }
}
