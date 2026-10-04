//
//  SessionGates.swift
//  Role: The one owner of the session's "may I?" questions — the app-level
//        policy gates that decide whether an action may claim what it is about
//        to claim. A gate that exists once cannot be derived differently at two
//        call sites.
//
//  Both call sites ask this type rather than re-deriving policy: physical
//  iDPC decided "may I use the origin fit quantitatively?" from
//  `hasFittedOrigin` alone (`AppState.idpcPhysicalCalibration`), while Q
//  calibration decided the same question from `originFitRefusal` — so an
//  origin fit whose residual exceeded the probe radius was refused for a Q
//  measurement and simultaneously admitted into "iDPC projected phase
//  (rad)". Same question, two derivations, the odd one out unreviewed.
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
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

@Observable
@MainActor
package final class SessionGates {

    // Explicit so the default initializer is `package` (synthesized ones are internal).
    package nonisolated init() {}

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
    package func originQuantitativeRefusal(
        for calibration: Calibration
    ) -> String? {
        calibration.originFitRefusal
    }

    /// May a *reciprocal* measurement be derived in this frame? — the
    /// stricter question (`docs/q-calibration-design.md` §2). Q calibration
    /// asks this one; everything that needs only a centred frame keeps
    /// asking the looser one above.
    ///
    /// Two predicates, ONE policy owner: the science lives in
    /// `Calibration.originSupportsReciprocalMetrology`, and what lives here
    /// is the rule that app code asks the gate — this same question was once
    /// answered four different ways at four call sites, so the split must
    /// not create a fifth; that is why the strict predicate is a second
    /// function on this type rather than a tighter threshold hand-rolled at
    /// the Q-calibration call site.
    ///
    /// It refuses a **stand-in origin** by kind, not by measuring how wrong
    /// it is: measured geometric-middle substitution error is 1.14 px on
    /// `sim_Au` and 7.07 px on `downsample_Si_SiGe_exp` (S13 E1), straddling
    /// the band any estimator check can see, so "watch for it" was never
    /// going to work.
    package func reciprocalMetrologyRefusal(
        for calibration: Calibration,
        descriptor: DatasetDescriptor,
        apertureCentre: (x: Float, y: Float)?
    ) -> String? {
        // The predicate is asked of `Calibration`, not re-derived here. An
        // earlier version composed `originQuantitativeRefusal` with its own
        // `origin.kind.isMeasuredBeamCentre` test, which left
        // `Calibration.originSupportsReciprocalMetrology` with **no
        // production caller at all** — two derivations of one question.
        // Gate B found it by deleting half the unused predicate and watching
        // the fixture stay green.
        guard !calibration.originSupportsReciprocalMetrology(
            detectorQX: descriptor.qx, detectorQY: descriptor.qy,
            apertureCentre: apertureCentre
        ) else { return nil }

        if let refusal = originQuantitativeRefusal(for: calibration) { return refusal }
        let origin = calibration.referenceOrigin(
            detectorQX: descriptor.qx, detectorQY: descriptor.qy,
            apertureCentre: apertureCentre
        )
        switch origin.kind {
        case .apertureCentre:
            // Deliberately does NOT say "the aperture you placed". Every app
            // call site passes a non-nil aperture and the aperture starts at
            // the detector's middle, so this fires for users who have placed
            // nothing — telling them "where you put it" describes an action
            // they did not take (Gate B finding).
            return "Reciprocal calibration needs a measured beam centre. This dataset has none, "
                + "so Bragg vectors would be re-centred on the detector aperture's current "
                + "position, which is not a measurement of where the beam is. Run Calibrate "
                + "Origin, or enter the reciprocal pixel size manually."
        case .geometricMiddle:
            return "Reciprocal calibration needs a measured beam centre. This dataset has none, "
                + "so Bragg vectors would be re-centred on the detector's geometric middle — a "
                + "guess, not a measurement. Run Calibrate Origin, or enter the reciprocal pixel "
                + "size manually."
        case .fittedMaps, .recordedMean:
            // Reachable: `originSupportsReciprocalMetrology` also fails when
            // the fit is not sane, and then the refusal above has already
            // returned. If it did not, say something rather than nothing.
            return originQuantitativeRefusal(for: calibration)
        }
    }

    // MARK: - May I rewrite the session sidecar?

    /// A recorded load specification this session failed to restore.
    package struct SidecarRestoreFailure: Equatable {
        package enum Kind: Equatable {
            /// The sidecar exists and the specification could not be read.
            case unreadable
            /// The specification was read and describes a region this file
            /// does not have — the dataset was replaced, or the sidecar was
            /// copied beside a different cube.
            case doesNotFit
        }
        package var kind: Kind
        package var message: String

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
        package nonisolated init(kind: Kind, message: String) {
            self.kind = kind
            self.message = message
        }
    }

    /// Set when `recordedLoadSpecification` failed on its `.unreadable` or
    /// does-not-fit branch and the dataset was loaded at full extent anyway.
    /// Cleared on EVERY path that changes the open dataset — `openFileAsync`
    /// and `discardPartialLoad` (beside `SessionSidecarLocator.release()`),
    /// plus `commitPendingLoad` and `openDemoFixture`, which change datasets
    /// without going through either. Pairing the clear with `release()` alone
    /// is not sufficient — Gate B refuted it with a configurator commit that
    /// carried dataset A's refusal onto dataset B's saves.
    ///
    /// Observable state, not a log line: reporting only through `statusText`
    /// gets overwritten by the loading stages moments later. The inspector
    /// renders this.
    package private(set) var sidecarRestoreFailure: SidecarRestoreFailure?

    package func noteSidecarRestoreFailed(
        _ kind: SidecarRestoreFailure.Kind, message: String
    ) {
        sidecarRestoreFailure = SidecarRestoreFailure(kind: kind, message: message)
    }

    package func clearSidecarRestoreFailure() {
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
    ///
    /// Review a5 / owner card D3 (a), 2026-10-02: with the recorded view
    /// restored, a rewrite is still refused while the sidecar holds results
    /// computed on ANOTHER view than the loaded one (after Promote, or a
    /// differently configured open) — see `carriedViewRefusal`.
    /// `removingKind` names a removal: it is the remedy, allowed when it takes
    /// out the last such result.
    package func sidecarRewriteRefusal(removingKind: String? = nil) -> String? {
        guard let failure = sidecarRestoreFailure else { return carriedViewRefusal(removingKind: removingKind) }
        let remedy: String
        switch failure.kind {
        case .unreadable:
            // `.unreadable` covers BOTH an access refusal (the sandbox) and a
            // file that read but could not be decoded (a mangled attribute, a
            // newer schema) — the classification upstream is a display
            // heuristic, not a fact this gate can rely on. So the remedy
            // names both paths rather than promising re-granting will fix a
            // damaged file — a printed remedy that cannot work is the F1.3h
            // defect (Gate B finding).
            // The controls named are the ones that exist (review 2026-10-02 e5): "Allow Access…" in the
            // sidebar's Session section and the Dataset menu, and Dataset › Change Session Sidecar….
            remedy = "If mac4DSTEM has not been granted access to it, "
                + "grant it with Allow Access… (sidebar or Dataset menu); "
                + "if the file itself cannot be read or decoded, move it "
                + "aside or choose a different companion file with "
                + "Dataset › Change Session Sidecar…. Then reopen the dataset."
        case .doesNotFit:
            remedy = "Move the sidecar aside, or choose a different companion "
                + "file with Dataset › Change Session Sidecar…, then reopen "
                + "the dataset."
        }
        return "This session could not restore the view recorded in the "
            + "session sidecar (\(failure.message)) Saving now would rewrite "
            + "the sidecar as a full-extent session and mislabel the results "
            + "it already holds. " + remedy
    }

    /// C4(a): the ONE property every save control that rewrites the session
    /// sidecar binds `.disabled` to (a Remove control binds
    /// `mayRemoveFromSidecar(kind:)`, the same gate), alongside its own check that the
    /// thing it would save actually exists. Before this, "Save to Results"
    /// and the two Remove controls were `.disabled(appState.isBusy)` only —
    /// enabled, then refusing through a modal after the click — while Info
    /// already told the user saving was disabled (§4 finding 2).
    package var mayWriteSidecar: Bool { sidecarRewriteRefusal() == nil }

    /// What a saved result's Remove control binds (review a5 / owner card D3 a):
    /// the same gate, asked for the removal it is — removing the last result
    /// saved on another view is the remedy the save refusal names, so it must
    /// stay enabled where saving is not.
    package func mayRemoveFromSidecar(kind: String) -> Bool {
        sidecarRewriteRefusal(removingKind: kind) == nil
    }

    /// Does removing a saved result take what is ON SCREEN away? Only when the screen shows THAT saved
    /// result: a product restored from the sidecar (`displayedOrigin`) while it is the one in view
    /// (`currentID`, the in-session selection the inventory carries). A live product computed this session
    /// is not what was removed, and neither is a different saved result in view — replacing either with the
    /// file's current result wiped a never-saved image (RC drive 2026-10-02 D3). Lane S, P3b.
    package nonisolated static func removalDisplacesDisplay(
        displayedOrigin: ProductOrigin?, currentID: String?, removedID: String
    ) -> Bool {
        displayedOrigin == .restoredFromSidecar && currentID == removedID
    }

    /// The inventory a removal leaves: the file's own, reread — except that the saved result in view (the
    /// in-session selection, `inView`) stays marked as the current one while the reread still holds it,
    /// because the screen still shows it. When the removed result was the one in view it is not in the reread
    /// and the file's own current stands.
    package nonisolated static func inventory(
        _ reread: SessionSidecarInventory, keepingInView inView: String?
    ) -> SessionSidecarInventory {
        guard let inView, reread.results.contains(where: { $0.id == inView }) else { return reread }
        return SessionSidecarInventory(
            hasSidecar: reread.hasSidecar, hasBraggVectors: reread.hasBraggVectors,
            hasCalibration: reread.hasCalibration, results: reread.results, currentResultID: inView)
    }

    // MARK: - Would a rewrite relabel results saved on another view?

    /// What the rewrite gate reads about the open session. AppState owns all
    /// three facts and hands them over through `sessionView`.
    package struct SessionView: Equatable {
        package struct SavedResult: Equatable {
            package var kind: String
            package var name: String
            package nonisolated init(kind: String, name: String) {
                self.kind = kind
                self.name = name
            }
        }
        /// The view the session sidecar records (`.fullExtent` included); nil
        /// when there is no sidecar, or it predates recorded views.
        package var recorded: LoadSpecification?
        package var loaded: LoadSpecification
        /// Every result node the sidecar holds.
        package var savedResults: [SavedResult]

        package nonisolated init(recorded: LoadSpecification?, loaded: LoadSpecification, savedResults: [SavedResult]) {
            self.recorded = recorded
            self.loaded = loaded
            self.savedResults = savedResults
        }
    }

    /// Installed once by the owner of the facts (`AppState.init`, the same hook
    /// shape as its other seams). Nil — a bare `SessionGates`, as in most tests —
    /// asks nothing.
    @ObservationIgnored package var sessionView: (@MainActor () -> SessionView?)?

    private func carriedViewRefusal(removingKind: String?) -> String? {
        sessionView?().flatMap { Self.carriedViewRefusal($0, removingKind: removingKind) }
    }

    /// Why a rewrite would relabel results saved on another view, or nil.
    ///
    /// Every rewrite restates the LOADED view for the whole file, while each
    /// result node keeps no view of its own: after Promote, Save to Results
    /// copied the rehearsal's results verbatim under the full-extent label, and
    /// the next reopen read them as full-scan (review a5). The invariant kept:
    /// every result in the sidecar was computed on the view it records. So a
    /// rewrite is allowed when the recorded view IS the loaded one, or when it
    /// leaves no result from the recorded view behind — a save when none is held,
    /// a removal when it removes the last. A removal of one of several would
    /// relabel the rest, so it is refused too (both directions: a rehearsal
    /// view of a dataset holding full-extent results refuses the same way).
    /// Stored disks are not counted: their restore refuses a view or shape that
    /// differs (`SessionPeakRestore`).
    package static func carriedViewRefusal(_ view: SessionView, removingKind: String? = nil) -> String? {
        guard let recorded = view.recorded, recorded != view.loaded else { return nil }
        let carried = view.savedResults
        let left = removingKind.map { kind in carried.filter { $0.kind != kind } } ?? carried
        guard !left.isEmpty else { return nil }
        let views = "saved: \(recorded.provenanceSummary ?? "whole file") · "
            + "loaded: \(view.loaded.provenanceSummary ?? "whole file")"
        let reopen = "Reopen the dataset — a plain open restores the saved view —"
        if let kind = removingKind {
            let name = carried.first { $0.kind == kind }?.name ?? kind
            let others = left.count == 1 ? "the other result" : "the \(left.count) other results"
            return "Removing “\(name)” rewrites the session sidecar as the loaded view, which would relabel "
                + "\(others) computed on another view of this file (\(views)). \(reopen) and remove them there."
        }
        if carried.count == 1 {
            let name = carried[0].name
            return "The session sidecar holds “\(name)”, computed on another view of this file (\(views)). "
                + "Saving now would relabel it as computed on the loaded view. "
                + "\(reopen) and save there, or remove “\(name)” in Results first."
        }
        return "The session sidecar holds \(carried.count) results computed on another view of this file "
            + "(\(views)). Saving now would relabel them as computed on the loaded view. "
            + "\(reopen) and save or remove them there."
    }

    // MARK: - May a compute failure stay on the status bar, or does it escalate?

    /// A data-source failure (corrupted or vanished file mid-scan) reaching a
    /// compute catch block is not an ordinary compute failure — it
    /// invalidates the session, so `AppState.presentComputeFailure` escalates
    /// it to the modal path regardless of which analysis stage surfaced it.
    /// Lives here rather than on `AppState` as a stateless predicate, paying
    /// down the `AppState` + `ResultExport` budget (CLAUDE.md) — a placement
    /// choice only, not a policy change. No harness compiles this file, so
    /// it is not subject to the small-single-module-list constraint the
    /// sibling `Core/Analysis` relocation would have hit.
    package static func isDataSourceFailure(_ error: Error) -> Bool {
        // A tile-read failure WRAPS its data-source error — judge the
        // wrapped error, or a mid-scan HDF5 failure would stay off the modal
        // path precisely because it now carries a type (Gate B finding).
        if case DiskDetection.FullScanError.tileRead(_, let underlying) = error {
            return isDataSourceFailure(underlying)
        }
        if error is H5Error || error is DM4Error || error is VendorRawError
            || error is FourDError {
            return true
        }
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain || ns.domain == NSPOSIXErrorDomain
    }
}
