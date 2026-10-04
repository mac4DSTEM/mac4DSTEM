//
//  SessionSidecarLocator.swift
//  Role: The one owner of "where is this dataset's session sidecar, and may I
//        read it?" — the derived sibling path, the security-scoped bookmark
//        that grants access to it, and the scoped URL currently held open.
//
//  This is the `AppState` seam for that question (docs/archive/development-process-2026-08-31.md §7).
//
//  `sessionSidecarURL` is still public and callable, so a new call site can
//  still bypass this type — what this type guarantees is only that every
//  EXISTING call site goes through it. Before it existed, nine call sites
//  needed a sidecar URL. Eight spelled it
//
//      resolvedSessionSidecarURL(for: descriptor)
//          ?? BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: descriptor.filePath)
//
//  and the ninth — `AppState.recordedLoadSpecification`, the one that decides
//  WHAT PART OF THE FILE TO LOAD — went straight to the derived path and never
//  consulted the bookmark at all. So a sidecar the app had been granted access
//  to could be read for results and calibration, and simultaneously be
//  unreadable for the crop that produced them: one question, several
//  spellings, and the odd one out is the one nobody re-reads.
//
//  That mattered more than "restore failed" because `recordedLoadSpecification`
//  swallowed the failure with `try?`, so a refused read was indistinguishable
//  from "this session recorded no crop" — and the dataset then opened at FULL
//  EXTENT, silently, while the sidecar beside it said it was a cropped view.
//  Right numbers, wrong extent, no warning. A gate whose miss path records an
//  error and continues is not a gate.
//
//  THE SANDBOX FACT UNDERNEATH, measured (docs/open-items.md). The app holds
//  `files.user-selected.read-write` only. The user picks the *source* cube in
//  a panel; the sidecar is a SIBLING they never picked, so it is reachable
//  only through a bookmark stored when they chose it in a save panel. With no
//  bookmark, `FileManager.fileExists` still returns true —
//  `application.sb:508` grants `file-read-metadata` broadly — and then
//  `H5Fopen` fails with **errno 1, EPERM, "Operation not permitted"**,
//  observed directly in the running app, not inferred. Anything here that
//  treats "the file is there" as "I can read it" is wrong for that reason.
//
//  **EPERM is not by itself proof of the sandbox**, and saying so would be
//  affirming the consequent: `tools/sidecar-error-detail-test` establishes
//  "sandbox denial implies EPERM", not the converse. EPERM is a kernel
//  MAC-policy refusal; on this path SIP, TCC, quarantine, ACLs and file flags
//  were each excluded individually (Gate D — including the decisive one, that
//  the source cube in the same directory opened fine at the same instant),
//  which leaves the sandbox as the only MAC policy in play. The
//  classification below is a heuristic for choosing what to TELL the user,
//  and it is worth nothing more than that.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// Domain, code and underlying error, not just the localized text. A bare
/// `localizedDescription` reads identically to a real sandbox denial — the
/// trap that motivated this (docs/open-items.md, "could not remember
/// access"). Lives in `Session/`, not `App/AppState`, because
/// `AppState.errorDetail` (`Support/ResultExport.swift`) calls this same
/// function rather than duplicating it, and `Session/` may not depend on
/// `App/` (architecture.md's layering rule) while `App/` may depend on
/// `Session/`.
///
/// The domain and code are for a system `NSError`, where the real cause hides
/// (-67034 did). The app's own Swift errors already say what happened in their
/// `errorDescription`; their bridged "domain" is a type name and their code an
/// enum index, so they read as written (driven 2026-09-30: every refusal read
/// "mac4DSTEM.SimpleError 1: …" or "DSTEMCore.EllipseCalibration.FitError 0: …").
package nonisolated func sessionErrorDetail(_ error: Error) -> String {
    let ns = error as NSError
    var text = "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    if !(type(of: error) is NSError.Type),
       let sentence = (error as? LocalizedError)?.errorDescription {
        text = sentence
    }
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
        text += " (underlying: \(underlying.domain) \(underlying.code))"
    }
    return text
}

