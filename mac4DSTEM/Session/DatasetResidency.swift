//
//  DatasetResidency.swift
//  Role: Everything the app knows about whether the open cube is held in
//        memory — the requested mode, whether it is actually held, how large it
//        is, and the preload's measured progress.
//
//  WHY THIS IS ITS OWN TYPE (docs/development-process.md §7, decided
//  2026-08-17). Every L-stage that touches `AppState` extracts one seam. L2
//  *adds* this state, so it lands here rather than becoming four more
//  properties on a facade that 172 stored properties already share.
//
//  `AppState` holds it and deliberately keeps **no forwarding properties**:
//  views read `appState.residency.…` directly. A forwarding property would
//  preserve the view API while putting this state back within reach of every
//  method on `AppState`, which is the exact thing the extraction is for.
//
//  It owns the state AND the transitions. Nothing outside may set `isResident`,
//  and the only way to change residency is `preload` / `release`, which keep
//  the published flags and the `FourDArray`'s actual buffer in step. A flag
//  that can drift from the buffer it describes would let the Performance panel
//  claim "Resident" about a cube that is being streamed.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

@MainActor
@Observable
package final class DatasetResidency {

    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2c
    package nonisolated init() {}

    /// What was asked for. `.streamed` is the shipped default — `.automatic`
    /// was dropped for v2 (owner decision 2026-08-18; it always streamed, so
    /// behaviour is unchanged). See the `Residency` enum for the return
    /// condition. // v2 S3
    package private(set) var mode: Residency = .streamed

    /// Whether a cube is actually held. Set only from the array's own answer,
    /// never from what was requested.
    package private(set) var isResident = false

    /// Bytes held (0 when streaming).
    package private(set) var byteCount = 0

    /// Determinate [0,1] while the preload runs, `nil` otherwise.
    ///
    /// The denominator is the cube, which is known exactly, so this phase is
    /// legitimately determinate (invariant I5) — and it is published only once
    /// real work has been reported, so a refused preload never flashes a 0%
    /// bar for a read that is not going to happen.
    package private(set) var preloadFraction: Double?

    package var isPreloading: Bool { preloadFraction != nil }

    /// One line for the Performance panel. The user must be able to tell at a
    /// glance which path their analyses are taking (L2.6).
    ///
    /// It states only what is known. "Streaming" is not annotated with a reason
    /// — too large, refused, not measured — because the reasons are not all
    /// distinguishable here, and a confident wrong explanation is worse than a
    /// bare fact.
    package var summary: String {
        if isPreloading { return "Loading into memory…" }
        guard isResident else { return "Streaming" }
        return "Resident · \(SystemMonitor.byteString(byteCount))"
    }

    /// Distinguishes one preload from the next. There is a single
    /// `DatasetResidency` on `AppState`, reused for every dataset, while a
    /// preload's progress ticks arrive through detached `Task { @MainActor }`
    /// hops that are unordered with respect to the preload's own completion.
    /// Without a generation, a tick enqueued just before the end could land
    /// after it — pinning `preloadFraction` non-nil forever, so the panel reads
    /// "Loading into memory…" with no preload running and nothing to clear it —
    /// and, across a dataset switch, dataset A's late ticks and final `sync`
    /// could publish A's residency onto the object that now describes B.
    /// Adversarial review 2026-08-17.
    private var generation = 0
    private var activePreload: Int?

    /// Forget everything. Called when a dataset is replaced — the incoming
    /// `FourDArray` is a different object with its own (absent) buffer.
    package func reset() {
        generation &+= 1
        activePreload = nil
        mode = .streamed
        isResident = false
        byteCount = 0
        preloadFraction = nil
    }

    package func request(_ newMode: Residency, on data: FourDArray?) async {
        mode = newMode
        guard let data else { return }
        await data.setResidencyRequest(newMode)
        await sync(with: data)
    }

    /// Read the whole cube into one buffer if this machine admits it.
    ///
    /// Returns whether the cube ended up resident. Never throws: invariant I6
    /// says every path degrades to streaming, so a refusal, an allocation
    /// failure, a cancelled preload or a failed read all leave the app opening
    /// the file normally — just streaming.
    ///
    /// `onProgress` receives the measured fraction of scan rows copied, so the
    /// caller can render it in whatever quantities it already uses.
    @discardableResult
    package func preload(
        _ data: FourDArray,
        maximumRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async -> Bool {
        // This stamp is DESTRUCTIVE under the `.streamed` default: the array
        // releases its cube when stamped `.streamed`, so a preload pass over
        // an array someone made resident BEHIND this seam (direct
        // `setResidencyRequest(.resident)` + `makeResident`, the tools/tests
        // pattern) drops that buffer — where the old `.automatic` stamp was
        // inert. Deliberate, not accidental (Gate A review, 2026-08-19): this
        // type's contract is that preload/release are the only residency
        // transitions and the published flags never drift from the buffer.
        // Forcing the array to the seam's own mode keeps both consistent;
        // preserving a cube this object never granted would reintroduce the
        // drift it exists to prevent. In-app the stamp is a no-op today —
        // `preloadResidentCube` only ever follows `activate`'s fresh array.
        await data.setResidencyRequest(mode)
        generation &+= 1
        let generation = self.generation
        activePreload = generation
        defer {
            // Order matters: clearing `activePreload` first means a tick that
            // lands after this point finds no active preload and drops, rather
            // than resurrecting `preloadFraction` on a finished load.
            if activePreload == generation { activePreload = nil }
            if self.generation == generation { preloadFraction = nil }
        }
        do {
            // `[weak self]` on BOTH closures — the shape `buildDatasetPreview`
            // already uses. Weak only on the inner Task left the progress
            // callback itself holding self strongly (#ImplicitStrongCapture),
            // and weak only on the outer made the inner read a captured var
            // from concurrent code (#SendableClosureCaptures, a Swift 6
            // error). The inner capture list re-takes its own weak box at
            // Task creation, which satisfies both. // v2 S3
            _ = try await data.makeResident(
                maximumRows: maximumRows, cancellation: cancellation
            ) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self, self.activePreload == generation else { return }
                    // Clamp monotonic. These arrive through detached tasks whose
                    // ordering is not guaranteed, and L1's whole point was a bar
                    // that never lies about direction.
                    let advanced = max(self.preloadFraction ?? 0, min(1, max(0, fraction)))
                    self.preloadFraction = advanced
                    onProgress(advanced)
                }
            }
        } catch {
            // Cancelled, or the read failed. Either way the array is still
            // streaming and still usable; the open continues.
        }
        // A `reset()` (dataset replaced) while this preload was in flight means
        // this object now describes a different dataset. Publishing here would
        // stamp the old cube's residency onto the new one.
        guard self.generation == generation else { return false }
        await sync(with: data)
        return isResident
    }

    /// Drop the cube and return to streaming. Safe at any time.
    package func release(_ data: FourDArray?) async {
        guard let data else { return }
        await data.releaseResident()
        await sync(with: data)
    }

    /// Publish what the array actually holds — never what was requested.
    private func sync(with data: FourDArray) async {
        isResident = await data.isResident
        byteCount = await data.residentByteCount
    }
}
