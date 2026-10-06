import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// WP3c, "the default fit range, not the continuum" (docs/archive/v5/wp3c-fit-range-preregistration-2026-10-06.md, P1-P6).
/// The default upper fit limit is min(axis end, beam, 20 keV), decided on the file's axis; a typed limit is Expert
/// (`QuantificationMethod.fitToKeV`, nil = default, absent from the JSON); the at% row falls back from an unsupported K-alpha
/// to the highest supported group, named; a range-sensitivity statement (one fit to the axis end, not a sigma term) runs
/// with the unlisted-line check when the axis runs past the default.
/// Fixture: `Fixtures/eds-realistic-l-sim.json` (generator `tools/edx-pins/realistic_l_sim.py`, 80 keV axis, Ti planted 3000,
/// `plantSn` for P6); lines added with the app's own shapes, Poisson counts from SplitMix64 per seed (platform independent).
/// The pinned numbers were measured by the lane's harness on the pristine and the new Core (lane C report, logs P1-P6).
@MainActor
final class SpectroscopyFitRangeTests: XCTestCase {

    private typealias Q = SpectroscopyQuantifyTests

    // MARK: The synthetic pool

    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }

    /// PTRS above 10, inversion below (as SpectroscopyUnlistedLineTests).
    private static func poisson(_ lam: Double, _ rng: inout SplitMix64) -> UInt64 {
        if lam <= 0 { return 0 }
        if lam < 10 {
            let l = exp(-lam); var k = 0.0; var p = 1.0
            repeat { k += 1; p *= rng.uniform() } while p > l
            return UInt64(k - 1)
        }
        let slam = lam.squareRoot(), loglam = log(lam)
        let b = 0.931 + 2.53 * slam, a = -0.059 + 0.02483 * b
        let invalpha = 1.1239 + 1.1328 / (b - 3.4), vr = 0.9277 - 3.6224 / (b - 2)
        while true {
            let u = rng.uniform() - 0.5, v = rng.uniform()
            let us = 0.5 - abs(u)
            let k = ((2 * a / us + b) * u + lam + 0.43).rounded(.down)
            if us >= 0.07 && v <= vr { return UInt64(k) }
            if k < 0 || (us < 0.013 && v > us) { continue }
            if log(v) + log(invalpha) - log(a / (us * us) + b) <= -lam + k * loglam - lgamma(k + 1) { return UInt64(k) }
        }
    }

    private struct Fixture: Decodable {
        let offset: Double, scale: Double, size: Int, beam: Double, fwhmMnKa: Double
        let continuum: [Double]; let areas: [String: Double]; let planted: [String]
        let listedFour: [String]; let listedSeven: [String]; let seeds: [UInt64]
        let plantSn: [String: Double]
        var axis: EnergyAxis { EnergyAxis(offset: offset, scale: scale, size: size) }
    }

    private static let fx: Fixture = try! JSONDecoder().decode(
        Fixture.self, from: Data(contentsOf: Q.fixtures.appendingPathComponent("eds-realistic-l-sim.json")))

    private static func counts(seed: UInt64, sn: Bool = false) -> [UInt64] {
        let axis = fx.axis
        var mu = fx.continuum, areas = fx.areas, els = fx.planted
        if sn { areas.merge(fx.plantSn) { $1 }; els.append("Sn") }
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        let model = EDSLineModel.build(elements: els, axis: axis, beamEnergy: fx.beam, resolutionMnKaEV: fx.fwhmMnKa, escapePeaks: false)
        for g in model.groups { if let area = areas[g.id] {
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            for i in mu.indices { mu[i] += area * col[i] }
        } }
        var rng = SplitMix64(state: seed)
        return mu.map { poisson($0, &rng) }
    }

    /// `locked`: the generator's own axis (E1-E3's protocol: the fit is EDSFit's on the true axis); else refined, as the room runs.
    private static func input(seed: UInt64, quantify: [String], fitOnly: [String] = [], fitTo: Double? = nil,
                              locked: Bool = true, sn: Bool = false) -> PooledQuantificationInput {
        var m = QuantificationMethod()
        m.elements = quantify.map { .init(symbol: $0, role: .quantify, isManual: false) } + fitOnly.map { .init(symbol: $0, role: .fitOnly, isManual: false) }
        m.beamEnergyKeV = fx.beam
        m.absorptionCorrection = false
        if locked { m.lockEnergyAxis = true }
        m.fitToKeV = fitTo
        let axis = fx.axis
        let meta = SpectrumImageMetadata(fileName: "eds-realistic-l-sim.json", filePath: "", scanWidth: 1, scanHeight: 1,
                                         channelCount: axis.size, energyOffsetEV: axis.offset * 1000, energyDispersionEV: axis.scale * 1000)
        return PooledQuantificationInput(counts: counts(seed: seed, sn: sn), axis: axis, method: m, metadata: meta,
                                         regionName: "synthetic", pixelCount: 1)
    }

    private static func row(_ q: PooledQuantification, _ el: String) throws -> PooledQuantification.Row {
        try XCTUnwrap(q.rows.first { $0.element == el }, el)
    }

    // MARK: P1

    /// P1: 7 elements, default settings: the fit stops at 20 keV (the channel holding it) and Ti is unbiased - E1's 20 keV row,
    /// Ti 2972/3147/2984/3080/3060, mean 3049 +- 108 (z +0.45); Expert 60 keV moves no other planted K-alpha's mean z by > 0.5.
    /// Mutation M1: `FitSettings.defaultFitTo` returning min(axis end, beam) (the fit forced to the axis end) - red (Ti z -2.28).
    func testP1TheDefaultStopsAt20keVAndTiIsUnbiased() throws {
        let measured: [Double] = [2972, 3147, 2984, 3080, 3060]
        let ka = ["O", "Si", "Ti", "Ni", "Ge", "Cu", "Ga"]
        var tis: [Double] = [], sigmas: [Double] = []
        var z20 = [String: Double](), z60 = [String: Double]()
        for (i, seed) in Self.fx.seeds.enumerated() {
            let q = try PooledQuantifier.run(Self.input(seed: seed, quantify: Self.fx.listedSeven), tables: nil)
            XCTAssertEqual(q.fitRange.source, .defaultLimit)
            XCTAssertEqual(q.fitRange.toKeV, 20)
            XCTAssertEqual(Self.fx.axis.energy(ofChannel: q.fit.channels.upperBound - 1), 20, accuracy: Self.fx.scale / 2)
            let ti = try Self.row(q, "Ti")
            XCTAssertEqual(ti.net, measured[i], accuracy: 1, "seed \(seed)")
            tis.append(ti.net); sigmas.append(ti.sigma)
            let q60 = try PooledQuantifier.run(Self.input(seed: seed, quantify: Self.fx.listedSeven, fitTo: 60), tables: nil)
            for el in ka {
                let a = try Self.row(q, el), b = try Self.row(q60, el), truth = Self.fx.areas[el + "_Ka"]!
                z20[el, default: 0] += (a.net - truth) / a.sigma / 5
                z60[el, default: 0] += (b.net - truth) / b.sigma / 5
            }
        }
        let mean = tis.reduce(0, +) / 5, sigma = sigmas.reduce(0, +) / 5
        XCTAssertLessThan(abs(mean - 3000) / sigma, 1, "mean Ti \(mean) +- \(sigma)")
        for el in ka where el != "Ti" {
            XCTAssertLessThanOrEqual(abs(z60[el]! - z20[el]!), 0.5, "\(el): mean z \(z20[el]!) at 20 keV, \(z60[el]!) at 60 keV")
        }
    }

    // MARK: P2

    /// P2: a record without `fitToKeV` keeps its bytes and its hash (pinned from the pristine encoder), the inspector's default
    /// writes no key, and an Expert limit at the old range (80 keV, clamped to the axis end) replays the old numbers exactly
    /// (H0-old-p2.log: Ti 2616/2911/2675/2794/2789). The footer names the default and the axis.
    /// Reading of P2 (session decision 2026-10-06): (a) bytes and hash kept, (b) Expert 80 keV reproduces the old numbers. A step
    /// recorded before WP3c on an 80 keV axis carries no key and so re-fits at the new 20 keV default on replay.
    /// Mutation M2: `QuantifySettings.apply` writing `fitTo ?? FitSettings.defaultUpperLimitKeV` (the key written when nil) - red.
    func testP2ARecordWithoutTheKeyKeepsItsHashAndTheOldRangeReplaysTheOldNumbers() throws {
        let plain = QuantificationMethod()
        XCTAssertEqual(plain.hash, "3fd1c05d3e9bfbd6e70349ad1139c60aa6ce07010b4a50a8be382b8b49f9e1f6")
        var all = QuantificationMethod()
        all.elements = [.init(symbol: "Al", role: .quantify, isManual: true), .init(symbol: "Cu", role: .fitOnly, isManual: false)]
        all.beamEnergyKeV = 200; all.polynomialOrder = 4; all.lockEnergyAxis = true
        all.thickness = .init(nanometres: 80, sigmaNanometres: 15); all.kReference = "Al"
        XCTAssertEqual(all.hash, "359a496d63f7f6f8d941d0ca5b9f3550eb549b457c2aa12584afc024904052f6")
        var viaInspector = QuantificationMethod()
        QuantifySettings().apply(to: &viaInspector)
        XCTAssertFalse(viaInspector.canonicalJSON.contains("fitToKeV"), viaInspector.canonicalJSON)
        XCTAssertNil(QuantificationMethod.decode(plain.canonicalJSON)?.fitToKeV)
        var typed = plain; typed.fitToKeV = 30
        XCTAssertTrue(typed.canonicalJSON.contains("\"fitToKeV\":30"))
        XCTAssertEqual(QuantificationMethod.decode(typed.canonicalJSON)?.fitToKeV, 30)

        let old: [Double] = [2616.0230409917299, 2911.3220308829077, 2674.5845706906089, 2794.44237432194, 2789.456075566367]
        for (i, seed) in Self.fx.seeds.enumerated() {
            let q = try PooledQuantifier.run(Self.input(seed: seed, quantify: Self.fx.listedSeven, fitTo: 80), tables: nil)
            XCTAssertEqual(try Self.row(q, "Ti").net, old[i], accuracy: 1e-6, "seed \(seed)")
            XCTAssertTrue(q.footerLines.contains { $0.hasPrefix("fit range 0.2\u{2013}79.9678 keV (typed 80 keV, clamped: axis to 79.97 keV)") }, "\(q.footerLines)")
        }
        let d = try PooledQuantifier.run(Self.input(seed: 0, quantify: Self.fx.listedSeven), tables: nil)
        XCTAssertTrue(d.footerLines.contains { $0.hasPrefix("fit range 0.2\u{2013}20 keV (default; axis to 79.97 keV)") }, "\(d.footerLines)")
    }

    // MARK: P3

    /// P3: past the default, one fit to the axis end, stated per element (E3: Ti -7.5 ... -12.0 %, -2.2 ... -3.3 sigma; every other
    /// element within 2 sigma), in the footer and the export, never in a sigma. On a 19.997 keV file (the weak-line sim, axis
    /// refined as the room runs, refined end up to 20.019 keV) no statement and no second fit; nor for a typed range.
    /// Mutation M1 (above) - red (the default reaches the axis end, no statement). Mutation M4: `FitRangeChoice` deciding the
    /// default on the used (refined) axis - red on the weak-line sim (a second fit "to 20.0024 keV" ran, lane C P3.log).
    func testP3TheSensitivityStatementAppearsOnlyPastTheDefault() throws {
        for seed in Self.fx.seeds {
            let input = Self.input(seed: seed, quantify: Self.fx.listedSeven)
            let q = try PooledQuantifier.run(input, tables: nil)
            XCTAssertEqual(try XCTUnwrap(FitRangeSensitivityCheck.alternative(for: q)), Self.fx.axis.highValue, accuracy: 1e-12)
            let s = try XCTUnwrap(FitRangeSensitivityCheck.run(input: input, quantification: q))
            XCTAssertNil(s.failure)
            for m in s.moves {
                let sd = try XCTUnwrap(m.inSigma)
                if m.element == "Ti" {
                    XCTAssertTrue((-0.125 ... -0.070).contains(try XCTUnwrap(m.relative)), "seed \(seed) Ti \(String(describing: m.relative))")
                    XCTAssertTrue((-3.4 ... -2.1).contains(sd), "seed \(seed) Ti \(sd) sigma")
                } else {
                    XCTAssertLessThanOrEqual(abs(sd), 2, "seed \(seed) \(m.element) \(sd) sigma")
                }
            }
            let shown = FitRangeSensitivityCheck.attaching(q, s)
            XCTAssertTrue(shown.footerLines.contains { $0.hasPrefix("range sensitivity (not in \u{03C3}): if fitted to 79.97 keV, ") }, "\(shown.footerLines)")
            XCTAssertEqual(shown.rows.map(\.sigma), q.rows.map(\.sigma), "a statement, not a sigma term")
            XCTAssertTrue(SpectroscopyExport.csv(shown, regionName: "synthetic").contains("# range sensitivity (not in \u{03C3}): if fitted to 79.97 keV, "))
        }
        // A typed range: the user chose it, no statement.
        let typed = try PooledQuantifier.run(Self.input(seed: 0, quantify: Self.fx.listedSeven, fitTo: 30), tables: nil)
        XCTAssertNil(FitRangeSensitivityCheck.alternative(for: typed))

        // The weak-line sim, 19.997 keV, refined as in the room.
        let url = Q.fixtures.appendingPathComponent("eds-weakline-sim.json")
        let o = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let axis = EnergyAxis(offset: o["offset"] as! Double, scale: o["scale"] as! Double, size: o["size"] as! Int)
        for level in (o["levels"] as! [[String: Any]]) {
            var rng = SplitMix64(state: 2)
            let counts = (level["expected"] as! [Double]).map { Self.poisson($0, &rng) }
            var m = QuantificationMethod()
            m.elements = ["Al", "Mg", "Si"].map { .init(symbol: $0, role: .quantify, isManual: false) } + [.init(symbol: "O", role: .fitOnly, isManual: false)]
            m.beamEnergyKeV = 200; m.absorptionCorrection = false
            let meta = SpectrumImageMetadata(fileName: "weakline", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: axis.size,
                                             energyOffsetEV: axis.offset * 1000, energyDispersionEV: axis.scale * 1000)
            let input = PooledQuantificationInput(counts: counts, axis: axis, method: m, metadata: meta, regionName: "w", pixelCount: 1)
            let q = try PooledQuantifier.run(input, tables: nil)
            XCTAssertEqual(q.fitRange.source, .defaultReach)
            XCTAssertEqual(q.fitRange.toKeV, q.usedAxis.highValue, "the fit runs to the refined axis end, as before WP3c")
            XCTAssertNil(FitRangeSensitivityCheck.alternative(for: q))
            XCTAssertNil(FitRangeSensitivityCheck.run(input: input, quantification: q), "no second fit on a 20 keV file")
        }
    }

    // MARK: P4

    /// P4: the unlisted-line check at the new default. Four listed (O, Si, Ti, Ni): Ti at the bound, Ge, Cu and Ga named, at%
    /// withheld, Ti's move many sigma (harness: +27.5 ... +29.4 against the 4-element row's sigma; E2's +27.8 ... +29.0 divided by
    /// the 7-element sigma). Mutation M1 (above) - red, through the pinned default (fitTo == 20); the withholding decision itself holds at
    /// both ranges, so this test guards the F1 premise at the default.
    func testP4TheUnlistedCheckStillWithholdsAtTheDefault() throws {
        for seed in Self.fx.seeds {
            let input = Self.input(seed: seed, quantify: Self.fx.listedFour)
            let q = try PooledQuantifier.run(input, tables: Q.tables)
            XCTAssertEqual(q.fitSettings.fitTo, 20)
            let ti = try Self.row(q, "Ti")
            XCTAssertTrue(ti.atBound, "seed \(seed): Ti \(ti.net)")
            let proposal = try UnlistedLineChecker.propose(counts: input.counts.map { Double($0) }, quantification: q)
            let check = UnlistedLineChecker.check(proposal: proposal, input: input, quantification: q)
            XCTAssertTrue(Set(check.names).isSuperset(of: ["Ge", "Cu", "Ga"]), "seed \(seed): \(check.summary)")
            XCTAssertTrue(check.withholds, check.summary)
            let move = try XCTUnwrap(check.moves.first { $0.element == "Ti" }, check.summary)
            XCTAssertGreaterThan((move.after - move.before) / move.sigma, 1, "seed \(seed)")
        }
    }

    // MARK: P5

    /// P5 (the part a unit test can hold; the byte-identical dumps of every 19.997 keV fixture, pristine vs new, are the lane's
    /// harness, P5-dump-{old,new}.log): on a file axis ending at or below 20 keV the default is exactly the old min(axis end, beam),
    /// whatever the refinement does to the used axis; past 20 keV it is 20.
    /// Mutation M4 (above) - red.
    func testP5AxesEndingAt20keVKeepTheOldRange() {
        let file = EnergyAxis(offset: -0.478, scale: 0.005, size: 4096)                      // 19.997 keV
        XCTAssertEqual(FitSettings.defaultFitTo(axis: file, beamEnergy: 200), file.highValue)
        let refined = EnergyAxis(offset: -0.4801, scale: 0.0050058, size: 4096)               // ends at 20.019 keV
        XCTAssertGreaterThan(refined.highValue, 20)
        var m = QuantificationMethod()
        let r = FitRangeChoice(method: m, fileAxis: file, usedAxis: refined, beamEnergy: 200)
        XCTAssertEqual(r.toKeV, refined.highValue)
        XCTAssertEqual(r.source, .defaultReach)
        XCTAssertEqual(r.footerText, "fit range 0.2\u{2013}20.0187 keV (default; the axis end)")
        let gms = EnergyAxis(offset: -0.4698, scale: 0.0050048, size: 4096)                   // 20.025 keV, as the demo GMS file (20.027)
        let g = FitRangeChoice(method: m, fileAxis: gms, usedAxis: gms, beamEnergy: 200)
        XCTAssertEqual(g.toKeV, 20); XCTAssertEqual(g.source, .defaultLimit)
        let beam = FitRangeChoice(method: m, fileAxis: Self.fx.axis, usedAxis: Self.fx.axis, beamEnergy: 15)
        XCTAssertEqual(beam.toKeV, 15); XCTAssertEqual(beam.source, .defaultReach)
        m.background = .wholeRangePolynomial6
        let poly = FitRangeChoice(method: m, fileAxis: Self.fx.axis, usedAxis: Self.fx.axis, beamEnergy: 200)
        XCTAssertEqual(poly.toKeV, Self.fx.axis.highValue, "eXSpy's whole-range polynomial keeps the whole axis")
        XCTAssertEqual(poly.source, .polynomialWholeRange)
    }

    // MARK: P6

    /// P6: Sn planted (L-alpha 3.44 keV inside the default range, K-alpha 25.27 keV outside). At the default the Sn row is on Sn_La,
    /// named in the row (and the table's note, and the CSV's flags), the 5-seed mean within 1 sigma of the plant (harness z +0.49);
    /// at Expert 80 keV it is on Sn_Ka. Mutation M3: the row's choice K-alpha only (`if let k = ka { gi = k }`) - red ("no support").
    func testP6TheSnRowUsesLAlphaInsideTheDefaultAndKAlphaWhenFittedTo80() throws {
        let listed = Self.fx.listedSeven + ["Sn"]
        var diffs: [Double] = [], sigmas: [Double] = []
        for seed in Self.fx.seeds {
            let q = try PooledQuantifier.run(Self.input(seed: seed, quantify: listed, sn: true), tables: Q.tables)
            let sn = try Self.row(q, "Sn")
            XCTAssertNil(sn.failure, "seed \(seed)")
            XCTAssertEqual(sn.groupID, "Sn_La")
            XCTAssertEqual(sn.lineNote, "fitted on Sn_La: Sn_Ka (25.27 keV) lies outside the fit range 0.2\u{2013}20 keV")
            diffs.append(sn.net - Self.fx.plantSn["Sn_La"]!); sigmas.append(sn.sigma)
            if seed == 0 {
                let shown = try XCTUnwrap(QuantifyPresentation.rows(q).first { $0.z == 50 })
                XCTAssertTrue(shown.conflictNote?.contains("fitted on Sn_La") == true, shown.conflictNote ?? "nil")
                XCTAssertTrue(SpectroscopyExport.csv(q, regionName: "s").contains("Sn,Sn_La,"))
                XCTAssertTrue(try XCTUnwrap(q.abundanceRefusal).contains("K lines only"), "the computed k still refuses an L line, by name")
            }
            let q80 = try PooledQuantifier.run(Self.input(seed: seed, quantify: listed, fitTo: 80, sn: true), tables: Q.tables)
            let sn80 = try Self.row(q80, "Sn")
            XCTAssertEqual(sn80.groupID, "Sn_Ka"); XCTAssertNil(sn80.lineNote); XCTAssertNil(sn80.failure)
        }
        let mean = diffs.reduce(0, +) / 5, sigma = sigmas.reduce(0, +) / 5
        XCTAssertLessThan(abs(mean) / sigma, 1, "Sn_La mean - plant \(mean), sigma \(sigma)")
    }

    // MARK: The inspector and the room

    /// The Expert "Fit to" row: the method's value shows, an empty or sub-0.2 keV value is the default (no key).
    /// Mutation: `fitTo = m.fitToKeV` dropped from `QuantifySettings.init(method:)` - red.
    func testTheExpertFitToRoundTrips() {
        var m = QuantificationMethod(); m.fitToKeV = 30
        var s = QuantifySettings(method: m, fileBeamKnown: true, fileBeam: 200)
        XCTAssertEqual(s.fitTo, 30)
        var back = QuantificationMethod(); s.apply(to: &back)
        XCTAssertEqual(back.fitToKeV, 30)
        s.fitTo = 0.1; s.apply(to: &back); XCTAssertNil(back.fitToKeV)
        s.fitTo = nil; s.apply(to: &back); XCTAssertNil(back.fitToKeV)
    }

    /// The room: on an 80 keV file the statement lands with the unlisted-line check, in the footer and the export; the proposer
    /// is not run twice (the statement's refit is a plain fit). Mutation M5: the `FitRangeSensitivityCheck.run` call removed from
    /// `startUnlistedCheck` - red.
    func testTheRoomAttachesTheStatementWithTheCheck() async throws {
        let axis = Self.fx.axis
        var meta = SpectrumImageMetadata(fileName: "realistic-l.emd", filePath: "/tmp/realistic-l.emd", scanWidth: 1, scanHeight: 1,
                                         channelCount: axis.size, energyOffsetEV: axis.offset * 1000, energyDispersionEV: axis.scale * 1000)
        meta.beamEnergyKeV = Self.fx.beam
        let image = LoadedSpectrumImage(image: DenseSpectrumImage(ny: 1, nx: 1, channels: axis.size, counts: Self.counts(seed: 0).map { UInt32($0) }),
                                        metadata: meta, energyAxis: axis)
        let state = AppState()
        state.openSpectrumImage(image)
        let c = state.spectroscopyRoom
        defer { withExtendedLifetime(state) {} }
        for z in [8, 14, 22, 28, 32, 29, 31] { c.model.elements.set(z, .quantify) }
        c.elementsChanged()
        let ok = await c.quantify()
        XCTAssertTrue(ok, c.model.fitFailure ?? "")
        XCTAssertTrue(c.model.resultsFooter.contains("fit range 0.2\u{2013}20 keV (default; axis to 79.97 keV)"), c.model.resultsFooter)
        await c.checkTask?.value
        XCTAssertTrue(c.model.resultsFooter.contains("range sensitivity (not in \u{03C3}): if fitted to"), c.model.resultsFooter)
        XCTAssertTrue(try XCTUnwrap(c.model.export.csv).contains("# range sensitivity (not in \u{03C3}): if fitted to"))
    }
}
