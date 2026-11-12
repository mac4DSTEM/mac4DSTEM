//
//  PhaseSetupRecord.swift
//  Role: the phase-mapping setup as the session file carries it, so a reopened session gets its phase list and
//        settings back: every slot (structure identity, matrix flag, zone axis, orientation relationship, slab), the
//        reference and matching settings with their exact values, and the text of each imported CIF.
//
//  It rides on the `phase_mapping` lineage node as one more parameter (`lineageKey`), JSON. Additive and safe to
//  ignore: a build that does not know the key shows it as a parameter and restores what it restored before. A
//  session saved before this record carries none, and its phase setup is entered once more.
//
//  An imported CIF is not on disk where the app may read it again (the sandbox grants the file once), and a
//  `CrystalStructure` rebuilt from its cell and sites alone would not carry the symmetry operations the file gave.
//  So the CIF text itself is kept, and the structure is rebuilt by the importer that built it, then checked against
//  the recorded id and content fingerprint. A structure that cannot be rebuilt is refused by name.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import DiffractoOrientation

package nonisolated struct PhaseSetupRecord: Codable, Equatable, Sendable {

    /// The `phase_mapping` node parameter that carries the record.
    package static let lineageKey = "phase_setup"
    package static let currentVersion = 1
    /// Above this the CIF texts are left out (the lineage has a size cap of its own); those phases are then named as
    /// missing on reopen, as a phase from an older session is.
    package static let maximumJSONBytes = 512 * 1024

    /// What `CIFModelImport.crystalModel(from:fileBaseName:)` was given.
    package nonisolated struct CIFSource: Codable, Equatable, Sendable {
        package var text: String
        package var fileBaseName: String

        package init(text: String, fileBaseName: String) {
            self.text = text
            self.fileBaseName = fileBaseName
        }
    }

    package nonisolated struct Slot: Codable, Equatable, Sendable {
        package var modelID: String
        package var displayName: String
        /// `CrystalModelSource.rawValue`.
        package var source: String
        /// `CrystalModel.contentFingerprint`: the rebuilt structure must give the same.
        package var fingerprint: String
        package var isMatrix: Bool
        package var u: Int, v: Int, w: Int
        package var orientationRelationshipText: String
        package var excitationSlabInvAngstrom: Double?
        /// The imported CIF, when the session holds its text.
        package var cif: CIFSource?
    }

    /// `PhaseReferenceSettings`, field for field.
    package nonisolated struct Reference: Codable, Equatable, Sendable {
        package var kMaxInvAngstrom: Double
        package var excitationSlabInvAngstrom: Double
        package var excitationWidthInvAngstrom: Double
        package var minimumIntensityFraction: Double
        package var maximumVectorsPerEntry: Int
        package var inPlaneStepDeg: Double
        package var maximumEntries: Int

        package init(_ s: PhaseReferenceSettings) {
            kMaxInvAngstrom = s.kMaxInvAngstrom
            excitationSlabInvAngstrom = s.excitationSlabInvAngstrom
            excitationWidthInvAngstrom = s.excitationWidthInvAngstrom
            minimumIntensityFraction = s.minimumIntensityFraction
            maximumVectorsPerEntry = s.maximumVectorsPerEntry
            inPlaneStepDeg = s.inPlaneStepDeg
            maximumEntries = s.maximumEntries
        }

        package var settings: PhaseReferenceSettings {
            var s = PhaseReferenceSettings()
            s.kMaxInvAngstrom = kMaxInvAngstrom
            s.excitationSlabInvAngstrom = excitationSlabInvAngstrom
            s.excitationWidthInvAngstrom = excitationWidthInvAngstrom
            s.minimumIntensityFraction = minimumIntensityFraction
            s.maximumVectorsPerEntry = maximumVectorsPerEntry
            s.inPlaneStepDeg = inPlaneStepDeg
            s.maximumEntries = maximumEntries
            return s
        }
    }

    /// `PhaseVectorSettings`, field for field.
    package nonisolated struct Matching: Codable, Equatable, Sendable {
        package var directBeamRadiusInvAngstrom: Double
        package var maximumVectorInvAngstrom: Double
        package var matrixToleranceInvAngstrom: Double
        package var pairRadiusInvAngstrom: Double
        package var minimumVectors: Int
        package var minimumMatrixEvidence: Int
        package var matrixFallbackExplainedFraction: Double
        package var minimumMatchedVectors: Int
        package var friedelPairMinimumMatchedVectors: Int
        package var chanceMatchMultiple: Double
        package var notIndexedAboveInvAngstrom: Double
        package var minimumPhaseContrastInvAngstrom: Double
        package var orientationRelationshipToleranceDeg: Double
        package var completenessAwareCrossPhaseRanking: Bool
        /// `PhaseVectorSettings.ClassificationRule.rawValue`.
        package var classificationRule: String
        package var directMatrixMaximumVectors: Int
        package var residualCutoffInvAngstrom: Double
        package var knownVariantsMinimumSpecificReflections: Int

        package init(_ s: PhaseVectorSettings) {
            directBeamRadiusInvAngstrom = s.directBeamRadiusInvAngstrom
            maximumVectorInvAngstrom = s.maximumVectorInvAngstrom
            matrixToleranceInvAngstrom = s.matrixToleranceInvAngstrom
            pairRadiusInvAngstrom = s.pairRadiusInvAngstrom
            minimumVectors = s.minimumVectors
            minimumMatrixEvidence = s.minimumMatrixEvidence
            matrixFallbackExplainedFraction = s.matrixFallbackExplainedFraction
            minimumMatchedVectors = s.minimumMatchedVectors
            friedelPairMinimumMatchedVectors = s.friedelPairMinimumMatchedVectors
            chanceMatchMultiple = s.chanceMatchMultiple
            notIndexedAboveInvAngstrom = s.notIndexedAboveInvAngstrom
            minimumPhaseContrastInvAngstrom = s.minimumPhaseContrastInvAngstrom
            orientationRelationshipToleranceDeg = s.orientationRelationshipToleranceDeg
            completenessAwareCrossPhaseRanking = s.completenessAwareCrossPhaseRanking
            classificationRule = s.classificationRule.rawValue
            directMatrixMaximumVectors = s.directMatrixMaximumVectors
            residualCutoffInvAngstrom = s.residualCutoffInvAngstrom
            knownVariantsMinimumSpecificReflections = s.knownVariantsMinimumSpecificReflections
        }

        /// Nil when the classification rule is one this build does not know.
        package var settings: PhaseVectorSettings? {
            guard let rule = PhaseVectorSettings.ClassificationRule(rawValue: classificationRule) else { return nil }
            var s = PhaseVectorSettings()
            s.directBeamRadiusInvAngstrom = directBeamRadiusInvAngstrom
            s.maximumVectorInvAngstrom = maximumVectorInvAngstrom
            s.matrixToleranceInvAngstrom = matrixToleranceInvAngstrom
            s.pairRadiusInvAngstrom = pairRadiusInvAngstrom
            s.minimumVectors = minimumVectors
            s.minimumMatrixEvidence = minimumMatrixEvidence
            s.matrixFallbackExplainedFraction = matrixFallbackExplainedFraction
            s.minimumMatchedVectors = minimumMatchedVectors
            s.friedelPairMinimumMatchedVectors = friedelPairMinimumMatchedVectors
            s.chanceMatchMultiple = chanceMatchMultiple
            s.notIndexedAboveInvAngstrom = notIndexedAboveInvAngstrom
            s.minimumPhaseContrastInvAngstrom = minimumPhaseContrastInvAngstrom
            s.orientationRelationshipToleranceDeg = orientationRelationshipToleranceDeg
            s.completenessAwareCrossPhaseRanking = completenessAwareCrossPhaseRanking
            s.classificationRule = rule
            s.directMatrixMaximumVectors = directMatrixMaximumVectors
            s.residualCutoffInvAngstrom = residualCutoffInvAngstrom
            s.knownVariantsMinimumSpecificReflections = knownVariantsMinimumSpecificReflections
            return s
        }
    }

    package var version: Int
    package var slots: [Slot]
    package var reference: Reference
    package var matching: Matching
    /// Where the orientations come from (`PhaseOrientationSource`). Absent in a session saved before 5.3: typed zones.
    package var orientationSource: String?

    // MARK: Writing

    /// The JSON the lineage node carries. With the CIF texts it must stay under `maximumJSONBytes`; over it they are
    /// left out. Nil only when encoding fails.
    package var jsonString: String? {
        func encoded(_ record: PhaseSetupRecord) -> String? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(record)).map { String(decoding: $0, as: UTF8.self) }
        }
        guard let full = encoded(self) else { return nil }
        guard full.utf8.count > Self.maximumJSONBytes else { return full }
        return encoded(withoutCIFTexts)
    }

    /// The list and settings alone: what an older run keeps once a newer one carries the texts.
    package var withoutCIFTexts: PhaseSetupRecord {
        var slim = self
        for index in slim.slots.indices { slim.slots[index].cif = nil }
        return slim
    }

    /// Nil for text that is not a record of a version this build reads.
    package static func decoded(from json: String) -> PhaseSetupRecord? {
        guard let record = try? JSONDecoder().decode(PhaseSetupRecord.self, from: Data(json.utf8)),
              record.version == currentVersion else { return nil }
        return record
    }

    // MARK: Reading

    /// The phase list and settings a record gives back.
    package nonisolated struct Restored: Sendable {
        package var phases: [PhaseMappingSlot]
        package var reference: PhaseReferenceSettings
        package var matching: PhaseVectorSettings
        /// The models rebuilt from a CIF text, with that text: they join the session's imported models.
        package var imported: [(model: CrystalModel, cif: CIFSource)]
    }

    /// Why a record is not restored. Nothing is restored in part: a list missing one phase maps other phases.
    package nonisolated enum Refusal: Error, Equatable, CustomStringConvertible {
        /// The structure is not in the session file, not built in, and not held by this window.
        case structureMissing(name: String)
        /// The structure was rebuilt and is not the one the run used (another fingerprint).
        case structureChanged(name: String)
        /// The settings name a classification rule this build does not know.
        case unknownSettings

        package var description: String {
            switch self {
            case .structureMissing(let name):
                "The saved phase list is not restored: the structure of \"\(name)\" is not in the session file. Add the phases again in Phases."
            case .structureChanged(let name):
                "The saved phase list is not restored: \"\(name)\" does not rebuild as the structure the saved run used. Add the phases again in Phases."
            case .unknownSettings:
                "The saved phase list is not restored: its settings were saved by a newer mac4DSTEM."
            }
        }
    }

    /// The model a slot names: one this window already holds (`held`, the imported models), a built-in one, or the
    /// CIF text rebuilt by the importer. Always checked against the recorded id and fingerprint.
    package static func model(for slot: Slot, held: [CrystalModel]) -> Result<(model: CrystalModel, rebuiltFrom: CIFSource?), Refusal> {
        func matches(_ model: CrystalModel) -> Bool {
            model.id == slot.modelID && model.contentFingerprint == slot.fingerprint
        }
        if let model = held.first(where: matches) { return .success((model, nil)) }
        if let model = CrystalModelLibrary.model(id: slot.modelID) {
            return matches(model) ? .success((model, nil)) : .failure(.structureChanged(name: slot.displayName))
        }
        guard let cif = slot.cif else { return .failure(.structureMissing(name: slot.displayName)) }
        guard let model = try? CIFModelImport.crystalModel(from: cif.text, fileBaseName: cif.fileBaseName), matches(model) else {
            return .failure(.structureChanged(name: slot.displayName))
        }
        return .success((model, cif))
    }
}

