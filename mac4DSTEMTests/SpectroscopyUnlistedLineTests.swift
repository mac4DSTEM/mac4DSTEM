import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// WP3b F1 (docs/archive/v5/wp3b-fit-robustness-preregistration-2026-10-06.md, P4 and P5): after a Quantify fit the
/// proposer names every unlisted line at or above L_D (sum-peak questions included), and at% is withheld only when fitting
/// them moves a quantified net by more than its reported sigma. Synthetic pool: `Fixtures/eds-unlisted-sim.json`
/// (generator `tools/edx-pins/unlisted_sim.py`, the refuter's S2c recipe), seeded Poisson noise here. The assertions are
/// the DECISIONS (named, withheld), not exact nets, so a continuum change (lane F23) does not re-band them.
@MainActor
final class SpectroscopyUnlistedLineTests: XCTestCase {

    private typealias Q = SpectroscopyQuantifyTests

    /// The measured outcomes for the lane report ($UNLISTED_NOTES via TEST_RUNNER_UNLISTED_NOTES); silent otherwise.
    private func note(_ s: String) {
        guard let path = ProcessInfo.processInfo.environment["UNLISTED_NOTES"] else { return }
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write((s + "\n").data(using: .utf8)!); try? h.close() }
        else { try? (s + "\n").write(toFile: path, atomically: false, encoding: .utf8) }
    }

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

    /// As SpectroscopyProposerTests (PTRS above 10, inversion below): platform independent.
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

    private struct Pool { let expected: [Double]; let axis: EnergyAxis; let beam: Double }

    private static let pool: Pool = {
        let url = Q.fixtures.appendingPathComponent("eds-unlisted-sim.json")
        let o = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let e = o["expected"] as! [Double]
        return Pool(expected: e, axis: EnergyAxis(offset: o["offset"] as! Double, scale: o["scale"] as! Double, size: e.count),
                    beam: o["beam"] as! Double)
    }()

    /// `plant`: extra families (group id -> area) added to the expected counts with the fit's own line shapes before the noise.
    private static func input(seed: UInt64, elements: [(String, QuantificationMethod.ElementRole)],
                              plant: [String: Double] = [:]) -> PooledQuantificationInput {
        var expected = pool.expected
        if !plant.isEmpty {
            let symbols = Array(Set(plant.keys.map { String($0.split(separator: "_")[0]) }))
            let model = EDSLineModel.build(elements: symbols, axis: pool.axis, beamEnergy: pool.beam, resolutionMnKaEV: 130, escapePeaks: false)
            let energies = (0..<pool.axis.size).map { pool.axis.energy(ofChannel: $0) }
            for g in model.groups { if let area = plant[g.id] {
                let col = EDSLineModel.column(of: g.lines, energies: energies, scale: pool.axis.scale)
                for i in expected.indices { expected[i] += area * col[i] }
            } }
        }
        var rng = SplitMix64(state: seed)
        let counts = expected.map { poisson($0, &rng) }
        var m = QuantificationMethod()
        m.elements = elements.map { .init(symbol: $0.0, role: $0.1, isManual: false) }
        m.beamEnergyKeV = pool.beam
        m.absorptionCorrection = false
        let meta = SpectrumImageMetadata(fileName: "eds-unlisted-sim.json", filePath: "", scanWidth: 1, scanHeight: 1,
                                         channelCount: pool.axis.size, energyOffsetEV: pool.axis.offset * 1000,
                                         energyDispersionEV: pool.axis.scale * 1000)
        return PooledQuantificationInput(counts: counts, axis: pool.axis, method: m, metadata: meta, regionName: "synthetic", pixelCount: 1)
    }

    private static let four: [(String, QuantificationMethod.ElementRole)] = [("O", .quantify), ("Si", .quantify), ("Ti", .quantify), ("Ni", .quantify)]

    // MARK: P4

    /// P4 (A2): listed O, Si, Ti, Ni on the S2c pool. The check names Ge, Cu and Ga (Cu and Ga as sum-peak questions: they must
    /// count; all far from a listed line, so elements). Ti, held at the bound, moves by far more than its sigma, and since A2 that
    /// BLANKS NOTHING: at% and the k-free ratio stay on every row, the caveat names the unlisted elements and the largest move,
    /// and the export carries it. `moves` are the numbers the old test asserted (Ti, same bar).
    /// Mutations (each alone): the candidates filtered to `!hasSumPeakQuestion` - red (Cu, Ga missing); the bar `> row.sigma`
    /// changed to `> 1e12` - red (nothing moves); blanking at% again (the deleted `blankAbundance`, 94e26370) - red (T3); the dismissed filter removed - red.
    func testP4FourListedNamesGeCuGaAndKeepsAtPercentWithACaveat() throws {
        let input = Self.input(seed: 0, elements: Self.four)
        let q = try PooledQuantifier.run(input, tables: Q.tables)
        XCTAssertTrue(q.hasAbundance, q.abundanceRefusal ?? "")
        let proposal = try UnlistedLineChecker.propose(counts: input.counts.map { Double($0) }, quantification: q)
        let check = UnlistedLineChecker.check(proposal: proposal, input: input, quantification: q)
        // Real Cu K-alpha is 563 eV = 3.0 FWHM from the listed Ni K-alpha (its K-beta, 217 eV away, is not a reference): an element.
        XCTAssertTrue(Set(check.elementNames).isSuperset(of: ["Ge", "Cu", "Ga"]), "named: \(check.names); \(check.summary)")
        XCTAssertTrue(check.candidates.filter { $0.element == "Cu" }.allSatisfy { $0.besideLine == nil && $0.sumPeakQuestion }, check.summary)
        XCTAssertTrue(check.withholds, check.summary)
        let ti = try XCTUnwrap(check.moves.first { $0.element == "Ti" }, check.summary)
        XCTAssertGreaterThan(abs(ti.after - ti.before), ti.sigma)
        note("P4 seed 0: " + check.summary + " | " + q.rows.map { String(format: "%@ %.0f±%.0f", $0.element, $0.net, $0.sigma) }.joined(separator: ", "))

        let shown = UnlistedLineChecker.withholding(q, check)
        XCTAssertTrue(shown.hasAbundance, "A2: the check never blanks at%")
        XCTAssertEqual(shown.rows.map(\.atomicPercent), q.rows.map(\.atomicPercent))
        XCTAssertEqual(shown.rows.map(\.kFreeRatio), q.rows.map(\.kFreeRatio))
        XCTAssertTrue(shown.rows.contains { $0.atomicPercent != nil })
        XCTAssertEqual(shown.rows.map(\.net), q.rows.map(\.net), "the nets stay")
        let caveat = try XCTUnwrap(shown.abundanceCaveat)
        XCTAssertTrue(caveat.hasPrefix("assumes the listed elements only; unlisted: "), caveat)
        for el in ["Ge", "Cu", "Ga"] { XCTAssertTrue(caveat.contains("\(el) (net "), caveat) }
        XCTAssertTrue(caveat.contains("largest move"), caveat)
        XCTAssertTrue(check.summary.contains("largest move"), check.summary)
        let csv = SpectroscopyExport.csv(shown, regionName: "synthetic")
        XCTAssertTrue(csv.contains("# unlisted-line check: found Ge"), csv)
        XCTAssertTrue(csv.contains("# at% caveat: assumes the listed elements only"), csv)
        XCTAssertFalse(csv.contains("withheld"))
        let tiRow = try XCTUnwrap(csv.split(separator: "\n").first { $0.hasPrefix("Ti,Ti_Ka,") }).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertNotEqual(tiRow[6], "", "at% is exported")
        // A beside candidate has no element number: the room offers "Add" only for elements (A2).
        XCTAssertEqual(QuantifyPresentation.unlistedNote(check).candidates.count, check.elementNames.count)

        // A person switched Ga and Cu Off: the same proposal, neither is a candidate any more.
        var dismissedInput = input
        dismissedInput.method.elements.append(.init(symbol: "Cu", role: .off, isManual: true))
        dismissedInput.method.elements.append(.init(symbol: "Ga", role: .off, isManual: true))
        var qd = q; qd.method = dismissedInput.method
        let without = UnlistedLineChecker.check(proposal: proposal, input: dismissedInput, quantification: qd)
        XCTAssertFalse(without.candidates.contains { $0.element == "Cu" || $0.element == "Ga" }, without.summary)
        XCTAssertTrue(without.elementNames.contains("Ge"))
    }

    // MARK: A2 (Gate D 2026-10-06: ship the quantity, label what is beside a listed line)

    private func groups(_ elements: [String]) -> [FitLineGroup] {
        EDSLineModel.build(elements: elements, axis: Self.pool.axis, beamEnergy: Self.pool.beam, resolutionMnKaEV: 130, escapePeaks: false).groups
    }

    // MARK: The room

    /// The verb returns at once; the table says "checking…" until the check lands, then its finding; the export carries the
    /// check's line and the sigma footer says the sigma is counting only. Mutation: `startUnlistedCheck` not called - red.
    func testTheRoomChecksAfterTheVerbAndExportsTheOutcome() async throws {
        let state = AppState()
        state.openSpectrumImage(try Q.image())
        let c = state.spectroscopyRoom
        defer { withExtendedLifetime(state) {} }
        for z in [13, 12, 14, 29] { c.model.elements.set(z, .quantify) }
        c.model.elements.set(8, .fitOnly); c.model.elements.set(31, .fitOnly)
        c.elementsChanged()
        let ok = await c.quantify()
        XCTAssertTrue(ok, c.model.fitFailure ?? "")
        let pending = try XCTUnwrap(c.model.unlisted)
        XCTAssertTrue(pending.checking)
        // Pending: the nets only; at%, the k-free ratios and the Mg/Si line wait, and no second note repeats "checking".
        XCTAssertFalse(c.model.results.isEmpty)
        // A2: the numbers are shown at once (the caveat says the check is running).
        let pendingAtomic = c.model.results.map(\.hasAbundance)
        XCTAssertTrue(c.model.resultsFooter.contains(PooledQuantifier.sigmaScopeLine))
        let early = try XCTUnwrap(c.model.export.csv)
        XCTAssertTrue(early.contains("# unlisted-line check: check not finished when this was exported"))
        XCTAssertTrue(early.contains("# at% caveat: unlisted-line check running"))
        let al = try XCTUnwrap(early.split(separator: "\n").first { $0.hasPrefix("Al,Al_Ka,") }).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(al[6] != "", pendingAtomic.first == true)
        // The user's map mode survives the check landing.
        c.model.mapMode = .atomic
        await c.checkTask?.value
        XCTAssertEqual(c.model.mapMode, .atomic)
        let done = try XCTUnwrap(c.model.unlisted)
        XCTAssertFalse(done.checking, done.text)
        XCTAssertTrue(done.text.hasPrefix("Unlisted lines"), done.text)
        let csv = try XCTUnwrap(c.model.export.csv)
        XCTAssertFalse(csv.contains("not finished"))
        XCTAssertTrue(csv.contains("# unlisted-line check: "))
        XCTAssertEqual(c.model.results.map(\.hasAbundance), pendingAtomic, "the check landing blanks nothing")
        XCTAssertFalse(csv.contains("withheld"))
    }

    /// A check from an older fit never lands: `landCheck` with a stale generation leaves the shown note; the current one lands.
    /// Mutation: the `gen == generation` guard removed from `landCheck` - red.
    func testACheckFromAnOlderFitNeverLands() async throws {
        let state = AppState()
        let image = try Q.image()
        state.openSpectrumImage(image)
        let c = state.spectroscopyRoom
        defer { withExtendedLifetime(state) {} }
        for z in [13, 12, 14] { c.model.elements.set(z, .quantify) }
        c.elementsChanged()
        let ok = await c.quantify()
        XCTAssertTrue(ok)
        await c.checkTask?.value
        let before = c.model.unlisted
        let q = try PooledQuantifier.run(Q.input(Q.method(elements: [("Al", .quantify), ("Mg", .quantify), ("Si", .quantify)]), image: image), tables: Q.tables)
        let zr = UnlistedLineCheck.Candidate(element: "Zr", group: "Zr_La", net: 900, detectionLimit: 400, sumPeakQuestion: false)
        let stale = UnlistedLineChecker.withholding(q, UnlistedLineCheck(candidates: [zr], moves: []))
        c.landCheck(stale, region: 0, generation: c.generation - 1)
        XCTAssertEqual(c.model.unlisted, before)
        c.landCheck(stale, region: 0, generation: c.generation)
        XCTAssertEqual(c.model.unlisted?.text, "Unlisted lines found: Zr", "positive control: the current generation lands")
    }

    /// "Add as Fit only" lists the named elements as Fit only; "Dismiss" switches them Off as the person's choice, and the
    /// method (what the replay step records) keeps the Off entry. Mutation: the Off entries left out of
    /// `mirrorElementsToSession` - red.
    func testTheTwoButtonsSetRolesAndTheMethodRecordsADismissal() throws {
        let state = AppState()
        state.openSpectrumImage(try Q.image())
        let c = state.spectroscopyRoom
        c.model.elements.set(13, .quantify); c.elementsChanged()
        c.model.unlisted = UnlistedLineNote(text: "Unlisted lines found: Zr, Lu", detail: nil, candidates: [40, 71])
        c.dismissUnlisted()
        let off = state.spectroscopy.method.elements.filter { $0.role == .off }
        XCTAssertEqual(Set(off.map(\.symbol)), ["Zr", "Lu"]); XCTAssertTrue(off.allSatisfy(\.isManual))
        c.model.unlisted = UnlistedLineNote(text: "Unlisted lines found: Zr", detail: nil, candidates: [40])
        c.addUnlistedAsFitOnly()
        XCTAssertEqual(state.spectroscopy.method.elements.first { $0.symbol == "Zr" }?.role, .fitOnly)
        XCTAssertEqual(state.spectroscopy.method.elements.first { $0.symbol == "Lu" }?.role, .off)
    }
}
