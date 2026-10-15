import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM
@testable import SpectroCore
@testable import SpectroEDX

/// WP3c, "the default fit range, not the continuum" (docs/registrations/wp3c-fit-range-preregistration-2026-10-06.md, P1-P6).
/// The default upper fit limit is min(axis end, beam, 20 keV), decided on the file's axis; a typed limit is Expert
/// (`QuantificationMethod.fitToKeV`, nil = default, absent from the JSON); the at% row falls back from an unsupported K-alpha
/// to the highest supported group, named; a range-sensitivity statement (one fit to the axis end, not a sigma term) runs
/// with the unlisted-line check when the axis runs past the default.
/// Fixture: `Fixtures/eds-realistic-l-sim.json` (generator `../_archive/mac4DSTEM/tools/edx-pins/realistic_l_sim.py`, 80 keV axis, Ti planted 3000,
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
