import SwiftUI
import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// v5.0 WP2 lane R: the seventh room (ADR 053 item 3, 054 item 8, 055), its
/// session owner, and the spectrum-only window. No 4D behaviour may change:
/// every rule here is checked both with and without a spectrum image.
@MainActor
final class SpectroscopyRoomTests: XCTestCase {

    /// A spectrum image with nothing behind it but its metadata: every sum is zero.
    private final class StubSpectrumImage: SpectrumImageSource {
        let metadata: SpectrumImageMetadata
        nonisolated let energyAxis = EnergyAxis(offset: -0.48, scale: 0.005, size: 4096)
        nonisolated let scanImage: [Float]? = nil
        nonisolated var ny: Int { metadata.scanHeight }
        nonisolated var nx: Int { metadata.scanWidth }
        nonisolated var channels: Int { metadata.channelCount }
        init(width: Int = 256, height: Int = 255) {
            metadata = SpectrumImageMetadata(
                fileName: "stub.emd", filePath: "/tmp/stub.emd", scanWidth: width, scanHeight: height,
                channelCount: 4096, energyOffsetEV: -480, energyDispersionEV: 5)
        }
        nonisolated func sum(mask: PixelMask?) -> [UInt64] { [UInt64](repeating: 0, count: channels) }
        nonisolated func windowSums(_ ranges: [Range<Int>]) -> [[UInt64]] {
            [[UInt64]](repeating: [UInt64](repeating: 0, count: nx * ny), count: ranges.count)
        }
    }

    // MARK: - The room list

    /// Spectroscopy sits before Results, Results stays last (ADR 053 item 3), and
    /// the shortcuts follow the list: Spectroscopy ⌘6, Results ⌘7.
    /// Mutation: `.spectroscopy` declared after `.results` — red.
    func testSpectroscopyIsTheSixthRoomAndResultsStaysLast() {
        XCTAssertEqual(WorkspaceArea.allCases,
                       [.prepare, .image, .braggDisks, .map, .reconstruct, .spectroscopy, .results])
        XCTAssertEqual(WorkspaceArea.allCases.map(\.shortcutDigit),
                       ["1", "2", "3", "4", "5", "6", "7"])
        XCTAssertEqual(WorkspaceArea.spectroscopy.shortcutDigit, "6")
        XCTAssertEqual(WorkspaceArea.results.shortcutDigit, "7")
        XCTAssertEqual(WorkspaceArea.spectroscopy.title, "Spectroscopy")
        XCTAssertEqual(WorkspaceArea.spectroscopy.subtitle,
                       "EDX spectrum images, alone or with the 4D scan")
        XCTAssertTrue(WorkspaceArea.spectroscopy.analysisModes.isEmpty,
                      "its steps are not AnalysisModes: they never enter the 4D task plumbing")
    }

    /// The five steps of ADR 054 item 8, in order; the room opens on the first.
    func testTheRoomHasTheFiveStepsOfADR054() {
        XCTAssertEqual(SpectroscopyStep.allCases.map(\.title),
                       ["Spectrum image", "Elements & maps", "Regions", "Quantify", "Export"])
        XCTAssertEqual(SpectroscopySession().selectedStep, .spectrumImage)
    }

    // MARK: - The session owner's defaults (ADR 054)

    /// Mutations: `estimator` defaulting to `.poissonMaximumLikelihood`, or
    /// `background` to `.wholeRangePolynomial6` — red.
    func testTheQuantificationMethodDefaultsAreADR054s() {
        let method = SpectroscopySession().method
        XCTAssertEqual(method.estimator, .leastSquares, "item 1: least squares, unweighted, is the named default")
        XCTAssertEqual(SpectroscopyQuantificationMethod.Background.allCases,
                       [.empiricalWithAlEdge, .wholeRangePolynomial6], "the eXSpy parity path, under Expert")
        XCTAssertEqual(method.background, .empiricalWithAlEdge, "item 2: empirical continuum + Al edge")
        XCTAssertEqual(method.kFactorSource, .brownPowell, "item 3: computed Brown-Powell k")
        XCTAssertTrue(method.absorptionCorrection, "ADR 053 item 5: absorption on")
        XCTAssertNil(method.thickness, "item 9: no thickness is assumed")
    }

    /// Opening seeds the whole map as the one region, at the first step; the method survives.
    /// Mutation: `open` not seeding the whole-map region — red.
    func testOpeningASpectrumImageStartsTheRoomOverOnTheWholeMap() {
        let session = SpectroscopySession()
        XCTAssertNil(session.source)
        XCTAssertTrue(session.regions.isEmpty)
        session.selectedStep = .quantify
        session.elements = [SpectroscopyElement(symbol: "Mg", role: .quantify, isManual: true)]
        session.method.estimator = .poissonMaximumLikelihood

        session.open(StubSpectrumImage(width: 256, height: 255))
        XCTAssertEqual(session.metadata?.fileName, "stub.emd")
        XCTAssertEqual(session.selectedStep, .spectrumImage)
        XCTAssertTrue(session.elements.isEmpty)
        XCTAssertEqual(session.regions.map(\.name), ["Whole map"])
        XCTAssertEqual(session.regions.first?.pixelCount, 256 * 255)
        XCTAssertEqual(session.selectedRegionID, session.regions.first?.id)
        XCTAssertEqual(session.method.estimator, .poissonMaximumLikelihood, "the method is the user's, kept")

        session.close()
        XCTAssertNil(session.source)
        XCTAssertTrue(session.regions.isEmpty)
        XCTAssertNil(session.selectedRegionID)
    }

