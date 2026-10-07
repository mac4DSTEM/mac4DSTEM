import Darwin
import Foundation

// tools/autoid-velox-check — the room's Auto ID against the elements Velox's own session had selected (lane L10, 2026-10-07).
//
//   main [--all] [--out <dir>] <file.emd | folder>...
//
// A folder is searched for `SI *.emd`. Each file is opened with the app's own opener (`SpectrumImageOpener`), its whole-map
// spectrum pooled (`source.sum(mask: nil)`, what the room's first Auto ID run sums), and `ElementProposer` run exactly as
// `SpectroscopyRoomController.runAutoID` runs it: `FitSettings.standard` with NO listed elements (a fresh room), the file's
// axis, the default resolution, the file's beam energy; the picks are `AutoIDPresentation.outcome`'s suggestions (the ones the
// room applies at once). The truth is `VeloxEMDReader.storedElementSelection()`: the elements Velox's session had selected
// (the owner picked them by hand; `elementsIdentified` is empty on every owner file). A file with no stored selection is
// skipped unless --all (then it prints the app's picks with no score). Read in place, nothing written beside the file.
//
// With --out <dir> it also writes, per file, `<n>.spectrum.u64` (the pooled counts, little-endian UInt64), `<n>.json` (the
// axis, the beam, every candidate the proposer returned with its numbers and which were picked) and `summary.json`, for the
// offline analysis in docs/archive/v5/autoid-velox-check-2026-10-07.md.

struct Pick { var z: Int; var symbol: String; var group: String; var energy: Double }

func findFiles(_ args: [String]) -> [String] {
    var out: [String] = []
    for a in args {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: a, isDirectory: &isDir) else { print("missing: \(a)"); continue }
        if !isDir.boolValue { out.append(a); continue }
        guard let walker = FileManager.default.enumerator(atPath: a) else { continue }
        for case let rel as String in walker {
            let name = (rel as NSString).lastPathComponent
            if name.hasPrefix("SI ") && name.lowercased().hasSuffix(".emd") { out.append(a + "/" + rel) }
        }
    }
    return out.sorted()
}

func grouped(_ x: Double) -> String { String(format: "%.0f", x) }

struct FileResult {
    var name: String
    var truth: [String]
    var picks: [String]
    var hits: [String] { picks.filter { truth.contains($0) } }
    var misses: [String] { truth.filter { !picks.contains($0) } }
    var extras: [String] { picks.filter { !truth.contains($0) } }
}

func analyse(path: String, truth: [String]?, outDir: String?, index: Int) throws -> (FileResult, [[String: Any]]) {
    let kind = SpectrumImageOpener.kind(ofFileAt: path)
    let loaded = try SpectrumImageOpener.open(path: path, kind: kind)
    let source: any SpectrumImageSource = loaded
    guard let beam = source.metadata.beamEnergyKeV, beam > 0 else { throw NSError(domain: "autoid", code: 1, userInfo: [NSLocalizedDescriptionKey: "no beam energy in the file"]) }
    let counts = source.sum(mask: nil)
    // Mirrors SpectroscopyRoomController.runAutoID: no listed elements, the file's axis, the default resolution.
    let settings = FitSettings.standard(elements: [], axis: source.energyAxis,
                                        resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV, beamEnergy: beam)
    let result = try ElementProposer().propose(counts: counts.map { Double($0) }, axis: source.energyAxis, settings: settings)
    let outcome = AutoIDPresentation.outcome(result, region: "", beside: AutoIDPresentation.besideCheck(settings: settings, axis: source.energyAxis))
    let pickedZ = Set(outcome.suggestions.map(\.z))
    let excessLabels = Set(outcome.excesses.map(\.proposerLabel))
    var rows: [[String: Any]] = []
    for c in result.candidates {
        let z = PeriodicLayout.z(of: c.element) ?? 0
        rows.append(["element": c.element, "z": z, "group": c.group, "energy": c.energyKeV, "net": c.net, "sigma": c.sigma,
                     "sigmaZero": c.sigmaZero, "lc": c.criticalLevel, "ld": c.detectionLimit, "significance": c.significance,
                     "proposed": c.isProposed, "sumQuestion": c.hasSumPeakQuestion, "conflicts": c.conflicts.map { $0.kind.rawValue },
                     "misfit": c.misfit, "picked": pickedZ.contains(z), "beside": excessLabels.contains(UnlistedLineChecker.displayName(c.group))])
    }
    if let outDir {
        let n = String(format: "%02d", index)
        counts.withUnsafeBytes { try? Data($0).write(to: URL(fileURLWithPath: "\(outDir)/\(n).spectrum.u64")) }
        let meta: [String: Any] = ["file": path, "kind": "\(kind)", "beamKeV": beam, "offsetKeV": source.energyAxis.offset, "scaleKeV": source.energyAxis.scale,
                                   "channels": source.energyAxis.size, "scan": [source.nx, source.ny], "totalCounts": counts.reduce(0, +),
                                   "truth": truth ?? [], "picks": outcome.suggestions.map { PeriodicLayout.symbol($0.z) },
                                   "chi2r": result.reducedChiSquared ?? NSNull(), "passes": result.passes, "settled": result.settled,
                                   "sumPeakQuestions": result.sumPeakQuestions.map { $0.element }, "candidates": rows]
        try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(outDir)/\(n).json"))
    }
    let picks = outcome.suggestions.map { PeriodicLayout.symbol($0.z) }
    return (FileResult(name: (path as NSString).lastPathComponent, truth: truth ?? [], picks: picks), rows)
}

