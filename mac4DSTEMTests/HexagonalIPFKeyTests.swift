//
//  HexagonalIPFKeyTests.swift
//  Pins the labelling of the hexagonal 6/mmm IPF key (Gate D, 2026-09-30;
//  open-items "Hexagonal IPF key may be labelled the wrong way round").
//
//  The crystal frame is py4DSTEM's: `Crystal.latReal` puts a along +x and b at
//  gamma = 120 deg, so Cartesian azimuth 0 is the a-axis [2-1-10] (equivalent
//  to [11-20] under 6/mmm) and azimuth 30 deg is [10-10]. The tests derive
//  each label's Cartesian direction from the real lattice, never from the key
//  table itself, so a swapped pair of labels cannot pass by symmetry.
//

import XCTest
import DSTEMCore
import DSTEMSession
import simd
@testable import mac4DSTEM

final class HexagonalIPFKeyTests: XCTestCase {

    private let hexagonal = Crystal(
        a: 3.209, b: 3.209, c: 5.211, alphaDeg: 90, betaDeg: 90, gammaDeg: 120,
        sites: [AtomSite(z: 12, fractional: SIMD3(0, 0, 0))])

    /// Cartesian direction of a Miller-Bravais [uvtw] direction:
    /// three-index [U V W] = [u - t, v - t, w], then `latReal`.
    private func cartesian(fourIndex label: String) throws -> SIMD3<Double> {
        // "2-1-10" -> [2, -1, -1, 0]; "10-10" -> [1, 0, -1, 0]; "0001" -> [0, 0, 0, 1].
        var indices: [Int] = []
        var sign = 1
        for character in label {
            if character == "-" { sign = -1; continue }
            indices.append(sign * Int(String(character))!)
            sign = 1
        }
        XCTAssertEqual(indices.count, 4, "\(label) is not a four-index direction")
        let uvw = SIMD3<Int>(indices[0] - indices[2], indices[1] - indices[2], indices[3])
        return LatticeVector.direction(uvw).cartesian(in: hexagonal)
    }

    private func azimuthDegrees(_ v: SIMD3<Double>) -> Double {
        atan2(v.y, v.x) * 180 / .pi
    }

    /// Pins the frame the labels are written against: a along +x, so [2-1-10]
    /// is azimuth 0 and [10-10] is azimuth 30 deg. If `Crystal` ever rotates
    /// the basal plane this fails before any label can silently go stale.
    func testPrismaticDirectionsSitAtTheAzimuthsTheKeyAssumes() throws {
        XCTAssertEqual(azimuthDegrees(try cartesian(fourIndex: "2-1-10")), 0, accuracy: 1e-9)
        XCTAssertEqual(azimuthDegrees(try cartesian(fourIndex: "10-10")), 30, accuracy: 1e-9)
        XCTAssertEqual(azimuthDegrees(try cartesian(fourIndex: "11-20")), 60, accuracy: 1e-9)
        XCTAssertEqual(try cartesian(fourIndex: "0001").z / simd_length(try cartesian(fourIndex: "0001")), 1, accuracy: 1e-12)
    }

    /// Every corner's printed label must be the crystal direction that sits at
    /// that corner (up to 6/mmm equivalence, via the production fold), and the
    /// colour the key gives that direction must be the colour it prints.
    /// Mutation: swap the "10-10" and "11-20"/"2-1-10" labels in `keyCorners`
    /// (the pre-2026-09-30 state) - the second corner's label then resolves to
    /// azimuth 30 while its direction is azimuth 0, and this goes red.
    func testEachKeyCornerCarriesTheLabelOfItsOwnDirection() throws {
        let corners = HexagonalOrientationSymmetry.keyCorners
        XCTAssertEqual(corners.count, 3)
        for corner in corners {
            let labelled = try cartesian(fourIndex: corner.label)
            let folded = HexagonalOrientationSymmetry.reduceDirection(labelled)
            let cornerDirection = simd_normalize(corner.direction)
            XCTAssertLessThan(
                simd_length(folded - cornerDirection), 1e-9,
                "corner \(corner.label) sits at \(cornerDirection) but the label is direction \(folded)")
            let colour = HexagonalOrientationSymmetry.ipfColor(direction: labelled)
            XCTAssertLessThan(
                simd_length(colour - corner.color), 1e-6,
                "corner \(corner.label): ipfColor of its own direction is \(colour), the key prints \(corner.color)")
        }
        XCTAssertEqual(corners.map(\.color), [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)],
                       "the key is red / green / blue in corner order")
    }

    /// The two prismatic corners must not be the same direction under a
    /// different name: [10-10] and [2-1-10] are 30 deg apart, so they get
    /// different colours (green vs blue) - guards a test that resolves both
    /// through the fold and would pass a key with a repeated label.
    func testThePrismaticCornersHaveDistinctLabelsAndColours() {
        let corners = HexagonalOrientationSymmetry.keyCorners
        XCTAssertEqual(Set(corners.map(\.label)).count, 3)
        XCTAssertEqual(Set(corners.map { "\($0.color)" }).count, 3)
    }
}
