import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

// Auto ID's pure half (v5.0 WP3 lane W, ADR 054 §6): the element proposer's `ProposalResult` (Core) -> what the
// Elements section and the spectrum show. The proposer RETURNS candidates and edits nothing; here they become
// `ElementSuggestion`s (the controller picks them, spec 2 D-3; the inspector's Picked row lists them with their reasons),
// sum-peak questions stay in the row's hover (their plot markers retire), and the refusals and notes stay compact. No SwiftUI, no compute; unit-tested in `SpectroscopyAutoIDTests`.

/// A pile-up question: an energy that is a sum peak or a candidate element, never offered as an element.
nonisolated struct AutoIDSuspect: Equatable, Sendable {
    var label: String            // "Al+Al sum? (or Ar Kα)": leads with the sum (R7, wp3e item 1a), never the candidate alone
    var energy: Double           // keV
    var question: String         // the proposer's own conflict text
    var stats = ""               // "net 8 400 000 counts, 1.4 × L_D, χ²ᵣ 54.8 (Pearson)" (F3.3)
}

/// A proposal that sits beside a listed line (`UnlistedLineChecker.neighbour`): an unexplained excess, never an element
/// (R7, wp3e F3.1: one source of truth with the quant panel's unlisted-line check).
nonisolated struct AutoIDExcess: Equatable, Sendable {
    var beside: String           // "Al Kα" or "the continuum split at 1.560 keV"
    var proposerLabel: String    // "Lu Mα": the proposer's own name for it
    var stats: String
    /// "unexplained excess beside Al Kα"
    var title: String { "unexplained excess beside \(beside)" }
    /// The full sentence, as the hover.
    var detail: String { "\(title) (proposer's label \(proposerLabel)): \(stats)" }
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
    /// Proposals beside a listed line: shown as excesses, no tile.
    var excesses: [AutoIDExcess] = []
    /// Elements the proposer did not test and the periodic table does not already grey (H to Be).
    var notTested: [AutoIDRefusal]
    /// The look-elsewhere line, the misfit line, the lowest-tested-line floor: the proposer's own words.
    var notes: [String]

    var hasDetails: Bool { !suspects.isEmpty || !excesses.isEmpty || !notTested.isEmpty || !notes.isEmpty }
}

