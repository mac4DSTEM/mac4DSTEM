//
//  RingShellsDoubleDiffractionTests.swift
//  Calibrate Q from crystal gives the kit the forbidden shells double diffraction reaches, as match-only candidates (#274): diamond
//  Si along [110] shows {002}, and without it the ring sequence {111}, {002}, {220} was read from another first shell. Along [001]
//  the assignment is what it was, and fcc and bcc have no such shell.
//

import XCTest
import DSTEMCore

final class RingShellsDoubleDiffractionTests: XCTestCase {
    private func ring(_ id: String) throws -> (shells: [Double], labels: [String], doubleDiffraction: [Double]) {
        let model = try XCTUnwrap(CrystalModelLibrary.model(id: id))
        return KnownCrystalQCalibration.ringShells(try model.structure.kinematicReflections(kMax: 2.5))
    }

    /// Rings at these |g| (Å⁻¹) and 0.0205 Å⁻¹ per pixel, four equivalents each, on 200 positions.
    private func positions(_ g: [Double]) -> [[Double]] {
        (0..<200).map { p in
            var radii: [Double] = []
            for r in g.map({ $0 / 0.0205 }) { for e in 0..<4 { radii.append(r * (1 + 0.002 * Double((p + e) % 5 - 2))) } }
            return radii
        }
    }

    private func label(_ outcome: ShellAssignment.Outcome?) -> String? {
        if case .assigned(let a)? = outcome { return a.label }
        return nil
    }

    func testDiamondHasTheDoubleDiffractionShellsAndFCCAndBCCNone() throws {
        let si = try ring("si_diamond")
        let a = 5.4309
        XCTAssertEqual(Array(si.labels.prefix(4)), ["{111}", "{220}", "{311}", "{400}"], "the kept shells are unchanged")
        XCTAssertEqual(Array(si.doubleDiffraction.prefix(3)), [4.0, 12.0, 20.0].map { $0.squareRoot() / a }, accuracy: 1e-4)
        for id in ["al_fcc", "au_fcc", "fe_bcc"] { XCTAssertEqual(try ring(id).doubleDiffraction, [], id) }
    }

    /// Si [110]: {111}, {002} (1 % above its kinematic radius, as measured on the Si-SiGe scan) and {220}. Mutation: the kit called
    /// without the double-diffraction shells (the app before #274) - not {111}, red.
    func testDiamond110IsAssignedToItsFirstShell() throws {
        let si = try ring("si_diamond")
        let radii = positions([si.shells[0], 1.01 * si.doubleDiffraction[0], si.shells[1]])
        XCTAssertNotEqual(label(ShellAssignment.assign(radiiPerPosition: radii, shellLengths: si.shells, labels: si.labels)), "{111}",
                          "without the forbidden shells the sequence starts elsewhere (the bug)")
        XCTAssertEqual(label(ShellAssignment.assign(radiiPerPosition: radii, shellLengths: si.shells, labels: si.labels,
                                                    doubleDiffractionShells: si.doubleDiffraction)), "{111}")
    }

    /// Si [001]: {220}, {400}, {440} keep their assignment.
    func testDiamond001IsUnchanged() throws {
        let si = try ring("si_diamond")
        let radii = positions([si.shells[1], si.shells[3], si.shells[7]])
        let plain = label(ShellAssignment.assign(radiiPerPosition: radii, shellLengths: si.shells, labels: si.labels))
        XCTAssertEqual(plain, "{220}")
        XCTAssertEqual(label(ShellAssignment.assign(radiiPerPosition: radii, shellLengths: si.shells, labels: si.labels,
                                                    doubleDiffractionShells: si.doubleDiffraction)), plain)
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
