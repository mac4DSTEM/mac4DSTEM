//
//  SessionGates.swift
//  Role: The one owner of the session's "may I?" questions — the app-level
//        policy gates that decide whether an action may claim what it is about
//        to claim. A gate that exists once cannot be derived differently at two
//        call sites.
//
//  This is S7's `AppState` seam (docs/development-process.md §7), and like S1's
//  it is the seam the session's own defect earned: physical iDPC decided "may I
//  use the origin fit quantitatively?" from `hasFittedOrigin` alone
//  (`AppState.idpcPhysicalCalibration`), while Q calibration decided the same
//  question from `originFitRefusal` — so an origin fit whose residual exceeded
//  the probe radius was refused for a Q measurement and simultaneously admitted
//  into "iDPC projected phase (rad)". Same question, two derivations, the odd
//  one out unreviewed. Both call sites now ask this type.
//
//  The type answers two questions today and is the stated home for the next
//  one (docs/open-items.md: unifying `PendingLoad.directBeamRefusal` with
//  `CalibrationReReference`'s beam-exclusion handling as one policy with two
//  severities — queued behind the TB1 owner decision on a "load anyway"
//  override, not implementable before it).
//
//  Refusals follow the release's refusal rule (docs/v2-release.md §4): a gate
//  answers with a named reason, never by recording an error and continuing.
//

import Foundation

@Observable
@MainActor
final class SessionGates {

    // MARK: - May I use the origin fit quantitatively?

    /// Why a quantitative claim derived from the fitted origin must be
    /// refused, or nil when there is nothing to refuse.
    ///
    /// The predicate itself lives in `Core/Data/Calibration.swift`
    /// (`originFitRefusal`, quoting the residual and the probe radius), because
    /// Core owns the science; what lives HERE is the rule that app code asks
    /// this gate rather than re-deriving the judgement from `hasFittedOrigin`
    /// or any other fragment of `Calibration`. Both call sites — Q calibration
    /// (`calibrateQFromCrystal`) and physical iDPC
    /// (`idpcPhysicalCalibration`) — go through this one function.
    ///
    /// Like `SessionSidecarLocator.sessionSidecarURL`, this makes a second
    /// derivation unlikely, not unrepresentable: `Calibration`'s members stay
    /// public for Core and the `tools/` harnesses.
    func originQuantitativeRefusal(
        for calibration: Calibration
    ) -> String? {
        calibration.originFitRefusal
    }

    // MARK: - May I rewrite the session sidecar?

    /// A recorded load specification this session failed to restore.
    struct SidecarRestoreFailure: Equatable {
        enum Kind: Equatable {
            /// The sidecar exists and the specification could not be read.
            case unreadable
            /// The specification was read and describes a region this file
            /// does not have — the dataset was replaced, or the sidecar was
            /// copied beside a different cube.
            case doesNotFit
        }
        var kind: Kind
        var message: String
    }

    /// Set when `recordedLoadSpecification` failed on its `.unreadable` or
    /// does-not-fit branch and the dataset was loaded at full extent anyway.
    /// Cleared on EVERY path that changes the open dataset — `openFileAsync`
    /// and `discardPartialLoad` (beside `SessionSidecarLocator.release()`),
    /// plus `commitPendingLoad` and `openDemoFixture`, which change datasets
    /// without going through either. The first version claimed "paired with
    /// every release()" was sufficient; Gate B refuted it with a configurator
    /// commit that carried dataset A's refusal onto dataset B's saves
    /// (2026-08-25).
    ///
    /// Observable state, not a log line: the does-not-fit branch used to
    /// report only through `statusText`, which S1 measured being overwritten
    /// three lines later by the loading stages — the same unreadable-channel
    /// defect S1 fixed for the sibling branch. The inspector renders this.
    private(set) var sidecarRestoreFailure: SidecarRestoreFailure?

    func noteSidecarRestoreFailed(
        _ kind: SidecarRestoreFailure.Kind, message: String
    ) {
        sidecarRestoreFailure = SidecarRestoreFailure(kind: kind, message: message)
    }

    func clearSidecarRestoreFailure() {
        sidecarRestoreFailure = nil
    }

    /// Why the session sidecar must not be rewritten right now, or nil when a
    /// rewrite is allowed.
    ///
    /// The defect this refuses (S5's Gate B-lite finding F9): every sidecar
    /// rewrite restates the CURRENT view's specification — correctly, because
    /// a nil specification means full extent, it cannot double as "unknown" —
    /// so a save issued after a FAILED crop restore would erase the recorded
    /// crop and relabel the preserved scan-indexed results as full-extent.
    /// Right numbers, wrong positions, exactly the misread L6 exists to
    /// prevent, reachable through an honest failure path.
    ///
    /// Session-scoped on purpose: "Save Session Sidecar As…" copies the old
    /// file byte-for-byte into the new location, so a rewrite into the copy
    /// mislabels the same results — changing sidecars does not clear this,
    /// only reopening the dataset with its recorded view restored (or
    /// knowably absent) does. No override is offered; the refusal rule says
    /// precision explains a rejection, it never grants an admission.
    func sidecarRewriteRefusal() -> String? {
        guard let failure = sidecarRestoreFailure else { return nil }
        let remedy: String
        switch failure.kind {
        case .unreadable:
            // `.unreadable` covers BOTH an access refusal (the sandbox) and a
            // file that read but could not be decoded (a mangled attribute, a
            // newer schema) — the classification upstream is a display
            // heuristic, not a fact this gate can rely on. So the remedy
            // names both paths rather than promising re-granting will fix a
            // damaged file — a printed remedy that cannot work is the F1.3h
            // defect (Gate B, 2026-08-25).
            remedy = "If mac4DSTEM has not been granted access to it, "
                + "re-grant with Change… in the dataset inspector (choosing "
                + "the same file); if the file itself cannot be read or "
                + "decoded, move it aside or choose a different companion "
                + "file with Change…. Then reopen the dataset."
        case .doesNotFit:
            remedy = "Move the sidecar aside, or choose a different companion "
                + "file with Change… in the dataset inspector, then reopen "
                + "the dataset."
        }
        return "This session could not restore the view recorded in the "
            + "session sidecar (\(failure.message)) Saving now would rewrite "
            + "the sidecar as a full-extent session and mislabel the results "
            + "it already holds. " + remedy
    }
}
