// Transient confirmation shown on the History detail screen after a purchase decision
// has been saved. It is presentation state only and is never persisted.
import SwiftUI

struct SavedDecisionNotice: Equatable {
    // A new event ID per save keeps two saves of similar purchases distinct.
    let eventID: UUID
    let evaluationID: UUID
    let purchaseName: String

    init(decision: SavedDecision, eventID: UUID = UUID()) {
        self.eventID = eventID
        evaluationID = decision.evaluationID
        // Copy the name so later edits or deletion cannot change the confirmation text.
        purchaseName = decision.purchaseName
    }

    var message: String { "Saved “\(purchaseName)” to History." }

    /// The notice belongs to the saved record, so it only applies while History is
    /// showing that exact decision.
    func applies(selectedTab: MainTabView.AppTab, historyPath: [UUID]) -> Bool {
        selectedTab == .history && historyPath.last == evaluationID
    }
}

struct SavedDecisionBanner: View {
    let notice: SavedDecisionNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ForesightTheme.success)
                .accessibilityHidden(true)
            Text(notice.message)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss saved confirmation")
        }
        .padding(.leading, 16)
        .padding(.vertical, 4)
        .padding(.trailing, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ForesightTheme.success.opacity(0.5), lineWidth: 1)
        }
        // Match the readable width used by the screen content below it.
        .frame(maxWidth: 720)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }
}
