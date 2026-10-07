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
//
// WP4 (lane L12, 2026-10-07) adds, to every <n>.json and without changing the per-file line: `configs` (the picks the room would make
// with no rule, with each registered rule alone, with R1+R2 and with R1+R2+R3, by `AutoIDPresentation.outcome(rules:)` itself),
// `withheld` / `released` (registered rules), `acquired` (the file's acquisition date, from its own metadata; `acquiredSource`), and
// with --h4 `h4` (the proposer run on the Mg-richest 1 % of pixels by the Mg K-alpha window map, for the Al-Mg-Si files). With
// `--ladder <dir>` (written by tools/autoid-velox-check/ladder_prep.py from References/demo-edx) it runs the same on the dose-ladder
// regions, whose truth is known, instead of on Velox files: the refutation of H3.

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

/// The room's own rule sets, by name: the picks each gives, through `AutoIDPresentation.outcome` (beside check and availability included).
let ruleConfigs: [(name: String, rules: ProposalRules)] = [
    ("base", .none),
    ("R1", ProposalRules(hygiene: true, corroboration: false, release: false)),
    ("R2", ProposalRules(hygiene: false, corroboration: true, release: false)),
    ("R3", ProposalRules(hygiene: false, corroboration: false, release: true)),
    ("R1R2", ProposalRules(hygiene: true, corroboration: true, release: false)),
    ("R1R2R3", .registered),
]

/// One proposer run as the room runs it (`SpectroscopyRoomController.runAutoID`): no listed elements, the file's axis, the default
/// resolution; returns the result and what each rule set picks.
func propose(counts: [UInt64], axis: EnergyAxis, beam: Double) throws -> (result: ProposalResult, settings: FitSettings, configs: [String: [String]], registered: RuledProposal) {
    let settings = FitSettings.standard(elements: [], axis: axis, resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV, beamEnergy: beam)
    let result = try ElementProposer().propose(counts: counts.map { Double($0) }, axis: axis, settings: settings)
    let beside = AutoIDPresentation.besideCheck(settings: settings, axis: axis)
    var configs: [String: [String]] = [:]
    for (name, rules) in ruleConfigs {
        let ruled = rules.isNone ? nil : rules.apply(result, resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV)
        configs[name] = AutoIDPresentation.outcome(result, region: "", beside: beside, rules: ruled).suggestions.map { PeriodicLayout.symbol($0.z) }
    }
    return (result, settings, configs, ProposalRules.registered.apply(result, resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV))
}

func candidateRows(_ result: ProposalResult, picked: Set<Int>, excessLabels: Set<String>) -> [[String: Any]] {
    result.candidates.map { c in
        let z = PeriodicLayout.z(of: c.element) ?? 0
        return ["element": c.element, "z": z, "group": c.group, "energy": c.energyKeV, "net": c.net, "sigma": c.sigma,
                "sigmaZero": c.sigmaZero, "lc": c.criticalLevel, "ld": c.detectionLimit, "significance": c.significance,
                "proposed": c.isProposed, "sumQuestion": c.hasSumPeakQuestion, "conflicts": c.conflicts.map { $0.kind.rawValue },
                "misfit": c.misfit, "picked": picked.contains(z), "beside": excessLabels.contains(UnlistedLineChecker.displayName(c.group))]
    }
}

/// Acquisition date: the file's own metadata (one frame read), else the first yyyymmdd in the file name.
func acquisitionDate(path: String) -> (iso: String?, source: String) {
    if let v = try? VeloxEMDReader(path: path).readSpectrumImage(frames: .range(0..<1)), let t = v.metadata.acquisitionStartUnixTime, t > 0 {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
        return (f.string(from: Date(timeIntervalSince1970: t)), "metadata")
    }
    let name = (path as NSString).lastPathComponent
    if let r = name.range(of: "20[0-9]{6}", options: .regularExpression) {
        let d = String(name[r]); return ("\(d.prefix(4))-\(d.dropFirst(4).prefix(2))-\(d.suffix(2))", "filename")
    }
    return (nil, "none")
}