    // MARK: - Which rooms a window offers

    /// A spectrum-only window offers Spectroscopy and Results; a 4D window offers
    /// all seven, with or without a spectrum image; no document offers none to the
    /// menu (unchanged: the Go to items were disabled without a dataset).
    /// Mutation: `needsFourDCube` true for `.results` — red.
    func testRoomAvailabilityFollowsWhatTheWindowHolds() {
        for area in WorkspaceArea.allCases {
            XCTAssertTrue(area.isAvailable(hasFourDCube: true, hasSpectrumImage: false), "\(area)")
            XCTAssertTrue(area.isAvailable(hasFourDCube: true, hasSpectrumImage: true), "\(area)")
            XCTAssertFalse(area.isAvailable(hasFourDCube: false, hasSpectrumImage: false), "\(area)")
        }
        let spectrumOnly = WorkspaceArea.allCases.filter {
            $0.isAvailable(hasFourDCube: false, hasSpectrumImage: true)
        }
        XCTAssertEqual(spectrumOnly, [.spectroscopy, .results])
    }

    /// The spectrum-only window: it opens in Spectroscopy, is a document but not
    /// a 4D dataset, and a 4D room cannot be entered (sidebar row disabled, menu
    /// item disabled, and `selectWorkspace` declines as the backstop).
    /// Mutation: the `isWorkspaceWithheld` guard removed from `selectWorkspace` — red.
    func testASpectrumOnlyWindowShowsSpectroscopyAndResultsOnly() {
        let state = AppState()
        XCTAssertFalse(state.hasDocument)
        state.openSpectrumImage(StubSpectrumImage())

        XCTAssertTrue(state.hasDocument)
        XCTAssertTrue(state.hasSpectrumImage)
        XCTAssertFalse(state.hasDataset, "hasDataset still means a 4D cube")
        XCTAssertTrue(state.isSpectrumOnly)
        XCTAssertEqual(state.navigation.workspaceArea, .spectroscopy, "a spectrum image opens in its room")

        state.selectWorkspace(.image)
        XCTAssertEqual(state.navigation.workspaceArea, .spectroscopy, "a 4D room is withheld")
        XCTAssertTrue(state.isWorkspaceWithheld(.image))
        XCTAssertFalse(state.isWorkspaceAvailable(.image))

        state.selectWorkspace(.results)
        XCTAssertEqual(state.navigation.workspaceArea, .results)
        XCTAssertTrue(state.isWorkspaceAvailable(.results))
        XCTAssertFalse(state.canRunPrimaryWorkspaceTask)
    }

    /// No document: nothing is withheld from the sidebar, so navigation behaves
    /// exactly as before the seventh room (the R1 prediction's guard).
    func testWithoutASpectrumImageNothingIsWithheld() {
        let state = AppState()
        for area in WorkspaceArea.allCases {
            XCTAssertFalse(state.isWorkspaceWithheld(area), "\(area)")
            state.selectWorkspace(area)
            XCTAssertEqual(state.navigation.workspaceArea, area)
        }
    }

    /// A 4D window keeps all seven rooms, and attaching a spectrum image to it
    /// changes no 4D state.
    func testA4DWindowKeepsEveryRoomAndASpectrumImageAttachesBeside() async {
        let state = AppState()
        await state.openDemoFixture()
        XCTAssertTrue(state.hasDataset)
        XCTAssertFalse(state.isSpectrumOnly)
        for area in WorkspaceArea.allCases {
            XCTAssertTrue(state.isWorkspaceAvailable(area), "\(area)")
        }
        let descriptor = state.descriptor
        state.openSpectrumImage(StubSpectrumImage())
        XCTAssertTrue(state.hasDataset)
        XCTAssertFalse(state.isSpectrumOnly)
        XCTAssertEqual(state.descriptor, descriptor, "the cube is untouched")
        state.selectWorkspace(.braggDisks)
        XCTAssertEqual(state.navigation.workspaceArea, .braggDisks)
    }

    // MARK: - Sidebar selection

    /// A step row selects the room and the step; reading the route back gives the step.
    /// Mutation: the binding's getter returning `.workspace(.spectroscopy)` — red.
    func testTheSidebarSelectsSpectroscopySteps() {
        let state = AppState()
        state.workspaceRoute.wrappedValue = .spectroscopyStep(.quantify)
        XCTAssertEqual(state.navigation.workspaceArea, .spectroscopy)
        XCTAssertEqual(state.spectroscopy.selectedStep, .quantify)
        XCTAssertEqual(state.workspaceRoute.wrappedValue, .spectroscopyStep(.quantify))

        // The room's own row lands on the step last selected.
        state.selectWorkspace(.prepare)
        state.workspaceRoute.wrappedValue = .workspace(.spectroscopy)
        XCTAssertEqual(state.workspaceRoute.wrappedValue, .spectroscopyStep(.quantify))
        XCTAssertEqual(WorkspaceRoute.spectroscopyStep(.regions).area, .spectroscopy)
    }

