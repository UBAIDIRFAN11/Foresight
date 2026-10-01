import SwiftUI
import SwiftData

struct SimulatorView: View {
    @Bindable var profile: FinancialProfile
    @Query private var goals: [FinancialGoal]
    @State private var selectedGoalID: UUID?
    @State private var purchaseName = ""
    @State private var amount = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Simulator")
                        .font(.largeTitle.weight(.bold))
                    Text("Big purchases. Smarter decisions.")
                        .font(.title3)
                }

                Picker("Goal", selection: $selectedGoalID) {
                    Text("Choose a goal").tag(UUID?.none)
                    ForEach(goals.sorted(by: goalSort)) { goal in
                        Text(goal.name).tag(Optional(goal.id))
                    }
                }
                .pickerStyle(.menu)
                .foresightCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Purchase Details")
                        .font(.headline)
                    TextField("Purchase name", text: $purchaseName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Text("TODO")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .foresightCard()

                if let previewAmount {
                    HStack(spacing: 16) {
                        Image(systemName: "creditcard")
                            .font(.largeTitle)
                            .foregroundStyle(ForesightTheme.accent)
                        VStack(alignment: .leading) {
                            Text(MoneyFormatting.display(previewAmount, currencyCode: profile.preferredCurrencyCode))
                                .font(.title.weight(.bold))
                            Text(profile.preferredCurrencyCode)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(ForesightTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Button {
                    errorMessage = "Purchase impact calculations TODO still"
                } label: {
                    Text("Calculate Impact")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let errorMessage {
                    Label(errorMessage, systemImage: "lightbulb")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(ForesightTheme.background)
        .onAppear {
            if selectedGoalID == nil {
                selectedGoalID = goals.sorted(by: goalSort).first?.id
            }
        }
    }

    private var previewAmount: Int64? {
        try? MoneyFormatting.parseMinorUnits(amount, currency: CurrencyDefinition.definition(for: profile.preferredCurrencyCode))
    }
}
