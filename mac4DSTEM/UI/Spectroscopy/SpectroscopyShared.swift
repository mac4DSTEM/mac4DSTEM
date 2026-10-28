//
//  SpectroscopyShared.swift
//  What the retired Spectroscopy room left that the rest of the app reads (2026-10-23, the EDS room replaced it): the result
//  number format (Results rows, the spectrum-only views, the histogram) and the unvalidated badge.
//

import ShellInspector
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// Number formatting for the table; separate so the pure part is testable.
enum ResultFormat {
    /// "88.1 ± 0.9". The digits are `String(format:)`'s (the same rounding as ever); the decimal separator is the locale's, so a
    /// German-region Mac reads "88,1 ± 0,9" (UI audit 2026-10-14, Right to left). Never grouped.
    static func plusMinus(_ v: Double, _ s: Double, digits: Int, locale: Locale = .current) -> String {
        number(v, digits, locale) + " ± " + number(s, digits, locale)
    }
    /// A number with `digits` decimals in `locale`'s decimal separator. The digits are printf's, on purpose: `String(format:locale:)`
    /// and `FormatStyle` round through ICU and differ on ties (0.35 reads 0.4 there, 0.3 in `%.1f`; measured 2026-10-14), and the
    /// digits a scientist reads must not move with the region. Only the separator is the locale's.
    static func number(_ v: Double, _ digits: Int, _ locale: Locale = .current) -> String {
        let text = String(format: "%.\(digits)f", v)
        guard let separator = locale.decimalSeparator, separator != "." else { return text }
        return text.replacingOccurrences(of: ".", with: separator)
    }
    /// The k-free ratio and abundance cells of a row. Until WP3 fits a spectrum there is neither: "—", never a number.
    static func fitCells(_ row: ResultRow, unit: AbundanceUnit, hasFit: Bool, locale: Locale = .current) -> (kFree: String, abundance: String) {
        guard hasFit else { return ("—", "—") }
        let abundance = row.hasAbundance
            ? (unit == .atomic ? plusMinus(row.atPercent, row.atSigma, digits: 1, locale: locale)
                               : plusMinus(row.wtPercent, row.wtSigma, digits: 1, locale: locale)) : "—"
        guard row.hasKFree else { return ("—", abundance) }
        return (row.kFreeSigma.map { plusMinus(row.kFreeRatio, $0, digits: 4, locale: locale) } ?? "1",
                abundance)
    }
    /// Narrow-space grouping (`SpectrumReadout.grouped`, kept beside the spectrum logic so tools/ harnesses compile without views).
    nonisolated static func grouped(_ v: Double, fraction: ClosedRange<Int> = 0...0, locale: Locale) -> String {
        SpectrumReadout.grouped(v, fraction: fraction, locale: locale)
    }
    /// 412380 -> "412 380" (thin grouping, as the mock prints counts).
    nonisolated static func counts(_ v: Double) -> String { SpectrumReadout.counts(v) }
}

/// The badge `validation:"none"` carries on screen (ADR 054 §3). Orange text on a tint,
/// as the mock draws it; the word is the claim.
struct UnvalidatedBadge: View {
    var body: some View {
        Text("unvalidated")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .accessibilityLabel("unvalidated")
    }
}