    // MARK: - The toolbar

    /// The centre display for a spectrum image names the scan grid in pixels, as the mock does.
    func testTheToolbarDisplayNamesASpectrumImagesGrid() {
        XCTAssertEqual(ToolbarDisplayFormat.idleSpectrumImage(file: "Al-Mg-Si_190330.emd",
                                                              room: "Spectroscopy", width: 256, height: 256),
                       "Al-Mg-Si_190330.emd · Spectroscopy · 256 × 256 px")
    }

    /// The verb is Quantify; with a spectrum image it exists, and it can run once an element is switched on.
    /// Mutation: `canQuantify` true without elements - red.
    func testTheRoomsVerbIsQuantifyAndRunsOnceAnElementIsOn() {
        let state = AppState()
        state.openSpectrumImage(StubSpectrumImage())
        XCTAssertEqual(PrimaryActionButton.spectroscopyActionTitle, "Quantify")
        XCTAssertTrue(state.hasPrimaryWorkspaceTask)
        XCTAssertFalse(state.canRunPrimaryWorkspaceTask)
        XCTAssertNotNil(state.spectroscopyRoom.quantifyBlocker)
        state.spectroscopyRoom.model.elements.set(13, .quantify)
        XCTAssertTrue(state.canRunPrimaryWorkspaceTask)
        XCTAssertNil(state.spectroscopyRoom.quantifyBlocker)
    }
    // MARK: - Round 2 (coordinator's items 2 and 4)

    /// A spectrum-only window's Settings tab never says "No dataset loaded": the
    /// Spectroscopy room shows its step, every other room one line.
    /// Mutation: `.results` mapped to `.step` — red.
    func testASpectrumOnlyWindowsSettingsShowTheStepOrOneLine() {
        XCTAssertEqual(SpectrumOnlySettings.content(for: .spectroscopy), .step)
        for area in WorkspaceArea.allCases where area != .spectroscopy {
            guard case .note(let text) = SpectrumOnlySettings.content(for: area) else {
                return XCTFail("\(area) shows a step inspector in a spectrum-only window")
            }
            XCTAssertFalse(text.isEmpty)
        }
    }

    /// A file opened while the window holds only a spectrum image goes to a new
    /// window and starts no load here; with no spectrum image, or beside a 4D
    /// cube, the open is not rerouted.
    /// Mutation: the guard in `routesOpenToNewWindow` reduced to the route's presence — red.
    func testAFileOpenedInASpectrumOnlyWindowGoesToANewWindow() async {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist.h5")
        var routed: [(URL, Bool)] = []

        let empty = AppState()
        empty.openInNewWindow = { routed.append(($0, $1)) }
        XCTAssertFalse(empty.routesOpenToNewWindow(url, configure: false), "an empty window opens the file itself")

        let state = AppState()
        state.openInNewWindow = { routed.append(($0, $1)) }
        state.openSpectrumImage(StubSpectrumImage())
        state.openFile(url: url)
        state.openFileForConfiguration(url: url)
        XCTAssertEqual(routed.map(\.0), [url, url])
        XCTAssertEqual(routed.map(\.1), [false, true], "Open with Options stays Open with Options")
        XCTAssertFalse(state.datasetSession.isLoading, "nothing starts loading in this window")
        XCTAssertTrue(state.isSpectrumOnly)

        let both = AppState()
        both.openInNewWindow = { routed.append(($0, $1)) }
        await both.openDemoFixture()
        both.openSpectrumImage(StubSpectrumImage())
        XCTAssertFalse(both.routesOpenToNewWindow(url, configure: false), "a 4D window opens as before")
        XCTAssertEqual(routed.count, 2)
    }

    /// The relay's new action opens the file in the window that takes it.
    func testTheRelayCarriesAFileToTheNewWindow() {
        let state = AppState()
        var routed: [URL] = []
        state.openInNewWindow = { url, _ in routed.append(url) }
        state.openSpectrumImage(StubSpectrumImage())
        let url = URL(fileURLWithPath: "/tmp/does-not-exist.h5")
        MenuActionRelay.run(.openFile(url, configure: false), in: state)
        XCTAssertEqual(routed, [url], "run reached openFile (which, spectrum-only here, routes it on)")
    }

    /// A spectrum image beside a 4D cube says it is not registered to the scan.
    /// Mutation: the note returned regardless of the cube — red.
    func testASpectrumImageBesideACubeIsMarkedNotRegistered() {
        XCTAssertNotNil(SpectroscopyPlaceholderFormat.registrationNote(hasFourDCube: true))
        XCTAssertNil(SpectroscopyPlaceholderFormat.registrationNote(hasFourDCube: false))
    }
}
