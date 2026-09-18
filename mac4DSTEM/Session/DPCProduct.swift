//
//  DPCProduct.swift
//  Role: seam 4 (docs/appstate-seams-plan.md) — the last of the night's four
//        unattended seams. The one owner of the DPC display choice
//        (`dpcDisplay`). Held by AppState as `let dpc = DPCProduct()`, no
//        forwarding properties; views read `dpc.…` (via `appState.dpc`).
//
//  Moved verbatim out of AppState.swift on 2026-09-18 (the seams plan, seam
//  4): `dpcDisplay` keeps its pre-seam name, type, default value and its
//  `didSet` (the display re-derivation).
//
//  `DPCDisplayMode` moved here too, and NOT because the plan named it: it is
//  `dpcDisplay`'s own type, previously declared at the top of AppState.swift
//  (App/, outside both `DSTEMCore` and `DSTEMSession`). `Session/` is its own
//  SwiftPM target (`DSTEMSession`, `Package.swift`) that `tools/run-tests.sh
//  core` builds standalone — a `DPCProduct` referencing a type App/ alone
//  declares would fail that build the moment it left the single-module Xcode
//  target. `ACOMDisplayMode` already lives beside its owner this way
//  (`Session/ACOMWorkflow.swift`, `package enum`) — the same precedent,
//  applied here. The case list and raw values are unchanged; only the
//  declaration's file moved.
//
//  What stayed on AppState, and why (the seam rule against logic changes —
//  plan §"Rules for every seam" #2 — means a function or computed property
//  that reads AppState-only or another owner's state cannot become a pure
//  member here without changing what it reads):
//  - `dpcMilliradiansPerDetectorPixel`: the plan's seam-4 bullet names it as
//    moving, but its body reads only `calibrationSession` (a sibling owner)
//    — no dependency on `dpcDisplay` or anything else this type would hold.
//    No owner in this codebase holds a reference to a sibling owner
//    (`DiskDetectionProduct.swift`'s header and `ACOMSession.swift`'s comment
//    on `acomInterpretationLabel` both document the same judgement for their
//    own combiners), and seam 3 already established the resolution when a
//    plan's "Moves" list turns out to include a cross-owner combiner:
//    `diskDetectionContext` and its three siblings were named to move in
//    seam 3's bullet but "left in place in AppState.swift" once their true
//    dependencies were read. `dpcMilliradiansPerDetectorPixel` follows the
//    same correction — left in place, unchanged, in `AppState.swift`.
//  - `runDPC`, `flipRotation180`, `applyDPCDisplay` (the 217-line DPC
//    section): read `comField`, `descriptor`, `calibrationSession`,
//    `aperture`, `navigation`, `phaseContrast`, `strain`, and call
//    `beginCancellableOperation`/`recordReplayStep`/`presentComputeFailure`/
//    `computeCoMField`/`applyStrainDisplay` — all AppState-only or another
//    owner's. They move to `App/AppState+DPC.swift` (placement, not an
//    owner) per rule 7, mirroring `App/AppState+DiskDetection.swift`.
//  - `computeCoMField` stays in `App/AppState+Calibration.swift`, named
//    explicitly by the plan as shared with R–Q rotation calibration; it
//    references neither `dpcDisplay` nor `dpcMilliradiansPerDetectorPixel`
//    (confirmed by grep), so nothing in it needed repointing.
//
//  The `dpcDisplay` `didSet` used to call `applyDPCDisplay()` directly for
//  its side effect (the return value, a `String?` failure reason, was
//  ignored at that call site — confirmed by reading it). `applyDPCDisplay()`
//  needs `comField`/`descriptor`/`navigation`/`calibrationSession`, none of
//  which this owner holds. Rule 1 forbids deleting or rewriting the
//  observer, so it is relocated into an installable hook (`onDisplayChange`,
//  `() -> Void` — the ignored return value needs no wider signature), the
//  same shape `PhaseContrastProduct` and `DiskDetectionProduct` use for
//  effects that need the window; AppState wires it once in `init()` to the
//  same `applyDPCDisplay()` call (now living in `AppState+DPC.swift`).
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
    /// which this owner holds — see the header note above.
    @ObservationIgnored package var onDisplayChange: (() -> Void)?

    package var dpcDisplay: DPCDisplayMode = .magnitude {
        didSet { onDisplayChange?() }
    }
}