@Observable
package final class SessionSidecarLocator {

    /// The scoped URL currently held open, WITH the source path it was resolved
    /// for.
    ///
    /// **The pairing is the fix for a second defect, not bookkeeping.** A bare
    /// cached URL consulted before the descriptor was even looked at
    /// (`ResultExport.swift:81`) let any dataset's resolved bookmark get
    /// handed to *every* later dataset — one cube's results written into
    /// another cube's companion. Pairing the URL with the source path it was
    /// resolved for is what makes that mismatch impossible rather than just
    /// unlikely.
    @ObservationIgnored private var scoped: (sourcePath: String, url: URL)?

    /// Whether a grant is currently held.
    ///
    /// Nothing in `mac4DSTEM/` reads this yet — only tests do. Kept because it
    /// is the natural signal for the affordance S4 will need ("this sidecar
    /// is reachable"), and deleting it now to re-add it then would be churn.
    package private(set) var hasGrant = false

    /// Whether this app wrote (or re-homed) the open dataset's sidecar since the
    /// dataset was opened. The Session sidebar says "Saved with the dataset"
    /// rather than "Loaded ... from earlier analysis" while this is true; the
    /// file may still carry earlier analysis too. Set by `noteWritten()` after
    /// a successful write, cleared by `release()` when the dataset changes.
    package private(set) var wroteThisSession = false

    package func noteWritten() { wroteThisSession = true }

    /// Set when a sidecar exists beside the dataset and could not be read, so
    /// the inspector can say the loaded extent may not be the recorded one.
    ///
    /// **This exists because `statusText` does not survive.** A refusal
    /// reported only through `statusText` gets overwritten within the same
    /// `activate` call — `recordedLoadSpecification` (`AppState.swift:1838`)
    /// is followed immediately by `activate` (`:1841`), whose
    /// `beginDatasetLoadingStage` assigns `statusText`, then preview sampling
    /// and the whole-cube pass do again. The user never sees a frame
    /// carrying the warning. A message written and then overwritten before
    /// it can be read is a log line, not a warning, and a silent
    /// full-extent reopen must not stay silent.
    ///
    /// Cleared by `release()`, i.e. when the open dataset changes, so it can
    /// never describe a dataset other than the one on screen.
    package private(set) var unreadableReason: String?

    /// Where bookmarks are persisted.
    ///
    /// Injectable for one reason, and it is the reason C10 exists: this store is
    /// keyed by bundle identifier, and a test that wrote into the real
    /// `UserDefaults.standard` would both pollute the user's defaults and be
    /// unable to prove the KEY is right — which Gate D showed was untested while
    /// being the single string the whole diagnosis is indexed by.
    @ObservationIgnored private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Where the sidecar is

    /// The sidecar's location for `descriptor`, preferring a granted URL and
    /// falling back to the derived sibling.
    ///
    /// Never nil, and deliberately so: the fallback is a real, well-defined path
    /// that may or may not be readable, and callers that need to know *which*
    /// they got must ask `grant(for:)`. This is the single derivation the eight
    /// former call sites now share.
    package func location(for descriptor: DatasetDescriptor) -> URL {
        location(forSourcePath: descriptor.filePath)
    }

    /// The same question keyed by source path.
    ///
    /// **The path is the primitive here, not a convenience overload:** the
    /// bookmark key has always been derived from the absolute source path, and
    /// `recordedLoadSpecification` runs before the app has committed to a
    /// descriptor — it is deciding what to load. Making the path form the real
    /// one is what lets that call site use the same derivation as every other,
    /// which is the whole point of this type.
    package func location(forSourcePath path: String) -> URL {
        grant(forSourcePath: path)
            ?? BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: path)
    }

    /// The bookmark-resolved URL for `descriptor`, or nil when the app has no
    /// grant for this dataset's sidecar.
    ///
    /// nil is the *normal* answer for a dataset whose sidecar has never been
    /// saved from this app installation — including every dataset after a
    /// bundle-identifier change, which replaces the container and so empties
    /// `UserDefaults` (docs/open-items.md C10).
    package func grant(for descriptor: DatasetDescriptor) -> URL? {
        grant(forSourcePath: descriptor.filePath)
    }

    /// The granted URL for a source path, or nil when there is no grant.
    package func grant(forSourcePath path: String) -> URL? {
        // Keyed by source path. The cache is only valid for the dataset it was
        // resolved for — see `scoped`.
        if let scoped, scoped.sourcePath == path { return scoped.url }

        guard let data = defaults.data(forKey: Self.bookmarkKey(path)) else {
            return nil
        }
        var stale = false
        do {
            // `.withoutMounting` for the same reason as
            // `WorkspaceRecoveryStore.resolve` (Gate D): this
            // runs synchronously on the main actor inside every open's
            // sidecar lookup, and a grant pointing at an unmounted network
            // volume otherwise blocks the UI ~30 s per attempt while the
            // system tries to mount it. A sidecar on an absent volume is
            // unreadable NOW — fast failure is the honest answer, and the
            // catch below already clears the dead key.
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            _ = url.startAccessingSecurityScopedResource()
            adopt(url, forSourcePath: path)
            if stale { try remember(url, forSourcePath: path) }
            return url
        } catch {
            // Forget the grant ONLY when the target is genuinely gone. A
            // sidecar legitimately living on a NAS (Save Session Sidecar
            // As… places no constraint on the destination) resolves fast-
            // fail here while the share is unplugged — deleting the key
            // then would silently re-target this dataset to the derived
            // local sibling, which does not exist, and the next open would
            // read as "no session recorded": the exact silent-full-extent
            // class this type's header exists to prevent, re-armed through
            // a new trigger (Gate D second reader). Unmounted keeps the
            // key; the grant simply is not available right now.
            if WorkspaceRecoveryStore.unmountedVolumeName(forBookmark: data) == nil {
                defaults.removeObject(forKey: Self.bookmarkKey(path))
            }
            return nil
        }
    }

    /// Record that a sidecar was found and could not be read.
    package func noteUnreadable(_ reason: String) {
        unreadableReason = reason
    }

    // MARK: - Grants

    /// Hold `url` as the grant for `descriptor`, releasing any previous one.
    package func adopt(_ url: URL, for descriptor: DatasetDescriptor) {
        adopt(url, forSourcePath: descriptor.filePath)
    }

    package func adopt(_ url: URL, forSourcePath path: String) {
        if let scoped, scoped.url != url {
            scoped.url.stopAccessingSecurityScopedResource()
        }
        scoped = (path, url)
        hasGrant = true
    }

    /// Persist a bookmark so this grant survives relaunch.
    ///
    /// Only ever called AFTER atomic publication: Foundation cannot bookmark the
    /// not-yet-existing URL an `NSSavePanel` returns.
    package func remember(_ url: URL, for descriptor: DatasetDescriptor) throws {
        try remember(url, forSourcePath: descriptor.filePath)
    }

    package func remember(_ url: URL, forSourcePath path: String) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: Self.bookmarkKey(path))
    }

    /// Drop the held grant. Called when the open dataset changes.
    package func release() {
        scoped?.url.stopAccessingSecurityScopedResource()
        scoped = nil
        hasGrant = false
        unreadableReason = nil
        wroteThisSession = false
    }

    // MARK: - The bookmark key

    /// Keyed by the **absolute source path**, so moving a dataset invalidates
    /// its grant rather than silently pointing at a sidecar beside the old copy.
    private static func bookmarkKey(_ sourcePath: String) -> String {
        "session-sidecar-bookmark." + Data(sourcePath.utf8).base64EncodedString()
    }
}