/// H4 (a diagnostic, no UI): the proposer on the Mg-richest 1 % of pixels, ranked by the Mg K-alpha window map (the room's own windows:
/// signal minus the scaled background windows), ties by pixel index. Whether Mg is among the picks, with and without the rules.
func h4(source: any SpectrumImageSource, beam: Double) throws -> [String: Any]? {
    let axis = source.energyAxis
    guard let w = ElementWindows.build(picks: [.init(symbol: "Mg")], axis: axis, beamEnergyKeV: beam).first, let win = w.window else { return nil }
    var ranges = [win.signal]
    if let b = win.background { ranges += [b.left, b.right] }
    let sums = source.windowSums(ranges)
    let n = source.nx * source.ny
    var net = [Double](repeating: 0, count: n)
    for p in 0..<n {
        net[p] = Double(sums[0][p])
        if let b = win.background { net[p] -= b.scale * Double(sums[1][p] + sums[2][p]) }
    }
    let k = max(1, Int((0.01 * Double(n)).rounded()))
    let top = (0..<n).sorted { net[$0] != net[$1] ? net[$0] > net[$1] : $0 < $1 }.prefix(k)
    var mask = [Bool](repeating: false, count: n)
    for p in top { mask[p] = true }
    let counts = source.sum(mask: mask)
    let out = try propose(counts: counts, axis: axis, beam: beam)
    return ["pixels": k, "of": n, "counts": counts.reduce(0, +), "meanNetTop": top.map { net[$0] }.reduce(0, +) / Double(k), "meanNetAll": net.reduce(0, +) / Double(n),
            "configs": out.configs, "mgBase": out.configs["base"]!.contains("Mg"), "mgRegistered": out.configs["R1R2R3"]!.contains("Mg")]
}

let alMgSiTruthRule = { (truth: [String]) in Set(["Mg", "Al", "Si"]).isSubset(of: Set(truth)) && !truth.contains("C") && !truth.contains("O") }

func analyse(path: String, truth: [String]?, outDir: String?, index: Int, withH4: Bool) throws -> (FileResult, [[String: Any]]) {
    let kind = SpectrumImageOpener.kind(ofFileAt: path)
    let loaded = try SpectrumImageOpener.open(path: path, kind: kind)
    let source: any SpectrumImageSource = loaded
    guard let beam = source.metadata.beamEnergyKeV, beam > 0 else { throw NSError(domain: "autoid", code: 1, userInfo: [NSLocalizedDescriptionKey: "no beam energy in the file"]) }
    let counts = source.sum(mask: nil)
    // Mirrors SpectroscopyRoomController.runAutoID: no listed elements, the file's axis, the default resolution.
    let run = try propose(counts: counts, axis: source.energyAxis, beam: beam)
    let result = run.result
    let outcome = AutoIDPresentation.outcome(result, region: "", beside: AutoIDPresentation.besideCheck(settings: run.settings, axis: source.energyAxis))
    let pickedZ = Set(outcome.suggestions.map(\.z))
    let excessLabels = Set(outcome.excesses.map(\.proposerLabel))
    let rows = candidateRows(result, picked: pickedZ, excessLabels: excessLabels)
    if let outDir {
        let n = String(format: "%02d", index)
        counts.withUnsafeBytes { try? Data($0).write(to: URL(fileURLWithPath: "\(outDir)/\(n).spectrum.u64")) }
        let date = acquisitionDate(path: path)
        var meta: [String: Any] = ["file": path, "kind": "\(kind)", "beamKeV": beam, "offsetKeV": source.energyAxis.offset, "scaleKeV": source.energyAxis.scale,
                                   "channels": source.energyAxis.size, "scan": [source.nx, source.ny], "totalCounts": counts.reduce(0, +),
                                   "truth": truth ?? [], "picks": outcome.suggestions.map { PeriodicLayout.symbol($0.z) },
                                   "chi2r": result.reducedChiSquared ?? NSNull(), "passes": result.passes, "settled": result.settled,
                                   "sumPeakQuestions": result.sumPeakQuestions.map { $0.element }, "candidates": rows,
                                   "configs": run.configs, "acquired": date.iso ?? NSNull(), "acquiredSource": date.source,
                                   "withheld": run.registered.withheld.map { ["element": $0.candidate.element, "rule": $0.rule.rawValue, "why": $0.why] },
                                   "released": run.registered.released.map { $0.candidate.element }]
        if withH4, let t = truth, alMgSiTruthRule(t), let h = try? h4(source: source, beam: beam) { meta["h4"] = h }
        try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(outDir)/\(n).json"))
    }
    let picks = outcome.suggestions.map { PeriodicLayout.symbol($0.z) }
    return (FileResult(name: (path as NSString).lastPathComponent, truth: truth ?? [], picks: picks), rows)
}

