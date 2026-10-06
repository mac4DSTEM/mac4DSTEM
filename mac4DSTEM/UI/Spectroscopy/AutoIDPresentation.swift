import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

// Auto ID's pure half (v5.0 WP3 lane W, ADR 054 §6): the element proposer's `ProposalResult` (Core) -> what the
// Elements & maps step and the spectrum show. The proposer RETURNS candidates and edits nothing; here they become
// `ElementSuggestion`s (a named conflict, one click to accept), sum-peak questions become suspect markers, and the
// refusals and notes stay compact. No SwiftUI, no compute; unit-tested in `SpectroscopyAutoIDTests`.

/// A pile-up question: an energy that is a sum peak or a candidate element, never offered as an element.
nonisolated struct AutoIDSuspect: Equatable, Sendable {
    var label: String            // "Ar Kα?"
    var energy: Double           // keV
    var question: String         // the proposer's own conflict text
}

nonisolated struct AutoIDRefusal: Equatable, Sendable {
    var element: String
    var reason: String
}

/// One run's result, as the room keeps it.
nonisolated struct AutoIDOutcome: Equatable, Sendable {
    /// The region whose spectrum was proposed from (the suggestions are about that one).
    var region: String
    var suggestions: [ElementSuggestion]
    var suspects: [AutoIDSuspect]
    /// Elements the proposer did not test and the periodic table does not already grey (H to Be).
    var notTested: [AutoIDRefusal]
    /// The look-elsewhere line, the misfit line, the lowest-tested-line floor: the proposer's own words.
    var notes: [String]

    var suspectMarkers: [LineMarker] {
        suspects.map { LineMarker(label: $0.label, energy: $0.energy, elementZ: nil, kind: .suspect,
                                  fwhm: XRayLines.fwhm(resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV, atEnergy: $0.energy)) }
    }
    var hasDetails: Bool { !suspects.isEmpty || !notTested.isEmpty || !notes.isEmpty }
}

nonisolated enum AutoIDPresentation {
    static func outcome(_ r: ProposalResult, region: String) -> AutoIDOutcome {
        var suggestions: [ElementSuggestion] = []
        for c in r.proposed {   // NOT `candidates.filter(\.isProposed)`: a sum-peak question is not a finding
            guard let z = PeriodicLayout.z(of: c.element), ElementSelection.unavailableReason(z: z) == nil else { continue }
            let questions = c.conflicts.map(\.question)
            let reason = questions.isEmpty
                ? String(format: "net %.0f counts, %.1f × L_D", c.net, c.significance)
                : questions.joined(separator: " ")
            // DEVIATION (the brief, ADR 054 §6): every suggestion proposes Quantify, not the proposer's Fit only default
            // for all but Cu; except a FIB question, whose own remedy is "keep Ga fitted but excluded from Quantify".
            let role: ElementRole = c.conflicts.contains { $0.kind == .fibContamination } ? .fitOnly : .quantify
            suggestions.append(ElementSuggestion(z: z, reason: reason, proposedRole: role))
        }
        let suspects: [AutoIDSuspect] = r.sumPeakQuestions.map { c in
            AutoIDSuspect(label: ElementWindows.label(ofLineID: c.group) + "?", energy: c.energyKeV,
                          question: c.conflicts.filter { $0.kind == .sumPeak }.map(\.question).joined(separator: " "))
        }
        let notTested = r.refused.filter { !LineConflicts.refusedElements.contains($0.element) }
            .map { AutoIDRefusal(element: $0.element, reason: $0.reason) }
        return AutoIDOutcome(region: region, suggestions: suggestions, suspects: suspects, notTested: notTested, notes: r.notes)
    }
}
