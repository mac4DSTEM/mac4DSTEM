//
//  MerlinSetAccess.swift
//  Role: ask once for the folder of a Merlin multi-file save under the App Sandbox (mac4DSTEM#120).
//
//  A picked default17.mib is one of 64 parts beside default.hdr; the sandbox grants that one file (Core/Data/MerlinSetFolder.swift).
//  The app asks for the folder with an Open panel already showing it, the way sandboxed Mac apps ask for a folder a document
//  needs; the user's choice is the grant. The folder's scope is held for the app's life, as RelatedFileAccess holds its
//  presenters: a mapped part can be reopened later. Outside the sandbox every file opens and nothing is asked.
//

import AppKit
import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
#endif

@MainActor
enum MerlinSetAccess {
    /// Folders granted this run, held open for the app's life.
    private static var held: [URL] = []

    /// Returns when the set `url` belongs to can be read (or `url` is no set); throws a sentence when the user declines or
    /// grants another folder.
    static func grantFolderIfNeeded(for url: URL) async throws {
        guard let need = MerlinSetFolder.unreadableSet(for: url) else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = need.folder
        panel.prompt = "Allow"
        panel.message = "\(url.lastPathComponent) is one of \(need.files) files of a Merlin acquisition (with \(need.header)). "
            + "To open them as one scan, allow mac4DSTEM to read this folder."
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        let declined = SimpleError("\(url.lastPathComponent) is one of \(need.files) files of a Merlin acquisition. mac4DSTEM reads "
            + "them only with access to their folder; open it again and allow the folder.")
        guard response == .OK, let folder = panel.url else { throw declined }
        if folder.startAccessingSecurityScopedResource() { held.append(folder) }
        guard MerlinSetFolder.unreadableSet(for: url) == nil else {
            throw SimpleError("The folder chosen is not the one that holds \(need.header). Open \(url.lastPathComponent) again and "
                + "allow its own folder.")
        }
    }
}
