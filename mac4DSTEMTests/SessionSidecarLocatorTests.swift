//
//  SessionSidecarLocatorTests.swift
//  S1's seam: the one owner of "where is this dataset's sidecar, and may I read
//  it?" (docs/v2-release.md §8, docs/open-items.md C10).
//
//  Each test below was verified by BREAKING the line it covers and watching it
//  fail — the named line is in the test's own comment, because "it went red" is
//  not evidence in this repo.
//
//  What these tests deliberately do NOT cover: the sandbox denial itself. EPERM
//  on a sibling file needs a real sandboxed process, and XCTest here is not one
//  — `tools/sidecar-error-detail-test` runs that case under `sandbox-exec`.
//  What is covered here is everything the app decides AROUND the denial: which
//  file it asks for, and whether it can tell a refusal from an absence.
//

import XCTest
@testable import mac4DSTEM

@MainActor
final class SessionSidecarLocatorTests: XCTestCase {

    private func descriptor(path: String) -> DatasetDescriptor {
        DatasetDescriptor(
            filePath: path, datasetPath: "/4DSTEM_experiment/data/datacubes/datacube_0/data",
            shape: [4, 5, 8, 8], dtypeDescription: "float32", chunkShape: nil
        )
    }

    // MARK: The derivation

    func testLocationFallsBackToTheDerivedSiblingWhenThereIsNoGrant() {
        let locator = SessionSidecarLocator()
        let cube = descriptor(path: "/tmp/mac4dstem-tests/polyAu.h5")

        XCTAssertNil(locator.grant(for: cube),
                     "a locator that has adopted nothing must report no grant")
        XCTAssertEqual(locator.location(for: cube).lastPathComponent, "polyAu.mac4dstem.h5",
                       "with no grant the location is the sibling beside the cube")
    }

    /// Breaking `location(forSourcePath:)` to ignore the grant
    /// (`SessionSidecarLocator.swift:90`, dropping the `grant(forSourcePath:)`
    /// term) makes this fail: the derived sibling is returned instead of the
    /// user-chosen file. That is the defect S1 fixed in
    /// `recordedLoadSpecification`, which never consulted the grant at all.
    func testAGrantedURLWinsOverTheDerivedSibling() {
        let locator = SessionSidecarLocator()
        let cube = descriptor(path: "/tmp/mac4dstem-tests/polyAu.h5")
        let chosen = URL(fileURLWithPath: "/tmp/mac4dstem-tests/elsewhere/chosen-name.h5")

        locator.adopt(chosen, for: cube)

        XCTAssertEqual(locator.location(for: cube), chosen,
                       "a sidecar the user chose in a panel is where the sidecar IS — "
                       + "the derived sibling is only the fallback")
        XCTAssertTrue(locator.hasGrant)
    }

    // MARK: The defect that armed itself

    /// **The regression test for the warm-cache defect.** Before S1 the cache
    /// was consulted before the descriptor was looked at
    /// (`ResultExport.swift:81`, `if let scopedSessionSidecarURL { return ... }`),
    /// so once ANY dataset's bookmark resolved, every later dataset was handed
    /// that same sidecar — one cube's results written into another cube's
    /// companion. Removing the `scoped.sourcePath == path` test in
    /// `SessionSidecarLocator.swift:109` reproduces it and fails this test.
    ///
    /// It was invisible in production only because no bookmark resolved at all
    /// after the bundle-identifier change; it would have armed itself the moment
    /// one did, which is exactly what S1's fix makes happen.
    func testAWarmGrantIsNeverHandedToADifferentDataset() {
        let locator = SessionSidecarLocator()
        let first = descriptor(path: "/tmp/mac4dstem-tests/polyAu.h5")
        let second = descriptor(path: "/tmp/mac4dstem-tests/siGe.h5")
        let firstSidecar = URL(fileURLWithPath: "/tmp/mac4dstem-tests/polyAu.mac4dstem.h5")

        locator.adopt(firstSidecar, for: first)

        XCTAssertNil(locator.grant(for: second),
                     "the second dataset has no grant of its own; returning the first "
                     + "dataset's sidecar would write one cube's results into another's companion")
        XCTAssertEqual(locator.location(for: second).lastPathComponent, "siGe.mac4dstem.h5",
                       "the second dataset falls back to ITS OWN sibling, not the first's")
        XCTAssertEqual(locator.location(for: first), firstSidecar,
                       "and the first dataset's grant is untouched by the question")
    }

    func testReleasingDropsTheGrant() {
        let locator = SessionSidecarLocator()
        let cube = descriptor(path: "/tmp/mac4dstem-tests/polyAu.h5")
        locator.adopt(URL(fileURLWithPath: "/tmp/mac4dstem-tests/chosen.h5"), for: cube)
        XCTAssertTrue(locator.hasGrant)

        locator.release()

        XCTAssertFalse(locator.hasGrant, "the open dataset changed; the grant does not carry")
        XCTAssertEqual(locator.location(for: cube).lastPathComponent, "polyAu.mac4dstem.h5")
    }

    // MARK: Telling a refusal from an absence

