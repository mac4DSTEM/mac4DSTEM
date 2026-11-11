//
//  CompanionFolder.swift
//  Role: does a picked file need companions of ANOTHER name that the App Sandbox does not let the app read yet (mac4DSTEM#120)?
//
//  The sandbox grants the picked file; RelatedFileAccess extends that to a sibling of the SAME name (scan.mib's scan.hdr,
//  scan.xml's scan.raw). Two real layouts name their companions otherwise, and only the folder reaches them
//  (App/CompanionFolderAccess.swift asks once):
//  - Merlin's "save to multiple files": default1.mib … defaultN.mib beside one default.hdr (the public SrTiO3 save, Zenodo 5113449).
//  - An EMPAD .xml whose raw_file names another file: acquisition_1.xml and scan_x256_y256.raw (Zenodo 23890861).
//  Names are visible without a grant (file-read-metadata is broad), so the companions are found here; whether each opens is the test.
//

import Foundation
import Darwin
import FormatoMIB

package nonisolated enum CompanionFolder {
    /// What the folder prompt says: the picked file's companions in words, and the folder that holds them.
    package struct Need: Equatable, Sendable {
        /// "one of 65 files of a Merlin acquisition (with default.hdr)", "the header of scan_x256_y256.raw".
        package let description: String
        package let folder: URL
    }

    /// The need when a companion of another name exists beside `url` and cannot be opened for reading; nil for any other file,
    /// and when every companion opens (outside the sandbox, or once the folder is granted).
    package static func need(for url: URL) -> Need? {
        switch url.pathExtension.lowercased() {
        case "mib":
            guard let set = MerlinSet.containing(url.path), !([set.header] + set.parts).allSatisfy(canOpen) else { return nil }
            return Need(description: "one of \(set.parts.count + 1) files of a Merlin acquisition (with \(URL(fileURLWithPath: set.header).lastPathComponent))",
                        folder: url.deletingLastPathComponent())
        case "xml":
            guard let raw = empadRawFile(named: url), raw.deletingPathExtension().lastPathComponent != url.deletingPathExtension().lastPathComponent,
                  FileManager.default.fileExists(atPath: raw.path), !canOpen(raw.path) else { return nil }
            return Need(description: "the EMPAD header of \(raw.lastPathComponent)", folder: url.deletingLastPathComponent())
        default:
            return nil
        }
    }

    /// The raw file an EMPAD XML names (`<raw_file filename="…">`), resolved against the XML's folder; nil when it names none.
    package static func empadRawFile(named xml: URL) -> URL? {
        guard let parser = XMLParser(contentsOf: xml) else { return nil }
        let finder = RawFileFinder()
        parser.delegate = finder
        parser.shouldResolveExternalEntities = false
        parser.parse()
        guard let name = finder.filename, !name.isEmpty, !name.contains("/") else { return nil }
        return xml.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Opens and closes the file: the sandbox answers EPERM here for a file it has not granted, where a metadata check says yes.
    package static func canOpen(_ path: String) -> Bool {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }
}

private nonisolated final class RawFileFinder: NSObject, XMLParserDelegate {
    var filename: String?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "raw_file", filename == nil { filename = attributes["filename"] }
    }
}
