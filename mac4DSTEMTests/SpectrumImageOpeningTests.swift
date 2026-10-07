import CoreGraphics
import XCTest
@testable import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// v5.0 WP2 lane R2: from a file to a spectrum image in the room. Fixtures: `demo-edx-tiny.dm4` (6 x 4 scan, 512 channels,
/// truth beside it) and `velox-tiny.emd` (3 rows x 2 columns, 8 channels, 2 frames: the main file of
/// `tools/velox-parity/make-tiny-fixture.py`, the same bytes VeloxEMDReaderTests embeds). Each test names its mutation.
@MainActor
final class SpectrumImageOpeningTests: XCTestCase {

    private static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    private static var dm4: String { dir.appendingPathComponent("demo-edx-tiny.dm4").path }
    private static var velox: String { dir.appendingPathComponent("velox-tiny.emd").path }
    private static var h5: String { dir.appendingPathComponent("qshape3.mac4dstem.h5").path }

    private func truth() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.dir.appendingPathComponent("demo-edx-tiny.truth.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func edsIndex() throws -> Int {
        try XCTUnwrap(try DM4Experiment.list(path: Self.dm4).first { $0.role == .eds }).index
    }

    // MARK: DM4 EDS decode

    /// The decoded cube against the truth, per recipe: the realised EDS counts the generator wrote for each recipe's
    /// pixels equal the sum of the decoded counts over that recipe's pixels in the map. nx = 6 != ny = 4, so a swapped
    /// pair of axes reads another recipe's pixels.
    /// Mutation: `nx`/`ny` swapped in `decodeEDS` (`dimensions[1], dimensions[0]`) — red.
    func testTheDM4EDSDecodeMatchesTheTruthPerRecipe() throws {
        let t = try truth()
        let map = try XCTUnwrap(t["recipe_map"] as? [[Int]])
        let names = try XCTUnwrap(t["recipe_names_in_map_order"] as? [String])
        let recipes = try XCTUnwrap(t["recipes"] as? [String: [String: Any]])
        let image = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: Self.dm4, fourD: nil))
        XCTAssertEqual([image.nx, image.ny, image.channels], [6, 4, 512])
        for (i, name) in names.enumerated() {
            var mask = PixelMask(repeating: false, count: 24)
            for y in 0..<4 { for x in 0..<6 where map[y][x] == i { mask[y * 6 + x] = true } }
            let expected = try XCTUnwrap(recipes[name]?["realised_total_eds_counts"] as? Int)
            XCTAssertEqual(image.sum(mask: mask).reduce(0, +), UInt64(expected), "recipe \(name)")
        }
    }

    /// The layout itself, read independently: memory order (channel, y, x), x fastest, against the (y, x, channel) result.
    /// Mutation: the plane stride `j * np` in `scatterEDS` replaced by `j * nch` — red.
    func testTheDM4EDSBlobIsTransposedFromEnergySlowest() throws {
        let objects = try DM4Experiment.list(path: Self.dm4)
        let eds = try XCTUnwrap(objects.first { $0.role == .eds })
        let d = try DM4Experiment.readEDSSpectrumImage(path: Self.dm4, index: eds.index)
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: Self.dm4))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(eds.dataOffset))
        let raw = try XCTUnwrap(try handle.read(upToCount: eds.dataByteCount))
        let counts: [UInt32] = raw.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        for ch in [0, 1, 100, 511] { for y in 0..<4 { for x in 0..<6 {
            XCTAssertEqual(d.counts[(y * 6 + x) * 512 + ch], counts[(ch * 4 + y) * 6 + x], "ch \(ch) y \(y) x \(x)")
        } } }
        XCTAssertNil(eds.dataOrderSwapped, "the simulator does not write the tag on the EDS object")
    }

    /// The axis the room shows is the FILE's (the perturbed one, truth `edx.axis_file`), never the generator's true axis:
    /// E(i) = (i - origin) * scale with the origin and dispersion as stored (float32, so 1e-5 keV). Elevation is the truth's.
    /// Mutation: the offset sign flipped (`offsetKeV = d.energyAxis.origin * …`) — red.
    func testTheDM4EnergyAxisAndMetadataAreTheFiles() throws {
        let t = try truth()
        let edx = try XCTUnwrap(t["edx"] as? [String: Any])
        let file = try XCTUnwrap(edx["axis_file"] as? [String: Double])
        let offsetKeV = try XCTUnwrap(file["offset_keV"]), dispersionEV = try XCTUnwrap(file["dispersion_eV"])
        let elevation = try XCTUnwrap(((t["forward_model"] as? [String: Any])?["absorption"] as? [String: Any])?["elevation_deg"] as? Double)
        let image = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: Self.dm4, fourD: nil))
        XCTAssertEqual(image.energyAxis.offset, offsetKeV, accuracy: 1e-5)
        XCTAssertEqual(image.energyAxis.scale, dispersionEV / 1000, accuracy: 1e-6)
        XCTAssertEqual(image.energyAxis.energy(ofChannel: 24), offsetKeV + 24 * dispersionEV / 1000, accuracy: 1e-5)
        let m = image.metadata
        XCTAssertEqual(m.energyOffsetEV, offsetKeV * 1000, accuracy: 1e-2)
        XCTAssertEqual(m.energyDispersionEV, dispersionEV, accuracy: 1e-3)
        XCTAssertEqual(m.origin, .gmsDM4)
        XCTAssertEqual(m.scanPixelSize, 5)
        XCTAssertEqual(m.scanPixelUnit, "nm")
        XCTAssertEqual(m.detectors.first?.elevationDegrees, elevation)
        XCTAssertEqual(image.scanImage?.count, 24, "the scan-grid HAADF of the same run sits on the EDS grid")
        XCTAssertFalse(m.sameScanAs4DCube, "no cube was named")
    }

    /// Only an EDS object is decoded, and a missing one is named.
    /// Mutation: the role guard in `decodeEDS` removed — red (the 4D object would be read as a 3D cube).
    func testOnlyAnEDSObjectDecodes() throws {
        let objects = try DM4Experiment.list(path: Self.dm4)
        let diffraction = try XCTUnwrap(objects.first { $0.role == .diffraction })
        XCTAssertThrowsError(try DM4Experiment.readEDSSpectrumImage(path: Self.dm4, index: diffraction.index)) {
            XCTAssertTrue($0.localizedDescription.contains("is not an EDS spectrum image"), "\($0.localizedDescription)")
        }
        XCTAssertThrowsError(try DM4Experiment.readEDSSpectrumImage(path: Self.dm4, index: 99)) {
            XCTAssertTrue($0.localizedDescription.contains("no image object 99"), "\($0.localizedDescription)")
        }
    }

    // MARK: GMS joint attach

    /// The same run (one Experiment ID) on the same grid registers by identity; another grid attaches with the reason.
    /// Mutation: the width compared with the EDS height (`cube.scanWidth == d.ny`) — red.
    func testTheEDSIsRegisteredToItsCubeByIdentityAndAMismatchSaysSo() throws {
        let index = try XCTUnwrap(try DM4Experiment.list(path: Self.dm4).first { $0.role == .diffraction }).index
        let same = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(
            path: Self.dm4, fourD: GMSFourDIdentity(objectIndex: index, scanWidth: 6, scanHeight: 4)))
        XCTAssertTrue(same.metadata.sameScanAs4DCube)
        XCTAssertNil(same.metadata.registrationNote)

        let other = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(
            path: Self.dm4, fourD: GMSFourDIdentity(objectIndex: index, scanWidth: 4, scanHeight: 6)))
        XCTAssertFalse(other.metadata.sameScanAs4DCube)
        XCTAssertTrue(try XCTUnwrap(other.metadata.registrationNote).hasPrefix("Not registered"))
    }

    /// Opened through the app: the EDS becomes the window's spectrum image beside the cube and the room does not change.
    /// Mutation: `attachSpectrumImage` calling `selectWorkspace(.spectroscopy)` — red.
    func testAGMSCubesEDSAttachesWithoutLeavingTheCubesRoom() async throws {
        let state = AppState()
        state.navigation.workspaceArea = .image
        let descriptor = DatasetDescriptor(filePath: Self.dm4, datasetPath: "ImageList.4.ImageData.Data",
                                           shape: [4, 6, 16, 16], dtypeDescription: "float32", chunkShape: [1, 1, 16, 16])
        XCTAssertEqual(AppState.gmsObjectIndex(descriptor.datasetPath), 4)
        state.descriptor = descriptor     // the cube is showing (4D), as it is when the attach runs after the load
        await state.attachGMSSpectrumImage(of: URL(fileURLWithPath: Self.dm4), descriptor: descriptor)
        XCTAssertTrue(state.hasSpectrumImage)
        XCTAssertEqual(state.spectroscopy.metadata?.sameScanAs4DCube, true)
        XCTAssertEqual(state.navigation.workspaceArea, .image, "the joint open lands on the cube's room, as before")
        XCTAssertEqual(state.spectroscopy.regions.first?.pixelCount, 24)
    }

    // MARK: Velox join

    /// The store joined to Core's sparse image gives the sums a densified reference gives, windows and masks included.
    /// Mutation: `windowSums` of `SparseSpectrumImage` using `<=` on the upper bound — red.
    func testTheVeloxStoreJoinsTheSparseImageAndSumsEqualADensifiedReference() throws {
        let store = try VeloxEMDReader(path: Self.velox).readSpectrumImage().eventStore
        let sparse = try SparseSpectrumImage(store)
        let dense = DenseSpectrumImage(ny: store.ny, nx: store.nx, channels: store.channels, counts: store.denseCounts())
        XCTAssertEqual([sparse.ny, sparse.nx, sparse.channels], [3, 2, 8])
        XCTAssertEqual(sparse.sum(mask: nil), dense.sum(mask: nil))
        XCTAssertEqual(sparse.sum(mask: nil), store.summedSpectrum())
        let mask: PixelMask = [true, false, true, true, false, false]
        XCTAssertEqual(sparse.sum(mask: mask), dense.sum(mask: mask))
        let ranges = [0..<3, 2..<8, 7..<8, 4..<4, 1..<2]
        XCTAssertEqual(sparse.windowSums(ranges), dense.windowSums(ranges))
        XCTAssertEqual(store.totalCounts, Int(sparse.sum(mask: nil).reduce(0, +)))
    }

    /// The opener's axis is the stream's, in keV, and the metadata the room shows is what the file stores.
    /// Mutation: `scaleKeV` doubled in `openVelox` — red.
    func testTheVeloxOpenerCarriesTheFilesAxisAndMetadata() throws {
        let v = try VeloxEMDReader(path: Self.velox).readSpectrumImage()
        let image = try SpectrumImageOpener.openVelox(path: Self.velox)
        let axis = try XCTUnwrap(v.metadata.energyAxis)
        XCTAssertEqual(image.energyAxis.offset, axis.offsetKeV, accuracy: 1e-12)
        XCTAssertEqual(image.energyAxis.scale, axis.scaleKeV, accuracy: 1e-12)
        XCTAssertEqual(image.metadata.energyDispersionEV, axis.scaleKeV * 1000, accuracy: 1e-9)
        XCTAssertEqual([image.ny, image.nx, image.channels], [3, 2, 8], "a non-square grid: 3 rows, 2 columns")
        XCTAssertEqual(image.metadata.origin, .veloxEMD)
        XCTAssertEqual(image.metadata.frames, 2)
        XCTAssertEqual(image.scanImage?.count, 6)
        XCTAssertFalse(image.metadata.detectors.isEmpty)
        XCTAssertEqual(image.metadata.beamEnergyKeV, 200)
        XCTAssertEqual(image.sum(mask: nil), v.eventStore.summedSpectrum())
    }

    // MARK: Routing

    /// What each file is. A Velox EMD is a spectrum image; a GMS file with a cube is not (it opens as a cube); neither is
    /// an HDF5 that is not Velox, nor a file merely NAMED .emd.
    /// Mutation: `kind` answering `.veloxSpectrumImage` for every .emd without asking `isVeloxEMD` — red.
    func testTheRouterTellsASpectrumImageFromACube() throws {
        XCTAssertEqual(SpectrumImageOpener.kind(ofFileAt: Self.velox), .veloxSpectrumImage)
        XCTAssertEqual(SpectrumImageOpener.kind(ofFileAt: Self.dm4), .other, "it has a Diffraction SI: a cube opens, its EDS is attached after")
        XCTAssertEqual(SpectrumImageOpener.kind(ofFileAt: Self.h5), .other)
        let fake = NSTemporaryDirectory() + "not-velox-\(UUID().uuidString).emd"
        try Data("not hdf5".utf8).write(to: URL(fileURLWithPath: fake))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: fake) }
        XCTAssertEqual(SpectrumImageOpener.kind(ofFileAt: fake), .other)
    }

    /// The shipped-behaviour change, through the open funnel: a Velox EMD opens as a spectrum image in a spectrum-only
    /// window with the Spectroscopy room selected, and no cube. The same funnel leaves a non-Velox file to the 4D open.
    /// Mutation: the `openAsSpectrumImageIfApplicable` line removed from `openFileAsync` — red.
    func testAVeloxEMDOpensAsASpectrumImageNotACube() async throws {
        let state = AppState()
        await state.openFileAsync(url: URL(fileURLWithPath: Self.velox))
        XCTAssertTrue(state.hasSpectrumImage)
        XCTAssertFalse(state.hasDataset, "not a one-row cube")
        XCTAssertTrue(state.isSpectrumOnly)
        XCTAssertEqual(state.navigation.workspaceArea, .spectroscopy)
        XCTAssertEqual(state.spectroscopy.metadata?.scanWidth, 2)
        XCTAssertEqual(state.spectroscopy.metadata?.scanHeight, 3)
        XCTAssertFalse(state.datasetSession.isLoading)

        let other = AppState()
        let opened = await other.openAsSpectrumImageIfApplicable(URL(fileURLWithPath: Self.h5))
        XCTAssertFalse(opened, "a non-Velox .h5 is left to the 4D open, untouched")
        XCTAssertFalse(other.hasSpectrumImage)
        XCTAssertFalse(other.datasetSession.isLoading)
        let cube = AppState()
        let openedCube = await cube.openAsSpectrumImageIfApplicable(URL(fileURLWithPath: Self.dm4))
        XCTAssertFalse(openedCube, "a GMS cube is not routed away")
    }

    // MARK: Regions and net counts

    /// A drawn region's sum is the sum over exactly its mask's pixels, and the pixel count is the mask's.
    /// Mutation: `.rectangle` masking `x0...x1` (inclusive) — red.
    func testARegionsSumIsTheSumOverItsMask() throws {
        let store = try VeloxEMDReader(path: Self.velox).readSpectrumImage().eventStore
        let image = try SpectrumImageOpener.openVelox(path: Self.velox)
        let shape = SpectrumRegionShape.rectangle(PixelRect(x0: 0, y0: 1, x1: 1, y1: 3))     // rows 1 and 2, column 0 only
        let mask = shape.mask(nx: 2, ny: 3)
        XCTAssertEqual(mask, [false, false, true, false, true, false])
        var expected = [UInt64](repeating: 0, count: 8)
        for p in [2, 4] { for (c, v) in store.spectrum(pixel: p).enumerated() { expected[c] += UInt64(v) } }
        XCTAssertEqual(image.sum(mask: mask), expected)
        let session = SpectroscopySession()
        session.open(image)
        let region = try XCTUnwrap(session.addDrawnRegion(shape))
        XCTAssertEqual(region.pixelCount, 2)
        XCTAssertEqual(session.selectedRegionID, region.id)
        XCTAssertNil(session.addDrawnRegion(.rectangle(PixelRect(x0: 5, y0: 5, x1: 6, y1: 6))), "a shape off the grid draws nothing")
        session.removeRegion(id: 0)
        XCTAssertEqual(session.regions.count, 2, "the whole map is never removed")
        session.removeRegion(id: region.id)
        XCTAssertEqual(session.selectedRegionID, 0)
    }

    /// An ellipse keeps the pixels whose centres are inside it: 12 of a 4 x 4 box, the four corners out.
    /// Mutation: `<= 1` replaced by `<= 1.5` in `SpectrumRegionShape.mask` — red.
    func testAnEllipseKeepsThePixelsWhoseCentresAreInside() {
        let mask = SpectrumRegionShape.ellipse(PixelRect(x0: 0, y0: 0, x1: 4, y1: 4)).mask(nx: 4, ny: 4)
        XCTAssertEqual(mask.filter { $0 }.count, 12)
        XCTAssertFalse(mask[0]); XCTAssertFalse(mask[3]); XCTAssertFalse(mask[12]); XCTAssertFalse(mask[15])
    }

    /// net = G - s B and sigma^2 = G + s^2 B, from the window's own sums (counting statistics, independent Poisson counts).
    /// Mutation: the variance `G + s²B` written `G + s·B` — red.
    func testNetCountsAndSigmaFollowThePoissonFormula() throws {
        // A window of known geometry whose scale is NOT 1 (eXSpy's windows are symmetric, so a real one has scale 1 and cannot
        // tell s from s^2): signal 10 channels, two background windows of 8 and 17 channels, scale 0.4.
        let window = ResolvedWindow(signal: 10..<20, background: .init(left: 2..<10, right: 30..<47, scale: 0.4))
        let lw = LineWindow(element: "Al", id: "Al_Ka", energy: 1.4865, fwhm: 0.07, window: window, failure: nil, conflicts: [])
        var spectrum = [UInt64](repeating: 0, count: 100)
        for c in 10..<20 { spectrum[c] = 7 }
        for c in 2..<10 { spectrum[c] = 3 }
        for c in 30..<47 { spectrum[c] = 5 }
        let g = 70.0, b = 3.0 * 8 + 5.0 * 17
        let c = try XCTUnwrap(ElementWindows.netCounts(spectrum: spectrum, windows: [lw]).first ?? nil)
        XCTAssertEqual(c.net, g - 0.4 * b, accuracy: 1e-9)
        XCTAssertEqual(c.sigma, (g + 0.4 * 0.4 * b).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(c.signal, 70); XCTAssertEqual(c.background, UInt64(b))
        // The same net count the per-pixel maps use, for a one-pixel image of this spectrum.
        let image = DenseSpectrumImage(ny: 1, nx: 1, channels: 100, counts: spectrum.map { UInt32($0) })
        XCTAssertEqual(try XCTUnwrap(ElementWindows.maps(image: image, windows: [lw]).first ?? nil)[0], c.net, accuracy: 1e-9)
        // With no background window: net = G and sigma = sqrt(G).
        let bare = LineWindow(element: "Al", id: "Al_Ka", energy: 1.4865, fwhm: 0.07,
                              window: ResolvedWindow(signal: 10..<20, background: nil), failure: nil, conflicts: [])
        let n = try XCTUnwrap(ElementWindows.netCounts(spectrum: spectrum, windows: [bare]).first ?? nil)
        XCTAssertEqual(n.net, 70); XCTAssertEqual(n.sigma, 70.0.squareRoot(), accuracy: 1e-12)
    }

    /// The conflict note names the line a background window sits on, in the table's own words, peaks before flanks.
    /// Mutation: the stable sort by `reachesIntegrationWindow` removed — red.
    func testConflictNotesNameTheOtherLine() {
        XCTAssertEqual(ElementWindows.label(ofLineID: "Al_Ka"), "Al Kα")
        XCTAssertEqual(ElementWindows.label(ofLineID: "Cu_Lb1"), "Cu Lβ1")
        let c = WindowConflict(line: "Mg_Ka", side: .right, other: "Si_Ka", otherEnergy: 1.74, overlap: 1.5...1.6, reachesIntegrationWindow: false)
        XCTAssertEqual(ElementWindows.conflictNote([c]), "background overlaps Si Kα")
        // A peak the background sits on is named before a flank it only touches, whatever the energy order.
        let flank = WindowConflict(line: "Mg_Ka", side: .left, other: "Cu_La", otherEnergy: 0.93, overlap: 1.03...1.06, reachesIntegrationWindow: false)
        let peak = WindowConflict(line: "Mg_Ka", side: .right, other: "Si_Ka", otherEnergy: 1.74, overlap: 1.65...1.7, reachesIntegrationWindow: true)
        XCTAssertEqual(ElementWindows.conflictNote([flank, peak]), "background overlaps Si Kα, Cu Lα")
        XCTAssertEqual(ElementWindows.conflictNote([flank, peak, c]), "background overlaps Si Kα, Cu Lα")
        XCTAssertNil(ElementWindows.conflictNote([]))
    }

    // MARK: The room, bound

    /// The results table has net counts and σ per element and NOTHING else until WP3: no at%, no k-free ratio.
    /// Mutation: `fitCells` ignoring `hasFit` — red.
    func testTheTableShowsNetCountsAndNoAtPercentBeforeWP3() async throws {
        let row = ResultRow(z: 13, netCounts: 100, netSigma: 10, kFreeRatio: 1, kFreeSigma: 0.1, atPercent: 88, atSigma: 1,
                            wtPercent: 80, wtSigma: 1, sigmaTerms: "")
        XCTAssertEqual(ResultFormat.fitCells(row, unit: .atomic, hasFit: false).abundance, "—")
        XCTAssertEqual(ResultFormat.fitCells(row, unit: .weight, hasFit: false).kFree, "—")
        XCTAssertNotEqual(ResultFormat.fitCells(row, unit: .atomic, hasFit: true).abundance, "—")

        let state = AppState()
        let image = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: Self.dm4, fourD: nil))
        state.openSpectrumImage(image)
        let model = state.spectroscopyRoom.model
        XCTAssertFalse(model.hasFit)
        XCTAssertTrue(model.isLive)
        for symbol in ["Al", "Mg", "Si", "Cu", "O"] { model.elements.click(try XCTUnwrap(PeriodicLayout.z(of: symbol))) }
        state.spectroscopyRoom.elementsChanged()
        try await waitFor { model.results.count == 5 }
        XCTAssertEqual(model.resultsFooter, "window net counts")
        XCTAssertEqual(model.tiles.count, 5)
        XCTAssertEqual(model.mixed, Set(model.results.map(\.z)),
                       "R10: a picked element is ticked into the mix, whether or not its line is a measurement (the note stays on tile and row)")
        for r in model.results { XCTAssertNil(r.kFreeSigma); XCTAssertEqual(r.atPercent, 0) }
        // The whole-map Al row is the exact window net count of the whole-map spectrum.
        let spectrum = image.sum(mask: nil)
        // Windows are built for the whole set (neighbouring lines merge their background windows), by Z as the room does.
        let windows = ElementWindows.build(elements: ["O", "Mg", "Al", "Si", "Cu"].map { ($0, nil) }, axis: image.energyAxis, beamEnergyKeV: image.metadata.beamEnergyKeV)
        let counts = ElementWindows.netCounts(spectrum: spectrum, windows: windows)
        let expected = try XCTUnwrap(counts[2])
        let al = try XCTUnwrap(model.results.first { $0.z == 13 })
        XCTAssertEqual(al.netCounts, expected.net, accuracy: 1e-9)
        XCTAssertEqual(al.netSigma, expected.sigma, accuracy: 1e-9)
        XCTAssertEqual(state.spectroscopy.elements.map(\.symbol), ["O", "Mg", "Al", "Si", "Cu"], "the session mirrors the roles, by Z")
    }

    /// A drawn region changes the spectrum and the rows to that region's, and the Whole map comes back.
    /// Mutation: `refresh` reading the whole map's mask instead of the selected region's — red.
    func testTheSelectedRegionDrivesTheSpectrumAndTheRows() async throws {
        let state = AppState()
        let image = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: Self.dm4, fourD: nil))
        state.openSpectrumImage(image)
        let controller = state.spectroscopyRoom, model = controller.model
        model.elements.click(13)
        controller.elementsChanged()
        try await waitFor("the whole map's row and spectrum", state: { "results \(model.results.count), spectrum sum \(model.series.data.reduce(0, +)), expected \(image.sum(mask: nil).reduce(0, +))" }) { model.results.count == 1 && model.series.data.reduce(0, +) == Double(image.sum(mask: nil).reduce(0, +)) }
        let rect = SpectrumRegionShape.rectangle(PixelRect(x0: 0, y0: 0, x1: 3, y1: 2))
        model.onRegionEdit?(rect, true)
        let regionTotal = Double(image.sum(mask: rect.mask(nx: 6, ny: 4)).reduce(0, +))
        try await waitFor("the region's spectrum", state: { "sum \(model.series.data.reduce(0, +)), expected \(regionTotal), regions \(model.regions.count)" }) { model.series.data.reduce(0, +) == regionTotal }
        XCTAssertEqual(model.regions.count, 2)
        XCTAssertEqual(model.spectrumTitle, "Spectrum · Region 1")
        XCTAssertEqual(model.spectrumPixels, 6)
        XCTAssertEqual(model.regionOutline, rect)
        model.selectedRegion = 0
        controller.regionPicked()
        try await waitFor("the whole map back", state: { model.spectrumTitle }) { model.spectrumTitle == "Spectrum · Whole map" }
        XCTAssertNil(model.regionOutline)
    }

    /// The Source row says how the spectrum image relates to the cube.
    func testTheSourceRowSaysSameScanOrNotRegistered() throws {
        let image = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: Self.dm4, fourD: nil))
        var meta = image.metadata
        XCTAssertNil(SpectroscopyRoomController.imageSettings(meta, axis: image.energyAxis, hasFourDCube: false).source)
        let beside = SpectroscopyRoomController.imageSettings(meta, axis: image.energyAxis, hasFourDCube: true)
        XCTAssertEqual(beside.source, "not registered to the 4D scan")
        XCTAssertTrue(beside.sourceWarning)
        meta.sameScanAs4DCube = true
        let same = SpectroscopyRoomController.imageSettings(meta, axis: image.energyAxis, hasFourDCube: true)
        XCTAssertEqual(same.source, "same scan as the 4D cube (one GMS run)")
        XCTAssertFalse(same.sourceWarning)
        XCTAssertTrue(try XCTUnwrap(same.liveDead).contains("as stored"))
        let elevation = try XCTUnwrap(((try truth()["forward_model"] as? [String: Any])?["absorption"] as? [String: Any])?["elevation_deg"] as? Double)
        XCTAssertEqual(same.geometry, "1 detector · elev. \(Int(elevation))°")
    }

    /// The hover's cut-off is the marker's own FWHM: a cursor 70 eV from a line 40 eV wide names no line, and one 30 eV away does.
    /// Mutation: the `?? lineTolerance` made unconditional — red.
    func testTheHoverCutOffIsTheLinesOwnFWHM() {
        let series = SpectrumSeries(energyStart: 1, energyStep: 0.01, data: [Double](repeating: 1, count: 100), background: [], model: [], overlay: nil)
        let vp = SpectrumViewport(domain: series.domain)
        let narrow = LineMarker(label: "Mg Kα", energy: 1.5, elementZ: 12, fwhm: 0.04)
        func line(at e: Double, _ m: LineMarker) -> String? {
            SpectrumHover.sample(series: series, viewport: vp, fraction: (e - vp.lo) / vp.span, markers: [m])?.line
        }
        XCTAssertNil(line(at: 1.57, narrow))
        XCTAssertEqual(line(at: 1.53, narrow), "Mg Kα")
        var wide = narrow; wide.fwhm = nil
        XCTAssertEqual(line(at: 1.57, wide), "Mg Kα", "no FWHM: the old 0.1 keV cut-off")
    }

    /// The ColorMix is one bitmap: a ticked tile in its colour, the rest black; no tick falls back to the scan image.
    /// Mutation: red and green swapped when the pixel bytes are written — red.
    func testTheColorMixRasterHasTheTilesColours() throws {
        let tile = MapTile(z: 13, width: 2, height: 1, values: [1, 0])
        let img = try XCTUnwrap(ColorMixRaster.image(tiles: [tile], mixed: [13], colors: [13: (1, 0, 0)], backdrop: [], width: 2, height: 1))
        XCTAssertEqual([img.width, img.height], [2, 1])
        let data = try XCTUnwrap(img.dataProvider?.data as Data?)
        XCTAssertEqual(Array(data.prefix(8)), [255, 0, 0, 255, 0, 0, 0, 255])
        let grey = try XCTUnwrap(ColorMixRaster.image(tiles: [tile], mixed: [], colors: [:], backdrop: [0, 1], width: 2, height: 1))
        let gdata = try XCTUnwrap(grey.dataProvider?.data as Data?)
        XCTAssertEqual(Array(gdata.prefix(8)), [0, 0, 0, 255, 255, 255, 255, 255])
        XCTAssertNil(ColorMixRaster.image(tiles: [], mixed: [], colors: [:], backdrop: [], width: 2, height: 1))
    }

    /// A drag on the map spans whole pixels, ends included, clamped to the grid.
    func testADragSpansTheStartAndEndPixels() {
        let r = RegionEditing.drawnRect(from: PixelPoint(x: 1.5, y: 0.5), to: PixelPoint(x: 4.4, y: 2.9), grid: (6, 4))
        XCTAssertEqual(r, PixelRect(x0: 1, y0: 0, x1: 5, y1: 3))
        XCTAssertEqual(RegionEditing.drawnRect(from: PixelPoint(x: -2, y: -2), to: PixelPoint(x: 9.9, y: 9.9), grid: (6, 4)),
                       PixelRect(x0: 0, y0: 0, x1: 6, y1: 4))
    }

    // MARK: Round 2 (Gate B)

    private final class ScopeLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [String] = []
        private var inScope = false
        var events: [String] { lock.withLock { _events } }
        func start() -> Bool { lock.withLock { inScope = true; _events.append("start") }; return true }
        func stop() { lock.withLock { inScope = false; _events.append("stop") } }
        func sniff() -> SpectrumFileKind { lock.withLock { _events.append("sniff in scope: \(inScope)") }; return .other }
    }

    /// The sniff runs inside the security scope: a bookmark URL cannot be read outside it, answers `.other`, and the 4D open would
    /// take a Velox HAADF stack for a one-row cube. Start, sniff, stop; balanced even when the answer is `.other`.
    /// Mutation: the `access.start(url)` call moved below the sniff — red.
    func testTheSniffRunsInsideTheSecurityScope() async {
        let log = ScopeLog()
        let access = AppState.SpectrumOpenAccess(start: { _ in log.start() }, stop: { _ in log.stop() }, kind: { _ in log.sniff() })
        let state = AppState()
        let opened = await state.openAsSpectrumImageIfApplicable(URL(fileURLWithPath: Self.velox), access: access)
        XCTAssertFalse(opened)
        XCTAssertEqual(log.events, ["start", "sniff in scope: true", "stop"])
    }

    /// A region chosen from the sidebar (through the controller) drives the room: model, outline, spectrum.
    /// Mutation: `selectRegion` not calling `refresh()` — red.
    func testSelectingARegionFromAnywhereDrivesTheRoom() async throws {
        let state = AppState()
        state.openSpectrumImage(try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: Self.dm4, fourD: nil)))
        let controller = state.spectroscopyRoom, model = controller.model
        model.onRegionEdit?(.rectangle(PixelRect(x0: 0, y0: 0, x1: 3, y1: 2)), true)
        try await waitFor("Region 1", state: { model.spectrumTitle }) { model.spectrumTitle == "Spectrum · Region 1" }
        controller.selectRegion(id: 0)
        XCTAssertEqual(model.selectedRegion, 0)
        XCTAssertEqual(state.spectroscopy.selectedRegionID, 0)
        try await waitFor("Whole map", state: { model.spectrumTitle }) { model.spectrumTitle == "Spectrum · Whole map" }
        controller.selectRegion(id: 99)
        XCTAssertEqual(model.selectedRegion, 0, "an unknown region changes nothing")
    }

    /// s·B >= G is not a measurement: its own windows decide, whatever else is selected.
    /// Mutation: `>=` weakened to `>` with s·B == G in the data, or the property returning false — red.
    func testABackgroundThatHoldsMoreThanTheSignalIsNotAMeasurement() throws {
        let window = ResolvedWindow(signal: 10..<20, background: .init(left: 2..<10, right: 30..<47, scale: 0.4))
        let lw = LineWindow(element: "Al", id: "Al_Ka", energy: 1.4865, fwhm: 0.07, window: window, failure: nil, conflicts: [])
        var spectrum = [UInt64](repeating: 0, count: 100)
        for c in 10..<20 { spectrum[c] = 1 }           // G = 10
        for c in 2..<10 { spectrum[c] = 4 }            // B = 32 + 4 * 17 = 100; s B = 40
        for c in 30..<47 { spectrum[c] = 4 }
        let bad = try XCTUnwrap(ElementWindows.netCounts(spectrum: spectrum, windows: [lw]).first ?? nil)
        XCTAssertTrue(bad.backgroundExceedsSignal)
        XCTAssertEqual(bad.notAMeasurementText, "not a measurement: the background windows (s·B = 40) hold more than the signal window (G = 10); they sit on neighbouring peaks")
        for c in 10..<20 { spectrum[c] = 4 }           // G = 40 = s B: equal counts as "not more", still refused (>=)
        XCTAssertTrue(try XCTUnwrap(ElementWindows.netCounts(spectrum: spectrum, windows: [lw]).first ?? nil).backgroundExceedsSignal)
        for c in 10..<20 { spectrum[c] = 9 }
        let good = try XCTUnwrap(ElementWindows.netCounts(spectrum: spectrum, windows: [lw]).first ?? nil)
        XCTAssertFalse(good.backgroundExceedsSignal)
        XCTAssertNil(good.notAMeasurementText)
    }

    /// In the room: such a row shows no number (failure text), keeps G/B/s in the σ terms, is not auto-ticked, with Al ALONE selected.
    /// Mutation: `failure: c.notAMeasurementText` removed from the row — red.
    func testTheRoomShowsNoNumberForALineWhoseBackgroundExceedsItsSignal() async throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1000)
        let windows = ElementWindows.build(elements: [("Al", nil)], axis: axis, beamEnergyKeV: nil)
        let w = try XCTUnwrap(windows.first?.window), bg = try XCTUnwrap(w.background)
        var counts = [UInt32](repeating: 0, count: 1000)
        for c in w.signal { counts[c] = 1 }
        for c in bg.left { counts[c] = 50 }
        for c in bg.right { counts[c] = 50 }
        let meta = SpectrumImageMetadata(fileName: "synthetic", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: 1000,
                                         energyOffsetEV: 0, energyDispersionEV: 10)
        let state = AppState()
        state.openSpectrumImage(LoadedSpectrumImage(image: DenseSpectrumImage(ny: 1, nx: 1, channels: 1000, counts: counts),
                                                    metadata: meta, energyAxis: axis))
        let model = state.spectroscopyRoom.model
        model.elements.click(13)
        state.spectroscopyRoom.elementsChanged()
        try await waitFor("the Al row", state: { "\(model.results.count)" }) { model.results.count == 1 }
        let row = try XCTUnwrap(model.results.first)
        XCTAssertTrue(try XCTUnwrap(row.failure).hasPrefix("not a measurement: the background windows"))
        XCTAssertTrue(row.sigmaTerms.contains("G = ") && row.sigmaTerms.contains("B = ") && row.sigmaTerms.contains("s = "))
        XCTAssertEqual(model.tiles.map(\.z), [13])
        // R10 (changed from "not auto-ticked"): the mix is a picture, the note is the honesty label; a picked element is in the mix.
        XCTAssertTrue(model.mixed.contains(13), "R10: a picked element is ticked into the mix even when its line is not a measurement")
        XCTAssertNotNil(model.tiles.first?.notMeasuredWhy, "the tile keeps its not-a-measurement note")
    }

    /// One window rule: a window that holds a 4D cube sends a spectrum-image file to a NEW window and attaches nothing.
    /// Mutation: the `hasDataset` rule removed — red.
    func testACubeWindowSendsASpectrumFileToANewWindow() async throws {
        let state = AppState()
        var routed: [URL] = []
        state.openInNewWindow = { url, _ in routed.append(url) }
        await state.openDemoFixture()
        XCTAssertTrue(state.hasDataset)
        let url = URL(fileURLWithPath: Self.velox)
        let handled = await state.openAsSpectrumImageIfApplicable(url)
        XCTAssertTrue(handled)
        XCTAssertEqual(routed, [url])
        XCTAssertFalse(state.hasSpectrumImage)
    }

    /// The map's bitmap is built once per state, again when the tiles (revision) or the ticks change.
    /// Mutation: `mixed` dropped from the cache key — red.
    func testTheRasterIsCachedByTilesAndTicks() {
        let cache = ColorMixRasterCache()
        var key = ColorMixRasterCache.Key(revision: 1, mixed: [13], width: 2, height: 1, backdropCount: 0)
        var made = 0
        func build() -> CGImage? { made += 1; return nil }
        _ = cache.image(for: key, build: build); _ = cache.image(for: key, build: build)
        XCTAssertEqual(made, 1)
        key.mixed = [13, 12]; _ = cache.image(for: key, build: build)
        XCTAssertEqual(made, 2)
        key.revision = 2; _ = cache.image(for: key, build: build)
        XCTAssertEqual(made, 3)
    }

    private func waitFor(_ what: String = "the room to update", timeout: TimeInterval = 20, state: () -> String = { "" },
                         _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { XCTFail("timed out waiting for \(what): \(state())"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
