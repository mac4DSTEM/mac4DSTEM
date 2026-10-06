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

    /// Records the Quantify run in the session's replay lineage; returns the node id (an existing id when
    /// the run collapsed into the previous one, ADR 047 R3). Input edges come from the lineage's policy.
    @discardableResult
    package func recordQuantification(in replay: SessionReplay, registration: RegistrationRecordM2? = nil,
                                      regionKind: String = "wholeMap",
                                      regionName: String = "Whole map") -> String {
        replay.record(kind: QuantificationStep.kind,
                      parameters: quantificationStep(registration: registration, regionKind: regionKind,
                                                     regionName: regionName).parameters,
                      under: .unknown)
    }

    /// A rewind to a quantification step restores its method into the room. Returns the step when the
    /// parameters are a readable quantification (method decoded, hash matching); nil leaves the method
    /// as it is.
    @discardableResult
    package func restoreQuantification(parameters: [String: String]) -> QuantificationStep? {
        guard let step = QuantificationStep(parameters: parameters) else { return nil }
        method = step.method
        return step
    }
}
