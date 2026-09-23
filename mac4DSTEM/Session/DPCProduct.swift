//
//  DPCProduct.swift
//  Role: the one owner of the DPC display choice (`dpcDisplay`). Held by
//        AppState as `let dpc = DPCProduct()`, no forwarding properties;
//        views read `dpc.…` via `appState.dpc`.
//        (docs/archive/v4/appstate-seams-plan.md, seam 4)
//
//  `DPCDisplayMode` lives here beside its owner: `Session/` is its own
//  SwiftPM target (`DSTEMSession`, `Package.swift`) that `tools/run-tests.sh
//  core` builds standalone, so a type declared only in App/ (outside
//  `DSTEMCore`/`DSTEMSession`) would fail that build. `ACOMDisplayMode`
//  follows the same precedent beside its owner in `Session/ACOMWorkflow.swift`.
//
//  What stays on AppState, and why — no owner in this codebase holds a
//  reference to a sibling owner's state, so a function or computed property
//  that reads another owner's state cannot become a pure member here:
//  - `dpcMilliradiansPerDetectorPixel` reads only `calibrationSession` (a
//    sibling owner) and stays in `AppState.swift`, unchanged.
//  - `runDPC`, `flipRotation180`, `applyDPCDisplay` read `comField`,
//    `descriptor`, `calibrationSession`, `aperture`, `navigation`,
//    `phaseContrast`, `strain`, and call
//    `beginCancellableOperation`/`recordReplayStep`/`presentComputeFailure`/
//    `computeCoMField`/`applyStrainDisplay` — all AppState-only or another
//    owner's. They live in `App/AppState+DPC.swift` (placement, not an
//    owner), mirroring `App/AppState+DiskDetection.swift`.
//  - `computeCoMField` stays in `App/AppState+Calibration.swift`, shared
//    with R–Q rotation calibration; it references neither `dpcDisplay` nor
//    `dpcMilliradiansPerDetectorPixel`.
//
//  `dpcDisplay`'s `didSet` needs `applyDPCDisplay()`, which requires
//  `comField`/`descriptor`/`navigation`/`calibrationSession` that this owner
//  doesn't hold. It is exposed as an installable hook (`onDisplayChange`,
//  `() -> Void`) — the same shape `PhaseContrastProduct` and
//  `DiskDetectionProduct` use for effects that need the window — and
//  AppState wires it once in `init()` to `applyDPCDisplay()` in
//  `AppState+DPC.swift`.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation

package enum DPCDisplayMode: String, CaseIterable, Identifiable {
    case magnitude = "Magnitude (detector px)"
    case magnitudeMrad = "Magnitude (mrad)"
    case angle = "Angle"
    case colorWheel = "Color Wheel"
    case idpc = "iDPC"

    package var id: String { rawValue }
}

@Observable
@MainActor
package final class DPCProduct {

    // Explicit so the default initializer is `package` (synthesized ones are internal).
    package nonisolated init() {}

    /// Installed once by AppState; the display derivation needs
    /// `comField`/`descriptor`/`navigation`/`calibrationSession`, none of
    /// which this owner holds — see the header note.
    @ObservationIgnored package var onDisplayChange: (() -> Void)?

    package var dpcDisplay: DPCDisplayMode = .magnitude {
        didSet { onDisplayChange?() }
    }
}
