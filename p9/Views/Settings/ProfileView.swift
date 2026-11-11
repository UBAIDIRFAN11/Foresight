
import SwiftUI
import SwiftData

//disp the profile management screen under Settings

struct ProfileView: View {
    @Bindable var profile: FinancialProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query private var goals: [FinancialGoal]
    @State private var errorMessage: String?
    @State private var isChoosingFocusGoal = false
    @AccessibilityFocusState private var focusChooserFocused: Bool
    @EnvironmentObject private var router: AppRouter

    private var sortedGoals: [FinancialGoal] {
        goals.sorted(by: goalSort)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Keep the heading and subtitle together.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)

                    Text("Personalise how Foresight helps you plan for your goals.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 4)

                //summary of the user's existing goals.
                planningOverview


                focusGoalCard



                NavigationLink {
                    FinancialProfileView(mode: .editing(profile))
                } label: {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "person.text.rectangle")
                            .font(.title2)
                            .foregroundStyle(ForesightTheme.accent)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Financial Profile")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Update your savings, income and recurring expenses.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ForesightTheme.accent)
                            .accessibilityHidden(true)
                    }
                    .foresightCard()
                }
                .buttonStyle(.plain)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(ForesightTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foresightReadableContent()
        }
        .background(ForesightTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isChoosingFocusGoal, onDismiss: {
            if !goals.isEmpty, router.selectedTab == .settings { focusChooserFocused = true }
        }) {
            NavigationStack {
                GoalSelectionSheet(
                    navigationTitle: "Preferred Focus Goal",
                    profile: profile,
                    evaluationDay: FinancialCalendar.localEvaluationDay(),
                    selectedID: preferredGoalID,
                    noneOption: GoalSelectionNoneOption(title: "Automatic", detail: "Home shows your highest-priority goal with the nearest deadline.")
                ) { id in
                    try savePreference(id)
                }
            }
        }
    }

    // Goal names can repeat, so the chosen goal is shown with its deadline.
    private var preferenceSummary: String {
        guard let id = preferredGoalID, let goal = goals.first(where: { $0.id == id }) else { return "Automatic" }
        let deadline = FinancialCalendar.displayDate(fromUTCNoon: goal.targetDate).formatted(.dateTime.day().month(.abbreviated).year())
        return "\(goal.name) · due \(deadline)"
    }

    //Planning Overview

    private var planningOverview: some View {
        VStack(alignment: .leading, spacing: 14) {

            Label("Planning overview", systemImage: "chart.bar.xaxis")
                .accessibilityAddTraits(.isHeader)
                .font(.headline)
                .foregroundStyle(ForesightTheme.accent)

            // Keep metrics evenly spaced. Stack at accessibility sizes.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))

            layout {
                planningMetric("Saved goals", count: goals.count)
                    .frame(maxWidth: .infinity, alignment: .leading)

                planningMetric(
                    "High-priority goals",
                    count: goals.filter { $0.priority == .high }.count
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foresightCard()
    }

    private func planningMetric(
        _ title: LocalizedStringKey,
        count: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(count, format: .number)
                .font(.title2.weight(.bold))
                .foregroundStyle(ForesightTheme.accent)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    //Preferred Focus Goal

    private var focusGoalCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "flag")
                .font(.title2)
                .foregroundStyle(ForesightTheme.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Preferred focus goal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    isChoosingFocusGoal = true
                } label: {
                    HStack(spacing: 6) {
                        Text(preferenceSummary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                }
                .tint(ForesightTheme.accent)
                .disabled(goals.isEmpty)
                .accessibilityLabel("Preferred focus goal")
                .accessibilityValue(preferenceSummary)
                .accessibilityHint("Sets the default goal shown on Home.")
                .accessibilityFocused($focusChooserFocused)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foresightCard()
    }

    //Persistence

    private var preferredGoalID: UUID? {
        // A preference for a deleted goal behaves as Automatic.
        profile.preferredFocusGoalID.flatMap { id in
            goals.contains { $0.id == id } ? id : nil
        }
    }

    //uses FinancialProfilePolicy.saveFocusPreference to save user's preferred focus goal.
    private func savePreference(_ id: UUID?) throws {
        do {
            // The policy rolls back the stored and in-memory preference if saving fails.
            try FinancialProfilePolicy.saveFocusPreference(
                id,
                for: profile,
                in: modelContext
            )
            errorMessage = nil
        } catch {
            errorMessage = "Could not save your preference. \(error.localizedDescription)"
            throw error
        }
    }
}
