import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif

/// Seam 7 placement: pending-load commit/discard and full-extent promotion.
extension AppState {
    /// Load what the configurator was showing.
    func commitPendingLoad() {
        // The beam gate is enforced HERE, not only by the Load button's
        // `.disabled` — a gate that exists only in a view modifier is not a
        // gate (the SessionSidecarLocator rule): any second entry point, menu
        // command or test would commit a beam-excluding crop without it.
        // // v2 S4
        //
        // DEVIATION (seam 7, 2026-09-18): the pre-seam guard peeked at
        // `pendingLoad` and only cleared it after every condition passed —
        // collapsing the peek into `promotionRun.take()` here cleared the
        // owner unconditionally, so a refused commit (beam-excluding crop,
        // no preview) silently dropped the configurator's in-progress load
        // instead of leaving it open for correction. Caught by
        // `PromotionCommitTests.testCommitRefusalPreservesThePendingLoadForCorrection`.
        guard let pending = promotionRun.pendingLoad, pending.view != nil,
              pending.directBeamRefusal == nil else { return }
        promotionRun.take()
        pending.cancelSingleDPFetch()
        Task {
            beginDatasetLoading("Opening \(pending.source.datasetPath)…")
            if let openURL { openURL.stopAccessingSecurityScopedResource() }
            openURL = pending.accessedSecurityScope ? pending.url : nil
            datasetSession.prepare(reader: pending.reader, datasets: [pending.source])
            // This path changes the open dataset WITHOUT `openFileAsync`, so
            // it must drop the previous dataset's restore-failure flag itself
            // — Gate B found the flag surviving a configurator commit and
            // refusing the NEW dataset's saves with the OLD dataset's message
            // (2026-08-25). (`sessionSidecar`'s own state has the same
            // blind spot, recorded in docs/open-items.md — S1's surface, not
            // changed here.)
            gates.clearSidecarRestoreFailure()
            await activate(
                descriptor: pending.source, reader: pending.reader,
                specification: pending.configuration.specification,
                runInitialAnalysis: false
            )
            if datasetSession.loadWasCancelled || !hasDataset {
                await discardPartialLoad()
                finishDatasetLoading()
                return
            }
            await runCurrentAnalysis()
            if datasetSession.loadWasCancelled {
                await discardPartialLoad()
                finishDatasetLoading()
                return
            }
            rememberOpenedDataset(pending.url)
            finishDatasetLoading()
        }
    }

