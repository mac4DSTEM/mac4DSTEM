//
//  CompanionFolderAccess.swift
//  Role: ask once for the folder of a dataset whose companions have other names, under the App Sandbox (mac4DSTEM#120).
//
//  A picked default17.mib is one of 64 parts beside default.hdr; a picked acquisition_1.xml names scan_x256_y256.raw. The sandbox
//  grants the picked file only (Core/Data/CompanionFolder.swift). The app asks for the folder with an Open panel already showing
//  it, the way sandboxed Mac apps ask for a folder a document needs; the user's choice is the grant. The folder's scope is held
//  for the app's life, as RelatedFileAccess holds its presenters: a mapped file can be reopened later. Outside the sandbox every
//  file opens and nothing is asked.
//

import AppKit
import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
#endif

@MainActor
enum CompanionFolderAccess {
    /// Folders granted this run, held open for the app's life.
    private static var held: [URL] = []

    /// Returns when `url`'s companions can be read (or it has none of another name); throws a sentence when the user declines
    /// or grants another folder.
    static func grantFolderIfNeeded(for url: URL) async throws {
        guard let need = CompanionFolder.need(for: url) else { return }
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
            throw SimpleError("\(url.lastPathComponent) is \(need.description). mac4DSTEM reads them only with access to their "
                + "folder: open it again and allow the folder.")
        }
        if folder.startAccessingSecurityScopedResource() { held.append(folder) }
        guard CompanionFolder.need(for: url) == nil else {
            throw SimpleError("The folder chosen is not the one that holds \(url.lastPathComponent). Open it again and allow its own folder.")
        }
    }
}
