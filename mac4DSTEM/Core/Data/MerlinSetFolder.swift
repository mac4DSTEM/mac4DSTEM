//
//  MerlinSetFolder.swift
//  Role: does a picked .mib belong to a Merlin multi-file save that the App Sandbox does not let the app read yet (mac4DSTEM#120)?
//
//  Merlin's "save to multiple files" writes default1.mib … defaultN.mib beside one default.hdr. The sandbox grants the picked
//  part only; the related-item grant (RelatedFileAccess) covers a sibling of the SAME name, so it cannot reach default.hdr or the
//  other parts. The narrowest grant left is the folder, asked once per window open (App/MerlinSetAccess.swift). Names are
//  visible without a grant (file-read-metadata is broad), so the set is found here; whether each file opens is the test.
//

import Foundation
import Darwin
import FormatoMIB

package nonisolated enum MerlinSetFolder {
    /// What the folder prompt names: how many files the set has and its shared header's name.
    package struct Need: Equatable, Sendable {
        package let files: Int
        package let header: String
        package let folder: URL
    }

    /// The set `url` belongs to when one of its files (the header or a part) cannot be opened for reading; nil for any other
    /// file, and for a set every file of which opens (outside the sandbox, or once the folder is granted).
    package static func unreadableSet(for url: URL) -> Need? {
        guard url.pathExtension.lowercased() == "mib", let set = MerlinSet.containing(url.path) else { return nil }
        guard !([set.header] + set.parts).allSatisfy(canOpen) else { return nil }
        return Need(files: set.parts.count + 1, header: URL(fileURLWithPath: set.header).lastPathComponent,
                    folder: url.deletingLastPathComponent())
    }

    /// Opens and closes the file: the sandbox answers EPERM here for a file it has not granted, where a metadata check says yes.
    package static func canOpen(_ path: String) -> Bool {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }
}
