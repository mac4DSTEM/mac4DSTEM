//
//  CIFModelImport.swift
//  Role: A CIF file becomes a `CrystalModel`. The reading is DiffractoKit's (`CIFImport.read`: tokenizer, symmetry
//        expansion, the Laue class DETECTED from the atoms); what stays here is what only the app has: the model id
//        (`imported_<sanitised base>`), the elements the electron scattering table covers, the mapping of the Laue
//        class to the orientation reduction ACOM implements (`ACOMCrystalSymmetry.reduction(for:)`), and the model
//        contract (`CrystalModel.validationIssues`).
//
//  Named `CIFModelImport` (it was `CIFImport` until 2026-10-15) because the kit's reader is `CIFImport` too and the
//  two collide in any file that imports both.
//
//  Per ROADMAP Priority 1 item 3, a new phase is only admitted through the generic model contract with an explicit
//  lattice, atomic basis, symmetry reduction, and structure factors. A structure whose Laue class is not one ACOM
//  reduces (every class but m-3m, 6/mmm and 2/m with b unique) is admitted as `.identity` ("Unreduced") rather than
//  coerced onto `.cubic`, which would fabricate an IPF colour key and a fundamental-zone sampling that do not
//  correspond to the actual crystal; `CrystalModel.supportsOrientationMapping` says what it cannot do. Since the kit
//  switch (2026-10-15) a trigonal structure in hexagonal axes, a Laue class 6/m or m-3 structure, or a tetragonal one
//  with an accidentally cubic metric is no longer REFUSED at import: it imports as `.identity`.
//
//  Errors are user-facing: every case names the offending tag, value, or symbol so a scientist can find and fix the
//  problem in their own file.
//

import Foundation
import DiffractoCore
import DiffractoScattering

package nonisolated enum CIFModelImportError: LocalizedError, Equatable {
    /// The kit's reader refused the file; its message names the tag, value or symbol.
    case cif(CIFImportError)
    /// The element resolved, but has no electron scattering-factor parameters (`ElectronScatteringFactors`, Z = 1 to
    /// 103), so kinematic structure factors cannot be computed for it.
    case unsupportedElement(symbol: String, z: Int)
    /// The assembled model failed `CrystalModel.validationIssues` for a reason not already surfaced more specifically.
    case invalidModel([String])

    package var errorDescription: String? {
        switch self {
        case .cif(let error):
            return error.description
        case .unsupportedElement(let symbol, let z):
            return "Element \(symbol) (Z=\(z)) has no electron scattering-factor parameters; ACOM cannot use it."
        case .invalidModel(let issues):
            return "Imported crystal model failed validation: \(issues.joined(separator: "; "))."
        }
    }
}

package nonisolated enum CIFModelImport {

    /// Parse `cifText` and build a validated, `.imported` `CrystalModel`. `fileBaseName` (typically the source
    /// filename without extension) builds the stable model id and is the display-name fallback when the CIF's own
    /// `data_` block name is empty or an editor's placeholder (`CIFImport.displayName`).
    package static func crystalModel(from cifText: String, fileBaseName: String) throws -> CrystalModel {
        let document: CIFDocument
        do {
            document = try CIFImport.read(cifText, fileBaseName: fileBaseName)
        } catch {
            throw CIFModelImportError.cif(error)
        }
        let structure = document.structure
        // The scattering-factor gate the built-in and custom editors rely on: the kit names 118 elements, the
        // table covers 103. Z ascending, so the first is the lowest, as before.
        if let firstUnsupportedZ = structure.unsupportedElements.first {
            let symbol = Element.symbol(forAtomicNumber: firstUnsupportedZ) ?? "Z\(firstUnsupportedZ)"
            throw CIFModelImportError.unsupportedElement(symbol: symbol, z: firstUnsupportedZ)
        }

        let model = CrystalModel(
            id: "imported_\(sanitize(fileBaseName))",
            displayName: document.displayName,
            structure: structure,
            symmetry: ACOMCrystalSymmetry.reduction(for: structure),
            source: .imported,
            spaceGroupNumber: document.declaredSpaceGroupNumber
        )
        let issues = model.validationIssues
        guard issues.isEmpty else {
            throw CIFModelImportError.invalidModel(issues.map(\.message))
        }
        return model
    }

    private static func sanitize(_ name: String) -> String {
        let mapped = name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        let result = String(mapped)
        return result.isEmpty ? "cif" : result
    }
}
