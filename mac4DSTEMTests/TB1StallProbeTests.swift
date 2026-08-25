//
//  TB1StallProbeTests.swift
//  Gate D probes for the two TB1 findings of 2026-08-25 (sitting 1 + 2):
//  the configurator previews that never draw (status frozen at
//  "Sampling a preview · row 33 of 34") and the open that never returns
//  from "Checking for a saved session…". Driven against the REAL files the
//  owner drove, so a pass here and a failure on screen is itself a finding.
//

import XCTest
@testable import mac4DSTEM

@MainActor
final class TB1StallProbeTests: XCTestCase {

    private let datasetDirectory = URL(
        fileURLWithPath: "/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/training_dataset"
    )

    private func requireFile(_ name: String) throws -> URL {
        let url = datasetDirectory.appendingPathComponent(name)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "\(name) is machine-local and absent here")
        return url
    }

    /// Sitting 1: Open with Options… on sim_Au produced blank real-space and
    /// max panes. The dialog was interactive, so the sampler RETURNED —
    /// meaning `try? await DatasetPreviewBuilder.make` swallowed a thrown
    /// error. This drives the same path and asserts the preview exists.
    func testConfiguratorPreviewBuildsForSimAu() async throws {
        let url = try requireFile("sim_Au_data_all_binned.h5")
        let state = AppState()
        state.openFileForConfiguration(url: url)
        let deadline = Date().addingTimeInterval(120)
        while state.pendingLoad == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let pending = try XCTUnwrap(state.pendingLoad, "The configurator never appeared")
        if pending.preview == nil {
            // Reproduced. Re-run the builder WITHOUT the try? so the real
            // error becomes the test message — the whole point of the probe.
            do {
                _ = try await DatasetPreviewBuilder.make(
                    data: pending.data, descriptor: pending.source,
                    cancellation: nil, progress: { _ in }
                )
                XCTFail("preview was nil from the app path but a direct build succeeded — timing/cancellation, not a thrown error")
            } catch {
                XCTFail("REPRODUCED — the sampler throws and the app swallows it: \(error)")
            }
        }
        XCTAssertNotNil(pending.preview)
        // The docs' "full 0→1 spread" claim, pinned reproducibly: the
        // display images behind the panes must carry contrast — a data-side
        // regression must not be able to masquerade as the (separate,
        // rendering-layer) flat-panes finding.
        let real = try XCTUnwrap(pending.realSpaceDisplay)
        let maxDP = try XCTUnwrap(pending.maxDPDisplay)
        func spread(_ pixels: [Float]) -> Float { (pixels.max() ?? 0) - (pixels.min() ?? 0) }
        XCTAssertGreaterThan(spread(real.pixels), 0.5,
                             "The real-space display image is (near-)flat")
        XCTAssertGreaterThan(spread(maxDP.pixels), 0.5,
                             "The max-DP display image is (near-)flat")
    }

    /// Sitting 2: opening a cube beside the staged sidecar froze at
    /// "Checking for a saved session…" for minutes. Same open, timed.
    func testOpeningWS2BesideItsSidecarCompletes() async throws {
        let url = try requireFile("polycrystal_2D_WS2.h5")
        _ = try requireFile("polycrystal_2D_WS2.mac4dstem.h5")
        let state = AppState()
        state.openFile(url: url)
        let deadline = Date().addingTimeInterval(180)
        var lastStatus = ""
        while Date() < deadline {
            lastStatus = state.statusText
            if state.hasDataset, !state.isLoadingDataset { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertTrue(state.hasDataset && !state.isLoadingDataset,
                      "Open did not complete in 180 s — last status: \(lastStatus)")
        // The staged sidecar records a 200×200 crop WS₂ cannot fit: the
        // does-not-fit gate must be armed, and the open must still finish.
        XCTAssertEqual(state.gates.sidecarRestoreFailure?.kind, .doesNotFit,
                       "The staged fixture should arm the rewrite gate")
    }
}

@MainActor
final class BookmarkResolutionLatencyTests: XCTestCase {

    /// Resolving a bookmark must never hang the caller on a mount attempt.
    /// Measured 2026-08-25 (Gate D, TB1 sitting-2 stall): WITHOUT
    /// `.withoutMounting`, resolving this machine's own recents bookmark for
    /// an unmounted NAS volume blocked for 30.03 s — on the main actor,
    /// where every production caller runs. This drives the REAL persisted
    /// recents (skip when none): every stored bookmark, reachable or not,
    /// must resolve or refuse within seconds, not block on the network.
    func testEveryStoredRecentsBookmarkResolvesOrRefusesFast() throws {
        let state = AppState()
        try XCTSkipUnless(!state.recents.entries.isEmpty,
                          "No persisted recents on this machine")
        for entry in state.recents.entries {
            let started = Date()
            _ = try? WorkspaceRecoveryStore.resolve(entry.bookmark)
            let elapsed = Date().timeIntervalSince(started)
            XCTAssertLessThan(elapsed, 5.0,
                "Resolving the bookmark for \(entry.id) took \(elapsed)s — a mount attempt is blocking the main actor again")
        }
    }

    /// The catch-split (Gate D second reader, 2026-08-25): a recents entry
    /// whose volume is merely UNMOUNTED must survive a click — pre-split,
    /// `openRecent` deleted it (destroying the only place the NAS path is
    /// shown) and told the user to "renew permission", a remedy that cannot
    /// work for an absent volume. Machine-local: needs a real stored entry
    /// on an unmounted volume; skips elsewhere. The teardown re-adds the
    /// entry if a regression removed it, so a mutated run cannot destroy
    /// the owner's real recents.
    func testClickingARecentOnAnUnmountedVolumeKeepsTheEntry() async throws {
        let state = AppState()
        let candidates = state.recents.entries.filter {
            WorkspaceRecoveryStore.unmountedVolumeName(forBookmark: $0.bookmark) != nil
        }
        try XCTSkipUnless(!candidates.isEmpty,
                          "No recents entry on an unmounted volume on this machine")
        let entry = candidates[0]
        addTeardownBlock { @MainActor in
            if state.recents.entry(withID: entry.id) == nil {
                state.recents.remember(entry)
            }
        }
        state.openRecent(entry)
        XCTAssertNotNil(state.recents.entry(withID: entry.id),
                        "An unmounted volume must not cost the user the entry")
        XCTAssertTrue(state.errorMessage?.contains("not mounted") == true,
                      "The message must name the true condition: \(state.errorMessage ?? "nil")")
        XCTAssertFalse(state.errorMessage?.contains("renew permission") == true,
                       "The permission remedy is wrong for an absent volume")
    }
}

