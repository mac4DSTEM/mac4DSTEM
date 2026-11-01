//
//  SpectroscopyShared.swift
//  What the retired Spectroscopy room left that the rest of the app reads (2026-10-23, the EDS room replaced it): the result
//  number format (Results rows, the spectrum-only views, the histogram).
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
    /// Digits grouped with a narrow no-break space (U+202F), in `locale`'s digits, decimal mark and minus sign. FormatStyle has no
    /// grouping-separator option, so the locale's own thousands mark is swapped for U+202F (pinned by `FormatStyleMigrationTests`).
    nonisolated static func grouped(_ v: Double, fraction: ClosedRange<Int> = 0...0, locale: Locale) -> String {
        v.formatted(.number.precision(.fractionLength(fraction)).locale(locale))
            .replacingOccurrences(of: locale.groupingSeparator ?? ",", with: "\u{202F}")
    }
    /// 412380 -> "412 380" (thin grouping, as the mock prints counts).
    nonisolated static func counts(_ v: Double) -> String { grouped(v, locale: Locale(identifier: "en_US")) }
}
