import SwiftUI

/// UI's whole number budget, in one file.
///
/// The rule UI is built on: **SwiftUI decides size, we decide bounds.** A
/// control is as wide as its content, a column is as wide as the user dragged
/// it, and spare space is margin. The only numbers here are the ones a
/// container genuinely cannot infer — a split column's range, a scientific
/// image's floor, and the width of a field holding six digits. Nothing in
/// UI may declare a `.frame(width:)`/`minWidth:` outside these constants;
/// the science panes are the one exception, and they take their floor from
/// `imagePaneMinimum` / `resultPaneMinimum` rather than spelling a number.
enum LayoutPolicy {
    /// The navigation column. Narrow on purpose: it holds five words and a
    /// task list, never a control.
    static let sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (190, 230, 320)

    /// The inspector: the workspace's settings and the dataset/product
    /// descriptor. Wider than the sidebar because forms live here.
    static let inspectorWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (280, 320, 460)

    /// Science: a diffraction or real-space pane below this stops being an
    /// image and becomes a smudge.
    static let imagePaneMinimum: CGFloat = 180

    /// Science: the Results pane shows one product at reading size.
    static let resultPaneMinimum = CGSize(width: 360, height: 300)

    /// Science: one panel of the A / B / A−B comparison row.
    static let comparisonPaneMinimum: CGFloat = 120

    /// Science: the rotation-curve diagnostic plot.
    static let diagnosticPlotHeight: CGFloat = 90

    /// About six digits. A numeric field is never as wide as its row.
    static let numericFieldWidth: CGFloat = 72

    /// A ceiling, not a size: a thumbnail grows with its column and stops
    /// here, so a square preview in a wide inspector is bounded by the
    /// column, not by this.
    static let thumbnailMaximumHeight: CGFloat = 320

    /// The output log's dragged height.
    static let outputLogHeight: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (80, 150, 420)

    /// A control popover (the colorbar chip).
    static let popoverWidth: CGFloat = 280

    /// Readable line length for prose on an otherwise empty workspace.
    static let readableWidth: CGFloat = 560

    /// Sheets: an ideal size and a floor, so a short display shrinks the
    /// sheet instead of pushing its footer off screen.
    static let configuratorSheet: (min: CGSize, ideal: CGSize) =
        (CGSize(width: 720, height: 500), CGSize(width: 880, height: 720))
    static let exportSheet: (min: CGSize, ideal: CGSize) =
        (CGSize(width: 540, height: 460), CGSize(width: 600, height: 700))

    /// An inline progress bar beside its status text.
    static let inlineProgressWidth: CGFloat = 110

    /// The grabbable width of a thin divider, centred on the drawn line. A
    /// 1 pt zone put the drag on the focus ring (owner finding (c),
    /// 2026-09-03); this is the same 9 pt the AppKit columns use.
    static let dividerGrabWidth: CGFloat = 9

    /// Largest box with `aspect` (width / height) that fits inside `size`.
    /// Letterboxing is the pane's job everywhere an image is drawn: a
    /// scientific image that is stretched to its container is a wrong image.
    static func fitted(in size: CGSize, aspect: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        return size.width / size.height > aspect
            ? CGSize(width: size.height * aspect, height: size.height)
            : CGSize(width: size.width, height: size.width / aspect)
    }
}

/// A numeric text field with an optional unit, for the trailing side of a
/// `LabeledContent` row — the one place a UI form control takes a width.
struct NumericField<Value, Format: ParseableFormatStyle>: View
where Format.FormatInput == Value, Format.FormatOutput == String {
    let title: String
    @Binding var value: Value
    let format: Format
    var unit: String?

    init(
        _ title: String,
        value: Binding<Value>,
        format: Format,
        unit: String? = nil
    ) {
        self.title = title
        self._value = value
        self.format = format
        self.unit = unit
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, value: $value, format: format)
                // Labelled by the row it sits in; the title stays for
                // VoiceOver.
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: LayoutPolicy.numericFieldWidth)
            if let unit {
                // The unit is part of the number's meaning: it never
                // truncates and never wraps.
                Text(unit)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .accessibilityLabel(title)
    }
}

/// How a running operation's numbers are worded, in one place.
///
/// The status bar and the inspector's Performance rows both print elapsed,
/// throughput and ETA (owner, 2026-09-04: the numbers belong beside the
/// progress bar, not only one tab away). Two copies of "53 s" versus "0:53"
/// is exactly the drift this session spent its time removing, so both read
/// from here.
enum OperationMetricsFormat {
    /// Seconds as "53 s" below a minute, "2:35" above it.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total >= 60
            ? String(format: "%d:%02d", total / 60, total % 60)
            : "\(total) s"
    }

    /// The virtual detector walks patterns; everything else walks scan
    /// positions. Keyed on the operation's own name, as it always was.
    static func throughputUnit(for operation: String?) -> String {
        operation == "Virtual detector" ? "patterns/s" : "positions/s"
    }

    static func throughput(_ rate: Double, for operation: String?) -> String {
        String(format: "%.1f %@", rate, throughputUnit(for: operation))
    }
}

/// Every byte quantity UI prints, through one formatter.
///
/// UI had three (2026-09-04 review): two hand-rolled 1024-based ones that
/// disagreed on precision, and `ByteCountFormatter(.file)` at 1000. The same
/// float32 cube read 4.00 GB in the inspector and 4.29 GB in the export sheet
/// the user opens to decide whether to write it. Apple's own split — `.memory`
/// for RAM, `.file` for disk, both labelled "GB" — is defensible in isolation
/// and wrong here, because these numbers are read against each other across
/// surfaces. One style, and it is Finder's, because Finder is the reference
/// the user already has on screen.
func displayByteString(_ bytes: Int) -> String {
    bytes.formatted(.byteCount(style: .file))
}

extension View {
    /// A preview image fills its column's width up to the one height cap.
    func thumbnailCapped() -> some View {
        frame(maxWidth: .infinity, maxHeight: LayoutPolicy.thumbnailMaximumHeight)
    }
}