    /// Reopen the same source, whole — the promote control's action.
    /// Promotion is *removing* the load specification — `.fullExtent` is the
    /// identity — never re-deriving anything from the reduced data
    /// (docs/v2-release.md §1, commitment 2).
    /// Deliberately NOT `openFileAsync`: that path re-applies the sidecar's
    /// recorded specification, which is exactly the crop being promoted away.
    /// The reader and the security scope are the ones the rehearsal already
    /// holds, so this is `commitPendingLoad`'s shape with the one
    /// specification the configurator never needs to validate.
    /// The source is `datasetSession.loadView`'s own — the descriptor the loaded view
    /// declares it was cut from — never `datasets.first`. The two are equal on
    /// every shipped path, but the button's caption prices `datasetSession.loadView`'s
    /// source, and Gate A found the pairing unpinned: the moment a
    /// multi-dataset path can carry a specification, `datasets.first` reopens
    /// the wrong cube while the caption describes the right one. A LoadView
    /// source is 4D by construction (its init throws otherwise), so no
    /// separate rank check is needed.
    /// What the reopened dataset shows is decided by machinery that already
    /// exists: `activate` re-references calibration into the full-extent view,
    /// and a session result restored from the sidecar is labelled with the
    /// view it was computed on when that differs (L6 item 3). Cancelling
    /// unwinds to the welcome screen like any cancelled open — the rehearsal
    /// view is a specification, not state worth half-restoring.
    /// Internal rather than private so the WIRING can be tested — the S1
    /// lesson: a test that cannot reach the call site pins the pure decision
    /// and not the path the app takes. // v2 S3
    /// `runReestablishingAnalysis: false` is the replay path's option (v2 S6):
    /// when a recorded pipeline is about to replay, the current-mode pass
    /// would be a redundant whole-cube run — at promote scale, a real cost —
    /// immediately overwritten by the recipe's own first step.
    func promoteToFullExtent(runReestablishingAnalysis: Bool = true) async {
        // The recipe SURVIVES a promote: same session, same dataset — the
        // promote run is what the recipe exists to feed, and `activate`'s
        // reset (correct for a dataset change) would otherwise destroy every
        // unsaved step at exactly the moment they become useful
        // (Gate B-lite F11). Re-adopted after success below, with the frame
        // it was recorded under — the sidecar re-adopt during `activate`
        // would otherwise stand, and its frame tag with it. // v2 S6
        let recipeBeforePromote = replay.record
        let frameBeforePromote = replay.parameterFrame
        // `!datasetSession.isLoading` is the reentrancy gate: without it, the
        // only protections were the button's `.disabled` (blind to a load
        // that starts after the click renders) and an ordering accident —
        // `activate` resets `loadedView` before its first suspension, so a
        // double-fired Task happened to fail the guard below. An accident is
        // not a contract; a second `beginDatasetLoading` would replace the
        // shared cancellation token and Cancel would stop only the newer
        // load (Gate A review, 2026-08-19).
        guard !datasetSession.isLoading, let reader = datasetSession.reader,
              let source = datasetSession.loadView?.source,
              !loadedView.isFullExtent else { return }
        // The recipe survives EVERY exit, not only success: `activate`
        // resets it and may re-adopt the sidecar's OLDER copy before a
        // cancel is noticed, so a success-only re-adopt let a cancelled
        // promote silently swap an unsaved recipe for the sidecar's stale
        // one (Gate A finding C5, 2026-08-25). `adopt` treats nil/absent as
        // absence, so an empty pre-promote record leaves whatever the
        // sidecar restore adopted in place. Registered after the guard: a
        // refused promote touched nothing and restates nothing.
        defer {
            replay.adopt(recipeBeforePromote.isEmpty ? nil : recipeBeforePromote,
                         recordedOn: frameBeforePromote)
        }
        beginDatasetLoading("Reopening \(source.fileName) at full extent…")
        await activate(
            descriptor: source, reader: reader,
            specification: .fullExtent,
            runInitialAnalysis: false
        )
        if datasetSession.loadWasCancelled || !hasDataset {
            await discardPartialLoad()
            finishDatasetLoading()
            return
        }
        guard loadedView.isFullExtent else {
            // `activate` presented its own error and left the rehearsal
            // loaded (its failure paths return before touching `loadedView`).
            // Unreachable today — a promotable source already survived a
            // rehearsal LoadView init, so the full-extent init cannot throw —
            // but without this bail a future error path in `activate` would
            // run the whole-cube pass under a "Reopening…" banner for a
            // reopen that never happened. Do not discard: the rehearsal is
            // intact and still what the user had.
            finishDatasetLoading()
            return
        }
        if runReestablishingAnalysis {
            await runCurrentAnalysis()
            if datasetSession.loadWasCancelled {
                await discardPartialLoad()
                finishDatasetLoading()
                return
            }
        }
        // The recipe re-adopt (Gate B-lite F11) now happens in the defer
        // above, covering the cancel and failure exits too. Re-stamp the
        // recovery record so the persisted (frame, position) pair describes
        // the promoted view now, not whenever the user next moves the cursor
        // (Gate B-lite F14). // v2 S5
        finishDatasetLoading()
        persistRecoveryPosition()
    }
    /// Walk away without loading. Releases the file access the pending open
    /// took, so a cancelled configuration leaves nothing held — and, as with a
    /// cancelled load, is not remembered.
    func discardPendingLoad() {
        guard let pending = promotionRun.take() else { return }
        // Before releasing the scope: a dropped PendingLoad must not keep a
        // detached pattern read running against a URL the app no longer has
        // scoped access to. // v2 S4
        pending.cancelSingleDPFetch()
        if pending.accessedSecurityScope {
            pending.url.stopAccessingSecurityScopedResource()
        }
        statusText = "No file loaded"
    }
}
