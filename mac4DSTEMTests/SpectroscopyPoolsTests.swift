//
//  SpectroscopyPoolsTests.swift
//  E1 (docs/archive/v5/e1-pooling-preregistration-2026-10-08.md): pooled spectra by phase, diffraction group and "Not indexed"
//  in the Spectroscopy room. H1-H8 here; H9 is a separate run on the simulated joint file. The chain tests run twice: through
//  an INJECTED non-identity record (the 4 x 4 -> 2 x 2 mirrored bin of RegistrationTests, which the app cannot create) and
//  through the identity on a non-square 5 x 3 image. Each test names the mutation it catches; each was broken once (the lane report).
//

import XCTest
@testable import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// A spectrum image that remembers how it was summed: a pool must never be summed with `mask: nil` (every pixel).
final class PoolSpyImage: SpectrumImageSource, @unchecked Sendable {
    let image: any SpectrumImage
    nonisolated let metadata: SpectrumImageMetadata
    nonisolated let energyAxis: EnergyAxis
    nonisolated let scanImage: [Float]? = nil
    private let lock = NSLock()
    private var nilMaskCalls = 0
    nonisolated var ny: Int { image.ny }
    nonisolated var nx: Int { image.nx }
    nonisolated var channels: Int { image.channels }

    init(image: any SpectrumImage, sameScan: Bool) {
        self.image = image
        var meta = SpectrumImageMetadata(fileName: "e1.emd", filePath: "/tmp/e1.emd", scanWidth: image.nx, scanHeight: image.ny,
                                         channelCount: image.channels, energyOffsetEV: 0, energyDispersionEV: 10)
        meta.beamEnergyKeV = 200
        meta.sameScanAs4DCube = sameScan
        metadata = meta
        energyAxis = EnergyAxis(offset: 0, scale: 0.01, size: image.channels)
    }
    var nilMasks: Int { lock.withLock { nilMaskCalls } }
    func resetSpy() { lock.withLock { nilMaskCalls = 0 } }
    nonisolated func sum(mask: PixelMask?) -> [UInt64] {
        if mask == nil { lock.withLock { nilMaskCalls += 1 } }
        return image.sum(mask: mask)
    }
    nonisolated func windowSums(_ ranges: [Range<Int>]) -> [[UInt64]] { image.windowSums(ranges) }
}

@MainActor
final class SpectroscopyPoolsTests: XCTestCase {
    private var keep: [AppState] = []
    private let channels = 6

    // MARK: fixtures

    /// Deterministic, different in every pixel and channel.
    private func raw(nx: Int, ny: Int) -> [UInt32] {
        (0..<(nx * ny * channels)).map { i in UInt32((i / channels) * 5 + (i % channels) * 3 + ((i / channels) * (i % channels)) % 7 + 1) % 17 }
    }
    private func dense(nx: Int, ny: Int) -> DenseSpectrumImage {
        DenseSpectrumImage(ny: ny, nx: nx, channels: channels, counts: raw(nx: nx, ny: ny))
    }
    private func sparse(nx: Int, ny: Int) throws -> SparseSpectrumImage {
        let r = raw(nx: nx, ny: ny)
        var offsets = [0], idx: [UInt16] = [], cnt: [UInt32] = []
        for p in 0..<(nx * ny) {
            for c in 0..<channels where r[p * channels + c] > 0 { idx.append(UInt16(c)); cnt.append(r[p * channels + c]) }
            offsets.append(cnt.count)
        }
        return try SparseSpectrumImage(ny: ny, nx: nx, channels: channels, rowOffsets: offsets, channelIndex: idx, counts: cnt)
    }
    /// The hand sum of the spectrum pixels `members`, channel by channel, as Double (what the room draws).
    private func handSum(nx: Int, ny: Int, _ members: [Int]) -> [Double] {
        let r = raw(nx: nx, ny: ny)
        return (0..<channels).map { c in members.reduce(0.0) { $0 + Double(r[$1 * channels + c]) } }
    }

