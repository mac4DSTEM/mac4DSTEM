//
//  SpectroscopyRealDataTests.swift
//  Role: the Spectroscopy room on the owner's real Velox EDX files, headless: how long the open, the first sums, Auto ID on open, a region and
//        the Quantify verb take, which elements Auto ID picks and what Quantify gives. A report, not a gate on numbers: the files have no truth
//        beyond what the owner says is in them.
//  Gate:  heavy, the owner's data (`$MACEM_DATA`, default ../data, read-only, never copied): skipped unless MAC4DSTEM_EDX_REAL=1. Run with
//        `../tools/memcap.sh --gb 8 -- env TEST_RUNNER_MAC4DSTEM_EDX_REAL=1 MAC4DSTEM_UNIT_ONLY=SpectroscopyRealDataTests tools/run-tests.sh unit`.
//        The files default to the two Velox SI under data/stem-edx that are not the 1.7 GB one; TEST_RUNNER_MAC4DSTEM_EDX_FILES (names, comma
//        separated) overrides them.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM
@testable import SpectroCore
@testable import SpectroEDX

@MainActor
final class SpectroscopyRealDataTests: XCTestCase {
    private static var data: URL {
        let org = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return (ProcessInfo.processInfo.environment["MACEM_DATA"].map { URL(fileURLWithPath: $0) } ?? org.appendingPathComponent("data"))
            .appendingPathComponent("stem-edx")
    }

    private func seconds(since t: Date) -> String { String(format: "%.1f s", Date().timeIntervalSince(t)) }

    private func waitFor(_ what: String, timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { print("EDX-REAL timed out waiting for \(what)"); return false }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return true
    }

    func testTheRealVeloxFilesOpenIdentifyAndQuantify() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MAC4DSTEM_EDX_REAL"] == "1", "heavy real-data run: set MAC4DSTEM_EDX_REAL=1 (command in this file's header)")
        let names = ProcessInfo.processInfo.environment["MAC4DSTEM_EDX_FILES"]?.split(separator: ",").map(String.init)
            ?? ["SI HAADF 1339 65000 x 20260508.emd", "SI HAADF 1840 23000 x 20260506.emd"]
        for name in names {
            let url = Self.data.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { print("EDX-REAL \(name): not found"); continue }
            let state = AppState()
            var t = Date()
            await state.openFileAsync(url: url)
            let opened = seconds(since: t)
            XCTAssertTrue(state.hasSpectrumImage, "\(name) opens as a spectrum image")
            guard let meta = state.spectroscopy.metadata, let c = Optional(state.spectroscopyRoom) else { continue }
            let m = c.model
            print("EDX-REAL \(name): open \(opened); \(meta.scanWidth) x \(meta.scanHeight) px, \(meta.channelCount) channels, \(meta.energyDispersionEV) eV/ch, offset \(meta.energyOffsetEV) eV, beam \(meta.beamEnergyKeV.map { "\($0) keV" } ?? "none"), pixel \(meta.scanPixelSize.map { "\($0)" } ?? "?") \(meta.scanPixelUnit ?? "")")
            t = Date()
            _ = await waitFor("the first spectrum", timeout: 120) { m.series.data.reduce(0, +) > 0 }
            print("EDX-REAL \(name): first spectrum \(seconds(since: t)) after the open, \(Int(m.series.data.reduce(0, +))) counts")
            t = Date()
            _ = await waitFor("Auto ID", timeout: 180) { !m.autoID.running && (m.autoID.outcome != nil || m.autoID.failure != nil) }
            let picks = m.elements.activeZ.map { PeriodicLayout.symbol($0) }
            print("EDX-REAL \(name): Auto ID \(seconds(since: t)); picks \(picks.joined(separator: " ")); failure \(m.autoID.failure ?? "none")")
            if let o = m.autoID.outcome {
                for s in o.suggestions { print("EDX-REAL   suggestion \(PeriodicLayout.symbol(s.z))") }
                for n in o.notes { print("EDX-REAL   note \(n)") }
            }
            // A region: the central quarter of the scan.
            t = Date()
            let nx = meta.scanWidth, ny = meta.scanHeight
            c.editRegion(.rectangle(PixelRect(x0: nx / 4, y0: ny / 4, x1: 3 * nx / 4, y1: 3 * ny / 4)), final: true)
            let before = m.series.data.reduce(0, +)
            _ = await waitFor("the region's sum", timeout: 60) { let s = m.series.data.reduce(0, +); return s > 0 && s != before }
            print("EDX-REAL \(name): region sum \(seconds(since: t)), \(Int(m.series.data.reduce(0, +))) counts")
            t = Date()
            let fitted = await c.quantify()
            print("EDX-REAL \(name): Quantify \(seconds(since: t)) fitted \(fitted); failure \(m.fitFailure ?? "none")")
            for r in m.results {
                print(String(format: "EDX-REAL   %@  net %.0f ± %.0f  %.2f at%%  %.2f wt%%  %@", PeriodicLayout.symbol(r.z), r.netCounts, r.netSigma, r.atPercent, r.wtPercent, r.failure ?? ""))
            }
            // The owner's expectation for these two files is Al, Mg and Si mainly: list Mg and Si by hand and fit again.
            if !m.elements.activeZ.contains(12) || !m.elements.activeZ.contains(14) {
                m.elements.set(12, .quantify); m.elements.set(14, .quantify)
                c.elementsChanged()
                t = Date()
                let again = await c.quantify()
                print("EDX-REAL \(name): with Mg and Si listed, Quantify \(seconds(since: t)) fitted \(again); failure \(m.fitFailure ?? "none")")
                for r in m.results {
                    print(String(format: "EDX-REAL   %@  net %.0f ± %.0f  %.2f at%%  %.2f wt%%  %@", PeriodicLayout.symbol(r.z), r.netCounts, r.netSigma, r.atPercent, r.wtPercent, r.failure ?? ""))
                }
            }
        }
    }
}
