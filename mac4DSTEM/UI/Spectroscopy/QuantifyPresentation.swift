import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

// The Quantify step's pure half (v5.0 R3, ADR 054): the inspector's settings <-> the session's
// `QuantificationMethod`, and a `PooledQuantification` (Core) -> what the table, the plot and the
// footers show. No SwiftUI, no compute; unit-tested in `SpectroscopyQuantifyTests`.

/// One element's typed k (relative to the reference element), as the sheet edits it.
nonisolated struct TypedKEntry: Equatable, Identifiable, Sendable {
    var element: String
    var k: Double?
    /// Relative sigma in percent; nil takes the method's flat sigma_k.
    var sigmaPercent: Double?
    var id: String { element }
}

/// The Quantify inspector's controls (ADR 054 item 8: at most seven rows, Expert behind a disclosure).
nonisolated struct QuantifySettings: Equatable, Sendable {
    var background: QuantificationMethod.Background = .empiricalWithAlEdge
    var kSource: QuantificationMethod.KFactorSource = .computed
    var absorption = true
    /// The last fit's own statement about the absorption correction (applied with its geometry, or the reason it was not).
    var absorptionNote: String?
    var thickness: Double?
    var thicknessSigma: Double?
    /// "χ²ᵣ 1.04 (Pearson)" or "reduced deviance 1.02"; nil before a fit.
    var quality: String?
    var expertOpen = false
    var estimator: QuantificationMethod.Estimator = .leastSquares
    /// Percent, flat per factor, 0 on the reference (second opinion C4).
    var sigmaK: Double? = 20
    var polyOrder = 6
    var lockEnergyAxis = false
    /// Typed beam energy (keV); asked only when the file does not state one.
    var beamEnergy: Double?
    var fileBeamKnown = true
    var typed: [TypedKEntry] = []
    var typedSource = ""
    var typedDate = ""
    var typedReference: String?

    init() {}

    init(method m: QuantificationMethod, fileBeamKnown: Bool) {
        background = m.background
        kSource = m.kFactorSource
        absorption = m.absorptionCorrection
        thickness = m.thickness?.nanometres
        thicknessSigma = m.thickness?.sigmaNanometres
        estimator = m.estimator
        sigmaK = m.sigmaK * 100
        polyOrder = m.polynomialOrder ?? 6
        lockEnergyAxis = m.lockEnergyAxis == true
        beamEnergy = m.beamEnergyKeV
        self.fileBeamKnown = fileBeamKnown
        typedSource = m.kSource
        typedDate = m.kFactorSource == .typed ? m.kDate : ""
        typedReference = m.kReference
        typed = m.typedK.map { TypedKEntry(element: $0.element, k: $0.k, sigmaPercent: $0.relativeSigma.map { $0 * 100 }) }
    }

    /// Writes the controls into the method. A computed k keeps no typed values; its source is filled by the run.
    func apply(to m: inout QuantificationMethod) {
        m.background = background
        m.kFactorSource = kSource
        m.absorptionCorrection = absorption
        m.thickness = (thickness ?? 0) > 0 ? .init(nanometres: thickness!, sigmaNanometres: max(thicknessSigma ?? 0, 0)) : nil
        m.estimator = estimator
        m.sigmaK = min(max(sigmaK ?? 20, 0), 100) / 100
        m.polynomialOrder = polyOrder == 6 ? nil : polyOrder
        m.lockEnergyAxis = lockEnergyAxis ? true : nil
        m.beamEnergyKeV = fileBeamKnown ? nil : beamEnergy
        switch kSource {
        case .typed:
            m.kSource = typedSource
            m.kDate = typedDate
            m.kReference = typedReference
            m.typedK = typed.compactMap { e in
                guard let k = e.k, k > 0 else { return nil }
                return .init(element: e.element, k: k, relativeSigma: e.sigmaPercent.map { $0 / 100 })
            }
        case .computed:
            m.kSource = ""; m.kDate = ""; m.kReference = nil; m.typedK = []
        }
    }

    /// The typed table follows the quantified elements: new ones appear empty, removed ones go, values stay.
    mutating func syncTypedElements(_ quantified: [String]) {
        typed = quantified.map { s in typed.first { $0.element == s } ?? TypedKEntry(element: s, k: nil, sigmaPercent: nil) }
        if let r = typedReference, !quantified.contains(r) { typedReference = nil }
    }

    /// Beam energy is needed from the user exactly when the file has none.
    var asksBeamEnergy: Bool { !fileBeamKnown }
}

/// A warning under the results: a short sentence and, when the fit's own text is long, the whole of it as the hover.
nonisolated struct FitWarning: Equatable, Sendable {
    var text: String
    var detail: String?
}