    /// 'A' 'B' 'C': indexed phases 0, 1, 2. 'N': not indexed, keeping the stale phaseIndex 0. 'M': matrix (phase 0).
    private func phaseMap(_ w: Int, _ h: Int, _ chars: String, names: [String] = ["A", "B"]) -> PhaseMap {
        var m = PhaseMap(width: w, height: h, matrixEntryIndex: -1, phaseNames: names, matrixPhaseIndex: 0)
        for (i, ch) in chars.enumerated() {
            switch ch {
            case "A": m.results[i].verdict = .indexed; m.results[i].phaseIndex = 0
            case "B": m.results[i].verdict = .indexed; m.results[i].phaseIndex = 1
            case "C": m.results[i].verdict = .indexed; m.results[i].phaseIndex = 2
            case "M": m.results[i].verdict = .matrix; m.results[i].phaseIndex = 0
            default: m.results[i].verdict = .notIndexed; m.results[i].phaseIndex = 0
            }
        }
        return m
    }
    private func groups(_ w: Int, _ h: Int, _ groupOf: [Int], k: Int) -> DiffractionEmbedding.Result {
        DiffractionEmbedding.Result(scanWidth: w, scanHeight: h, coordinates: [Float](repeating: 0, count: w * h), mean: [0], basis: [0],
                                    explainedVariance: [1], groupOf: groupOf, groupCentroids: [Float](repeating: 0, count: k))
    }
    private static func runRecord() -> PhaseMappingProduct.RunRecord {
        PhaseMappingProduct.RunRecord(
            phaseSignature: "e1", reference: PhaseReferenceSettings(), matching: PhaseVectorSettings(), libraryEntryCount: 1,
            matrixEntryIndex: 0, matrixInPlaneDegrees: .nan, worstChanceMatchPercent: 0, invAngstromPerPixel: 0.01,
            qScaleIsPhysical: false, peakCount: 0,
            calibration: PhaseMappingProduct.CalibrationStamp(calibration: Calibration(), referenceOrigin: (0, 0)))
    }
    /// 4 x 4 scan -> 2 x 2 spectrum grid, mirrored in x: each spectrum pixel is a 2 x 2 block of scan pixels (RegistrationTests).
    private let mirror = RegistrationRecordM2(matrix: [-0.5, 0, 1.25, 0, 0.5, -0.25], source: .typed,
                                              scanWidth: 4, scanHeight: 4, spectrumWidth: 2, spectrumHeight: 2)
    /// Spectrum pixel (row-major v*2+u) <- scan block: 1 <- x 0-1,y 0-1 (all A); 0 <- x 2-3,y 0-1 (2 A, 2 B: an exact TIE);
    /// 3 <- x 0-1,y 2-3 (3 B, 1 not indexed: B at 0.75); 2 <- x 2-3,y 2-3 (3 A, 1 B: A at 0.75).
    private let mirrorMap = "AAAB" + "AAAB" + "NBAA" + "BBAB"
    private let path = "/tmp/e1.h5"

    private func joint(image: any SpectrumImage, sameScan: Bool = true, record: RegistrationRecordM2? = nil,
                       map: PhaseMap? = nil, groups g: DiffractionEmbedding.Result? = nil) async -> (AppState, SpectroscopyRoomController, PoolSpyImage) {
        let state = AppState()
        keep.append(state)
        state.descriptor = DatasetDescriptor(filePath: path, datasetPath: "/d", shape: [3, 5, 8, 8], dtypeDescription: "float32", chunkShape: nil)
        let source = PoolSpyImage(image: image, sameScan: sameScan)
        state.openSpectrumImage(source)
        state.spectroscopyRoom.autoIDOnOpen?.cancel()
        if let record { state.spectroscopy.registration = record; state.spectroscopy.registeredCubePath = path }
        if let map { state.phaseMapping.publish(map, ranWith: Self.runRecord()) }
        if let g { state.diffractionGroups.publish(g, ranWith: DiffractionEmbedding.Settings()) }
        state.refreshSpectroscopyPools()
        await state.spectroscopy.poolTask?.value
        await state.spectroscopyRoom.lastRefresh?.value
        return (state, state.spectroscopyRoom, source)
    }

    private func shown(_ c: SpectroscopyRoomController, pool id: Int) async -> [Double] {
        c.selectRegion(id: id)
        await c.lastRefresh?.value
        return c.model.series.data
    }

    // MARK: H1

