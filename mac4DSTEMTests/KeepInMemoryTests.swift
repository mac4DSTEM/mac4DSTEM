import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane K2 (owner 2026-10-01): the per-open "Keep in memory" switch.
@MainActor
final class KeepInMemoryTests: XCTestCase {

    private let GB: UInt64 = 1 << 30

    private func decide(_ cube: UInt64, limit: UInt64 = 40, ram: UInt64 = 64,
                        buffer: UInt64 = 1000) -> KeepInMemoryDecision {
        KeepInMemoryDecision.decide(
            cubeBytes: Int(cube * GB), limitBytes: limit * GB,
            maxBufferBytes: buffer * GB, physicalMemory: ram * GB)
    }

    /// Mutation: refuse threshold compared with `>=` or against RAM instead of the limit.
    func testRefusedOnlyAboveTheGPUWorkingSetLimit() {
        XCTAssertEqual(decide(41), .refused)
        XCTAssertNotEqual(decide(40), .refused, "at the limit is still allowed")
        XCTAssertNotEqual(decide(39), .refused)
    }

    /// Mutation: warn fraction 0.5 changed, or warn applied to refused/fits.
    func testWarnsAboveHalfOfPhysicalMemoryOnly() {
        XCTAssertEqual(decide(33), .warn)
        XCTAssertEqual(decide(32), .fits, "exactly half does not warn")
        XCTAssertEqual(decide(10), .fits)
    }

    /// Mutation: dropping the maxBufferLength term (UI and shouldAdmit could disagree).
    func testOneMetalBufferIsAHardCeilingToo() {
        XCTAssertEqual(decide(20, buffer: 16), .refused)
    }

    func testDefaultsOffOnEveryOpen() async throws {
        let reader = DemoFourDDataSource()
        let descriptor = try await reader.discoverPrimaryDataset()
        let pending = PendingLoad(
            source: descriptor, reader: reader,
            url: URL(fileURLWithPath: descriptor.filePath),
            accessedSecurityScope: false, fileByteCount: nil)
        XCTAssertFalse(pending.keepInMemory)
        XCTAssertFalse(pending.effectiveKeepInMemory)
        pending.keepInMemory = true
        // The demo cube is tiny: allowed, so the flag takes effect.
        XCTAssertTrue(pending.effectiveKeepInMemory)
    }

    /// Mutation: `activate` ignoring `keepInMemory` (never requesting `.resident`).
    func testActivateWithTheSwitchOnLeavesTheCubeResidentAndOffStreams() async throws {
        let reader = DemoFourDDataSource()
        let descriptor = try await reader.discoverPrimaryDataset()
        let on = AppState()
        await on.activate(descriptor: descriptor, reader: reader,
                          runInitialAnalysis: false, keepInMemory: true)
        XCTAssertEqual(on.residency.mode, .resident)
        XCTAssertTrue(on.residency.isResident)

        let off = AppState()
        await off.activate(descriptor: descriptor, reader: DemoFourDDataSource(),
                           runInitialAnalysis: false)
        XCTAssertEqual(off.residency.mode, .streamed)
        XCTAssertFalse(off.residency.isResident)
    }
}
