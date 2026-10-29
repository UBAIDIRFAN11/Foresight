
import SwiftUI
import SwiftData

struct ProfileView: View {
    @Bindable var profile: FinancialProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query private var goals: [FinancialGoal]
    @State private var errorMessage: String?

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

                Picker("Preferred focus goal", selection: preferenceBinding) {
                    Text("Automatic").tag(nil as UUID?)

                    ForEach(sortedGoals) { goal in
                        Text(goal.name).tag(Optional(goal.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(ForesightTheme.accent)
                .disabled(goals.isEmpty)
                .accessibilityHint("Sets the default goal shown on Home.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foresightCard()
    }

    //Persistence

    private var preferenceBinding: Binding<UUID?> {
        Binding(
            get: {
                profile.preferredFocusGoalID.flatMap { id in
                    goals.contains { $0.id == id } ? id : nil
                }
            },
            set: { id in
                do {
                    try FinancialProfilePolicy.saveFocusPreference(
                        id,
                        for: profile,
                        in: modelContext
                    )
                    errorMessage = nil
                } catch {
                    errorMessage = "Could not save your preference. \(error.localizedDescription)"
                    if let errorMessage { AccessibilityNotification.Announcement(errorMessage).post() }
                }
            }
        )
    }
}