    /// The pool through labels -> transport -> session region -> `compute` is the channel-wise integer sum of its members, on a
    /// non-square 5 x 3 image, dense AND sparse (identity), and on the mirrored bin (a tie, a 0.75 pixel).
    /// Mutations: pool mask built from a record that ignores the mirror - red (mirrored); the last pixel dropped from the mask - red;
    /// `groupOf` off by one - red (H3); the verdict condition dropped - red (H3).
    func testAPoolIsTheChannelWiseSumOfItsMembersDenseSparseAndMirrored() async throws {
        //                 x0 x1 x2 x3 x4
        let chars = "AABBN" + "AABNN" + "ABBBN"
        let map = phaseMap(5, 3, chars)
        let members: (Character) -> [Int] = { ch in chars.enumerated().filter { $0.element == ch }.map(\.offset) }
        for image in [dense(nx: 5, ny: 3) as any SpectrumImage, try sparse(nx: 5, ny: 3)] {
            let (state, c, _) = await joint(image: image, map: map)
            XCTAssertNotNil(state.spectroscopy.registration, "a GMS joint attach states the identity")
            XCTAssertEqual(state.spectroscopy.registration?.sourceNote, "same scan, identity; no lag check")
            for (id, ch) in [(1000, Character("A")), (1001, "B"), (1900, "N")] {
                let got = await shown(c, pool: id)
                XCTAssertEqual(got, handSum(nx: 5, ny: 3, members(ch)), "\(image is DenseSpectrumImage ? "dense" : "sparse") pool \(ch)")
            }
        }
        // Mirrored bin: A = spectrum pixels 1 and 2, B = pixel 3; pixel 0 is the tie and joins none.
        let (_, c, _) = await joint(image: dense(nx: 2, ny: 2), sameScan: false, record: mirror, map: phaseMap(4, 4, mirrorMap))
        let a = await shown(c, pool: 1000), b = await shown(c, pool: 1001)
        XCTAssertEqual(a, handSum(nx: 2, ny: 2, [1, 2]))
        XCTAssertEqual(b, handSum(nx: 2, ny: 2, [3]))
        // A non-square, non-mirrored 2 x 2 bin, 6 x 4 scan -> 3 x 2 spectrum grid. The identity and the square mirror cannot tell nx from ny
        // (a swapped grid keeps the row-major index); this one can.
        let bin = RegistrationRecordM2(matrix: [0.5, 0, -0.25, 0, 0.5, -0.25], source: .typed,
                                       scanWidth: 6, scanHeight: 4, spectrumWidth: 3, spectrumHeight: 2)
        let wide = String((0..<24).map { i -> Character in [1, 3, 4].contains((i / 6 / 2) * 3 + (i % 6) / 2) ? "A" : "B" })
        let (_, c2, _) = await joint(image: dense(nx: 3, ny: 2), sameScan: false, record: bin, map: phaseMap(6, 4, wide))
        let a2 = await shown(c2, pool: 1000), b2 = await shown(c2, pool: 1001)
        XCTAssertEqual(a2, handSum(nx: 3, ny: 2, [1, 3, 4]))
        XCTAssertEqual(b2, handSum(nx: 3, ny: 2, [0, 2, 5]))
    }

    // MARK: H2

    /// Phase pools are pairwise disjoint; pools + the pixels in no pool = the whole map, channel by channel; on the mirrored bin
    /// the tied pixel is in no pool.
    /// Mutations: pools from `TransportedLabels.mask(forClass:)` per class (a tie enters two pools) - red.
    func testPhasePoolsPartitionAndTheTieJoinsNone() async throws {
        let (state, _, source) = await joint(image: dense(nx: 2, ny: 2), sameScan: false, record: mirror, map: phaseMap(4, 4, mirrorMap))
        let pools = state.spectroscopy.poolCatalogue.pools
        XCTAssertEqual(pools.map(\.name), ["A", "B"], "Not indexed holds no spectrum pixel by more than half here")
        var inNone: [Int] = []
        for p in 0..<4 {
            let n = pools.filter { $0.mask[p] }.count
            XCTAssertLessThanOrEqual(n, 1, "pixel \(p) is in \(n) pools")
            if n == 0 { inNone.append(p) }
        }
        XCTAssertEqual(inNone, [0], "the exact tie is in no pool")
        var total = [Double](repeating: 0, count: channels)
        for pool in pools { for (c, v) in source.sum(mask: pool.mask).enumerated() { total[c] += Double(v) } }
        for (c, v) in handSum(nx: 2, ny: 2, inNone).enumerated() { total[c] += v }
        XCTAssertEqual(total, source.sum(mask: nil).map { Double($0) })
    }

    // MARK: H3

