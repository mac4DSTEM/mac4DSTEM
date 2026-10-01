//
//  MaterialsProjectImportRow6Tests.swift
//  Lane F-B row 6 (docs/archive/v4/review-2026-09-30-findings.md): the Materials Project
//  importer classified the family from the cell metric alone; the CIF importer's
//  `verifyFamily` (the atom-position check) never ran on MP data.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class MaterialsProjectImportRow6Tests: XCTestCase {

    private func document(
        lattice a: Double, c: Double, gamma: Double, sites: [[Double]], symbol: String, number: Int
    ) -> MaterialsProjectDocument {
        MaterialsProjectDocument(
            materialID: "mp-row6", formulaPretty: "X",
            structure: MaterialsProjectStructure(
                lattice: MaterialsProjectLattice(
                    a: a, b: a, c: c, alpha: 90, beta: 90, gamma: gamma,
                    matrix: [[a, 0, 0], [0, a, 0], [0, 0, c]]
                ),
                sites: sites.map {
                    MaterialsProjectSite(
                        species: [MaterialsProjectSpecies(element: "Fe", occu: 1.0)], abc: $0)
                }
            ),
            symmetry: MaterialsProjectSymmetry(crystalSystem: "x", symbol: symbol, number: number)
        )
    }

    /// Pa-3 (pyrite-type, Laue m-3): a cubic metric whose 4-fold axis is missing.
    func testRow6PyriteTypeCubicMetricButNoFourFoldIsRefused() {
        let u = 0.385
        let sites: [[Double]] = [
            [0, 0, 0], [0, 0.5, 0.5], [0.5, 0, 0.5], [0.5, 0.5, 0],
            [u, u, u], [-u + 0.5, -u, u + 0.5], [-u, u + 0.5, -u + 0.5], [u + 0.5, -u + 0.5, -u],
            [-u, -u, -u], [u + 0.5, u, -u + 0.5], [u, -u + 0.5, u + 0.5], [-u + 0.5, u + 0.5, u],
        ].map { $0.map { $0 - floor($0) } }
        let doc = document(lattice: 5.42, c: 5.42, gamma: 90, sites: sites, symbol: "Pa-3", number: 205)
        XCTAssertThrowsError(try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())) { error in
            guard case CIFImportError.symmetryNotSupportedByStructure(let family, _)? =
                error as? CIFImportError else {
                return XCTFail("expected symmetryNotSupportedByStructure, got \(error)")
            }
            XCTAssertEqual(family, "cubic")
        }
    }

    /// Control: genuine HCP (P6_3/mmc, Mg) still imports as hexagonal.
    func testRow6GenuineHexagonalStillImports() throws {
        let doc = document(
            lattice: 3.21, c: 5.21, gamma: 120,
            sites: [[1.0 / 3, 2.0 / 3, 0.25], [2.0 / 3, 1.0 / 3, 0.75]],
            symbol: "P6_3/mmc", number: 194)
        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())
        XCTAssertEqual(model.symmetry, .hexagonal)
    }
}
