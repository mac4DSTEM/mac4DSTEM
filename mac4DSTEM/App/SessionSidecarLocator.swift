//
//  SessionSidecarLocator.swift
//  Role: The one owner of "where is this dataset's session sidecar, and may I
//        read it?" — the derived sibling path, the security-scoped bookmark
//        that grants access to it, and the scoped URL currently held open.
//
//  This is S1's `AppState` seam (docs/development-process.md §7), and it is the
//  seam this session earned rather than a convenient one: the defect S1 fixes is
//  literally that the same question was answered in two different ways.
//
//  THE DEFECT THIS TYPE MAKES UNLIKELY — not unrepresentable, and the first
//  version of this header claimed the stronger thing. `sessionSidecarURL` is
//  still public and still callable, so a new call site can bypass this type the
//  same way the old ones did; what changed is that every EXISTING one goes
//  through it. Gate D found a ninth site doing exactly that
//  (`UI/InspectorPanels.swift`), which the first version of this comment had
//  missed while asserting completeness. Nine call sites needed a sidecar URL.
//  Eight spelled it
//
//      resolvedSessionSidecarURL(for: descriptor)
//          ?? BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: descriptor.filePath)
//
//  and the eighth — `AppState.recordedLoadSpecification`, the one that decides
//  WHAT PART OF THE FILE TO LOAD — went straight to the derived path and never
//  consulted the bookmark at all. So a sidecar the app had been granted access
//  to could be read for results and calibration, and simultaneously be
//  unreadable for the crop that produced them. That is the `sources.manifest`
//  lesson in app code: one question, several spellings, and the odd one out is
//  the one nobody re-reads.
//
//  WHY THAT MATTERED MORE THAN "restore failed". `recordedLoadSpecification`
//  swallowed the failure with `try?`, so a refused read was indistinguishable
//  from "this session recorded no crop" — and the dataset then opened at FULL
//  EXTENT, silently, while the sidecar beside it said it was a cropped view.
//  Right numbers, wrong extent, no warning. The refusal rule's own words: a gate
//  whose miss path records an error and continues is not a gate.
//
//  THE SANDBOX FACT UNDERNEATH, measured rather than assumed (2026-08-19,
//  docs/open-items.md). The app holds `files.user-selected.read-write` only. The
//  user picks the *source* cube in a panel; the sidecar is a SIBLING they never
//  picked, so it is reachable only through a bookmark stored when they chose it
//  in a save panel. With no bookmark, `FileManager.fileExists` still returns
//  true — `application.sb:508` grants `file-read-metadata` broadly — and then
//  `H5Fopen` fails with **errno 1, EPERM, "Operation not permitted"**. Observed
//  in the running app at 09:34:27 that day, not inferred. Anything here that
//  treats "the file is there" as "I can read it" is wrong for that reason.
//
//  **EPERM is not by itself proof of the sandbox**, and saying so would be
//  affirming the consequent: `tools/sidecar-error-detail-test` establishes
//  "sandbox denial implies EPERM", not the converse. EPERM is a kernel
//  MAC-policy refusal; on this path SIP, TCC, quarantine, ACLs and file flags
//  were each excluded individually (Gate D, 2026-08-19 — including the decisive
//  one, that the source cube in the same directory opened fine at the same
//  instant), which leaves the sandbox as the only MAC policy in play. The
//  classification below is a heuristic for choosing what to TELL the user, and
//  it is worth nothing more than that.
//

import Foundation

@Observable
final class SessionSidecarLocator {

    /// The scoped URL currently held open, WITH the source path it was resolved
    /// for.
    ///
    /// **The pairing is the fix for a second defect, not bookkeeping.** The
    /// previous cache was a bare `scopedSessionSidecarURL` consulted before the
    /// descriptor was even looked at (`ResultExport.swift:81`), so once any
    /// dataset's bookmark resolved, *every* later dataset was handed that same
    /// sidecar — one cube's results written into another cube's companion. It
    /// was masked only because no bookmark resolved at all after the
    /// bundle-identifier change, and it would have armed itself the moment one
    /// did, which is the moment S1's fix creates. Recorded as its own item on
    /// 2026-08-19; closed here because the seam is where it lives.
    @ObservationIgnored private var scoped: (sourcePath: String, url: URL)?

    /// Whether a grant is currently held.
    ///
    /// Nothing in `mac4DSTEM/` reads this yet — only tests do. Said plainly
    /// because the first version of this comment claimed it was "observable so
    /// the UI can say whether the companion is reachable", describing a UI that
    /// does not exist (Gate D, 2026-08-19). It is kept because it is the natural
    /// signal for the affordance S4 will need — "this sidecar is reachable" —
    /// and deleting it now to re-add it then is churn; but until then it is
    /// state with one reader, and that is worth knowing.
    private(set) var hasGrant = false

    /// Set when a sidecar exists beside the dataset and could not be read, so
    /// the inspector can say the loaded extent may not be the recorded one.
    ///
    /// **This exists because `statusText` does not survive.** S1's first attempt
    /// reported the refusal there; Gate D traced the actual sequence and found
    /// it overwritten three lines later — `recordedLoadSpecification`
    /// (`AppState.swift:1838`) is followed immediately by `activate`
    /// (`:1841`), whose `beginDatasetLoadingStage` assigns `statusText`, and then
    /// again by preview sampling and the whole-cube pass. The user never saw a
    /// frame carrying the warning. A message that is written and then
    /// overwritten before it can be read is not a warning; it is a log line, and
    /// this session's whole point is that a silent full-extent reopen must not
    /// stay silent.
    ///
    /// Cleared by `release()`, i.e. when the open dataset changes, so it can
    /// never describe a dataset other than the one on screen.
    private(set) var unreadableReason: String?