/// `--replay <dir>`: re-selects among the candidates a PREVIOUS run already wrote (`<n>.json`: every candidate with net, sigma, L_C, L_D, group, energy, conflict
/// kinds) with the CURRENT rule code (`ProposalRules` through `AutoIDPresentation.outcome`), so the rules can be measured on files that are not at hand (the owner's
/// drive). The proposer is not run: its output is exactly what the earlier run recorded. Each `<n>.json` is written to --out with `configs`/`withheld`/`released` added.
func runReplay(dir: String, outDir: String?) {
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".json") && $0 != "summary.json" && !$0.contains("meta") }.sorted()
    print("autoid-velox-check --replay: \(files.count) recorded file(s)")
    var mismatches = 0
    for f in files {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: dir + "/" + f)), var meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = meta["candidates"] as? [[String: Any]], let beam = meta["beamKeV"] as? Double, let offset = meta["offsetKeV"] as? Double,
              let scale = meta["scaleKeV"] as? Double, let channels = meta["channels"] as? Int else { print("skip \(f)"); continue }
        let candidates: [ElementCandidate] = rows.map { r in
            let kinds = (r["conflicts"] as? [String] ?? []).compactMap { LineConflict.Kind(rawValue: $0) }
            let group = r["group"] as! String
            let conflicts = kinds.map { LineConflict(id: "replay-\($0.rawValue)", kind: $0, element: r["element"] as! String, line: group, energiesKeV: [], requires: [], question: "", remedy: "") }
            return ElementCandidate(element: r["element"] as! String, group: group, energyKeV: r["energy"] as! Double, net: r["net"] as! Double, sigma: r["sigma"] as! Double,
                                    sigmaZero: r["sigmaZero"] as! Double, criticalLevel: r["lc"] as! Double, detectionLimit: r["ld"] as! Double, conflicts: conflicts,
                                    suggestedRole: .fitOnly, holeRegionNote: nil, misfit: r["misfit"] as! Double)
        }
        let result = ProposalResult(candidates: candidates, sumPeaks: [], refused: [], currie: .standard, notes: [], passes: 1, settled: true, reducedChiSquared: meta["chi2r"] as? Double)
        // the recorded flags must reproduce, or the replay is not of the same data
        for (c, r) in zip(candidates, rows) where c.isProposed != (r["proposed"] as? Bool) || c.hasSumPeakQuestion != (r["sumQuestion"] as? Bool) { mismatches += 1 }
        let axis = EnergyAxis(offset: offset, scale: scale, size: channels)
        let settings = FitSettings.standard(elements: [], axis: axis, resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV, beamEnergy: beam)
        let beside = AutoIDPresentation.besideCheck(settings: settings, axis: axis)
        var configs: [String: [String]] = [:]
        for (name, rules) in ruleConfigs {
            let ruled = rules.isNone ? nil : rules.apply(result, resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV)
            configs[name] = AutoIDPresentation.outcome(result, region: "", beside: beside, rules: ruled).suggestions.map { PeriodicLayout.symbol($0.z) }
        }
        let reg = ProposalRules.registered.apply(result, resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV)
        meta["configs"] = configs
        meta["withheld"] = reg.withheld.map { ["element": $0.candidate.element, "rule": $0.rule.rawValue, "why": $0.why] }
        meta["released"] = reg.released.map { $0.candidate.element }
        meta["replayedFrom"] = dir
        if let outDir { try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: outDir + "/" + f)) }
        print("\(f) | base: \((configs["base"] ?? []).joined(separator: " ")) | recorded picks: \((meta["picks"] as? [String] ?? []).joined(separator: " ")) | R1R2R3: \((configs["R1R2R3"] ?? []).joined(separator: " "))")
    }
    print("recorded proposed/sumQuestion flags that did not reproduce: \(mismatches)")
}