// MARK: - Reading refusals

/// Why a sidecar that exists could not be read.
///
/// Exists so the caller can tell "there is no saved session" from "there is one
/// and the sandbox will not let me open it" — two states that
/// `recordedLoadSpecification` previously collapsed into `nil` with `try?`, and
/// the collapse is what let a cropped session reopen silently at full extent.
package enum SessionSidecarReadFailure: Equatable {
    /// The sandbox refused the file. EPERM, errno 1, "Operation not permitted".
    case notPermitted
    /// It failed for some other reason — corrupt, truncated, wrong format.
    case unreadable

    /// Classify an error thrown while opening a sidecar.
    ///
    /// Matched on the HDF5 error detail added to the six sidecar read throw
    /// sites, which carries the innermost frame verbatim — including
    /// `errno = 1, error message = 'Operation not permitted'`. Matching on
    /// **errno rather than the message text** is deliberate: the message is
    /// localised by `strerror`, the number is not. The distinction that makes
    /// this worth classifying at all is measured: a sandbox denial is EPERM
    /// (1) while an ordinary POSIX permission problem is EACCES (13) —
    /// established by `tools/sidecar-error-detail-test`.
    package static func classify(_ error: Error) -> SessionSidecarReadFailure {
        let text = "\(error)" + " " + error.localizedDescription
        return text.contains("errno = 1,") ? .notPermitted : .unreadable
    }

    /// What to tell the user, naming the remedy rather than the mechanism. The remedy is the control that
    /// exists for it: with the sidecar unreadable every save is refused (`sidecarRewriteRefusal`), so "save
    /// the session once" could never work, and the Save commands live in the Dataset menu, not File.
    ///
    /// Production asks `reason(sidecar:error:)`, the one text API; this is the sandbox class's fixed sentence that
    /// `reason` returns. The `.unreadable` arm is not reached from production (that class's text is its raw detail,
    /// built in `reason`); it stays only while `FinalPolishS2Tests` asks this on `.notPermitted` — when that test
    /// asks `reason` instead, the method and the arm go.
    package func explanation(sidecar: String) -> String {
        switch self {
        case .notPermitted:
            return "\(sidecar) sits beside this dataset but mac4DSTEM has not been granted access "
                + "to it by macOS. Choose Allow Access… (sidebar or Dataset menu) and pick that "
                + "file; the dataset then reopens with its session."
        case .unreadable:
            return "\(sidecar) could not be read."
        }
    }

    /// The ONE sentence for "a sidecar is there and could not be read", asked by both places that learn it
    /// (`recordedOutcome` at open, and `AppState.loadSessionSnapshot` in `activate`) — two writers used to say
    /// two things and the later one, the raw HDF5 error stack, won (P5c). A sandbox refusal gets the remedy
    /// and none of the mechanism (the stack goes to the activity log); any other failure keeps its raw
    /// detail, the only clue there is.
    package static func reason(sidecar: String, error: Error) -> String {
        let failure = classify(error)
        switch failure {
        case .notPermitted: return failure.explanation(sidecar: sidecar)
        case .unreadable: return "Could not restore \(sidecar): \(sessionErrorDetail(error))"
        }
    }
}