    /// The string is the one the app actually printed on 2026-08-19 at 09:34:27,
    /// copied verbatim rather than paraphrased — a classifier tested against a
    /// tidied-up version of its input is testing the tidying.
    private static let observedDenial = """
        HDF5 failed while opening the session sidecar — HDF5 reported: unable to open file: \
        name = '/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/\
        training_dataset/sim_Au_data_all_binned.mac4dstem.h5', errno = 1, \
        error message = 'Operation not permitted', flags = 0, o_flags = 0
        """

    /// Breaking the marker in `SessionSidecarLocator.swift` (`"errno = 1,"` →
    /// `"errno = 13,"`) fails this and passes the EACCES test below — which is
    /// precisely the mistake `tools/sidecar-error-detail-test` shipped in its
    /// first version and Gate B caught: EPERM is the sandbox, EACCES is an
    /// ordinary POSIX permission problem, and swapping them sends the diagnosis
    /// the other way.
    func testTheObservedSandboxDenialIsClassifiedAsNotPermitted() {
        let failure = SessionSidecarReadFailure.classify(
            SimpleError(Self.observedDenial)
        )
        XCTAssertEqual(failure, .notPermitted,
                       "errno 1 / EPERM is the sandbox refusing a file the app was never granted")

        let explanation = failure.explanation(sidecar: "sim_Au.mac4dstem.h5")
        XCTAssertTrue(explanation.contains("not been granted access"),
                      "the message must name the cause, not the mechanism")
        XCTAssertTrue(explanation.contains("Save Calibration to Session Sidecar"),
                      "and it must name the remedy — a refusal the user cannot act on is just a log line")
    }

    func testAnOrdinaryPermissionErrorIsNotReportedAsASandboxDenial() {
        let posix = "unable to open file: name = '/tmp/x.mac4dstem.h5', errno = 13, "
            + "error message = 'Permission denied', flags = 0, o_flags = 0"
        XCTAssertEqual(SessionSidecarReadFailure.classify(SimpleError(posix)), .unreadable,
                       "EACCES is a chmod problem, not the sandbox; telling the user to re-save "
                       + "would send them somewhere that cannot help")
    }

    // MARK: The silent full-extent load — the defect S1 actually fixed

    /// **The regression test for the worst behaviour in this session's scope.**
    /// A refused read must never be reported as "this session recorded no crop".
    /// Before S1 the read was `try?` inside `recordedLoadSpecification`, so a
    /// sidecar that said "this was a cropped view" and could not be opened
    /// produced the same `nil` as no sidecar at all — and the dataset then
    /// opened at FULL EXTENT in silence, with results that belong to a different
    /// extent than the one on screen.
    ///
    /// Breaking `recordedOutcome(from:sidecar:)` so its `.failure` branch returns
    /// `.noneRecorded` reproduces exactly that and fails this test. That
    /// breakage was run: with the earlier `try?`-shaped code the whole suite
    /// stayed GREEN, which is why this test exists at all.
    func testARefusedReadIsNeverReportedAsNoRecordedCrop() {
        let outcome = SessionSidecarLocator.recordedOutcome(
            from: .failure(SimpleError(Self.observedDenial)), sidecar: "sim_Au.mac4dstem.h5"
        )
        XCTAssertNotEqual(outcome, .noneRecorded,
                          "a sidecar that could not be read is not a sidecar that recorded nothing — "
                          + "collapsing them reopens a cropped session at full extent, silently")
        guard case .unreadable(let message) = outcome else {
            return XCTFail("expected .unreadable, got \(outcome)")
        }
        XCTAssertTrue(message.contains("sim_Au.mac4dstem.h5"),
                      "the message names the file it could not read")
        XCTAssertTrue(message.contains("Loading the whole dataset"),
                      "and says what the app did instead, because that is the part "
                      + "that changes how the numbers on screen should be read")
    }

    func testASidecarThatRecordsNothingLoadsTheWholeFileQuietly() {
        XCTAssertEqual(
            SessionSidecarLocator.recordedOutcome(from: .success(nil), sidecar: "x.mac4dstem.h5"),
            .noneRecorded,
            "no recorded specification is the ordinary case and must stay silent")
        XCTAssertEqual(
            SessionSidecarLocator.recordedOutcome(
                from: .success(.fullExtent), sidecar: "x.mac4dstem.h5"),
            .noneRecorded,
            "a session recorded at full extent is indistinguishable from no specification — "
            + "that identity is what makes promotion `removing` the specification")
    }

    func testARecordedCropIsCarriedThrough() {
        let crop = LoadSpecification(
            scanCrop: AxisCrop(yOffset: 24, xOffset: 12, height: 76, width: 48),
            detectorBin: 2
        )
        XCTAssertEqual(
            SessionSidecarLocator.recordedOutcome(
                from: .success(crop), sidecar: "x.mac4dstem.h5"),
            .recorded(crop),
            "a reduced specification reaches the caller unchanged")
    }

    // MARK: The two things Gate D showed were untested

