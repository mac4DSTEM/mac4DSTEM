import SwiftUI
import DSTEMCore
import DSTEMSession

/// The single surface that explains whether the active task can run, shown
/// directly under the workspace primary action. Rows come from
/// `ProductWorkflow.prerequisiteItems(for:)` — the same source that disables
/// the button — so the checklist can never disagree with the gate, and every
/// current or future task gets it with no per-task casing here.
///
/// **Ownership (design pass 2026-08-05, backlog #21).** Readiness lives here
/// and *only* here. The sidebar used to render the missing subset a second
/// time, which cost 191pt of the main pane and 47pt of an already-overflowing
/// sidebar column for the same information twice; the sidebar now carries a
/// per-task ✓/! glyph instead. This view therefore also owns the
/// "ready, but limited interpretation" guidance that the sidebar block used to
/// show, so no state is explained in two places or in none.
///
/// **Density.** Unmet requirements get a full row with the control that fixes
/// them; satisfied ones collapse to a single line, because five equal-weight
/// rows above the images were most of what made the workspace read as cramped.
/// The whole detail section is collapsible, and re-expands on arriving at a
/// different task so a blocked action always explains itself on first sight.
struct TaskPrerequisiteChecklist: View {
    @Environment(AppState.self) private var appState
    @State private var isExpanded = false

    /// **Do not remove the `lineLimit` this constant feeds. It is the fix for
    /// backlog #16/#22, and without it the window's layout collapses.**
    ///
    /// Every wrapping `Text` in this view carries
    /// `.fixedSize(horizontal: false, vertical: true)` so its explanation is not
    /// truncated — this checklist is the *single owner* of readiness (#21), so
    /// silently cutting it off is not acceptable. But `fixedSize(vertical:)`
    /// means "give me whatever height my content needs at the proposed width",
    /// and measured at a narrow proposed width these strings wrap to many lines.
    /// That turns into a **hard minimum height** which propagates up through the
    /// detail column, the outer `NSSplitView` and the hosting view — *past the
    /// window's own height*. The sidebar then inherits a column taller than the
    /// window, its top rows are laid out off-screen, and the titlebar hit-tests
    /// over them: exactly the reported "controls go inert / rows draw across the
    /// traffic lights".
    ///
    /// Measured 2026-08-06 in a 1470 × 923 window: switching Image → DPC took
    /// the sidebar scroll view to **1291.5 pt** and the root's `fittingSize` to
    /// **1343.5 pt**. Capping the wrap caps the demand and both return to 923.
    ///
    /// This view is the only place in the app where an unbounded vertical text
    /// demand sits in the detail column outside a scroll view — the other 18
    /// `fixedSize` sites are inside the sidebar `List`, which scrolls, so they
    /// are harmless. Pinned by
    /// `SplitViewHeightTests.testNothingIsLaidOutTallerThanTheWindowOnATaskSwitch`.
    ///
    /// Four rather than three: at the narrowest supported detail column the
    /// longest of these strings (the satisfied summary, which concatenates every
    /// met requirement) needs about three, so four leaves headroom while still
    /// bounding the demand. A cap does not *force* lines — short strings are
    /// unaffected — so a generous cap costs nothing and only removes the
    /// pathological case.
    private static let explanationLineLimit = 4

    private var items: [TaskPrerequisite] {
        ProductWorkflow.prerequisiteItems(
            for: appState.navigation.analysisMode,
            readiness: appState.productWorkflowReadiness
        )
    }

    private var guidance: [String] {
        ProductWorkflow.guidance(
            for: appState.navigation.analysisMode,
            readiness: appState.productWorkflowReadiness
        )
    }

    var body: some View {
        let items = self.items
        let unmet = items.filter { !$0.isSatisfied }
        let guidance = self.guidance

        Group {
            if !unmet.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    summaryRow(total: items.count, unmet: unmet)
                    if isExpanded {
                        ForEach(unmet) { prerequisiteRow($0) }
                        satisfiedSummary(items.filter(\.isSatisfied))
                    }
                }
            } else if !guidance.isEmpty {
                limitedInterpretation(guidance)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.prerequisites")
        .onChange(of: appState.navigation.analysisMode) { isExpanded = false }
    }

    private func summaryRow(total: Int, unmet: [TaskPrerequisite]) -> some View {
        HStack(spacing: 10) {
            Label(
                "Needed before \(appState.navigation.analysisMode.productTitle) can run",
                systemImage: "exclamationmark.circle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)

            Text("\(unmet.count) of \(total) missing")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if !isExpanded, let first = unmet.first {
                resolutionView(for: first)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help(isExpanded ? "Hide the requirement detail" : "Show the requirement detail")
            .accessibilityLabel(
                isExpanded ? "Hide requirement detail" : "Show requirement detail"
            )
            .accessibilityIdentifier("workspace.prerequisites.disclosure")
        }
    }

    @ViewBuilder
    private func satisfiedSummary(_ satisfied: [TaskPrerequisite]) -> some View {
        if !satisfied.isEmpty {
            Label(
                "Ready: " + satisfied.map(\.title).joined(separator: ", "),
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(Self.explanationLineLimit)   // #16 — see the constant
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("workspace.prerequisites.satisfied")
        }
    }

    private func limitedInterpretation(_ guidance: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Ready · limited interpretation", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(guidance, id: \.self) { item in
                Text(item)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(Self.explanationLineLimit)   // #16 — see the constant
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Improve in Prepare") { appState.selectWorkspace(.prepare) }
                .font(.caption)
                .accessibilityIdentifier("workspace.guidance.improve")
        }
        .accessibilityIdentifier("workspace.guidance")
    }

    @ViewBuilder
    private func prerequisiteRow(_ item: TaskPrerequisite) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(item.title, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.orange)
                Spacer()
                Text("Missing")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.orange)
            }
            resolutionView(for: item)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.prerequisite.\(item.id)")
    }

    @ViewBuilder
    private func resolutionView(for item: TaskPrerequisite) -> some View {
        switch item.resolution {
        case .prepare:
            Button("Open Prepare") { appState.selectWorkspace(.prepare) }
                .font(.caption)
                .accessibilityIdentifier("workspace.prerequisite.\(item.id).action")
        case .task(let mode):
            Button("Open \(mode.productTitle)") { appState.changeMode(mode) }
                .font(.caption)
                .accessibilityIdentifier("workspace.prerequisite.\(item.id).action")
        case .taskPanel(let hint):
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(Self.explanationLineLimit)   // #16 — see the constant
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("workspace.prerequisite.\(item.id).hint")
        }
    }
}
