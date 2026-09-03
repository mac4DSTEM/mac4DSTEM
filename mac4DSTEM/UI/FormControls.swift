import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The presentation contract's few numbers, in one place (architecture.md,
/// rule 4: "no fixed frames except the science; thumbnails cap their height
/// by rule, not by a number per site"). Every sidebar, inspector and sheet
/// sizes its numeric fields and thumbnails through these two rules; the
/// inventory gate greps for any other `.frame(width:)` outside the panes.
enum FormPolicy {
    /// A numeric field is as wide as about six digits — never the row. It was
    /// 90, which with a unit beside it ran a 250pt sidebar row past its edge
    /// ("Voltage 200 k", measured on screen 2026-09-03).
    static let numericFieldWidth: CGFloat = 72
    /// A thumbnail grows with its column and stops here.
    ///
    /// This number is a CEILING, not a size: `.aspectRatio(.fit)` fits the
    /// image inside (column width x this), so for a square preview the
    /// smaller of the two wins. At 160 that was always the height, so the
    /// preview stayed 160pt wide however wide the inspector was dragged
    /// (owner, 2026-09-03). At 320 the column width wins through the
    /// inspector's usable range and the cap only catches a very wide column.
    static let thumbnailMaximumHeight: CGFloat = 320
}

/// The window's own few numbers (rule 1: structure is fixed, content is
/// fluid): strips, inline progress bars, popovers and sheets. Everything
/// else takes the width it is given.
enum WindowPolicy {
    /// The output log strip under the panes.
    static let outputStripHeight: CGFloat = 100
    /// An inline progress bar beside its status text.
    static let inlineProgressWidth: CGFloat = 110
    /// A control popover (the colorbar chips).
    static let popoverWidth: CGFloat = 260
    /// Readable line length on the welcome workspace.
    static let readableWidth: CGFloat = 560
    /// The load configurator and export sheets: an ideal size and a floor,
    /// so a short display shrinks the sheet instead of losing its footer
    /// (the 2026-08-18 fixed-height defect).
    static let configuratorSheet = (min: CGSize(width: 780, height: 520), ideal: CGSize(width: 900, height: 760))
    static let exportSheet = (min: CGSize(width: 560, height: 480), ideal: CGSize(width: 620, height: 720))
}

/// A numeric text field with an optional unit, for the trailing side of a
/// `LabeledContent` row. The only place a form control takes a width.
struct NumericField<Value, Format: ParseableFormatStyle>: View
where Format.FormatInput == Value, Format.FormatOutput == String {
    let title: String
    @Binding var value: Value
    let format: Format
    var unit: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, value: $value, format: format)
                // A Form labels its text fields; this one is labelled by
                // the row it sits in, and the title stays for accessibility.
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: FormPolicy.numericFieldWidth)
            if let unit {
                // The unit is part of the number's meaning: it never
                // truncates, and it never wraps to a second line.
                Text(unit)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .accessibilityLabel(title)
    }
}

extension View {
    /// Rule 4: a thumbnail fills the column's width up to the one height cap.
    func thumbnailCapped() -> some View {
        frame(maxWidth: .infinity, maxHeight: FormPolicy.thumbnailMaximumHeight)
    }
}
