import Foundation

/// Accumulates the per-datacube markdown QC log and writes it to disk.
/// Plain text building, no XCTest dependency — easy to eyeball independent
/// of the automation that fills it in.
final class RunLog {
    private var lines: [String] = []
    private var errors: [String] = []
    private(set) var exportedFiles: [String] = []

    init(datacubeFileName: String, sourceURL: URL) {
        lines.append("# QC Playthrough — \(datacubeFileName)")
        lines.append("")
        lines.append("- Source file: `\(sourceURL.path)`")
        if let size = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int {
            lines.append("- Source size: \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
        }
        lines.append("- Started: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
    }

    func section(_ title: String) {
        lines.append("## \(title)")
        lines.append("")
    }

    func subsection(_ title: String) {
        lines.append("### \(title)")
        lines.append("")
    }

    func bullet(_ text: String) {
        lines.append("- \(text)")
    }

    func note(_ text: String) {
        lines.append(text)
        lines.append("")
    }

    func recordScreenshot(step: String, fileName: String) {
        bullet("Screenshot (\(step)): `\(fileName)`")
    }

    func recordExport(fileName: String) {
        exportedFiles.append(fileName)
        bullet("Exported: `\(fileName)`")
    }

    func recordError(_ message: String) {
        errors.append(message)
        bullet("ERROR: \(message)")
    }

    var hasErrors: Bool { !errors.isEmpty }

    func write(to url: URL) {
        section("Errors")
        if errors.isEmpty {
            note("None.")
        } else {
            for error in errors { bullet(error) }
            lines.append("")
        }
        let text = lines.joined(separator: "\n")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