    /// **The bookmark key round-trip.** Gate D reintroduced C10's failure by
    /// changing one token — the `session-sidecar-bookmark.` prefix in
    /// `SessionSidecarLocator.swift` — and every test stayed green, though that
    /// string is the single key the entire diagnosis is indexed by (it is what
    /// was read out of the old container's plist to establish the cause). This
    /// pins persistence end to end: store, forget everything, resolve again.
    func testAStoredBookmarkIsFoundAgainByAFreshLocator() throws {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("could not make a scratch defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sidecar = directory.appendingPathComponent("cube.mac4dstem.h5")
        try Data("not really hdf5".utf8).write(to: sidecar)
        let cube = descriptor(path: directory.appendingPathComponent("cube.h5").path)

        let writer = SessionSidecarLocator(defaults: defaults)
        try writer.remember(sidecar, for: cube)

        // A different instance, as after a relaunch: nothing in memory, only the
        // store. This is what fails the moment the key changes.
        let reader = SessionSidecarLocator(defaults: defaults)
        XCTAssertEqual(reader.grant(for: cube)?.standardizedFileURL, sidecar.standardizedFileURL,
                       "a remembered sidecar must be found again from the store alone — "
                       + "when this breaks, every saved session silently stops being reachable, "
                       + "which is exactly what the bundle-identifier change did")
        XCTAssertEqual(reader.location(for: cube).standardizedFileURL, sidecar.standardizedFileURL)

        // AND THE KEY ITSELF, spelled out here rather than asked of the code.
        // The round-trip above uses the same type on both sides, so it agrees
        // with ANY consistent key — including a changed one. Gate D reintroduced
        // C10 by editing that one string and this test stayed green until this
        // assertion existed. It is the L3 transpose lesson in miniature: a
        // self-consistent check cannot see a change both sides share.
        let expected = "session-sidecar-bookmark." + Data(cube.filePath.utf8).base64EncodedString()
        XCTAssertNotNil(defaults.data(forKey: expected),
                        "the bookmark must be stored under the documented key — this exact string "
                        + "is what was read out of the old container's plist to establish C10, so "
                        + "changing it silently orphans every saved session AND invalidates the "
                        + "evidence trail. Keys present: \(defaults.dictionaryRepresentation().keys.sorted())")
    }

    /// **The wiring, not just the decision.** Gate D reverted
    /// `AppState.recordedLoadSpecification`'s URL derivation to the pre-S1 form
    /// — the literal defect S1 exists to fix — and all ten tests stayed green,
    /// because every one of them addressed the locator and none addressed the
    /// call site.
    ///
    /// This pins the call site's URL CHOICE without ever completing a read. A
    /// grant is adopted pointing somewhere that does not exist, while a file
    /// does sit at the derived sibling path. The fixed code honours the grant,
    /// finds nothing there and returns quietly. Code that ignores the grant —
    /// the pre-S1 defect — reaches the derived file instead and tries to open
    /// it, which does not return quietly.
    ///
    /// **Why the assertion is "no reason recorded" rather than a read result:**
    /// driving a real HDF5 open from this target is not available. The bundled
    /// `libhdf5` **crashes the unsigned test host** on a malformed file — seen
    /// while writing this test, XCTest relaunching mid-suite to continue — which
    /// is consistent with the `Threadsafety: OFF` / `EXC_BAD_ACCESS` fragility
    /// already recorded in `docs/open-items.md`. So the green path here is
    /// deliberately one that never calls into HDF5 at all.
    func testRecordedLoadSpecificationAsksTheLocatorWhereTheSidecarIs() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("cube.h5")
        // A file at the DERIVED path — what the pre-S1 code would have opened.
        try Data("not an HDF5 file at all".utf8).write(
            to: directory.appendingPathComponent("cube.mac4dstem.h5")
        )
        let cube = descriptor(path: source.path)

        let state = AppState()
        // The grant says the sidecar is somewhere else, and that somewhere is empty.
        state.sessionSidecar.adopt(
            directory.appendingPathComponent("moved-away.h5"), for: cube
        )

        let recorded = await state.recordedLoadSpecification(
            forSourcePath: source.path, source: cube
        )

        XCTAssertNil(recorded, "there is no readable session at the granted location")
        XCTAssertNil(state.sessionSidecar.unreadableReason,
                     "and nothing was reported, because nothing was there to fail on — "
                     + "if this records a reason, the call site read the DERIVED sibling "
                     + "instead of the granted location, which is the defect S1 fixed")
    }

    func testASidecarThatIsAbsentIsNotReportedAsAProblem() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("cube.h5")

        let state = AppState()
        let recorded = await state.recordedLoadSpecification(
            forSourcePath: source.path, source: descriptor(path: source.path)
        )

        XCTAssertNil(recorded)
        XCTAssertNil(state.sessionSidecar.unreadableReason,
                     "no sidecar is the ordinary case; warning about it would train the user "
                     + "to ignore the warning that matters")
    }

    func testACorruptSidecarIsNotReportedAsASandboxDenial() {
        let corrupt = "HDF5 failed while opening the session sidecar — HDF5 reported: "
            + "file signature not found"
        XCTAssertEqual(SessionSidecarReadFailure.classify(SimpleError(corrupt)), .unreadable)
    }
}