// MARK: - What a failed read MEANS

/// The outcome of asking a sidecar what part of the file a session recorded.
///
/// **Three cases, because collapsing them to two is the defect.** Before S1 this
/// decision was a `try?` inside `AppState.recordedLoadSpecification`, which made
/// `unreadable` indistinguishable from `noneRecorded` — so a sidecar saying "this
/// was a cropped view" that the sandbox refused to open produced the same answer
/// as no sidecar at all, and the dataset opened at FULL EXTENT in silence.
///
/// This lives here, as a pure function over an already-performed read, for a
/// reason that is about testing and worth stating: the I/O cannot be exercised
/// in the unit target — no test in `mac4DSTEMTests` opens a real HDF5 file, and
/// EPERM needs a genuinely sandboxed process — but the DECISION can be, and the
/// decision is where the defect lived. Verified by breaking it: making
/// `unreadable` return `noneRecorded` reproduces the silent full-extent load and
/// fails `SessionSidecarLocatorTests`.
package enum RecordedSpecificationOutcome: Equatable {
    /// No sidecar, or one that records the full extent. Load the whole file.
    case noneRecorded
    /// The session recorded this reduced specification.
    case recorded(LoadSpecification)
    /// A sidecar is there and could not be read. Carries what to tell the user.
    case unreadable(String)
}

extension SessionSidecarLocator {

    /// Interpret the result of reading a sidecar's recorded specification.
    ///
    /// `read` is `.success(nil)` when the sidecar opened but recorded nothing.
    package static func recordedOutcome(
        from read: Result<LoadSpecification?, Error>, sidecar: String
    ) -> RecordedSpecificationOutcome {
        switch read {
        case .failure(let error):
            // NEVER `.noneRecorded`. "I could not read it" is not "there was
            // nothing to read", and the whole point of this type is that the
            // caller cannot accidentally treat them alike.
            return .unreadable(
                SessionSidecarReadFailure.reason(sidecar: sidecar, error: error)
                    + " Loading the whole dataset."
            )
        case .success(let specification):
            guard let specification, !specification.isFullExtent else { return .noneRecorded }
            return .recorded(specification)
        }
    }

    /// How moving the sidecar file itself went. `nothingToCopy` is a normal
    /// outcome (no sidecar has been written yet), not a failure. Moved from
    /// `AppState.SidecarCopyOutcome` (C7 session 4, budget relocation) — pure
    /// Foundation file work with no AppState dependency.
    package nonisolated enum SidecarCopyOutcome: Equatable {
        case copied
        case nothingToCopy
        case failed(String)
    }

