//
//  ProbeRadiusEntryTests.swift
//  Role: the typed probe radius of Bragg Disks › Probe kernel (mac4DSTEM#114): which numbers it accepts, and that a typed
//        radius becomes the synthetic kernel's (Thronsen et al.'s recipe builds at 2 px; before the field only Calibrate
//        Origin or the ring hint could set the radius).
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class ProbeRadiusEntryTests: XCTestCase {
    private let descriptor = DatasetDescriptor(filePath: "/synthetic/probe.h5", datasetPath: "/d", shape: [4, 4, 128, 128],
                                               dtypeDescription: "float32", chunkShape: nil)

    /// Mutation: accepting 0, a negative, NaN or a radius wider than half the detector -> red.
    func testOnlyAPositiveRadiusThatFitsTheDetectorIsAccepted() {
        XCTAssertEqual(ProbeRadiusEntry.radius(typed: 2, descriptor: descriptor), 2)
        XCTAssertEqual(ProbeRadiusEntry.radius(typed: 64, descriptor: descriptor), 64)
        XCTAssertNil(ProbeRadiusEntry.radius(typed: 64.5, descriptor: descriptor))
        XCTAssertNil(ProbeRadiusEntry.radius(typed: 0, descriptor: descriptor))
        XCTAssertNil(ProbeRadiusEntry.radius(typed: -1, descriptor: descriptor))
        XCTAssertNil(ProbeRadiusEntry.radius(typed: .nan, descriptor: descriptor))
        XCTAssertEqual(ProbeRadiusEntry.radius(typed: 2.5, descriptor: nil), 2.5)
    }

    /// A typed radius replaces the measured one as a manual value and rebuilds the synthetic kernel at it.
    /// Mutation: the field's commit not reaching `useProbeRadius`, or the rebuild keeping the old radius -> red.
    @MainActor
    func testATypedRadiusRebuildsTheSyntheticKernelAtIt() async throws {
        let state = AppState()
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        await state.openDemoFixture(specification: spec)
        await state.generateProbeKernel()
        let measured = try XCTUnwrap(state.probeKernel?.probeRadius)
        let typed = try XCTUnwrap(ProbeRadiusEntry.radius(typed: 2, descriptor: state.descriptor))
        XCTAssertNotEqual(measured, typed, "precondition: the demo's measured radius is not 2 px")
        await state.useProbeRadius(typed)
        XCTAssertEqual(state.calibrationSession.calibration.probeRadius, 2)
        XCTAssertEqual(state.calibrationSession.provenance.probe, .manual)
        XCTAssertEqual(state.probeKernel?.probeRadius, 2)
        XCTAssertEqual(state.probeKernel?.source, .synthetic)
    }
}