/// `--ladder <dir>`: the dose-ladder regions (ladder_prep.py's `<n>.spectrum.u64` + `<n>.meta.json`); same JSON per region, the truth is the planted elements.
func runLadder(dir: String, outDir: String?) {
    let metas = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".meta.json") }.sorted()
    print("autoid-velox-check --ladder: \(metas.count) region(s)")
    for (i, m) in metas.enumerated() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: dir + "/" + m)), let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let offset = meta["offsetKeV"] as? Double, let scale = meta["scaleKeV"] as? Double, let beam = meta["beamKeV"] as? Double,
              let truth = meta["truth"] as? [String] else { print("bad meta \(m)"); continue }
        let raw = (try? Data(contentsOf: URL(fileURLWithPath: dir + "/" + m.replacingOccurrences(of: ".meta.json", with: ".spectrum.u64")))) ?? Data()
        let counts: [UInt64] = raw.withUnsafeBytes { Array($0.bindMemory(to: UInt64.self)) }
        let start = Date()
        do {
            let axis = EnergyAxis(offset: offset, scale: scale, size: counts.count)
            let run = try propose(counts: counts, axis: axis, beam: beam)
            let outcome = AutoIDPresentation.outcome(run.result, region: "", beside: AutoIDPresentation.besideCheck(settings: run.settings, axis: axis))
            let rows = candidateRows(run.result, picked: Set(outcome.suggestions.map(\.z)), excessLabels: Set(outcome.excesses.map(\.proposerLabel)))
            if let outDir {
                let meta2: [String: Any] = ["file": m, "region": meta["region"] ?? i, "dose": meta["dose"] ?? NSNull(), "beamKeV": beam, "offsetKeV": offset, "scaleKeV": scale,
                                            "channels": counts.count, "totalCounts": counts.reduce(0, +), "truth": truth, "picks": outcome.suggestions.map { PeriodicLayout.symbol($0.z) },
                                            "chi2r": run.result.reducedChiSquared ?? NSNull(), "candidates": rows, "configs": run.configs,
                                            "withheld": run.registered.withheld.map { ["element": $0.candidate.element, "rule": $0.rule.rawValue, "why": $0.why] },
                                            "released": run.registered.released.map { $0.candidate.element }]
                try? JSONSerialization.data(withJSONObject: meta2, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(outDir)/ladder\(String(format: "%02d", i)).json"))
            }
            print("\(m) | truth: \(truth.joined(separator: " ")) | base: \(run.configs["base"]!.joined(separator: " ")) | R1R2R3: \(run.configs["R1R2R3"]!.joined(separator: " ")) | released: \(run.registered.released.map { $0.candidate.element }.joined(separator: " ")) | \(String(format: "%.0f", Date().timeIntervalSince(start))) s")
        } catch { print("\(m): failed \(error)") }
    }
}

@main struct AutoIDVeloxCheck {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        var all = false, withH4 = false
        var outDir: String?, ladder: String?, replay: String?
        while let a = args.first, a.hasPrefix("--") {
            args.removeFirst()
            if a == "--all" { all = true } else if a == "--h4" { withH4 = true } else if a == "--out", !args.isEmpty { outDir = args.removeFirst() }
            else if a == "--ladder", !args.isEmpty { ladder = args.removeFirst() } else if a == "--replay", !args.isEmpty { replay = args.removeFirst() } else { print("unknown option \(a)"); exit(2) }
        }
        if let outDir { try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true) }
        if let ladder { runLadder(dir: ladder, outDir: outDir); return }
        if let replay { runReplay(dir: replay, outDir: outDir); return }
        guard !args.isEmpty else { print("usage: main [--all] [--h4] [--out <dir>] <file.emd | folder>...   |   main --ladder <dir> [--out <dir>]"); exit(2) }
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
                let (r, _) = try autoreleasepool { try analyse(path: path, truth: truth, outDir: outDir, index: index, withH4: withH4) }
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
