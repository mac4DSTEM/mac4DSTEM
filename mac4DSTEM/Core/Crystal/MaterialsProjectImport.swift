//
//  MaterialsProjectImport.swift
//  Role: the app's model assembly for the Materials Project (MP) importer. The `GET /materials/summary/` wire types, the
//        request, the decoding, the refusals, the conversion of a document to a structure (primitive to conventional cell
//        through `CellStandardisation`, species lists and disorder as one atom per species, the symmetry detected from the
//        atoms) and the check against the phase the user expected are DiffractoKit's `MaterialsProjectImport`
//        (DiffractoCore, 0.7.1). What stays here is what is the app's: the `CrystalModel` built from the kit's structure (the
//        orientation reduction `ACOMCrystalSymmetry.reduction(for:)`, the display name, the provenance, the model's own
//        validation), as an extension of the kit's namespace so a call site reads `MaterialsProjectImport.crystalModel(...)`.
//        The network fetch (`AppState+MaterialsProject`) and the key store stay in the app.
//
//        MP's own `symmetry.crystal_system` and `symbol` are recorded in provenance only, never used to choose
//        `ACOMCrystalSymmetry` (the kit uses them to standardise a centred cell and detects the symmetry from the atoms).
//
//        DEVIATION from the former app importer (DiffractoKit's `structure(from:)`): (1) a disordered site of a centred
//        primitive cell leaves one atom per species, species-major and then centring translation, where the app's adapter
//        kept the species of a site together; same atoms, positions and occupancies, a different order of
//        `structure.sites` (so `revisionID`, `atomic_basis` and `contentFingerprint` differ for that case only; a
//        conventional or an ordered cell is unchanged). (2) A centred cell with a site that has no coordinates is refused
//        naming the site ("Site 1 of mp-... has no usable fractional coordinates.") instead of the former unnamed message.
//        (3) Atoms carry the MP site label and the structure the material id as name; neither reaches the model's identity.
//

import Foundation
import DiffractoCore

extension MaterialsProjectImport {

    /// Build a validated `CrystalModel` from one fetched document.
    ///
    /// Structural absence (`structure`/`lattice`/`sites` missing, a site with no coordinates, no species, or an unrecognized
    /// element symbol) and a centred primitive cell that cannot be verified as convertible are the kit's refusals
    /// (`structure(from:)`). Everything else a *number* can get wrong — non-finite cell parameters, non-finite fractional
    /// coordinates, an occupancy out of (0, 1], an unsupported element's missing scattering factors, atoms too close
    /// together — is left to `CrystalModel.validationIssues`, the same gate every built-in, custom and CIF-imported model
    /// already passes through; any issue becomes `Failure.malformed`.
    package nonisolated static func crystalModel(from doc: MaterialsProjectDocument, fetchedAt: Date) throws -> CrystalModel {
        let imported = try structure(from: doc)
        let crystalStructure = imported.structure
        let symmetry = ACOMCrystalSymmetry.reduction(for: crystalStructure)

        let formulaLabel = doc.formulaPretty?.trimmingCharacters(in: .whitespaces)
        let displayName: String
        if let formulaLabel, !formulaLabel.isEmpty {
            displayName = "\(formulaLabel) (\(doc.materialID))"
        } else {
            displayName = doc.materialID
        }

        let cellProvenance: String
        switch imported.cell {
        case .asServed:
            cellProvenance = "as served"
        case .conventional(let centring):
            cellProvenance = "conventional from \(centring)-centred primitive"
        }
        var extraProvenance: [String: String] = [
            "materials_project_id": doc.materialID,
            "materials_project_fetched": isoFormatter.string(from: fetchedAt),
            "materials_project_cell": cellProvenance,
        ]
        if doc.deprecated == true {
            extraProvenance["materials_project_deprecated"] = "true"
        }
        if let symbol = doc.symmetry?.symbol {
            extraProvenance["materials_project_symbol"] = symbol
        }
        if let crystalSystem = doc.symmetry?.crystalSystem {
            extraProvenance["materials_project_crystal_system"] = crystalSystem
        }

        let model = CrystalModel(
            id: doc.materialID,
            displayName: displayName,
            structure: crystalStructure,
            symmetry: symmetry,
            source: .materialsProject,
            spaceGroupNumber: doc.symmetry?.number,
            extraProvenance: extraProvenance
        )
        let issues = model.validationIssues
        guard issues.isEmpty else {
            throw Failure.malformed(
                "\(doc.materialID) failed validation: \(issues.map(\.message).joined(separator: "; "))"
            )
        }
        return model
    }

    /// ISO-8601 UTC, fixed regardless of the caller's calendar/time zone — `materials_project_fetched` records when
    /// mac4DSTEM asked, not a locale-dependent rendering of it.
    private nonisolated static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
