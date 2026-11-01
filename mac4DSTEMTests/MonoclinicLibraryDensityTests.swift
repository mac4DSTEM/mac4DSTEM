//
//  MonoclinicLibraryDensityTests.swift
//  Item B2 (registration the archived notes):
//  a monoclinic phase's template library has 4x the quality preset's count; the Work row, the plan and
//  the duration estimate show it; every other symmetry is unchanged.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class MonoclinicLibraryDensityTests: XCTestCase {

    /// Mutation (multiplier 1x, or applied to every symmetry): red.
    func testMonoclinicLibraryIsFourTimesThePresetAndOthersAreUnchanged() {
        let expected: [(ACOMQualityPreset, Int, Int)] = [(.fast, 96, 384), (.balanced, 200, 800), (.best, 400, 1600)]
        for (preset, base, monoclinic) in expected {
            XCTAssertEqual(preset.templateCount, base)
            XCTAssertEqual(preset.templateCount(for: .monoclinic), monoclinic)
            for other in [ACOMCrystalSymmetry.cubic, .hexagonal, .identity] {
                XCTAssertEqual(preset.templateCount(for: other), base, "\(other)")
            }
        }
    }

    /// The estimate scales with the multiplied library: the CPU baseline (1,150 pos/s at 400 templates).
    func testDurationEstimateUsesTheMultipliedLibrary() throws {
        let session = ACOMSession()
        session.quality = .best
        XCTAssertEqual(try XCTUnwrap(session.estimatedDuration(forPositions: 1_150, symmetry: .cubic)), 1.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(session.estimatedDuration(forPositions: 1_150, symmetry: .monoclinic)), 4.0, accuracy: 1e-9)
        // A prior measurement is rescaled by the ratio of measured to current count, current count multiplied.
        session.lastPositionsPerSecond = 500
        session.lastMeasuredTemplateCount = 400
        session.lastMeasuredBackend = .cpu
        XCTAssertEqual(try XCTUnwrap(session.estimatedDuration(forPositions: 500, symmetry: .monoclinic)), 4.0, accuracy: 1e-9)
    }

    /// The Work row and the count the plan is built with come from one property.
    func testWorkRowAndPlanCountShowTheMultipliedLibrary() async throws {
        let state = AppState()
        state.descriptor = DatasetDescriptor(
            filePath: "/tmp/b2.h5", datasetPath: "/data",
            shape: [32, 32, 16, 16], dtypeDescription: "float32", chunkShape: nil)
        state.acomSession.quality = .balanced
        state.acomSession.modelSelection = .library("au_fcc")
        XCTAssertEqual(state.acomTemplateCount, 200)
        XCTAssertTrue(state.acomWorkSummary.hasSuffix("× 200 templates"), state.acomWorkSummary)
        let cubicEstimate = try XCTUnwrap(state.acomEstimatedDuration)
        XCTAssertGreaterThan(cubicEstimate, 0)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("b2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("bdp.cif")
        try MonoclinicOrientationTests.betaDoublePrimeCIF.write(to: url, atomically: true, encoding: .utf8)
        state.importCrystalModel(from: url)
        let model = try XCTUnwrap(state.acomSession.importedCrystalModels.first)
        XCTAssertEqual(model.symmetry, .monoclinic)
        state.acomSession.modelSelection = .imported(model.id)
        XCTAssertEqual(state.acomTemplateCount, 800)
        XCTAssertTrue(state.acomWorkSummary.hasSuffix("× 800 templates"), state.acomWorkSummary)
        XCTAssertEqual(try XCTUnwrap(state.acomEstimatedDuration), 4 * cubicEstimate, accuracy: 1e-9,
                       "the Work row's estimate shows the multiplied library")
        // The plan itself is built at the multiplied count (the same property feeds generateOrientationPlan).
        await state.generateOrientationPlan()
        XCTAssertEqual(state.acomSession.orientationPlan?.count, 800)
        XCTAssertEqual(state.acomSession.orientationPlan?.symmetry, .monoclinic)
        state.acomSession.quality = .best
        XCTAssertEqual(state.acomTemplateCount, 1600)
        XCTAssertTrue(state.acomWorkSummary.hasSuffix("× 1600 templates"), state.acomWorkSummary)
    }
}
