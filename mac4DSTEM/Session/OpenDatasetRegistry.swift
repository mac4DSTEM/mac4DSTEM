//
//  OpenDatasetRegistry.swift
//  Role: Which dataset files the windows of this process hold open, so a second
//        window cannot open one another window holds (review a6, owner card D2
//        answer a, 2026-10-02). Two windows on one dataset share one session
//        sidecar, and the second save silently replaced the first window's
//        recipe, lineage, calibration and labels.
//
//  Process-wide and main-actor, the `DetectorTrainingSession.liveSessions`
//  shape: each window's state graph enrols itself (`AppState.init`) and is held
//  WEAKLY, so a closed window drops out on its own; its window also withdraws it
//  on close, so a state graph something else still retains cannot keep a file
//  locked. What a window holds is read LIVE through the closure it enrolled with
//  (its loaded dataset, a configured open waiting in Open with Options…) — never
//  cached, so a window that opened another file, cancelled, or closed holds
//  nothing without having to say so. An open in flight claims its file for its
//  own duration (`beginOpening`/`endOpening`): nothing in the window names the
//  file until the reader has discovered it.
//
//  Identity, not spelling: a symlink, a hard link and a case-different path are
//  one file. The volume's file identifier (device and inode) decides when both
//  files exist; the symlink-resolved, standardized path decides as well, so a
//  file replaced at the same path (same sidecar) still counts.
//

import Foundation

@MainActor
package enum OpenDatasetRegistry {

    /// One window's claims: `held` is asked on every question, `opening` lists
    /// its opens in flight (a path per call, removed once each).
    private final class Holder {
        weak var owner: AnyObject?
        var held: @MainActor () -> [String]
        var opening: [String] = []
        init(owner: AnyObject, held: @escaping @MainActor () -> [String]) {
            self.owner = owner
            self.held = held
        }
    }

    private static var holders: [Holder] = []

    /// Enrols `owner`; a second call for the same owner replaces its reader.
    package static func enroll(_ owner: AnyObject, held: @escaping @MainActor () -> [String]) {
        holders.removeAll { $0.owner == nil }
        if let existing = holders.first(where: { $0.owner === owner }) {
            existing.held = held
        } else {
            holders.append(Holder(owner: owner, held: held))
        }
    }

    /// Drops `owner` and everything it claimed (its window closed).
    package static func withdraw(_ owner: AnyObject) {
        holders.removeAll { $0.owner == nil || $0.owner === owner }
    }

    /// Claims `url` for an open `owner` has in flight; pair with `endOpening`.
    package static func beginOpening(_ url: URL, by owner: AnyObject) {
        holders.first { $0.owner === owner }?.opening.append(url.path)
    }

    package static func endOpening(_ url: URL, by owner: AnyObject) {
        guard let holder = holders.first(where: { $0.owner === owner }),
              let index = holder.opening.firstIndex(of: url.path) else { return }
        holder.opening.remove(at: index)
    }

    /// The path another live window holds that names the same file as `url`.
    package static func otherHolder(of url: URL, excluding owner: AnyObject) -> String? {
        holders.removeAll { $0.owner == nil }
        for holder in holders where holder.owner !== owner {
            for path in holder.held() + holder.opening
            where sameFile(url, URL(fileURLWithPath: path)) {
                return path
            }
        }
        return nil
    }

    /// The one line an open of `url` by `owner` is refused with, or nil when no
    /// other window holds that file. Names the other window's dataset; a second
    /// name for it (a link, an EMPAD .xml beside its .raw) is said as such.
    package static func refusal(opening url: URL, by owner: AnyObject) -> String? {
        guard let held = otherHolder(of: url, excluding: owner) else { return nil }
        let requested = url.lastPathComponent
        let theirs = URL(fileURLWithPath: held).lastPathComponent
        let subject = requested == theirs
            ? theirs : "\(requested) is the same file as \(theirs), which"
        return "\(subject) is already open in another window — use that window, or close it first."
    }

    /// One file under two names? Symlinks are resolved first: a link's own
    /// resource identifier is the link's, not its target's.
    package nonisolated static func sameFile(_ a: URL, _ b: URL) -> Bool {
        let first = a.resolvingSymlinksInPath().standardizedFileURL
        let second = b.resolvingSymlinksInPath().standardizedFileURL
        if first.path == second.path { return true }
        guard let one = identifier(of: first), let other = identifier(of: second) else { return false }
        return one.isEqual(other)
    }

    private nonisolated static func identifier(of url: URL) -> (any NSObjectProtocol)? {
        (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
    }
}
