//
//  ThicknessEntry.swift
//  Role: the specimen thickness behind a precipitate count (design rooms-2026-10-21 §3): a typed value with its sigma and WHERE it
//        came from, in words, so an areal density read as a volume density names its thickness. Typed by the owner, or typed after
//        reading the EELS t/lambda method JSON that macTEM exports (`EELSCompute.methodJSON`): the JSON names the source (file,
//        method, mean free path, badge); the thickness itself stays the person's number until the EELS route is validated.
//        Persisted through the lineage node of the objects run (`ThicknessEntry.parameters`), which the sidecar carries.
//

import Foundation

package nonisolated struct ThicknessEntry: Codable, Equatable, Sendable {
    package enum Origin: Codable, Equatable, Sendable {
        case typed
        /// macTEM's EELS method JSON, read: its file name, the method line, the mean free path when the JSON states one, its badge.
        case eelsMethodJSON(file: String, method: String, lambdaNanometres: Double?, validation: String?)
    }

    package var nanometres: Double
    package var sigmaNanometres: Double
    /// What the person says it is ("EELS t/λ, λ = 120 nm", "CBED fringes"); never empty in a stored entry.
    package var source: String
    package var origin: Origin

    package init(nanometres: Double, sigmaNanometres: Double, source: String, origin: Origin = .typed) {
        self.nanometres = nanometres; self.sigmaNanometres = sigmaNanometres; self.source = source; self.origin = origin
    }

    /// Positive, finite, with a non-negative sigma and a source.
    package var isUsable: Bool {
        nanometres > 0 && nanometres.isFinite && sigmaNanometres >= 0 && sigmaNanometres.isFinite
            && !source.trimmingCharacters(in: .whitespaces).isEmpty
    }

    package enum JSONError: Error, LocalizedError, Equatable {
        case notAnObject, notAnEELSMethod
        package var errorDescription: String? {
            switch self {
            case .notAnObject: "That file is not JSON."
            case .notAnEELSMethod: "That JSON is not an EELS thickness method (it has no \u{201C}method\u{201D} and \u{201C}file\u{201D})."
            }
        }
    }

    /// The source words and origin macTEM's method JSON gives; the thickness and its sigma are still the person's.
    package static func source(fromEELSMethodJSON json: String) throws -> (text: String, origin: Origin) {
        guard let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw JSONError.notAnObject }
        guard let file = object["file"] as? String, let method = object["method"] as? String else { throw JSONError.notAnEELSMethod }
        let lambda = (object["mean_free_path_nm"] as? NSNumber)?.doubleValue
        let validation = object["validation"] as? String
        var text = "EELS t/\u{03BB} of \(file), \(method)"
        if let lambda { text += String(format: ", \u{03BB} = %.4g nm", lambda) }
        if let validation { text += ", validation: \(validation)" }
        return (text, .eelsMethodJSON(file: file, method: method, lambdaNanometres: lambda, validation: validation))
    }

    // MARK: lineage parameters (the sidecar's record of it)

    package static let keys = ["thickness_nm", "thickness_sigma_nm", "thickness_source", "thickness_origin"]

    package var parameters: [String: String] {
        [
            "thickness_nm": String(nanometres), "thickness_sigma_nm": String(sigmaNanometres), "thickness_source": source,
            "thickness_origin": { if case .typed = origin { "typed" } else { "eels_method_json" } }(),
        ]
    }

    package init?(parameters p: [String: String]) {
        guard let t = p["thickness_nm"].flatMap(Double.init), let s = p["thickness_sigma_nm"].flatMap(Double.init),
              let source = p["thickness_source"] else { return nil }
        self.init(nanometres: t, sigmaNanometres: s, source: source,
                  origin: p["thickness_origin"] == "eels_method_json"
                    ? .eelsMethodJSON(file: "", method: "", lambdaNanometres: nil, validation: nil) : .typed)
        guard isUsable else { return nil }
    }

    /// The CSV provenance pairs.
    package var provenancePairs: [(String, String)] {
        [("thickness", String(format: "%.6g nm +/- %.6g nm (typed value; areal density becomes volume density only through N_V, not estimated yet)", nanometres, sigmaNanometres)),
         ("thickness_source", source)]
    }
}