    /// Under the identity each phase pool's mask is `MaskTransport.mask(phase:in:)` bit for bit, Not indexed is the
    /// notIndexed verdicts (one keeps a stale phaseIndex), and each group pool's mask is `groupOf == g` (one `-1`).
    /// Mutations: verdict condition dropped (the stale phaseIndex joins A) - red; `groupOf` off by one - red.
    func testMembershipFollowsItsSourceBitForBit() async throws {
        let chars = "AABBN" + "AABNN" + "ABBBN"
        let map = phaseMap(5, 3, chars)
        let groupOf = [0, 0, 1, 1, -1, 0, 2, 1, 1, 2, 0, 0, 1, 1, 2]
        let (state, _, _) = await joint(image: dense(nx: 5, ny: 3), map: map, groups: groups(5, 3, groupOf, k: 3))
        let pools = state.spectroscopy.poolCatalogue.pools
        for (i, name) in ["A", "B"].enumerated() {
            let pool = try XCTUnwrap(pools.first { $0.name == name })
            XCTAssertEqual(pool.mask, MaskTransport.mask(phase: i, in: map), name)
        }
        let notIndexed = try XCTUnwrap(pools.first { $0.kind == .notIndexed })
        XCTAssertEqual(notIndexed.mask, chars.map { $0 == "N" })
        XCTAssertEqual(notIndexed.name, "Not indexed")
        for g in 0..<3 {
            let pool = try XCTUnwrap(pools.first { $0.name == "Group \(g + 1)" })
            XCTAssertEqual(pool.mask, groupOf.map { $0 == g }, "group \(g)")
            XCTAssertEqual(pool.id, PoolCatalogue.groupIDBase + g)
        }
        XCTAssertTrue(pools.filter { $0.kind == .group }.allSatisfy { !$0.mask[4] }, "groupOf -1 is in no group")
    }

    // MARK: H4

    /// Each refusal is a sentence and makes no region. Cases: a 4 x 3 map on a 5 x 3 registration; a 3 x 5 map (the same count)
    /// on it; an empty class; a singular record; no registration; a registration onto another grid.
    /// Mutation: the width/height check dropped (only the 3 x 5 case goes red).
    func testEveryRefusalIsASentenceAndNoPool() {
        let id5x3 = PoolCatalogue.identityRegistration(width: 5, height: 3)
        func build(_ map: PhaseMap?, _ reg: RegistrationRecordM2?, w: Int = 5, h: Int = 3) -> PoolCatalogue {
            PoolCatalogue.build(.init(hasFourDCube: true, registration: reg, spectrumWidth: w, spectrumHeight: h, phaseMap: map, phaseGeneration: 1))
        }
        let wrongWidth = build(phaseMap(4, 3, String(repeating: "A", count: 12)), id5x3)
        XCTAssertTrue(wrongWidth.pools.isEmpty)
        XCTAssertTrue(wrongWidth.notes[0].text.contains("4 × 3") && wrongWidth.notes[0].text.contains("5 × 3"), wrongWidth.notes[0].text)
        let transposed = build(phaseMap(3, 5, String(repeating: "A", count: 15)), id5x3)
        XCTAssertTrue(transposed.pools.isEmpty, "same pixel count, not the same scan")
        XCTAssertTrue(transposed.notes[0].text.contains("3 × 5") && transposed.notes[0].text.contains("5 × 3"), transposed.notes[0].text)
        let empty = build(phaseMap(5, 3, String(repeating: "A", count: 15), names: ["A", "B"]), id5x3)
        XCTAssertEqual(empty.pools.map(\.name), ["A"])
        XCTAssertTrue(empty.notes.contains { $0.text.hasPrefix("B ") && $0.text.contains("no pool") }, "\(empty.notes)")
        let singular = RegistrationRecordM2(matrix: [1, 0, 0, 2, 0, 0], source: .typed, scanWidth: 5, scanHeight: 3, spectrumWidth: 5, spectrumHeight: 3)
        let s = build(phaseMap(5, 3, String(repeating: "A", count: 15)), singular)
        XCTAssertTrue(s.pools.isEmpty); XCTAssertTrue(s.notes[0].text.contains("singular"), s.notes[0].text)
        let none = build(phaseMap(5, 3, String(repeating: "A", count: 15)), nil)
        XCTAssertTrue(none.pools.isEmpty); XCTAssertEqual(none.notes[0].text, PoolCatalogue.noRegistrationLine)
        let other = build(phaseMap(5, 3, String(repeating: "A", count: 15)), id5x3, w: 4, h: 4)
        XCTAssertTrue(other.pools.isEmpty); XCTAssertTrue(other.notes[0].text.contains("5 × 3") && other.notes[0].text.contains("4 × 4"), other.notes[0].text)
        // Before any phase map exists: the one line the picker shows.
        let noMap = build(nil, id5x3)
        XCTAssertEqual(noMap.notes, [PoolNote(section: .phases, text: PoolCatalogue.noPhaseMapLine)])
        // No 4D cube: nothing offered, nothing said.
        XCTAssertEqual(PoolCatalogue.build(.init(hasFourDCube: false, registration: id5x3, spectrumWidth: 5, spectrumHeight: 3)), PoolCatalogue())
    }

