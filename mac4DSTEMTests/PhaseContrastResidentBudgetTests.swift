//
//  PhaseContrastResidentBudgetTests.swift
//  Lane MB (2026-10-01): the phase-contrast working limit is half of RAM less the cube the user keeps in memory.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class PhaseContrastResidentBudgetTests: XCTestCase {
    private let gib: UInt64 = 1_073_741_824

    func testAStreamedCubeLeavesTheLimitUnchanged() {
        XCTAssertEqual(PhaseContrastMemoryBudget.workingLimitBytes(physicalMemory: 64 * gib, residentCubeBytes: 0), Int(32 * gib))
        XCTAssertEqual(PhaseContrastMemoryBudget.workingLimitBytes(physicalMemory: 64 * gib),
                       PhaseContrastMemoryBudget.workingLimitBytes(physicalMemory: 64 * gib, residentCubeBytes: 0))
    }

    func testAResidentCubeIsSubtractedFromHalfOfRAM() {
        XCTAssertEqual(PhaseContrastMemoryBudget.workingLimitBytes(physicalMemory: 64 * gib, residentCubeBytes: Int(20 * gib)),
                       Int(12 * gib))
    }

    func testAResidentCubeAtOrAboveHalfFallsToTheFloor() {
        XCTAssertEqual(PhaseContrastMemoryBudget.workingLimitBytes(physicalMemory: 64 * gib, residentCubeBytes: Int(32 * gib)),
                       Int(gib))
        XCTAssertEqual(PhaseContrastMemoryBudget.workingLimitBytes(physicalMemory: 64 * gib, residentCubeBytes: Int(50 * gib)),
                       Int(gib))
    }

    func testTheRefusalNamesTheResidentCubeOnlyWhenThereIsOne() {
        let error = ParallaxAligner.AlignmentError.memoryLimit(bytes: 5_000_000_000, limit: 1_073_741_824)
        let plain = PhaseContrastMemoryBudget.refusalMessage(error, residentCubeBytes: 0)
        XCTAssertFalse(plain.contains("kept in memory"))
        let withCube = PhaseContrastMemoryBudget.refusalMessage(error, residentCubeBytes: 28_600_000_000)
        XCTAssertTrue(withCube.hasPrefix(plain))
        XCTAssertTrue(withCube.contains("half of RAM less the"), withCube)
        XCTAssertTrue(withCube.contains("cube kept in memory"), withCube)
        // Not a memory refusal: untouched.
        let other = ParallaxPreprocessor.PreprocessError.invalidData("x")
        XCTAssertEqual(PhaseContrastMemoryBudget.refusalMessage(other, residentCubeBytes: 28_600_000_000),
                       other.localizedDescription)
    }

    func testEveryStageRefusalIsRecognised() {
        XCTAssertTrue(PhaseContrastMemoryBudget.isMemoryRefusal(ParallaxPreprocessor.PreprocessError.stackTooLarge(bytes: 1, limit: 1)))
        XCTAssertTrue(PhaseContrastMemoryBudget.isMemoryRefusal(ParallaxAligner.AlignmentError.memoryLimit(bytes: 1, limit: 1)))
        XCTAssertTrue(PhaseContrastMemoryBudget.isMemoryRefusal(ParallaxSubpixelReconstructor.ReconstructionError.memoryLimit(bytes: 1, limit: 1)))
        XCTAssertTrue(PhaseContrastMemoryBudget.isMemoryRefusal(ParallaxDepthSectioner.DepthError.memoryLimit(bytes: 1, limit: 1)))
        XCTAssertTrue(PhaseContrastMemoryBudget.isMemoryRefusal(ParallaxAberrationCorrector.CorrectionError.memoryLimit(bytes: 1, limit: 1)))
        XCTAssertTrue(PhaseContrastMemoryBudget.isMemoryRefusal(SingleslicePtychography.ReconstructionError.memoryLimit(bytes: 1, limit: 1)))
    }
}
