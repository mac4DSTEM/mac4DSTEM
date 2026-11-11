//
//  CompanionFolderAccess.swift
//  Role: ask once for the folder of a dataset whose companions have other names, under the App Sandbox (mac4DSTEM#120).
//
//  A picked default17.mib is one of 64 parts beside default.hdr; a picked acquisition_1.xml names scan_x256_y256.raw. The sandbox
//  grants the picked file only (Core/Data/CompanionFolder.swift). The app asks for the folder with an Open panel already showing
//  it, the way sandboxed Mac apps ask for a folder a document needs; the user's choice is the grant. The folder's scope is held
//  for the app's life, as RelatedFileAccess holds its presenters (a mapped file can be reopened later), and kept as an app-scoped
//  bookmark so the folder is asked for once, not once per launch. Outside the sandbox every
//  file opens and nothing is asked.
//

import AppKit
import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
#endif

@MainActor
enum CompanionFolderAccess {
    /// The user's own Cancel at the folder prompt: said in the status line, never as an error alert (AppState.present).
    struct Declined: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Folders granted this run, held open for the app's life.
    private static var held: [URL] = []

    /// App-scoped bookmarks of granted folders, by folder path, so a folder is asked for once, not once per launch.
    private static let bookmarksKey = "CompanionFolderBookmarks"

    /// Returns when `url`'s companions can be read (or it has none of another name); throws a sentence when the user declines
    /// or grants another folder.
    static func grantFolderIfNeeded(for url: URL) async throws {
        guard let need = CompanionFolder.need(for: url) else { return }
        if restoreBookmark(for: need.folder), CompanionFolder.need(for: url) == nil { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = need.folder
        panel.prompt = "Allow"
        panel.message = "\(url.lastPathComponent) is \(need.description). To read them together, allow mac4DSTEM to read this folder."
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let folder = panel.url else {
            throw Declined(message: "Not opened: \(url.lastPathComponent) is \(need.description), and mac4DSTEM reads them only with "
                + "access to their folder.")
        }
        if folder.startAccessingSecurityScopedResource() { held.append(folder) }
        saveBookmark(of: folder)
        guard CompanionFolder.need(for: url) == nil else {
            throw SimpleError("The folder chosen is not the one that holds \(url.lastPathComponent). Open it again and allow its own folder.")
        }
    }

    /// Starts the access a saved bookmark of `folder` (or a folder above it) grants; false when there is none or it no longer resolves.
    private static func restoreBookmark(for folder: URL) -> Bool {
        let saved = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
        let path = folder.standardizedFileURL.path
        guard let (key, data) = saved.first(where: { path == $0.key || path.hasPrefix($0.key + "/") }) else { return false }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
              resolved.startAccessingSecurityScopedResource() else {
            var pruned = saved; pruned[key] = nil
            UserDefaults.standard.set(pruned, forKey: bookmarksKey)
            return false
        }
        held.append(resolved)
        if stale { saveBookmark(of: resolved) }
        return true
    }

    private static func saveBookmark(of folder: URL) {
        // try? OK: without a bookmark the folder is simply asked for again next launch.
        guard let data = try? folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        var saved = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
        saved[folder.standardizedFileURL.path] = data
        UserDefaults.standard.set(saved, forKey: bookmarksKey)
    }
}
