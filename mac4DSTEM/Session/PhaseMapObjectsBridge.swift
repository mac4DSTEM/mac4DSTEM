//
//  PhaseMapObjectsBridge.swift
//  Role: the PURE mapping from a finished `PhaseMap` to the labels and role
//        sets `PrecipitateSegmentation.classObjects` needs — no AppState, no
//        pixel size, no publish. `AppState+PhaseMapping.swift` composes this
//        with the session's own real-space calibration (or nil, when there
//        is none); this file is what makes that composition unit-testable
//        without a running app. Session S3,
//        `docs/v3-precipitate-classification.md` §2 steps 5–6.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

package nonisolated enum PhaseMapObjectsBridge {

    /// A class label per scan position, plus the role every label present in
    /// it plays — the vocabulary `PrecipitateSegmentation.classObjects`
    /// reads.
    package nonisolated struct LabeledMap: Sendable, Equatable {
        package let labels: [Int32]
        package let roles: PrecipitateSegmentation.LabelRoles

        package nonisolated init(labels: [Int32], roles: PrecipitateSegmentation.LabelRoles) {
            self.labels = labels
            self.roles = roles
        }
    }

    /// Label written for a `.notIndexed` or `.noData` verdict. Distinct from
    /// every `phaseIndex` (always >= 0 in a `PhaseMap` that has run), so it
    /// can never collide with a real phase and the two role sets stay
    /// disjoint, which `classObjects` requires.
    package nonisolated static let notIndexedLabel: Int32 = -1

    /// `.matrix` / `.indexed` positions become their `phaseIndex`;
    /// `.notIndexed` / `.noData` positions become `notIndexedLabel`. Roles:
    /// the map's one matrix phase is `.matrix`, every OTHER phase name is a
    /// candidate and therefore `.precipitate` — including one that never
    /// actually won a position this run, so an absent class still reports as
    /// a zero-object row rather than disappearing from Results — and
    /// `notIndexedLabel` is `.notIndexed`.
    package nonisolated static func labeledMap(from map: PhaseMap) -> LabeledMap {
        var labels = [Int32](repeating: notIndexedLabel, count: map.results.count)
        for (index, result) in map.results.enumerated() {
            switch result.verdict {
            case .matrix, .indexed:
                labels[index] = result.phaseIndex
            case .notIndexed, .noData:
                labels[index] = notIndexedLabel
            }
        }

        var precipitateClasses = Set<Int32>()
        var matrix = Set<Int32>()
        for phaseIndex in map.phaseNames.indices {
            let label = Int32(phaseIndex)
            if phaseIndex == map.matrixPhaseIndex {
                matrix.insert(label)
            } else {
                precipitateClasses.insert(label)
            }
        }

        let roles = PrecipitateSegmentation.LabelRoles(
            precipitateClasses: precipitateClasses, matrix: matrix, notIndexed: [notIndexedLabel]
        )
        return LabeledMap(labels: labels, roles: roles)
    }
}
