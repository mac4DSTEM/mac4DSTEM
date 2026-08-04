import Foundation

/// Reads the machine-readable py4DSTEM parity records that
/// tools/training-dataset-campaign publishes under
/// References/parity_records/latest/, so the QC log can cite the parity
/// number for the product the playthrough just produced. This is the QC half
/// of the closed evaluation loop (docs/py4dstem-pipelines.md §10): a UI
/// finding about a step can now carry "and its output agrees/disagrees with
/// py4DSTEM by this much" instead of leaving the two evidence streams for a
/// human to join.
enum ParityRecords {
    static var recordsDirectory: URL {
        OutputLayout.repoRoot.appendingPathComponent(
            "References/parity_records/latest", isDirectory: true
        )
    }

    /// Mirrors safeStem() in tools/training-dataset-campaign/main.swift so
    /// record filenames resolve for datasets with non-alphanumeric names.
    static func safeStem(_ value: String) -> String {
        value.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : "_"
        }.joined()
    }

    /// One markdown log line for the datacube+product. Absence of a record is
    /// reported explicitly, so a log never silently loses the parity claim.
    static func citation(datacubeFileName: String, product: String) -> String {
        let url = recordsDirectory.appendingPathComponent(
            "\(safeStem(datacubeFileName)).\(product).json"
        )
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            return "Parity vs py4DSTEM (\(product)): no record on this machine — "
                + "run tools/training-dataset-campaign/run.sh to generate "
                + "References/parity_records/latest/"
        }
        let status: String
        if let pass = record["pass"] as? Bool {
            status = pass ? "PASS" : "FAIL"
        } else {
            status = "not comparable (see record notes)"
        }
        var details: [String] = []
        if let metrics = record["metrics"] as? [String: Any] {
            let headline = [
                "e_xx_median_absdiff", "e_yy_median_absdiff",
                "misorientation_median_deg_confident",
                "fraction_within_5deg_confident", "positions_compared",
            ]
            for key in headline {
                if let value = metrics[key] as? Double {
                    details.append("\(key) \(String(format: "%.4g", value))")
                } else if let value = metrics[key] as? Int {
                    details.append("\(key) \(value)")
                }
            }
        }
        let reference = record["reference"] as? String ?? "py4DSTEM"
        let generated = record["generated"] as? String ?? "unknown time"
        let suffix = details.isEmpty ? "" : " · " + details.joined(separator: " · ")
        return "Parity vs \(reference) (\(product)): \(status)\(suffix) — "
            + "`References/parity_records/latest/\(url.lastPathComponent)`, "
            + "generated \(generated)"
    }
}
