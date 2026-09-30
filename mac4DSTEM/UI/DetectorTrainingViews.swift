import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import DSTEMTraining
#endif

/// The comparison a finished fine-tuning run puts in front of the user (C4b, ADR 048 D7/D8): the active
/// model beside the fine-tuned one on the HELD-OUT positions, recall and precision at 2 px. Presentation
/// only; the rules are `TrainingPolicy`, the actions are `AppState`'s. "Keep Current Model" is the default
/// (Return, and Escape too); "Use Fine-Tuned Model" exists only when the candidate is at least as good on
/// both numbers and better on one, and otherwise the sheet names the number that fell. The word
/// "validated" never appears: the badge says what was measured, on what.
struct DetectorTrainingReviewSheet: View {
    @Environment(AppState.self) private var appState
    let review: DetectorTrainingSession.Review

    private var outcome: DetectorFineTuningOutcome { review.outcome }
    private var saving: Bool { appState.detectorTraining.isSaving }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fine-Tuned Model")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    header("Active", sha: outcome.active.modelSHA256)
                    header("Fine-tuned", sha: outcome.candidate.modelSHA256)
                }
                GridRow {
                    Text("Recall")
                    cell(outcome.active.score.recall, outcome.active.score.matched, of: outcome.active.score.truth)
                    cell(outcome.candidate.score.recall, outcome.candidate.score.matched, of: outcome.candidate.score.truth)
                }
                GridRow {
                    Text("Precision")
                    cell(outcome.active.score.precision, outcome.active.score.matched, of: outcome.active.score.predicted)
                    cell(outcome.candidate.score.precision, outcome.candidate.score.matched, of: outcome.candidate.score.predicted)
                }
            }

            // The badge (D8): what was measured, and on what. Never "validated".
            Text(judgedOn)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("training.review.judgedOn")

            verdict

            HStack {
                Spacer()
                Button("Keep Current Model") { appState.discardFineTunedReview() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving)
                    .accessibilityIdentifier("training.review.keep")
                if review.offer == .offer {
                    Button("Use Fine-Tuned Model") { Task { await appState.adoptFineTunedModel() } }
                        .disabled(saving)
                        .accessibilityIdentifier("training.review.use")
                }
            }
        }
        .padding(20)
        // A fixed width, not `.fixedSize()`: that took the sentence below at its one-line ideal width and the
        // sheet ran past both window edges (owner's drive, 2026-09-30). The inspector's widest width is the
        // one number the shell already owns for a column of rows like these.
        .frame(width: LayoutPolicy.inspectorWidth.max)
        .interactiveDismissDisabled(saving)
    }

    private var judgedOn: String {
        let s = outcome.candidate
        return "Judged on \(s.heldOutPositions) held-out positions of \(review.datasetFile): \(s.score.truth) disk centres, "
            + String(format: "match radius %.0f px, threshold %.2f", s.radiusPx, s.threshold)
            + ", detected on the Neural Engine. "
            + "Trained on \(outcome.trained.count) other positions; the held-out positions never trained it, and they neighbour the training positions, so this holds for this dataset only."
    }

    @ViewBuilder private var verdict: some View {
        switch review.offer {
        case .offer:
            Label("At least as good on recall and precision, and better on one.", systemImage: "checkmark.circle")
                .font(.callout)
        case .decline(let reason):
            InspectorWarning(reason)
        }
    }

    private func header(_ title: String, sha: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).fontWeight(.semibold)
            Text(sha.prefix(8)).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    private func cell(_ fraction: Double, _ matched: Int, of total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TrainingPolicy.percent(fraction)).monospacedDigit()
            Text("\(matched) of \(total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