    /// A pool is summed over its own mask, never `mask: nil` (every pixel); a refused source has no region to select.
    /// Mutation: `SpectroscopySession.mask(of:)` returning nil for a pool region - red (the spy sees `sum(mask: nil)`).
    func testAPoolIsNeverSummedOverEveryPixel() async throws {
        let (state, c, source) = await joint(image: dense(nx: 5, ny: 3), map: phaseMap(5, 3, "AABBN" + "AABNN" + "ABBBN"))
        XCTAssertGreaterThan(source.nilMasks, 0, "the open sums the whole map once")
        source.resetSpy()
        for id in [1000, 1001, 1900] { _ = await shown(c, pool: id) }
        XCTAssertEqual(source.nilMasks, 0)
        let region = try XCTUnwrap(state.spectroscopy.regions.first { $0.id == 1000 })
        XCTAssertNotNil(state.spectroscopy.mask(of: region))
        // A refused product leaves no pool region at all.
        let (state2, _, _) = await joint(image: dense(nx: 5, ny: 3), map: phaseMap(3, 5, String(repeating: "A", count: 15)))
        XCTAssertEqual(state2.spectroscopy.regions.map(\.kind), [.wholeMap])
        XCTAssertEqual(state2.spectroscopyRoom.model.poolNotes.count, 1)
    }

    // MARK: H5, H6

    /// Quantifying a pool through the room is quantifying its hand-summed spectrum with the same method: every row field equal, the
    /// footer names the pool's pixel count. The lineage step carries the registration and the region kind.
    /// Mutations: the request's pixelCount `nx * ny` instead of the region's - red (footer); `registration:` omitted in the
    /// `recordQuantification` call - red.
    func testQuantifyingAPoolIsQuantifyingItsSumAndTheStepRecordsItsProvenance() async throws {
        let loaded = try SpectroscopyQuantifyTests.image()
        let nx = loaded.nx, ny = loaded.ny   // 6 x 4
        XCTAssertEqual([nx, ny], [6, 4])
        let map = phaseMap(nx, ny, String(repeating: "AAABBB", count: ny))
        let state = AppState(); keep.append(state)
        state.descriptor = DatasetDescriptor(filePath: path, datasetPath: "/d", shape: [ny, nx, 8, 8], dtypeDescription: "float32", chunkShape: nil)
        state.openSpectrumImage(loaded)
        let c = state.spectroscopyRoom; c.autoIDOnOpen?.cancel()
        state.spectroscopy.registration = PoolCatalogue.identityRegistration(width: nx, height: ny)
        state.spectroscopy.registeredCubePath = path
        state.phaseMapping.publish(map, ranWith: Self.runRecord())
        await state.spectroscopy.poolTask?.value
        for z in [13, 12, 14, 29] { c.model.elements.set(z, .quantify) }
        c.elementsChanged()
        if loaded.metadata.beamEnergyKeV == nil { c.model.quantify.beamEnergy = 200; c.quantifySettingsChanged() }
        c.selectRegion(id: 1000)
        await c.lastRefresh?.value
        state.navigation.workspaceArea = .spectroscopy
        await state.runPrimaryWorkspaceTask()
        await c.checkTask?.value
        let room = try XCTUnwrap(c.lastFit)
        // Direct: the hand sum of the columns 0-2 and the same method.
        let dense = try XCTUnwrap(loaded.image as? DenseSpectrumImage)
        let members = (0..<(nx * ny)).filter { $0 % nx < 3 }
        var hand = [UInt64](repeating: 0, count: dense.channels)
        for p in members { for k in 0..<dense.channels { hand[k] += UInt64(dense.counts[p * dense.channels + k]) } }
        let input = PooledQuantificationInput(counts: hand, axis: loaded.energyAxis, method: room.method, metadata: loaded.metadata,
                                              regionName: "A", pixelCount: members.count)
        let direct = try PooledQuantifier.run(input, tables: SpectroscopyQuantifyTests.tables)
        XCTAssertEqual(room.rows, direct.rows)
        XCTAssertEqual(room.footerLines, direct.footerLines)
        XCTAssertTrue(room.footerLines.joined(separator: "\n").contains("\(members.count) px pooled (A)"))
        // H6: provenance.
        let step = try XCTUnwrap(state.replay.lineage.nodes.last { $0.kind == "quantification" })
        XCTAssertEqual(step.parameters["region_kind"], "phase")
        XCTAssertEqual(step.parameters["region_name"], "A")
        XCTAssertEqual(step.parameters["registration_source"], RegistrationRecordM2.Source.identityFromOneRun.rawValue)
        XCTAssertEqual(step.parameters["registration"], PoolCatalogue.identityRegistration(width: nx, height: ny).canonicalJSON)
    }

