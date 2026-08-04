import SwiftUI

/// Generic ✓/✗ prerequisite checklist for the active task, shown directly
/// under the workspace primary action whenever that action is gated. Rows come
/// from `ProductWorkflow.prerequisiteItems(for:)` — the same source that
/// disables the button — so the checklist can never disagree with the gate,
/// and every current or future task gets it with no per-task casing here.
/// Visual language mirrors `CalibrationReadinessChecklist`.
struct TaskPrerequisiteChecklist: View {
    @Environment(AppState.self) private var appState

    private var items: [TaskPrerequisite] {
        ProductWorkflow.prerequisiteItems(
            for: appState.analysisMode,
            readiness: appState.productWorkflowReadiness
        )
    }

    var body: some View {
        let items = self.items
        if items.contains(where: { !$0.isSatisfied }) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Needed before \(appState.analysisMode.productTitle) can run")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(items) { item in
                    prerequisiteRow(item)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workspace.prerequisites")
        }
    }

    @ViewBuilder
    private func prerequisiteRow(_ item: TaskPrerequisite) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(
                    item.title,
                    systemImage: item.isSatisfied
                        ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(item.isSatisfied ? Color.green : Color.orange)
                Spacer()
                Text(item.isSatisfied ? "Ready" : "Missing")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.isSatisfied ? Color.secondary : Color.orange)
            }
            if !item.isSatisfied {
                resolutionView(for: item)
            }
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
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("workspace.prerequisite.\(item.id).hint")
        }
    }
}
