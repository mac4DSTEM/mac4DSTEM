import CoreGraphics
import XCTest
@testable import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM
@testable import FormatoDM
@testable import FormatoEMD
@testable import SpectroCore
@testable import SpectroEDX

/// v5.0 WP2 lane R2: from a file to a spectrum image in the room. Fixtures: `demo-edx-tiny.dm4` (6 x 4 scan, 512 channels,
/// truth beside it) and `velox-tiny.emd` (3 rows x 2 columns, 8 channels, 2 frames: the main file of
/// archived `tools/velox-parity/make-tiny-fixture.py`, the same bytes VeloxEMDReaderTests embeds). Each test names its mutation.
@MainActor
final class SpectrumImageOpeningTests: XCTestCase {

    private static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    private static var dm4: String { dir.appendingPathComponent("demo-edx-tiny.dm4").path }
    private static var velox: String { dir.appendingPathComponent("velox-tiny.emd").path }
    private static var h5: String { dir.appendingPathComponent("qshape3.mac4dstem.h5").path }

    // MARK: GMS joint attach

    /// The same run (one Experiment ID) on the same grid registers by identity; another grid attaches with the reason.
    /// Mutation: the width compared with the EDS height (`cube.scanWidth == d.ny`) — red.
    func testTheEDSIsRegisteredToItsCubeByIdentityAndAMismatchSaysSo() throws {
        let index = try XCTUnwrap(try DM4Experiment.list(path: Self.dm4).first { $0.role == .diffraction }).index
        let same = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(
            path: Self.dm4, fourD: GMSFourDIdentity(objectIndex: index, scanWidth: 6, scanHeight: 4)))
        XCTAssertTrue(same.metadata.sameScanAsCube)
        XCTAssertNil(same.metadata.registrationNote)

        let other = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(
            path: Self.dm4, fourD: GMSFourDIdentity(objectIndex: index, scanWidth: 4, scanHeight: 6)))
        XCTAssertFalse(other.metadata.sameScanAsCube)
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
        XCTAssertEqual(state.spectroscopy.metadata?.sameScanAsCube, true)
        XCTAssertEqual(state.navigation.workspaceArea, .image, "the joint open lands on the cube's room, as before")
        XCTAssertEqual(state.spectroscopy.regions.first?.pixelCount, 24)
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

    // MARK: The room, bound

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

    /// One sniff per open, and none for a file the extension rules out: a 4D `.h5` is never sniffed here (it used to be routed
    /// on the main actor first), and an `.emd` is sniffed exactly once, off the main thread (design review 2026-10-22).
    /// Mutation: the route moved back before the guard, or the sniff run twice — red.
    func testASpectrumCandidateIsSniffedOnceOffTheMainThreadAndOthersNotAtAll() async {
        let log = ScopeLog()
        let offMain = LockedFlag()
        let access = AppState.SpectrumOpenAccess(start: { _ in log.start() }, stop: { _ in log.stop() },
                                                 kind: { _ in offMain.set(!Thread.isMainThread); return log.sniff() })
        let state = AppState()
        _ = await state.openAsSpectrumImageIfApplicable(URL(fileURLWithPath: Self.velox), access: access)
        XCTAssertEqual(log.events.filter { $0.hasPrefix("sniff") }.count, 1)
        XCTAssertTrue(offMain.value, "the sniff ran on the main thread")

        let other = ScopeLog()
        let untouched = AppState.SpectrumOpenAccess(start: { _ in other.start() }, stop: { _ in other.stop() }, kind: { _ in other.sniff() })
        let opened = await state.openAsSpectrumImageIfApplicable(URL(fileURLWithPath: "/tmp/not-a-spectrum-candidate.h5"), access: untouched)
        XCTAssertFalse(opened)
        XCTAssertEqual(other.events, [], "a file the extension rules out is neither scoped nor sniffed")
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

    private func waitFor(_ what: String = "the room to update", timeout: TimeInterval = 20, state: () -> String = { "" },
                         _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { XCTFail("timed out waiting for \(what): \(state())"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}


/// A flag set from a detached task and read after it: the sniff seam is `@Sendable`.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func set(_ v: Bool) { lock.lock(); flag = v; lock.unlock() }
}