nonisolated enum QuantifyPresentation {
    /// The weak-line bias note is the fit's own, 600 characters long; the room shows the sentence and keeps the text as help.
    static func warnings(_ raw: [String]) -> [FitWarning] {
        raw.map { w in
            w == ContinuumForm.weakLineBiasNote
                ? FitWarning(text: "Weak-line bias: a weak line beside Al K\u{03B1} reads low by \u{2248} 300 counts per pooled spectrum on synthetic data; unmeasured on real data.", detail: w)
                : FitWarning(text: w, detail: nil)
        }
    }

    /// The table's rows for a fit. Window maps are untouched; these are the fitted areas.
    static func rows(_ q: PooledQuantification) -> [ResultRow] {
        q.rows.compactMap { r in
            guard let z = PeriodicLayout.z(of: r.element) else { return nil }
            var row = ResultRow(
                z: z, netCounts: r.net, netSigma: r.sigma,
                kFreeRatio: r.kFreeRatio ?? 0, kFreeSigma: r.isReference ? nil : r.kFreeSigma,
                atPercent: r.atomicPercent ?? 0, atSigma: r.atomicSigma ?? 0,
                wtPercent: r.weightPercent ?? 0, wtSigma: r.weightSigma ?? 0,
                sigmaTerms: r.atomicTermsText.isEmpty ? termsWithoutAbundance(r, q) : r.atomicTermsText)
            row.sigmaTermsWeight = r.weightTermsText.isEmpty ? nil : r.weightTermsText
            row.hasAbundance = r.atomicPercent != nil
            row.hasKFree = r.kFreeRatio != nil
            row.failure = r.failure
            if r.atBound && r.failure == nil {
                row.conflictNote = "held at 0 by the non-negativity bound: the line is not detected, read the \u{03C3} as an upper-limit scale"
            }
            return row
        }
    }

    private static func termsWithoutAbundance(_ r: PooledQuantification.Row, _ q: PooledQuantification) -> String {
        guard r.failure == nil else { return "" }
        let rel = r.net > 0 ? r.sigma / r.net : nil
        return "counting (fit covariance) \(rel.map { String(format: "%.1f %%", $0 * 100) } ?? "n/a") of the area"
    }

    /// The ratio line: Mg / Si when both are quantified and measured, else nothing (the column carries the rest).
    static func ratioLine(_ q: PooledQuantification) -> RatioLine? {
        guard let mg = q.rows.first(where: { $0.element == "Mg" && $0.failure == nil && $0.net > 0 }),
              let si = q.rows.first(where: { $0.element == "Si" && $0.failure == nil && $0.net > 0 }),
              let gi = q.fit.groupIDs.firstIndex(of: mg.groupID), let gj = q.fit.groupIDs.firstIndex(of: si.groupID) else { return nil }
        let ratio = mg.net / si.net
        let rel = q.fit.ratioRelativeVariance(gi, gj)
        guard rel.isFinite, rel >= 0 else { return nil }
        return RatioLine(label: "Mg / Si net ratio", value: ratio, sigma: ratio * rel.squareRoot(),
                         note: "k-free: fitted areas, fit covariance only; no k, no absorption")
    }

    /// The series the plot draws: the data, the fitted background, the model, restricted to the fitted channels.
    static func series(data: [UInt64], axis: EnergyAxis, _ q: PooledQuantification) -> SpectrumSeries {
        let a = q.usedAxis
        var s = SpectrumSeries(energyStart: a.offset, energyStep: a.scale, data: data.map { Double($0) },
                               background: q.plotBackground, model: q.plotModel, overlay: nil)
        s.fitChannels = q.fit.channels
        return s
    }

    /// The Spectrum image step's "file vs refined" readouts.
    static func axisReadouts(_ q: PooledQuantification) -> (file: String, refined: String?) {
        let file = String(format: "%.3f\u{2013}%.3f keV \u{00B7} %.2f eV/ch \u{00B7} from the file", q.fileAxis.lowValue, q.fileAxis.highValue, q.fileAxis.scale * 1000)
        if q.axisLocked { return (file, "locked: the file's axis is used") }
        guard let r = q.refinement else { return (file, "not refined") }
        let used = q.usedAxis == r.refinedAxis
        return (file, String(format: "%+.1f eV, gain %+.3f %%, FWHM %.0f eV%@", r.offsetShiftEV, r.gainShift * 100, r.resolutionMnKaEV, used ? "" : " (not used)"))
    }

    /// The plot's one-line footer: the estimator and background by name, the fit quality.
    static func plotFooter(_ q: PooledQuantification) -> String {
        "\(q.fit.methodLabel) \u{00B7} \(q.fit.backgroundLabel.components(separatedBy: ",").first ?? q.fit.backgroundLabel) \u{00B7} \(q.qualityLabel) \(String(format: "%.2f", q.quality))"
    }
}
