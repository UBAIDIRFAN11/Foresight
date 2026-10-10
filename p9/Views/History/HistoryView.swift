import SwiftUI
import SwiftData

struct HistoryView: View {
    // Newest saved decisions appear first in the history list.
    @Query(sort: [SortDescriptor(\SavedDecision.savedAt, order: .reverse)]) private var decisions: [SavedDecision]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("History")
                        .font(.largeTitle.weight(.bold))
                    Text("Your saved hypothetical decisions.")
                        .font(.title3)
                }

                if decisions.isEmpty {
                    ContentUnavailableView(
                        "No Saved Decisions",
                        systemImage: "folder",
                        description: Text("Save a purchase impact result to build your decision history.")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(groupedDecisions, id: \.month) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.month)
                                .font(.headline)
                            ForEach(group.decisions) { decision in
                                NavigationLink {
                                    // Open the saved snapshot, not a recalculation.
                                    PurchaseImpactView(
                                        evaluation: decision.evaluationSnapshot,
                                        mode: .saved(savedAt: decision.savedAt),
                                        onSaved: nil,
                                        onAmountChange: nil,
                                        onAdjust: nil
                                    )
                                } label: {
                                    decisionRow(decision)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .foresightReadableContent()
        }
        .background(ForesightTheme.background)
    }

    private var groupedDecisions: [(month: String, decisions: [SavedDecision])] {
        // Group rows under month headings while keeping newest groups first.
        Dictionary(grouping: decisions) { decision in
            decision.savedAt.formatted(.dateTime.month(.wide).year())
        }
        .map { (month: $0.key, decisions: $0.value.sorted { $0.savedAt > $1.savedAt }) }
        .sorted { lhs, rhs in
            guard let lhsDate = lhs.decisions.first?.savedAt, let rhsDate = rhs.decisions.first?.savedAt else {
                return lhs.month < rhs.month
            }
            return lhsDate > rhsDate
        }
    }

    private func decisionRow(_ decision: SavedDecision) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(decision.purchaseName)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(MoneyFormatting.display(decision.purchaseAmountMinor, currencyCode: decision.currencyCode))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            Text(decision.goalName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(impactText(decision))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foresightCard()
    }

    private func impactText(_ decision: SavedDecision) -> String {
        // Compact row summary; the detail screen shows the full calculation.
        let snapshot = decision.evaluationSnapshot
        if snapshot.result.afterPurchase.deadlineBalanceMinor < snapshot.goalTargetMinor {
            return "Deadline missed after purchase."
        }
        if let months = snapshot.result.purchaseDelay.monthCount {
            return months == 0 ? "No completion delay." : "Completion delayed by \(months) \(months == 1 ? "month" : "months")."
        }
        return "Completion delay unavailable."
    }
}
