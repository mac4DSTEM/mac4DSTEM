//
//  RelatedFileAccess.swift
//  Role: read access to a dataset's companion file under the App Sandbox (mac4DSTEM#120, App Store item 2).
//
//  The sandbox grants the file the user picked (`files.user-selected.read-write`), not the file beside it. Two formats
//  need a sibling: a Merlin .mib needs its .hdr (scan shape), an EMPAD .xml names its .raw and a picked .raw looks for its
//  .xml. Without a grant the sibling still "exists" (file-read-metadata is broad) and the read fails with EPERM, the same
//  fact SessionSidecarLocator measured for the session sidecar.
//
//  The narrow grant macOS offers for this is the related item: Info.plist declares the companion extensions with
//  `NSIsRelatedItemType`, and a file presenter whose `primaryPresentedItemURL` is the picked file and whose
//  `presentedItemURL` is the sibling (same folder, same name, other extension) gets the sibling's access once it is
//  registered and a coordinated read has run. The presenter stays registered for the app's life: a mapped reader can
//  reopen its file later (DM4Reader's and the vendor readers' `reopen` after a disk comes back).
//

import Foundation

nonisolated final class RelatedFileAccess: NSObject, NSFilePresenter, @unchecked Sendable {
    let primaryPresentedItemURL: URL?
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()

    private init(primary: URL, related: URL) {
        primaryPresentedItemURL = primary
        presentedItemURL = related
        super.init()
    }

    /// The companion extensions each picked extension reads. Info.plist declares the right-hand sides as related item
    /// types; RelatedFileAccessTests holds the two lists together.
    static let companionExtensions: [String: [String]] = [
        "mib": ["hdr"],
        "xml": ["raw"],
        "raw": ["xml"],
    ]

    /// The siblings a picked file may need: same folder and name, each companion extension, upper case when the picked
    /// extension is upper case (SCAN.MIB beside SCAN.HDR). The folder cannot be listed under the sandbox, so the case
    /// follows the picked file rather than a directory read; APFS's default case-insensitivity covers a mixed pair.
    static func companions(of url: URL) -> [URL] {
        let picked = url.pathExtension
        guard let extensions = companionExtensions[picked.lowercased()] else { return [] }
        let upper = !picked.isEmpty && picked == picked.uppercased()
        return extensions.map { url.deletingPathExtension().appendingPathExtension(upper ? $0.uppercased() : $0) }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var held: [String: RelatedFileAccess] = [:]

    /// Registers a presenter for each companion of `url` that is not yet held, and runs one coordinated read so the
    /// sandbox extends the grant. Safe to call for any file: other formats have no companions, and outside the sandbox
    /// the grant is a no-op. Call it while the picked file's own security scope is held.
    static func grant(for url: URL) {
        for related in companions(of: url) {
            let key = related.standardizedFileURL.path
            let presenter: RelatedFileAccess? = lock.withLock {
                guard held[key] == nil else { return nil }
                let presenter = RelatedFileAccess(primary: url, related: related)
                held[key] = presenter
                return presenter
            }
            guard let presenter else { continue }
            NSFileCoordinator.addFilePresenter(presenter)
            var error: NSError?
            NSFileCoordinator(filePresenter: presenter)
                .coordinate(readingItemAt: related, options: .withoutChanges, error: &error) { _ in }
        }
    }
}
