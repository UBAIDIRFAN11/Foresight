import SwiftUI
import SwiftData

struct SimulatorView: View {
    @Bindable var profile: FinancialProfile
    @Query private var goals: [FinancialGoal]
    @State private var selectedGoalID: UUID?
    @State private var purchaseName = ""
    @State private var amount = ""
    @State private var errorMessage: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: Field?

    private enum Field {
        case amount
    }

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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Purchase name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Coffee machine", text: $purchaseName)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Amount")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .amount)
                    }
                    Text("TODO")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foresightCard()

                if let previewAmount {
                    let previewLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(alignment: .center, spacing: 16))

                    previewLayout {
                        Image(systemName: "creditcard")
                            .font(.largeTitle)
                            .foregroundStyle(ForesightTheme.accent)
                        VStack(alignment: .leading) {
                            Text(MoneyFormatting.display(previewAmount, currencyCode: profile.preferredCurrencyCode))
                                .font(.title.weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)
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
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foresightPrimaryAction()

                if let errorMessage {
                    Label(errorMessage, systemImage: "lightbulb")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foresightReadableContent()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ForesightTheme.background)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
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
