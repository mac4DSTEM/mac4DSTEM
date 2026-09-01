import SwiftUI

/// S22d, verified live: the sidebar's `.sidebar`-style `List` does not offer
/// its rows a width, so `fixedSize(horizontal: false, vertical: true)` never
/// wraps there — text takes its one-line ideal width and truncates (the
/// dataset card's two-line comment recorded the same result on 2026-08-27:
/// "fixedSize … was tried first and did NOT fix it"). The cure is to hand
/// long texts the column's real width: a `GeometryReader` around the List
/// publishes it, and `.sidebarWrapped()` pins the text to it so it trades
/// width for lines like anywhere else.
enum SidebarTextWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var sidebarTextWidth: CGFloat? {
        get { self[SidebarTextWidthKey.self] }
        set { self[SidebarTextWidthKey.self] = newValue }
    }
}

private struct SidebarWrapped: ViewModifier {
    @Environment(\.sidebarTextWidth) private var width

    func body(content: Content) -> some View {
        if let width {
            content
                // The explicit nil overrides whatever line limit the sidebar
                // list style inherits into its rows — without it the width
                // frame alone still ellipsized (verified live, 2026-09-01).
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .leading)
        } else {
            // Outside the sidebar (or before the width is known) fall back to
            // the ordinary wrap request.
            content.fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    /// Wrap instead of truncating, inside the sidebar List. See
    /// `SidebarTextWidthKey`.
    func sidebarWrapped() -> some View { modifier(SidebarWrapped()) }
}