    /// Where bookmarks are persisted.
    ///
    /// Injectable for one reason, and it is the reason C10 exists: this store is
    /// keyed by bundle identifier, and a test that wrote into the real
    /// `UserDefaults.standard` would both pollute the user's defaults and be
    /// unable to prove the KEY is right — which Gate D showed was untested while
    /// being the single string the whole diagnosis is indexed by.
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
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
    func location(for descriptor: DatasetDescriptor) -> URL {
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
    func location(forSourcePath path: String) -> URL {
        grant(forSourcePath: path)
            ?? BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: path)
    }

    /// The bookmark-resolved URL for `descriptor`, or nil when the app has no
    /// grant for this dataset's sidecar.
    ///
    /// nil is the *normal* answer for a dataset whose sidecar has never been
    /// saved from this app installation — including every dataset after a
    /// bundle-identifier change, which replaces the container and so empties
    /// `UserDefaults` (the 2026-08-14 `1e5727d` change; docs/open-items.md C10).
    func grant(for descriptor: DatasetDescriptor) -> URL? {
        grant(forSourcePath: descriptor.filePath)
    }

    /// The granted URL for a source path, or nil when there is no grant.
    func grant(forSourcePath path: String) -> URL? {
        // Keyed by source path. The cache is only valid for the dataset it was
        // resolved for — see `scoped`.
        if let scoped, scoped.sourcePath == path { return scoped.url }

        guard let data = defaults.data(forKey: Self.bookmarkKey(path)) else {
            return nil
        }
        var stale = false
        do {
            // `.withoutMounting` for the same reason as
            // `WorkspaceRecoveryStore.resolve` (Gate D, 2026-08-25): this
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
            // a new trigger (Gate D second reader, 2026-08-25). Unmounted
            // keeps the key; the grant simply is not available right now.
            if WorkspaceRecoveryStore.unmountedVolumeName(forBookmark: data) == nil {
                defaults.removeObject(forKey: Self.bookmarkKey(path))
            }
            return nil
        }
    }

    /// Record that a sidecar was found and could not be read.
    func noteUnreadable(_ reason: String) {
        unreadableReason = reason
    }

    // MARK: - Grants

    /// Hold `url` as the grant for `descriptor`, releasing any previous one.
    func adopt(_ url: URL, for descriptor: DatasetDescriptor) {
        adopt(url, forSourcePath: descriptor.filePath)
    }

    func adopt(_ url: URL, forSourcePath path: String) {
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
    func remember(_ url: URL, for descriptor: DatasetDescriptor) throws {
        try remember(url, forSourcePath: descriptor.filePath)
    }

    func remember(_ url: URL, forSourcePath path: String) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: Self.bookmarkKey(path))
    }

    /// Drop the held grant. Called when the open dataset changes.
    func release() {
        scoped?.url.stopAccessingSecurityScopedResource()
        scoped = nil
        hasGrant = false
        unreadableReason = nil
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
enum SessionSidecarReadFailure: Equatable {
    /// The sandbox refused the file. EPERM, errno 1, "Operation not permitted".
    case notPermitted
    /// It failed for some other reason — corrupt, truncated, wrong format.
    case unreadable

    /// Classify an error thrown while opening a sidecar.
    ///
    /// Matched on the HDF5 error detail S1 added to the six sidecar read throw
    /// sites, which carries the innermost frame verbatim — including
    /// `errno = 1, error message = 'Operation not permitted'`. Matching on
    /// **errno rather than the message text** is deliberate: the message is
    /// localised by `strerror`, the number is not. The measured distinction that
    /// makes this worth classifying at all is that a sandbox denial is EPERM (1)
    /// while an ordinary POSIX permission problem is EACCES (13) — established
    /// by `tools/sidecar-error-detail-test`, whose first version asserted the
    /// wrong one of the two and would have sent the diagnosis the other way.
    static func classify(_ error: Error) -> SessionSidecarReadFailure {
        let text = "\(error)" + " " + error.localizedDescription
        return text.contains("errno = 1,") ? .notPermitted : .unreadable
    }

    /// What to tell the user, naming the remedy rather than the mechanism.
    func explanation(sidecar: String) -> String {
        switch self {
        case .notPermitted:
            return "\(sidecar) sits beside this dataset but mac4DSTEM has not been "
                + "granted access to it. Save the session once (File ▸ Save Calibration "
                + "to Session Sidecar) and choose that file, which grants access for "
                + "future opens."
        case .unreadable:
            return "\(sidecar) could not be read."
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
enum RecordedSpecificationOutcome: Equatable {
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
    static func recordedOutcome(
        from read: Result<LoadSpecification?, Error>, sidecar: String
    ) -> RecordedSpecificationOutcome {
        switch read {
        case .failure(let error):
            // NEVER `.noneRecorded`. "I could not read it" is not "there was
            // nothing to read", and the whole point of this type is that the
            // caller cannot accidentally treat them alike.
            return .unreadable(
                SessionSidecarReadFailure.classify(error).explanation(sidecar: sidecar)
                    + " Loading the whole dataset."
            )
        case .success(let specification):
            guard let specification, !specification.isFullExtent else { return .noneRecorded }
            return .recorded(specification)
        }
    }
}