    /// The badge is the pool's own: a phase and a Not indexed pool are unvalidated, a group pool is not called validated and
    /// carries no badge; the room's Phase row follows the selected pool; a drawn region's step has no registration key.
    /// Mutation: `SpectrumPool.isUnvalidated` through `ValidationState.isUnvalidated` (nil reads as unvalidated) - red (group).
    func testTheBadgeIsThePoolsOwn() async throws {
        let groupOf = [0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1]
        let (state, c, _) = await joint(image: dense(nx: 5, ny: 3), map: phaseMap(5, 3, "AABBN" + "AABNN" + "ABBBN"), groups: groups(5, 3, groupOf, k: 2))
        let pools = state.spectroscopy.poolCatalogue.pools
        XCTAssertEqual(pools.filter { $0.kind == .group }.map(\.isUnvalidated), [false, false])
        XCTAssertTrue(pools.filter { $0.kind != .group }.allSatisfy { $0.isUnvalidated })
        XCTAssertFalse(PoolCatalogue.isUnvalidated(validation: nil))
        _ = await shown(c, pool: 1000)
        let identity = "same scan, identity; no lag check"   // card E5 a: every pool says how it reached the spectrum grid
        XCTAssertEqual(c.model.regionSettings, RegionSettings(phase: "A", phaseUnvalidated: true, registrationNote: identity))
        _ = await shown(c, pool: 1900)
        XCTAssertEqual(c.model.regionSettings, RegionSettings(phase: "Not indexed", phaseUnvalidated: true, registrationNote: identity))
        _ = await shown(c, pool: 2000)
        XCTAssertEqual(c.model.regionSettings, RegionSettings(registrationNote: identity), "a group has no phase row and no badge, and says its registration")
        _ = await shown(c, pool: 0)
        XCTAssertEqual(c.model.regionSettings, RegionSettings(), "the whole map states no registration")
        let group = try XCTUnwrap(state.spectroscopy.regions.first { $0.id == 2000 })
        XCTAssertEqual(state.spectroscopy.quantificationParameters(registration: state.spectroscopy.registration(of: group),
                                                                   regionKind: group.kind.rawValue, regionName: group.name)["region_kind"], "group")
        let drawn = state.spectroscopy.quantificationParameters(registration: state.spectroscopy.registration(of: state.spectroscopy.regions[0]))
        XCTAssertNil(drawn["registration"])
    }

    // MARK: H7

    /// With a 4D product present and pools in the picker, the whole-map and drawn-region outputs are byte-identical to the
    /// recording from the build before E1 (`docs/archive/v5/e1-results-2026-10-12/`).
    /// Mutation: a drawn rectangle's mask dilated by one pixel whenever the catalogue holds pools - red.
    func testNoExistingNumberMovesWithAProductPresent() async throws {
        for s in E1Recording.Scenario.allCases {
            let loaded = try E1Recording.image(s)
            let (nx, ny) = (loaded.nx, loaded.ny)
            for w in E1Recording.Which.allCases {
                let text = try await E1Recording.output(s, w, prepare: { state in
                    state.descriptor = DatasetDescriptor(filePath: self.path, datasetPath: "/d", shape: [ny, nx, 8, 8], dtypeDescription: "float32", chunkShape: nil)
                    state.spectroscopy.registration = PoolCatalogue.identityRegistration(width: nx, height: ny)
                    state.spectroscopy.registeredCubePath = self.path
                    state.phaseMapping.publish(self.phaseMap(nx, ny, String((0..<(nx * ny)).map { $0 % 2 == 0 ? Character("A") : "B" })),
                                               ranWith: Self.runRecord())
                    await state.spectroscopy.poolTask?.value
                    XCTAssertFalse(state.spectroscopy.poolCatalogue.pools.isEmpty, "the pools are there")
                })
                let recorded = try String(contentsOf: E1Recording.recordedDirectory.appendingPathComponent(E1Recording.fileName(s, w)), encoding: .utf8)
                XCTAssertEqual(text, recorded, "\(E1Recording.fileName(s, w)) moved")
            }
        }
    }

