// Shared goal chooser used by Simulator, Home focus and the Profile preference.
// Goal names are not unique, so each choice is the full GoalCard (description,
// target and deadline) and selection is always by UUID.
import SwiftUI
import SwiftData

//an optional "no specific goal" choice, worded by each caller (for example "Automatic").
struct GoalSelectionNoneOption {
    let title: String
    let detail: String
}

struct GoalSelectionSheet: View {
    let navigationTitle: String
    let profile: FinancialProfile
    let evaluationDay: Date
    let selectedID: UUID?
    var noneOption: GoalSelectionNoneOption? = nil
    /// Commits through the caller's existing workflow. Throwing keeps the sheet open
    /// and shows the failure instead of implying the choice was saved.
    let onSelect: (UUID?) throws -> Void

    @Environment(\.dismiss) private var dismiss
    // Live query so goals deleted or edited while the sheet is open update immediately.
    @Query private var goals: [FinancialGoal]
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Goal amounts are in \(CurrencyDefinition.definition(for: profile.preferredCurrencyCode).displayName).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let noneOption {
                    choiceButton(id: nil) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(noneOption.title)
                                .font(.title3.weight(.bold))
                            Text(noneOption.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foresightCard()
                        .accessibilityElement(children: .combine)
                    }
                }

                // Same order as every other goal list in the app.
                ForEach(goals.sorted(by: goalSort)) { goal in
                    choiceButton(id: goal.id) {
                        GoalCard(goal: goal, profile: profile, today: evaluationDay, showsNavigationIndicator: false, showsCurrencyCode: true)
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ForesightTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foresightReadableContent()
        }
        .background(ForesightTheme.background)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func choiceButton<Content: View>(id: UUID?, @ViewBuilder label: () -> Content) -> some View {
        let isSelected = id == selectedID
        return Button {
            select(id)
        } label: {
            label()
                // The current choice gets an accent outline and checkmark on top of the card's own border.
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(ForesightTheme.accent, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(ForesightTheme.accent)
                            .padding(10)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ id: UUID?) {
        // Re-check against the live goals: the card may belong to a goal deleted a moment ago.
        if let id, !goals.contains(where: { $0.id == id }) {
            show("That goal is no longer available. Choose another goal.")
            return
        }
        do {
            try onSelect(id)
            dismiss()
        } catch {
            show("Could not save your choice. \(error.localizedDescription)")
        }
    }

    private func show(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
    }
}
