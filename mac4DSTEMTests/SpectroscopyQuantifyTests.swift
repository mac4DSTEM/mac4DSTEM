import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM
@testable import SpectroCore
@testable import SpectroEDX

/// v5.0 R3: the Quantify verb on the simulated tiny GMS fixture (`demo-edx-tiny.dm4` + truth): the pooled fit, its
/// sigma as named terms, at% only with a k source, absorption refused where the geometry is unknown.
@MainActor
final class SpectroscopyQuantifyTests: XCTestCase {

    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    /// The six tables as the app reads them: SpectroKit's own copy (`Bundle.module`, inside the app bundle) since S4.
    static let tables = QuantificationTables.bundled()!

    static func image() throws -> LoadedSpectrumImage {
        try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: fixtures.appendingPathComponent("demo-edx-tiny.dm4").path, fourD: nil))
    }

    /// Truth: the summed expected counts of the named component over the whole map.
    static func truthArea(_ component: String) throws -> Double {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("demo-edx-tiny.truth.json"))
        let t = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let names = try XCTUnwrap(t["component_names"] as? [String])
        let arrays = try XCTUnwrap(t["arrays"] as? [String: Any])
        let comp = try XCTUnwrap(arrays["component_expected_counts"] as? [[[Double]]])
        let i = try XCTUnwrap(names.firstIndex(of: component))
        return comp[i].flatMap { $0 }.reduce(0, +)
    }

    static func method(elements: [(String, QuantificationMethod.ElementRole)] = [("Al", .quantify), ("Mg", .quantify), ("Si", .quantify), ("Cu", .quantify), ("O", .fitOnly), ("Ga", .fitOnly)]) -> QuantificationMethod {
        var m = QuantificationMethod()
        m.elements = elements.map { QuantificationMethod.ElementState(symbol: $0.0, role: $0.1, isManual: false) }
        m.beamEnergyKeV = 200          // the GMS EDS object does not state it
        return m
    }

    static func input(_ method: QuantificationMethod, image: LoadedSpectrumImage) -> PooledQuantificationInput {
        PooledQuantificationInput(counts: image.sum(mask: nil), axis: image.energyAxis, method: method, metadata: image.metadata,
                                  regionName: "Whole map", pixelCount: image.metadata.pixelCount)
    }

    /// The weak-line bias note is in the result, and the room's short sentence keeps the fit's full text as its help.
    /// Mutation: `warnings` returns the raw text only (detail nil) - red.
    func testTheWeakLineWarningIsShown() throws {
        let r = try PooledQuantifier.run(Self.input(Self.method(), image: try Self.image()), tables: Self.tables)
        XCTAssertTrue(r.warnings.contains(ContinuumForm.weakLineBiasNote))
        let shown = QuantifyPresentation.warnings(r.warnings)
        let w = try XCTUnwrap(shown.first { $0.detail == ContinuumForm.weakLineBiasNote })
        XCTAssertTrue(w.text.hasPrefix("Weak-line bias"))
        XCTAssertLessThan(w.text.count, 200)
    }

    /// The room's weak-line sentence quotes the neighbour that was measured: Mg's ≈ 300 counts when Mg is fitted, Si's own −164 of
    /// 1 879 when Si is the only weak neighbour. Mutation: drop the Si branch (Si-only fits quote Mg's 300) - red.
    func testTheWeakLineSentenceQuotesTheFittedNeighbour() {
        let si = QuantifyPresentation.weakLineSentence(elements: ["Al", "Si"])
        XCTAssertTrue(si.contains("Si K\u{03B1}") && si.contains("164"), si)
        XCTAssertFalse(si.contains("300"), si)
        for elements in [["Al", "Mg"], ["Al", "Mg", "Si"], []] {
            XCTAssertTrue(QuantifyPresentation.weakLineSentence(elements: elements).contains("\u{2248} 300"), "\(elements)")
        }
    }

    // MARK: - at% needs a k source

    /// Typed k with no source is not a k: no at% anywhere, the reason says why, the k-free ratio is still there.
    /// With a source and a date the typed k is used and named; the computed one carries its source string and the
    /// unvalidated validation. Rows sum to 100 and carry named sigma terms.
    /// Mutation: `isComplete` ignoring the source (QuantificationMethod) - red; at% produced without the k set - red.
    func testAtPercentIsAbsentWithoutAKSourceAndNamedWithOne() throws {
        let image = try Self.image()
        var m = Self.method()
        m.kFactorSource = .typed                                  // nothing typed
        var r = try PooledQuantifier.run(Self.input(m, image: image), tables: Self.tables)
        XCTAssertFalse(r.hasAbundance)
        XCTAssertTrue(try XCTUnwrap(r.abundanceRefusal).contains("typed k is incomplete"))
        XCTAssertTrue(r.rows.allSatisfy { $0.atomicPercent == nil && $0.weightPercent == nil })
        XCTAssertNotNil(r.rows[1].kFreeRatio, "the k-free ratio does not need a k")
        XCTAssertTrue(r.footerLines.contains { $0.hasPrefix("at%: not computed") })

        let computed = try PooledQuantifier.run(Self.input(Self.method(), image: image), tables: Self.tables)
        XCTAssertTrue(computed.hasAbundance)
        XCTAssertEqual(computed.rows.compactMap(\.atomicPercent).reduce(0, +), 100, accuracy: 1e-9)
        XCTAssertEqual(computed.rows.compactMap(\.weightPercent).reduce(0, +), 100, accuracy: 1e-9)
        XCTAssertTrue(try XCTUnwrap(computed.kSet).source.contains("Bote-Salvat"))
        XCTAssertEqual(computed.method.kSource.contains("Bote-Salvat"), true, "the recorded method names the computed source")
        XCTAssertEqual(computed.method.kDate, QuantificationMethod.computedKTableIdentity)
        XCTAssertEqual(PooledQuantification.abundanceValidation, "none")
        XCTAssertTrue(ValidationState.isUnvalidated(PooledQuantification.abundanceValidation))
        // The sigma terms are named: counting, k (20 % flat; Al is the reference), absorption (refused here), no thickness.
        let mg = try XCTUnwrap(computed.rows.first { $0.element == "Mg" })
        XCTAssertTrue(mg.atomicTermsText.hasPrefix("counting "), mg.atomicTermsText)
        XCTAssertTrue(mg.atomicTermsText.contains("k ") && mg.atomicTermsText.contains("absorption not applied"))
        XCTAssertTrue(mg.atomicTermsText.contains(" at% \u{00B7} absorption not applied"), mg.atomicTermsText)
        let terms = try XCTUnwrap(mg.atomicTerms)
        XCTAssertEqual(terms[.k], 0.2, accuracy: 0.05, "Mg k moved by 20 % moves its share by about that much")
        XCTAssertEqual(terms[.absorption], 0); XCTAssertEqual(terms[.thickness], 0)
        XCTAssertEqual(try XCTUnwrap(computed.rows.first { $0.element == "Al" }).atomicTerms?[.k] ?? 1, 0, accuracy: 0.05, "the reference carries sigma_k = 0, so Al's k term is small")
        XCTAssertEqual(try XCTUnwrap(mg.atomicSigma), mg.atomicTerms!.combined * mg.atomicPercent!, accuracy: 1e-9)

        // A complete typed k: the user's source and date, and no computed string.
        var typed = Self.method(); typed.kFactorSource = .typed
        typed.kSource = "Williams & Carter, table 35.1 (test values)"; typed.kDate = "2026-10-06"; typed.kReference = "Al"
        typed.typedK = [("Al", 1.0), ("Mg", 1.1), ("Si", 1.2), ("Cu", 1.9)].map { .init(element: $0.0, k: $0.1) }
        r = try PooledQuantifier.run(Self.input(typed, image: image), tables: Self.tables)
        XCTAssertTrue(r.hasAbundance)
        XCTAssertEqual(r.kSet?.kind, .typed)
        XCTAssertTrue(r.footerLines.contains { $0.contains("Williams & Carter") && $0.contains("2026-10-06") })
    }

    func testSettingsRoundTripThroughTheMethod() {
        var s = QuantifySettings()
        s.estimator = .poissonMaximumLikelihood; s.background = .wholeRangePolynomial6; s.polyOrder = 4
        s.sigmaK = 30; s.lockEnergyAxis = true; s.thickness = 80; s.thicknessSigma = 15; s.absorption = false
        s.fileBeamKnown = false; s.beamEnergy = 200
        s.kSource = .typed; s.typedSource = "src"; s.typedDate = "2026-10-06"; s.typedReference = "Al"
        s.typed = [TypedKEntry(element: "Al", k: 1, sigmaPercent: nil), TypedKEntry(element: "Mg", k: nil, sigmaPercent: nil)]
        var m = QuantificationMethod(); s.apply(to: &m)
        XCTAssertEqual(m.estimator, .poissonMaximumLikelihood); XCTAssertEqual(m.polynomialOrder, 4)
        XCTAssertEqual(m.sigmaK, 0.3, accuracy: 1e-12); XCTAssertEqual(m.lockEnergyAxis, true)
        XCTAssertEqual(m.thickness, .init(nanometres: 80, sigmaNanometres: 15)); XCTAssertFalse(m.absorptionCorrection)
        XCTAssertEqual(m.beamEnergyKeV, 200); XCTAssertEqual(m.typedK.map(\.element), ["Al"], "an empty k is not a factor")
        let back = QuantifySettings(method: m, fileBeamKnown: false)
        XCTAssertEqual(back.polyOrder, 4); XCTAssertEqual(back.sigmaK ?? 0, 30, accuracy: 1e-9); XCTAssertEqual(back.typedSource, "src")
        // A file that states its beam energy never has the typed one written into the method.
        var known = s; known.fileBeamKnown = true; known.fileBeam = 200
        var m2 = QuantificationMethod(); known.apply(to: &m2); XCTAssertNil(m2.beamEnergyKeV)
        // Computed k clears the typed values.
        var c = s; c.kSource = .computed
        var m3 = m; c.apply(to: &m3); XCTAssertTrue(m3.typedK.isEmpty); XCTAssertEqual(m3.kSource, "")
    }

    // MARK: - The room: verb, live fit, replay step

    /// The controller holds its session weakly: the caller keeps the AppState alive for the length of the test.
    private func openedRoom() throws -> (AppState, SpectroscopyRoomController) {
        let state = AppState()
        state.openSpectrumImage(try Self.image())
        state.spectroscopyRoom.autoIDOnOpen?.cancel()   // these tests drive Auto ID by hand, or not at all
        let c = state.spectroscopyRoom
        for z in [13, 12, 14, 29] { c.model.elements.set(z, .quantify) }
        c.model.elements.set(8, .fitOnly); c.model.elements.set(31, .fitOnly)
        c.elementsChanged()
        return (state, c)
    }

    /// The simulated GMS EDS object states its beam energy (Microscope Info.Voltage): the inspector does not ask, and the verb fits.
    /// The table holds the table then holds fitted areas, the k-free column, at% badged unvalidated, the sigma-term
    /// line and the warnings; the replay records ONE quantification step whose method hash is the fitted method's.
    /// Mutation: `recordQuantification` not called in `runPrimaryWorkspaceTask` - red.
    func testTheVerbFitsRecordsTheStepAndShowsTheResults() async throws {
        let (state, c) = try openedRoom()
        XCTAssertEqual(c.model.quantify.shownBeam, 200); XCTAssertEqual(c.model.quantify.beamPhrase, "from the file")
        XCTAssertFalse(c.model.hasFit)
        state.navigation.workspaceArea = .spectroscopy
        await state.runPrimaryWorkspaceTask()
        await c.checkTask?.value   // WP3b F1: at% is held until the unlisted-line check lands
        let m = c.model
        XCTAssertTrue(m.hasFit); XCTAssertNil(m.fitFailure)
        XCTAssertEqual(m.results.map { PeriodicLayout.symbol($0.z) }, ["Mg", "Al", "Si", "Cu"].sorted { PeriodicLayout.z(of: $0)! < PeriodicLayout.z(of: $1)! })
        XCTAssertTrue(m.results.allSatisfy { $0.hasAbundance && $0.hasKFree && $0.failure == nil })
        XCTAssertEqual(m.validation, "none"); XCTAssertTrue(m.unvalidated)
        let mg = try XCTUnwrap(m.results.first { $0.z == 12 })
        XCTAssertTrue(mg.sigmaTerms.hasPrefix("counting "), mg.sigmaTerms)
        XCTAssertNotNil(mg.sigmaTermsWeight)
        XCTAssertNotNil(m.ratioLine)
        XCTAssertTrue(m.fitWarnings.contains { $0.detail == ContinuumForm.weakLineBiasNote })
        XCTAssertTrue(m.resultsFooter.contains("least squares, unweighted"))
        XCTAssertTrue(m.fitFooter.contains("least squares, unweighted"))
        XCTAssertTrue(m.series.hasModel && m.series.hasBackground && m.series.fitChannels != nil)
        XCTAssertNotNil(m.quantify.quality); XCTAssertNotNil(m.image.energyAxisRefined)
        XCTAssertTrue(try XCTUnwrap(m.quantify.absorptionNote).contains("GMS"))

        let steps = state.replay.lineage.nodes.filter { $0.kind == "quantification" }
        XCTAssertEqual(steps.count, 1)
        let hash = try XCTUnwrap(steps[0].parameters["method_hash"])
        XCTAssertEqual(hash, state.spectroscopy.method.hash, "the recorded step names the fitted method, kSource filled")
        XCTAssertEqual(steps[0].parameters["region_kind"], "wholeMap")
        // Spec 2 D-11: `method` is the short hash, the JSON the restore needs sits under `method_json`, and the readable keys are there.
        XCTAssertEqual(steps[0].parameters["method"], String(hash.prefix(8)))
        XCTAssertTrue(try XCTUnwrap(steps[0].parameters["method_json"]).contains("Bote-Salvat"))
        XCTAssertEqual(steps[0].parameters["k_factors"], "Computed"); XCTAssertEqual(steps[0].parameters["background"], "Empirical")
        XCTAssertEqual(steps[0].parameters["absorption"], "on"); XCTAssertEqual(steps[0].parameters["beam_energy_kev"], "200")
        XCTAssertEqual(steps[0].parameters["elements"], "O, Mg, Al, Si, Cu, Ga")
    }

    /// After the verb the fit is live: a setting changes the numbers without another press, and an unchanged setting
    /// (the results writing the quality back) does not re-fit. Mutation: `quantifySettingsChanged` not refreshing - red.
    func testTheFitIsLiveAfterTheVerb() async throws {
        let (state, c) = try openedRoom()
        defer { withExtendedLifetime(state) {} }
        c.model.quantify.beamEnergy = 200
        let ok = await c.quantify()
        XCTAssertTrue(ok, c.model.fitFailure ?? "no failure")
        let before = c.model.fitFooter
        XCTAssertFalse(before.lowercased().contains("poisson"))
        c.model.quantify.estimator = .poissonMaximumLikelihood
        c.quantifySettingsChanged()
        await c.lastRefresh?.value
        XCTAssertTrue(c.model.fitFooter.lowercased().contains("poisson"), c.model.fitFooter)
        XCTAssertTrue(c.model.quantify.quality?.hasPrefix("reduced deviance") == true)
        // Absorption off: the row's terms change with it and the note goes.
        c.model.quantify.absorption = false
        c.quantifySettingsChanged()
        await c.lastRefresh?.value
        XCTAssertNil(c.model.quantify.absorptionNote)
        // No re-fit for an identical setting.
        let task = c.lastRefresh
        c.quantifySettingsChanged()
        XCTAssertEqual(c.lastRefresh == nil, task == nil)
    }

    /// A row without an at% shows "\u{2014}" in the abundance cell, never 0 (a missing number is not zero).
    /// Mutation: `fitCells` ignoring `hasAbundance` - red.
    func testARowWithoutAnAbundanceShowsADash() {
        var row = ResultRow(z: 12, netCounts: 27, netSigma: 10, kFreeRatio: 0.06, kFreeSigma: 0.02, atPercent: 0, atSigma: 0,
                            wtPercent: 0, wtSigma: 0, sigmaTerms: "")
        row.hasAbundance = false
        XCTAssertEqual(ResultFormat.fitCells(row, unit: .atomic, hasFit: true).abundance, "\u{2014}")
        XCTAssertEqual(ResultFormat.fitCells(row, unit: .weight, hasFit: true).abundance, "\u{2014}")
        XCTAssertNotEqual(ResultFormat.fitCells(row, unit: .atomic, hasFit: true).kFree, "\u{2014}")
        row.hasAbundance = true; row.atPercent = 5.2; row.atSigma = 1.1
        XCTAssertEqual(ResultFormat.fitCells(row, unit: .atomic, hasFit: true, locale: Locale(identifier: "en_US")).abundance, "5.2 \u{00B1} 1.1")
    }

    /// A removed region takes its spectrum and refinements with it (its id is reused by the next drawn region), but only
    /// its own: region 2's keys never match region 12's. Mutation: `hasPrefix` replaced by `contains` - red.
    func testAForgottenRegionLeavesNoStaleSpectrumOrRefinement() throws {
        let cache = SpectrumComputeCache()
        let image = try Self.image()
        let r = try PooledQuantifier.run(Self.input(Self.method(), image: image), tables: Self.tables)
        let refinement = try XCTUnwrap(r.refinement)
        cache.setSpectrum([1, 2, 3], 2); cache.setSpectrum([4], 12)
        cache.setRefinement(refinement, "2|Al|x"); cache.setRefinement(refinement, "12|Al|x")
        cache.forget(region: 2)
        XCTAssertNil(cache.spectrum(2)); XCTAssertNil(cache.refinement("2|Al|x"))
        XCTAssertNotNil(cache.spectrum(12)); XCTAssertNotNil(cache.refinement("12|Al|x"))
    }

    /// The abundance column says "no absorption" whenever the at% was computed without the correction.
    /// Mutation: the helper ignores the flag - red.
    func testTheAbundanceHeaderNamesAMissingAbsorption() {
        XCTAssertEqual(ResultFormat.abundanceHeader(unit: .atomic, noAbsorption: true), "at% \u{00B1} \u{03C3} \u{00B7} no absorption")
        XCTAssertEqual(ResultFormat.abundanceHeader(unit: .weight, noAbsorption: false), "wt% \u{00B1} \u{03C3}")
    }

    func testTheRoomFlagsAtPercentWithoutAbsorption() async throws {
        let (state, c) = try openedRoom()
        defer { withExtendedLifetime(state) {} }
        c.model.quantify.beamEnergy = 200
        let ok = await c.quantify()
        XCTAssertTrue(ok)
        await c.checkTask?.value   // WP3b F1: at% is held until the unlisted-line check lands
        XCTAssertTrue(c.model.abundanceWithoutAbsorption, "GMS: absorption refused, at% shown and marked")
    }

    /// k-free reference: kReference, else Al when quantified and measured (even if not the largest), else the largest.
    /// Mutation: the Al preference removed - red; the kReference branch removed - red.
    func testTheKFreeReferenceRule() throws {
        let image = try Self.image()
        var counts = image.sum(mask: nil)
        // Shrink Al K-alpha (~1.487 keV, file axis) by 20: Al stays measured but Si becomes the largest area.
        let ch = Int(((1.4865 - image.energyAxis.offset) / image.energyAxis.scale).rounded())
        for c in (ch - 6)...(ch + 6) { counts[c] /= 20 }
        var input = Self.input(Self.method(), image: image); input.counts = counts
        var r = try PooledQuantifier.run(input, tables: Self.tables)
        let al = try XCTUnwrap(r.rows.first { $0.element == "Al" }), si = try XCTUnwrap(r.rows.first { $0.element == "Si" })
        XCTAssertGreaterThan(si.net, al.net); XCTAssertGreaterThan(al.net, 0)
        XCTAssertEqual(r.referenceElement, "Al")
        XCTAssertTrue(r.footerLines.contains("k-free ratio: net / net(Al)"))
        input.method.kReference = "Si"
        r = try PooledQuantifier.run(input, tables: Self.tables)
        XCTAssertEqual(r.referenceElement, "Si")
        r = try PooledQuantifier.run(Self.input(Self.method(elements: [("Mg", .quantify), ("Si", .quantify), ("Cu", .quantify)]), image: image), tables: Self.tables)
        XCTAssertEqual(r.referenceElement, "Si", "no Al quantified: the largest area")
    }
}
