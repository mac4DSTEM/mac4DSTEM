//
//  NumberFormat.swift
//  Role: the one way the app writes a number a person reads in a pane overlay or the status line: printf's digits with the
//        user's decimal mark, never grouped. `String(format:)` without a locale always prints a period, so a German Mac
//        showed "Threshold, 0.25" in the confidence gate beside a scale bar of "2,5 nm". The digits stay printf's on purpose:
//        `FormatStyle` and `String(format:locale:)` round ties differently (0.35 reads 0.4 there, 0.3 in `%.1f`, measured
//        2026-10-14, `ResultFormat.number`), and the digits a scientist reads must not move with the region.
//        Strings a script reads (provenance keys, CSV, exported captions) keep their fixed point: they are not for reading.
//

import Foundation

nonisolated enum Num {
    /// `value` with exactly `places` decimals ("0,01250" in a comma locale), as `%.<places>f` rounds it.
    static func fixed(_ value: Double, _ places: Int, locale: Locale = .autoupdatingCurrent) -> String {
        localized(String(format: "%.\(max(places, 0))f", zeroed(value, places)), locale: locale)
    }

    /// `value` with up to `digits` significant digits and no trailing zeros, as `%.<digits>g` writes it.
    static func sig(_ value: Double, _ digits: Int, locale: Locale = .autoupdatingCurrent) -> String {
        localized(String(format: "%.\(max(digits, 1))g", value), locale: locale)
    }

    /// A value that rounds to zero at `places` decimals is zero: never "-0,00" for a tiny negative (or a negative zero).
    private static func zeroed(_ value: Double, _ places: Int) -> Double {
        let scale = pow(10, Double(max(places, 0)))
        return (value * scale).rounded() == 0 ? 0 : value
    }

    /// printf's text with `locale`'s decimal mark in place of its period.
    private static func localized(_ text: String, locale: Locale) -> String {
        guard let mark = locale.decimalSeparator, mark != "." else { return text }
        return text.replacingOccurrences(of: ".", with: mark)
    }
}
