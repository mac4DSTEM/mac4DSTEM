//
//  ResultMetadata.swift
//  Role: the kind / display-name / value-units triple for the CURRENT scalar
//        result, one arm per presentable product.
//
//  This is a FILE-PLACEMENT move out of `ResultExport.swift` (2026-09-11), not
//  the consolidation it superficially resembles. It stays an `extension
//  AppState` and its body is unchanged, because it reads `resultPresentation.virtualShape`,
//  `dpc.dpcDisplay`, `strain.component`, `acomSession`, `phaseContrast.parallaxDepth` and more —
//  so it cannot join the `extension AnalysisMode` tables in
//  `App/ProductWorkflow.swift` the way `AnalysisMode` itself did at step 1.
//
//  Why it moved: `AppState.swift` + `Support/ResultExport.swift` may never net
//  positive lines in a commit (CLAUDE.md, measured by `tools/run-tests.sh
//  inventory`), and wiring diffraction grouping needs a handful of lines in
//  `AppState.swift`. The port analysis pre-registered this as the lever to
//  spend. Say so rather than letting a reader think the file was split for
//  cohesion.
//

import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif

extension AppState {

    // Internal, not private, since v2.5 step 3b-2: the display-mode publishers
    // in AppState.swift build their product value from it until each site
    // carries its own kind/name/units (deletion condition 2, plan §9d).
    var currentScalarResultMetadata:
        (kind: String, displayName: String, valueUnits: String) {
        switch navigation.analysisMode {
        case .virtualDetector:
            return ("virtual_\(resultPresentation.virtualShape.rawValue.lowercased())",
                    "Virtual detector · \(resultPresentation.virtualShape.rawValue)", "intensity")
        case .dpc:
            switch dpc.dpcDisplay {
            case .magnitude:  return ("dpc_magnitude", "DPC magnitude", "detector_px")
            case .magnitudeMrad:
                let physical = dpcMilliradiansPerDetectorPixel != nil
                return (physical ? "dpc_magnitude_mrad" : "dpc_magnitude",
                        physical ? "DPC magnitude (mrad)" : "DPC magnitude",
                        physical ? "mrad" : "detector_px")
            case .angle:      return ("dpc_angle", "DPC angle", "rad")
            case .idpc:
                let physical = idpcPhysicalCalibration != nil
                return (
                    physical ? "idpc_phase" : "idpc_qualitative",
                    physical ? "iDPC projected phase" : "iDPC (qualitative)",
                    physical ? "rad" : "detector_px_scan_px"
                )
            case .colorWheel: return ("dpc_color", "DPC color wheel", "rgba")
            }
        case .strain:
            let units: String
            switch strain.component {
            case .theta: units = "rad"
            case .residual: units = "detector_px"
            case .indexed: units = "boolean"
            case .exx, .eyy, .exy: units = "strain"
            }
            let kind: String
            switch strain.component {
            case .exx:   kind = "strain_exx"
            case .eyy:   kind = "strain_eyy"
            case .exy:   kind = "strain_exy"
            case .theta: kind = "strain_theta"
            case .residual: kind = "strain_fit_residual"
            case .indexed: kind = "strain_indexed"
            }
            return (kind, "Strain · \(strain.component.rawValue)", units)
        case .diffractionGroups:
            // The published map is a GROUP INDEX per scan position, not a
            // physical quantity — the units say so rather than inventing one.
            // The k the run used is carried in the display name, because a
            // k=4 map and a k=8 map are otherwise indistinguishable in Results
            // and in the sidecar (the owner's drive, `drive-groups` defect 5).
            // Same kind, name and units the run itself publishes
            // (`AppState+DiffractionGroups.runDiffractionGroups`), through the
            // same helper AND from the same number: the run's ACTUAL group
            // count, which `DiffractionEmbedding.compute` clamps to the
            // position count — the requested k is only the fallback when no
            // result exists (audit 2026-09-14).
            let k = diffractionGroups.result?.groupCount
                ?? diffractionGroups.lastRunSettings?.groups
                ?? diffractionGroups.settings.groups
            return ("diffraction_groups",
                    DiffractionGroupsProduct.groupMapDisplayName(groups: k),
                    "group")
        case .phaseMapping:
            // A phase INDEX per scan position, not a physical quantity — and
            // the candidate count is in the name for the same reason k is in
            // the group map's: two runs over different phase lists are
            // otherwise indistinguishable in Results and in the sidecar
            // (`drive-groups` defect 5). Same helper the run itself publishes
            // through, so the fallback and the real product cannot drift.
            let candidates = max(0, (phaseMapping.map?.phaseNames.count ?? 1) - 1)
            return ("phase_map",
                    PhaseMappingProduct.mapDisplayName(candidatePhases: candidates),
                    "phase")
        case .acom:
            let angular: Set<ACOMDisplayMode> = [.inPlane, .phi1, .Phi, .phi2, .disorientation]
            let baseKind: String
            switch acomSession.display {
            case .ipfZ:        baseKind = "acom_ipf_z"
            case .reliability: baseKind = "acom_reliability"
            case .disorientation:
                baseKind = "acom_\(acomSession.orientationMap?.symmetry.rawValue ?? "symmetry")_fz_angle"
            case .inPlane:     baseKind = "acom_in_plane"
            case .phi1:        baseKind = "acom_phi1"
            case .Phi:         baseKind = "acom_Phi"
            case .phi2:        baseKind = "acom_phi2"
            case .score:       baseKind = "acom_score"
            }
            // All three scopes are named, including full scan. Previously the
            // qualifier was empty only for full scan, so the most complete
            // product was the one whose label said least about how it was made,
            // and preview vs full-scan results were told apart by the *absence*
            // of a word — which silently matched a stale preview in the QC
            // harness and is unresolvable for a user comparing exported PNGs.
            let scope = acomSession.lastRunScope ?? .fullScan
            let kind = "acom_\(scope.resultQualifier)_\(baseKind.dropFirst(5))"
            return (kind, "ACOM \(scope.rawValue.lowercased()) · \(acomSession.display.rawValue)",
                    angular.contains(acomSession.display) ? "rad" : "dimensionless")
        case .disks:
            return ("bragg_vector_map", "Bragg vector map", "log_intensity")
        case .ptychography, .singleslicePtychography:
            switch phaseContrast.parallaxResultProduct {
            case .correctedPhase:
                return ("parallax_corrected_phase", "Parallax corrected phase",
                        "arbitrary_phase")
            case .subpixel:
                return ("parallax_subpixel_bf", "Parallax subpixel BF",
                        "normalized_intensity")
            case .alignment:
                return ("parallax_alignment", "Parallax aligned BF",
                        "normalized_intensity")
            case .preprocess:
                return ("parallax_preprocess", "Parallax incoherent BF preview",
                        "normalized_intensity")
            case .depth:
                let depth = phaseContrast.parallaxDepth?.depthsAngstrom[phaseContrast.parallaxDepthSelectedIndex] ?? 0
                return ("parallax_depth", String(format: "Parallax depth %.1f Å", depth),
                        "arbitrary_phase")
            case .iterativePhase:
                return ("ptychography_object_phase", "Ptychography object phase", "rad")
            case .iterativeAmplitude:
                return ("ptychography_object_amplitude", "Ptychography object amplitude",
                        "dimensionless")
            case .iterativeProbePhase:
                return ("ptychography_probe_phase", "Ptychography probe phase", "rad")
            case .iterativeProbeAmplitude:
                return ("ptychography_probe_amplitude", "Ptychography probe amplitude",
                        "dimensionless")
            }
        }
    }
}
