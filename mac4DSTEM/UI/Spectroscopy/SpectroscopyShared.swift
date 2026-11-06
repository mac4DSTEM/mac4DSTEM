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
    /// Digits grouped with a narrow no-break space (U+202F), in `locale`'s digits, decimal mark and minus sign. FormatStyle has no
    /// grouping-separator option, so the locale's own thousands mark is swapped for U+202F (pinned by `FormatStyleMigrationTests`).
    nonisolated static func grouped(_ v: Double, fraction: ClosedRange<Int> = 0...0, locale: Locale) -> String {
        v.formatted(.number.precision(.fractionLength(fraction)).locale(locale))
            .replacingOccurrences(of: locale.groupingSeparator ?? ",", with: "\u{202F}")
    }
    /// 412380 -> "412 380" (thin grouping, as the mock prints counts).
    nonisolated static func counts(_ v: Double) -> String { grouped(v, locale: Locale(identifier: "en_US")) }
}