// The slot type is the window's (main actor); the record is plain data.
extension PhaseSetupRecord {

    /// The setup as it stands: `cifSources` is the text of each imported CIF this window holds, by model id.
    @MainActor
    package init(phases: [PhaseMappingSlot], reference: PhaseReferenceSettings, matching: PhaseVectorSettings,
                 cifSources: [String: CIFSource], orientationSource: PhaseOrientationSource = .typedZones) {
        self.version = Self.currentVersion
        self.orientationSource = orientationSource.rawValue
        self.slots = phases.map { slot in
            Slot(modelID: slot.model.id, displayName: slot.model.displayName, source: slot.model.source.rawValue,
                 fingerprint: slot.model.contentFingerprint, isMatrix: slot.isMatrix, u: slot.u, v: slot.v, w: slot.w,
                 orientationRelationshipText: slot.orientationRelationshipText,
                 excitationSlabInvAngstrom: slot.excitationSlabInvAngstrom,
                 cif: slot.model.source == .imported ? cifSources[slot.model.id] : nil)
        }
        self.reference = Reference(reference)
        self.matching = Matching(matching)
    }

    /// The source the setup was saved with; a session from before 5.3 has none and was typed zones.
    package var restoredOrientationSource: PhaseOrientationSource {
        orientationSource.flatMap(PhaseOrientationSource.init(rawValue:)) ?? .typedZones
    }

    /// The phase list and settings, or why not. `held`: the imported models this window already has.
    @MainActor
    package func restored(held: [CrystalModel]) -> Result<Restored, Refusal> {
        guard let matchingSettings = matching.settings else { return .failure(.unknownSettings) }
        var phases: [PhaseMappingSlot] = []
        var imported: [(model: CrystalModel, cif: CIFSource)] = []
        for slot in slots {
            // A structure rebuilt for an earlier slot serves a later one (one CIF at two zone axes).
            switch Self.model(for: slot, held: held + imported.map(\.model)) {
            case .failure(let refusal):
                return .failure(refusal)
            case .success(let found):
                if let cif = found.rebuiltFrom { imported.append((found.model, cif)) }
                phases.append(PhaseMappingSlot(
                    model: found.model, isMatrix: slot.isMatrix, u: slot.u, v: slot.v, w: slot.w,
                    orientationRelationshipText: slot.orientationRelationshipText,
                    excitationSlabInvAngstrom: slot.excitationSlabInvAngstrom))
            }
        }
        return .success(Restored(phases: phases, reference: reference.settings, matching: matchingSettings, imported: imported))
    }
}