nonisolated enum AutoIDPresentation {
    /// "net 900 counts, 3.0 × L_D, χ²ᵣ 54.8 (Pearson)": the quantity every suggestion carries (F3.3), whatever the verdict on it.
    static func stats(_ c: ElementCandidate, chiSquared: Double?) -> String {
        var t = String(format: "net %@ counts, %.1f \u{00D7} L_D", UnlistedLineChecker.grouped(c.net), c.significance)
        if let x = chiSquared { t += ", " + PooledQuantifier.qualityText(label: "\u{03C7}\u{00B2}\u{1D63} (Pearson)", value: x) }
        return t
    }

    /// "Al+Al sum" out of a sum-peak conflict's id ("sum-Al+Al sum-Ar").
    static func sumLabel(_ conflict: LineConflict) -> String {
        var t = conflict.id
        if t.hasPrefix("sum-") { t.removeFirst(4) }
        let tail = "-" + conflict.element
        if t.hasSuffix(tail) { t.removeLast(tail.count) }
        return t
    }

    /// What a candidate at an energy sits beside (a listed alpha line within +-2 FWHM, a split edge within +-1), as the quant
    /// panel's check computes it; nil when it is clear. `listed` is the fit's own element list, axis and width.
    static func besideCheck(settings: FitSettings, axis: EnergyAxis) -> (Double, String) -> String? {
        let listed = EDSLineModel.build(elements: settings.elements, axis: axis, beamEnergy: settings.beamEnergy,
                                        resolutionMnKaEV: settings.resolutionMnKaEV, escapePeaks: settings.escapePeaks).groups
        var edges: [Double] = []
        if case .continuum(let form) = settings.background { edges = form.edges }
        return { e, element in
            UnlistedLineChecker.neighbour(energyKeV: e, listedGroups: listed, resolutionMnKaEV: settings.resolutionMnKaEV, edges: edges, element: element)?.line
        }
    }

    /// Strongest first (net / L_D, D3 of wp3e Gate D2); equal significance keeps the given order.
    static func bySignificance(_ cs: [ElementCandidate]) -> [ElementCandidate] {
        cs.enumerated().sorted { $0.element.significance != $1.element.significance ? $0.element.significance > $1.element.significance : $0.offset < $1.offset }.map(\.element)
    }

    /// Why a pick is applied as Fit only when the k-factors are computed and its line group is an L or M one.
    static let noComputedKPrefix = "fit only (no computed k for L/M lines): "

    /// Whether a computed k can quantify this line group ("Eu_La" is an L group, "Cu_Ka" a K one). A group the line table
    /// does not know is not judged here.
    static func isKGroup(_ group: String) -> Bool { XRayLines.line(group).map { $0.family == .K } ?? true }

    /// `beside` answers "what listed line is this energy (of this element) next to?" (nil = nothing): see `besideCheck`.
    /// `computedK`: the Quantification k-factors are Computed, which cover K lines only (the sheet's row 2c); with a Typed k the
    /// person's own factor may cover any line, so the old rule holds.
    /// `rules`: the registered post-selection (`ProposalRules.apply`); nil keeps the proposer's own picks. With it the picks, the
    /// sum-peak questions and the notes are the ruled ones, each pick a rule acted on says which in its reason, and every pick a rule
    /// withheld is named in the notes (never silently gone).
    static func outcome(_ r: ProposalResult, region: String, beside: (Double, String) -> String? = { _, _ in nil },
                        computedK: Bool = false, rules: RuledProposal? = nil) -> AutoIDOutcome {
        var suggestions: [ElementSuggestion] = []
        var excesses: [AutoIDExcess] = []
        for c in bySignificance(rules?.picks ?? r.proposed) {   // NOT `candidates.filter(\.isProposed)`: a sum-peak question is not a finding
            let stats = stats(c, chiSquared: r.reducedChiSquared)
            if let line = beside(c.energyKeV, c.element) {   // F3.1: a misfit of that line's shape or the continuum, not a detected element
                excesses.append(AutoIDExcess(beside: line, proposerLabel: UnlistedLineChecker.displayName(c.group), stats: stats))
                continue
            }
            guard let z = PeriodicLayout.z(of: c.element), ElementSelection.unavailableReason(z: z) == nil else { continue }
            let questions = c.conflicts.map(\.question)
            // DEVIATION (the brief, ADR 054 §6; the sheet's row 2c): every suggestion proposes Quantify, not the proposer's Fit only
            // default for all but Cu, except a FIB question (its own remedy is "keep Ga fitted but excluded from Quantify") and, with
            // a computed k, a pick whose lines are L or M: no k exists for them, so it is fitted for the lines it takes from its
            // neighbours and never enters at% (Velox's deconvolution-only). A role, not a number: no at% is renormalised.
            let noK = computedK && !isKGroup(c.group)
            let fib = c.conflicts.contains { $0.kind == .fibContamination }
            let role: ElementRole = (noK || fib) ? .fitOnly : .quantify
            var reason = (noK ? noComputedKPrefix : "") + (questions.isEmpty ? stats : stats + ". " + questions.joined(separator: " "))
            if let rule = rules?.ruleReason(for: c.element) { reason += (reason.hasSuffix(".") ? " " : ". ") + rule }
            suggestions.append(ElementSuggestion(z: z, reason: reason, proposedRole: role, significance: c.significance))
        }
        let suspects: [AutoIDSuspect] = bySignificance(rules?.heldQuestions ?? r.sumPeakQuestions).map { c in
            let sums = c.conflicts.filter { $0.kind == .sumPeak }
            let lead = sums.map(sumLabel).joined(separator: " / ")
            return AutoIDSuspect(label: "\(lead)? (or \(ElementWindows.label(ofLineID: c.group)))", energy: c.energyKeV,
                                 question: sums.map(\.question).joined(separator: " "), stats: stats(c, chiSquared: r.reducedChiSquared))
        }
        let notTested = r.refused.filter { !LineConflicts.refusedElements.contains($0.element) }
            .map { AutoIDRefusal(element: $0.element, reason: $0.reason) }
        return AutoIDOutcome(region: region, suggestions: suggestions, suspects: suspects, excesses: excesses, notTested: notTested,
                             notes: r.notes + (rules.map(ruleNotes) ?? []))
    }

    /// The rules' own lines for the notes: which picks each withheld (with the number), which were released, and where the cuts
    /// come from. Empty when no rule is on.
    static func ruleNotes(_ p: RuledProposal) -> [String] {
        guard !p.rules.isNone else { return [] }
        var lines: [String] = []
        if !p.withheld.isEmpty {
            lines.append("Withheld by the rules: " + p.withheld.map { w in
                "\(UnlistedLineChecker.displayName(w.candidate.group)) (\(w.rule.rawValue), \(w.why))"
            }.joined(separator: ", ") + ".")
        }
        if !p.released.isEmpty {
            lines.append("Released from the sum-peak hold (R3): " + p.released.map { UnlistedLineChecker.displayName($0.candidate.group) }.joined(separator: ", ") + ".")
        }
        lines.append("Rules " + ProposalRules.Rule.allCases.filter { rule in
            switch rule { case .hygiene: p.rules.hygiene; case .corroboration: p.rules.corroboration; case .release: p.rules.release }
        }.map(\.rawValue).joined(separator: ", ") + " " + ProposalRules.source + ".")
        return lines
    }
}
