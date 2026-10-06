//
//  SpectroscopyQuantification.swift
//  Role: The room's side of the replay step "quantification" (v5.0 WP3 lane M, ADR 047 / 054 item 8):
//        record the method (and the registration and region it pooled over) as a lineage step, and put a
//        step's method back after a rewind. No UI and no fit: the Quantify verb (a later step) calls
//        these.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

extension SpectroscopySession {

    /// The step the Quantify verb records for the current method.
    package func quantificationStep(registration: RegistrationRecordM2? = nil,
                                    regionKind: String = "wholeMap",
                                    regionName: String = "Whole map") -> QuantificationStep {
        QuantificationStep(method: method, registration: registration, regionKind: regionKind,
                           regionName: regionName)
    }

    /// The parameters the lineage records for the Quantify run (spec 2 D-11): what `QuantificationStep` needs to put the method
    /// back (`method_json`, `method_hash`, the registration, `region_kind`, `region_name`) and the readable keys the lineage pane
    /// shows as they are: `background`, `k_factors`, `absorption`, `estimator`, `beam_energy_kev`, `elements`, and when set
    /// `thickness_nm`, `fit_to_kev`, `polynomial_order`; `method` is the short hash (`SpectroscopyExport.shortHash`).
    ///
    /// DEVIATION from `QuantificationStep.parameters` (Core, unchanged): there the full method JSON sits under `method`. A restore
    /// cannot be rebuilt from readable keys and a hash (a hash is not invertible), so the JSON stays, under `method_json`, and
    /// `restoreQuantification` reads it from there (and from `method`, as steps recorded before this wrote it).
    package func quantificationParameters(registration: RegistrationRecordM2? = nil, regionKind: String = "wholeMap",
                                          regionName: String = "Whole map") -> [String: String] {
        let step = quantificationStep(registration: registration, regionKind: regionKind, regionName: regionName)
        var p = step.parameters
        let m = method
        p["method_json"] = p["method"]
        p["method"] = SpectroscopyExport.shortHash(m)
        p["background"] = m.background == .empiricalWithAlEdge ? "Empirical" : "Polynomial"
        p["k_factors"] = m.kFactorSource == .typed ? "Typed" : "Computed"
        p["absorption"] = m.absorptionCorrection ? "on" : "off"
        p["estimator"] = m.estimator == .leastSquares ? "Least squares" : "Poisson ML"
        if let beam = m.beamEnergyKeV ?? source?.metadata.beamEnergyKeV { p["beam_energy_kev"] = Self.number(beam) }
        if let t = m.thickness { p["thickness_nm"] = "\(Self.number(t.nanometres)) ± \(Self.number(t.sigmaNanometres))" }
        if let to = m.fitToKeV { p["fit_to_kev"] = Self.number(to) }
        if m.background == .wholeRangePolynomial6, let order = m.polynomialOrder { p["polynomial_order"] = "\(order)" }
        let listed = m.elements.filter { $0.role != .off }.map(\.symbol)
        if !listed.isEmpty { p["elements"] = listed.joined(separator: ", ") }
        return p
    }

    /// Up to six significant digits, no trailing zeros, a period whatever the locale.
    private static func number(_ v: Double) -> String { String(format: "%g", v) }

    /// Records the Quantify run in the session's replay lineage; returns the node id (an existing id when
    /// the run collapsed into the previous one, ADR 047 R3). Input edges come from the lineage's policy.
    @discardableResult
    package func recordQuantification(in replay: SessionReplay, registration: RegistrationRecordM2? = nil,
                                      regionKind: String = "wholeMap",
                                      regionName: String = "Whole map") -> String {
        replay.record(kind: QuantificationStep.kind,
                      parameters: quantificationParameters(registration: registration, regionKind: regionKind,
                                                           regionName: regionName),
                      under: .unknown)
    }

    /// A rewind to a quantification step restores its method into the room. Returns the step when the
    /// parameters are a readable quantification (method decoded, hash matching); nil leaves the method
    /// as it is.
    @discardableResult
    package func restoreQuantification(parameters: [String: String]) -> QuantificationStep? {
        var p = parameters
        if let json = p["method_json"] { p["method"] = json }   // the recorded form (`quantificationParameters`); older steps hold it under `method`
        guard let step = QuantificationStep(parameters: p) else { return nil }
        method = step.method
        return step
    }
}
