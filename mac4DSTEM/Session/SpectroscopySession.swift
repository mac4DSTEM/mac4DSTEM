//
//  SpectroscopySession.swift
//  Role: the window's spectrum image and what the EDS room records about it (v5.0 WP2, ADR 053–055):
//        the opened EDX spectrum image, the selected tool, the quantification method the lineage step
//        records, and the registration to the window's 4D scan. The EDS room's own state (regions, pools,
//        the fit) is `EDXSession`'s. Held by AppState as
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

    package var method = SpectroscopyQuantificationMethod()

    /// The registration of this spectrum image to the window's 4D scan, when the app states one (E1): the identity of a GMS
    /// joint attach, "same scan, identity; no lag check". Owner: this session; the window sets it at attach. Nil: no pool.
    package var registration: RegistrationRecordM2?
    /// The 4D file the registration was stated for: another cube in the window does not inherit the claim.
    package var registeredCubePath: String?
    /// The newest pool request; a build that lands for an older one is dropped (the window bumps it).
    package var poolRequest = 0
    /// The build in flight, so a newer request can cancel it.
    package var poolTask: Task<Void, Never>?

    package var metadata: SpectrumImageMetadata? { source?.metadata }

    /// Takes a spectrum image as this window's, and starts the room over on it:
    /// no elements yet (the proposer runs on open, WP3). The method is kept — it is the user's
    /// choice, not a property of the file (as `DiffractionGroupsProduct`
    /// keeps its run controls across datasets).
    package func open(_ source: any SpectrumImageSource) {
        self.source = source
        selectedTool = .edx
        elements = []
        registration = nil; registeredCubePath = nil
        poolTask?.cancel(); poolTask = nil
        poolRequest += 1
    }

    /// Lets go of the spectrum image and everything derived from it.
    package func close() {
        poolTask?.cancel(); poolTask = nil
        poolRequest += 1
        registration = nil; registeredCubePath = nil
        source = nil
        selectedTool = .edx
        elements = []
    }
}
