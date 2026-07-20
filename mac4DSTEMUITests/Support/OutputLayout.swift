import Foundation

/// Discovers the training-dataset inputs and creates the timestamped output
/// tree under References/training_runs. Read-only with respect to the app —
/// this only manages the QC playthrough's own evaluation artifacts.
enum OutputLayout {
    /// The checked-out repo root. Prefers an explicit override (set by
    /// tools/ui-qc-playthrough/run.sh) and otherwise derives it from this
    /// source file's own on-disk path: Xcode compiles directly from the
    /// working copy (no staging copy), so #filePath is the real repo path
    /// at both build and run time.
    static var repoRoot: URL {
        if let override = ProcessInfo.processInfo.environment["MAC4DSTEM_REPO_ROOT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // OutputLayout.swift
        url.deleteLastPathComponent() // Support/
        url.deleteLastPathComponent() // mac4DSTEMUITests/
        return url
    }

    static var datasetDirectory: URL {
        repoRoot.appendingPathComponent("References/training_dataset", isDirectory: true)
    }

    static var runsRootDirectory: URL {
        repoRoot.appendingPathComponent("References/training_runs", isDirectory: true)
    }

    /// Optional dev/debug narrowing, e.g. for iterating on the automation
    /// against one file instead of the full multi-gigabyte set. Read from a
    /// file, not an environment variable: xcodebuild's UI-test runner
    /// process does not reliably inherit env vars exported by the invoking
    /// shell (confirmed — MAC4DSTEM_QC_ONLY exported before `xcodebuild
    /// test-without-building` never reached ProcessInfo here). A file next
    /// to the repo root, written by tools/ui-qc-playthrough/run.sh, sidesteps
    /// that entirely.
    static var filterFileURL: URL {
        repoRoot.appendingPathComponent(".ui-qc-filter")
    }

    static func discoverDatacubes() throws -> [URL] {
        let items = try FileManager.default.contentsOfDirectory(
            at: datasetDirectory, includingPropertiesForKeys: nil
        )
        var datacubes = items
            .filter { $0.pathExtension.lowercased() == "h5" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        if let filterList = try? String(contentsOf: filterFileURL, encoding: .utf8) {
            let needles = filterList.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !needles.isEmpty {
                datacubes = datacubes.filter { url in
                    needles.contains { url.lastPathComponent.localizedCaseInsensitiveContains($0) }
                }
            }
        }
        return datacubes
    }

    static func makeRunDirectory(timestamp: String) throws -> URL {
        let dir = runsRootDirectory.appendingPathComponent("run_\(timestamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func makeDatacubeDirectory(in runDirectory: URL, datacubeBaseName: String) throws -> URL {
        let dir = runDirectory.appendingPathComponent(datacubeBaseName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