    // MARK: H8

    /// A new map, a cleared map and a new group result are never shown stale: the selected pool is recomputed from the new
    /// mask (or the whole map is shown, with a sentence), its pin and its Auto ID outcome go, the generation counts.
    /// Mutations: `cache.forget` skipped in `poolsChanged` - red (old spectrum); pins kept on a source change - red.
    func testAPoolIsNeverStale() async throws {
        let (state, c, _) = await joint(image: dense(nx: 5, ny: 3), map: phaseMap(5, 3, "AABBN" + "AABNN" + "ABBBN"))
        let g0 = state.phaseMapping.generation
        _ = await shown(c, pool: 1000)
        c.pinRegion()
        XCTAssertEqual(c.model.pins.count, 1)
        let t = c.model.beginAutoID()
        _ = c.model.finishAutoID(token: t, outcome: AutoIDOutcome(region: "A", suggestions: [], suspects: [], notTested: [], notes: []))
        XCTAssertNotNil(c.model.autoID.outcome)
        // A new map: A is now other pixels.
        let newChars = "BBAAN" + "BBANN" + "BAAAN"
        state.phaseMapping.publish(phaseMap(5, 3, newChars), ranWith: Self.runRecord())
        XCTAssertEqual(state.phaseMapping.generation, g0 + 1)
        await state.spectroscopy.poolTask?.value
        await c.lastRefresh?.value
        XCTAssertEqual(c.model.series.data, handSum(nx: 5, ny: 3, newChars.enumerated().filter { $0.element == "A" }.map(\.offset)))
        XCTAssertTrue(c.model.pins.isEmpty, "a pin taken from the old pool goes with it")
        XCTAssertNil(c.model.autoID.outcome, "so does the Auto ID outcome about it")
        // The map is cleared: the pool's source vanished.
        state.phaseMapping.clear()
        await state.spectroscopy.poolTask?.value
        await c.lastRefresh?.value
        XCTAssertEqual(state.spectroscopy.selectedRegionID, 0)
        XCTAssertEqual(state.spectroscopy.regions.map(\.kind), [.wholeMap])
        XCTAssertTrue(state.statusText.contains("is gone"), state.statusText)
        XCTAssertEqual(c.model.poolNotes, [PoolNote(section: .phases, text: PoolCatalogue.noPhaseMapLine)])
        // A group result is replaced: its generation counts too.
        let gen = state.diffractionGroups.generation
        state.diffractionGroups.publish(groups(5, 3, [Int](repeating: 0, count: 15), k: 1), ranWith: DiffractionEmbedding.Settings())
        XCTAssertEqual(state.diffractionGroups.generation, gen + 1)
        await state.spectroscopy.poolTask?.value
        XCTAssertEqual(state.spectroscopy.regions.map(\.name), ["Whole map", "Group 1"])
    }

    /// The same chain through the injected mirrored record: a re-published map recomputes the selected pool from the new mask.
    /// Mutation: `cache.forget` skipped - red.
    func testAPoolIsNeverStaleThroughTheMirroredRecord() async throws {
        let (state, c, _) = await joint(image: dense(nx: 2, ny: 2), sameScan: false, record: mirror, map: phaseMap(4, 4, mirrorMap))
        let before = await shown(c, pool: 1000)
        XCTAssertEqual(before, handSum(nx: 2, ny: 2, [1, 2]))
        // Everything is A on the scan: every spectrum pixel is A, the tie is gone.
        state.phaseMapping.publish(phaseMap(4, 4, String(repeating: "A", count: 16)), ranWith: Self.runRecord())
        await state.spectroscopy.poolTask?.value
        await c.lastRefresh?.value
        XCTAssertEqual(c.model.series.data, handSum(nx: 2, ny: 2, [0, 1, 2, 3]))
    }