@main struct AutoIDVeloxCheck {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        var all = false
        var outDir: String?
        while let a = args.first, a.hasPrefix("--") {
            args.removeFirst()
            if a == "--all" { all = true } else if a == "--out", !args.isEmpty { outDir = args.removeFirst() } else { print("unknown option \(a)"); exit(2) }
        }
        guard !args.isEmpty else { print("usage: main [--all] [--out <dir>] <file.emd | folder>..."); exit(2) }
        if let outDir { try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true) }
        let files = findFiles(args)
        print("autoid-velox-check: \(files.count) file(s)")
        var results: [FileResult] = []
        var skipped: [(String, String)] = []
        var index = 0
        for path in files {
            let name = (path as NSString).lastPathComponent
            let truth: [String]?
            do { truth = try VeloxEMDReader(path: path).storedElementSelection() } catch { skipped.append((name, "refused: \(error.localizedDescription)")); continue }
            if truth == nil && !all { skipped.append((name, "no stored element selection")); continue }
            let start = Date()
            do {
                let (r, _) = try autoreleasepool { try analyse(path: path, truth: truth, outDir: outDir, index: index) }
                index += 1
                if truth != nil { results.append(r) }
                let tag = truth == nil ? "no truth" : "hit \(r.hits.count)/\(r.truth.count) | extra \(r.extras.count)"
                print("\(name) | velox: \(r.truth.joined(separator: " ")) | app: \(r.picks.joined(separator: " ")) | \(tag) | \(String(format: "%.0f", Date().timeIntervalSince(start))) s")
            } catch { skipped.append((name, "failed: \(error.localizedDescription)")) }
        }
        for (n, why) in skipped where !why.hasPrefix("no stored") { print("skipped \(n): \(why)") }
        let noSel = skipped.filter { $0.1.hasPrefix("no stored") }.count
        print("skipped without a stored selection: \(noSel)")
        // Totals.
        let truthN = results.reduce(0) { $0 + $1.truth.count }, pickN = results.reduce(0) { $0 + $1.picks.count }
        let hitN = results.reduce(0) { $0 + $1.hits.count }
        let pct = { (a: Int, b: Int) in b == 0 ? "n/a" : String(format: "%.1f %%", 100 * Double(a) / Double(b)) }
        print("scored files \(results.count): velox elements \(truthN), app picks \(pickN), hits \(hitN)")
        print("precision \(pct(hitN, pickN)) (hits / app picks), recall \(pct(hitN, truthN)) (hits / velox elements)")
        let exact = results.filter { $0.misses.isEmpty && $0.extras.isEmpty }.count
        print("files with the exact set: \(exact) of \(results.count); with every velox element found: \(results.filter { $0.misses.isEmpty }.count)")
        func tally(_ items: [String]) -> String {
            var counts: [String: Int] = [:]
            for item in items { counts[item, default: 0] += 1 }
            let ranked: [(key: String, value: Int)] = counts.sorted { (a, b) in a.value != b.value ? a.value > b.value : a.key < b.key }
            return ranked.prefix(12).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        }
        print("most frequent false picks: \(tally(results.flatMap(\.extras)))")
        print("most frequent misses: \(tally(results.flatMap(\.misses)))")
        if let outDir {
            let summary: [String: Any] = ["files": results.map { ["file": $0.name, "truth": $0.truth, "picks": $0.picks] }, "precision": pickN == 0 ? 0 : Double(hitN) / Double(pickN),
                                          "recall": truthN == 0 ? 0 : Double(hitN) / Double(truthN)]
            try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(outDir)/summary.json"))
        }
    }
}