    /// Copy the existing sidecar to the newly chosen URL, replacing what the
    /// user agreed to replace in the save panel. Copy, never move: the
    /// original stays where it was, because silently deleting the previous
    /// companion would be the one destructive step in an otherwise reversible
    /// gesture. Moved from `AppState.copySidecarFile` (C7 session 4, budget
    /// relocation).
    /// One file under two spellings (a symlink, a case-differing path): by file identity, never by path string.
    /// The test "Save As… chose the sidecar it already had" and "Allow Access… chose this dataset's sidecar" both
    /// rest on it; a name test would let a sidecar of another cube be read as this one's session.
    package nonisolated static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        BraggVectorEMDWriter.isSameFile(a, b)
    }

    package nonisolated static func copySidecarFile(from current: URL, to url: URL) -> SidecarCopyOutcome {
        let manager = FileManager.default
        guard current != url, manager.fileExists(atPath: current.path) else {
            return .nothingToCopy
        }
        // Same-FILE guard by filesystem identity, not by path string: a
        // case-insensitive APFS volume or a symlink alias spells one file two
        // ways, and a string comparison here would REMOVE the only sidecar and
        // then fail to copy it — the user asked for a rename and got a
        // deletion. Identity is unreadable only when `url` does not exist yet,
        // which is exactly the case where removing nothing is safe.
        if let currentIdentity = try? current.resourceValues(
               forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
           let chosenIdentity = try? url.resourceValues(
               forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
           currentIdentity.isEqual(chosenIdentity) {
            return .nothingToCopy
        }
        // Copy into a scratch file on the destination's volume, THEN rename it over the destination (review
        // 2026-10-02 a1): the destination is never removed before a complete copy exists, so a failed copy (an
        // unreadable current sidecar — the very state this remedy is offered for) leaves it untouched. The scratch
        // directory is the one the writer's publish uses (`.itemReplacementDirectory`: sandbox-writable, same volume).
        let scratchDirectory = try? manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                appropriateFor: url, create: true)
        let temporary = (scratchDirectory ?? url.deletingLastPathComponent())
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer {
            // try? OK: best-effort scratch cleanup; after a successful rename the temporary no longer exists.
            try? manager.removeItem(at: temporary)
            if let scratchDirectory { try? manager.removeItem(at: scratchDirectory) }
        }
        do {
            try manager.copyItem(at: current, to: temporary)
        } catch {
            return .failed(sessionErrorDetail(error) + " The chosen destination was not changed.")
        }
        let status = temporary.path.withCString { source in
            url.path.withCString { target in Darwin.rename(source, target) }
        }
        guard status == 0 else {
            return .failed(String(cString: strerror(errno)) + " The chosen destination was not changed.")
        }
        return .copied
    }

    /// Why the sidecar save panel may not adopt `url`: it is the dataset itself (review 2026-10-02 a1 — a first save
    /// renamed a session file over the raw cube; Change… removed it). Only the SOURCE is refused: the sidecar's own
    /// default path is this panel's correct answer, so `BraggVectorEMDWriter.exportDestinationRefusal` (which also
    /// refuses the sidecar) is the wrong test here. By file identity, so a symlink to the dataset is refused too.
    package nonisolated static func sidecarDestinationRefusal(_ url: URL, sourcePath: String) -> String? {
        guard isSameFile(url, URL(fileURLWithPath: sourcePath)) else { return nil }
        return "Choose a different file: \(url.lastPathComponent) is the dataset itself, which is never changed."
    }

    /// The cancellable operations (`AppState.beginCancellableOperation` names, `Support/ResultExport.swift`) that
    /// rewrite the session sidecar. Opening another dataset resets the operation centre and cancels them before
    /// they publish (review 2026-10-02 c4), so the open commands are refused while one runs.
    package nonisolated static let saveOperationNames: Set<String> = [
        "Session sidecar", "Session calibration", "Session result removal",
    ]

    /// Whether `activeOperation` (the operation centre's current name) is a sidecar save that opening another
    /// dataset would cancel.
    package nonisolated static func isSaveInFlight(_ activeOperation: String?) -> Bool {
        activeOperation.map(saveOperationNames.contains) ?? false
    }

    /// Whether the sidebar may say "Nothing saved yet" (review 2026-10-02 e10): not while a session file beside the
    /// dataset could not be read — something IS saved there, and the warning above already says so.
    package func mayClaimNothingSaved(hasSidecar: Bool) -> Bool {
        !hasSidecar && unreadableReason == nil
    }
}