    /// The identity of a GMS joint attach is stated for one cube; another cube in the window does not inherit the claim.
    func testTheIdentityClaimIsDroppedWhenTheCubeIsNotTheOne() async throws {
        let (state, _, _) = await joint(image: dense(nx: 5, ny: 3), map: phaseMap(5, 3, String(repeating: "A", count: 15)))
        XCTAssertFalse(state.spectroscopy.poolCatalogue.pools.isEmpty)
        state.descriptor = DatasetDescriptor(filePath: "/tmp/other.h5", datasetPath: "/d", shape: [3, 5, 8, 8], dtypeDescription: "float32", chunkShape: nil)
        state.refreshSpectroscopyPools()
        await state.spectroscopy.poolTask?.value
        XCTAssertNil(state.spectroscopy.registration)
        XCTAssertTrue(state.spectroscopy.poolCatalogue.pools.isEmpty)
    }

    // MARK: H8, the cache fence

    /// A pass that read its epoch before `poolsChanged` forgot the pool cannot put the old spectrum back after the forget; a pass
    /// started after the forget caches as usual.
    /// Mutation: `setSpectrum` ignoring the epoch - red.
    func testAComputePastItsCancelCheckCannotRecacheAForgottenPool() {
        let image = PoolSpyImage(image: dense(nx: 5, ny: 3), sameScan: true)
        let cache = SpectrumComputeCache()
        let mask = PixelMask((0..<15).map { $0 < 4 })
        func request(epoch: Int) -> SpectroscopyRoomController.Request {
            SpectroscopyRoomController.Request(source: image, region: 1000, mask: mask, picks: [], integrated: false, beam: 200, quantify: nil, epoch: epoch)
        }
        let started = request(epoch: cache.epoch(1000))   // the old pass: epoch read when it was made
        cache.forget(region: 1000)                        // poolsChanged, between that and the pass's set
        _ = SpectroscopyRoomController.compute(started, cache: cache)
        XCTAssertNil(cache.spectrum(1000), "the old pass's spectrum must not come back")
        _ = SpectroscopyRoomController.compute(request(epoch: cache.epoch(1000)), cache: cache)
        XCTAssertEqual(cache.spectrum(1000), image.sum(mask: mask), "a pass made after the forget caches")
    }

    // MARK: Membership at exactly one half

    /// The rule as `MaskTransport.labelling` actually applies it (inherited, not set by E1): a spectrum pixel joins the class with
    /// the largest overlap when that overlap is AT LEAST one half and no other class matches it; exact ties between classes join
    /// none. So a pixel half in group g and half in `groupOf == -1` (no class) JOINS g, and a pixel half g, half h joins neither.
    /// Under the identity coverage is 0 or 1 and this cannot arise in the app today.
    /// Mutation: the inclusion threshold read as strictly above one half - red.
    func testAHalfCoveredPixelBesideNoClassJoinsTheClassAndATieJoinsNone() {
        // Mirrored bin: spectrum pixel 0 is the scan block x 2-3, y 0-1.
        //   x:  0 1 2 3
        let groupOf = [1, 1, 0, -1,
                       1, 1, 0, -1,
                       1, 1, 1, 1,
                       1, 1, 1, 1]
        let c = PoolCatalogue.build(.init(hasFourDCube: true, registration: mirror, spectrumWidth: 2, spectrumHeight: 2,
                                          groups: groups(4, 4, groupOf, k: 2), groupGeneration: 1))
        XCTAssertEqual(c.pools.map(\.name), ["Group 1", "Group 2"])
        XCTAssertEqual(c.pools[0].mask, [true, false, false, false], "half group 1, half unlabelled: joins group 1")
        XCTAssertEqual(c.pools[1].mask, [false, true, true, true])
        // Half group 1, half group 2: an exact tie, in neither.
        let tied = [1, 1, 0, 1,
                    1, 1, 0, 1,
                    1, 1, 1, 1,
                    1, 1, 1, 1]
        let t = PoolCatalogue.build(.init(hasFourDCube: true, registration: mirror, spectrumWidth: 2, spectrumHeight: 2,
                                          groups: groups(4, 4, tied, k: 2), groupGeneration: 1))
        XCTAssertEqual(t.pools.map(\.name), ["Group 2"], "Group 1 covers no pixel by more than a tie")
        XCTAssertEqual(t.pools[0].mask, [false, true, true, true])
    }
}
