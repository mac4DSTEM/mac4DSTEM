//
//  MerlinHeaderCompanion.swift
//  Role: a Merlin acquisition is a header (`scan.hdr`) and its data (`scan.mib`, or `scan1.mib` … `scanN.mib` when saved to
//        multiple files). The readers open the data; a user who picks the header means the same acquisition (mac4DSTEM#262),
//        so the header is answered with its data file. Names only: no file is read here.
//

import Foundation

package nonisolated enum MerlinHeaderCompanion {
    /// The data file a header stands for, among the names of its folder: `<base>.mib`, else the lowest-numbered
    /// `<base><N>.mib` (the reader takes the other parts of a multi-file save from there). Nil when the folder holds neither.
    /// Extensions compare without case; the base name must match exactly.
    package static func mib(forHeader header: String, among names: [String]) -> String? {
        let base = (header as NSString).deletingPathExtension
        var single: String?
        var numbered: [(number: Int, name: String)] = []
        for name in names where (name as NSString).pathExtension.lowercased() == "mib" {
            let stem = (name as NSString).deletingPathExtension
            if stem == base { single = name; continue }
            guard stem.hasPrefix(base) else { continue }
            let tail = stem.dropFirst(base.count)
            if !tail.isEmpty, tail.allSatisfy(\.isNumber), let number = Int(tail) { numbered.append((number, name)) }
        }
        return single ?? numbered.min { $0.number < $1.number }?.name
    }

    /// What to say when the header cannot be answered: the folder could not be listed (the sandbox grants the picked file
    /// only), or it holds no data file of that name.
    package static func refusal(header: String, folderWasReadable: Bool) -> String {
        let base = (header as NSString).deletingPathExtension
        return folderWasReadable
            ? "\(header) is a Merlin header, and no \(base).mib or \(base)1.mib is beside it. Open the acquisition's .mib file."
            : "\(header) is a Merlin header. Pick one of the .mib files in its folder: the acquisition opens from there."
    }
}
