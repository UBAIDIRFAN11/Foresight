// Shows the live goal calculation and owns the optional weekly check-in reminder
// controls for that specific goal.
import SwiftUI
import SwiftData

struct GoalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var reminderCoordinator: ReminderCoordinator
    @AppStorage("remindersPaused") private var remindersPaused = false
    @Query private var goals: [FinancialGoal]
    @Query private var reminderRecords: [ReminderRecord]

    @Bindable var profile: FinancialProfile
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?
    @State private var reminderError: String?
    @State private var reminderEnabled = false
    @State private var selectedWeekday = 1
    @State private var selectedTime = Calendar.current.date(from: DateComponents(hour: 18, minute: 0)) ?? Date()
    
    
    //tracks the beginning of displayed timeline
    @State private var visibleStartMonth = 0
    
    //tracks the selected chart date
    @State private var selectedChartDate: Date?
    
    //provides the current day for projection
    let evaluationDay: Date
    private var today: Date { evaluationDay }

    init(goalID: UUID, profile: FinancialProfile, evaluationDay: Date) {
        // Query only the selected goal so edits/deletes update this view automatically.
        _goals = Query(filter: #Predicate<FinancialGoal> { goal in
            goal.id == goalID
        })
        self.profile = profile
        self.evaluationDay = evaluationDay
    }

    var body: some View {
        Group {
            if let goal = goals.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(goal.name)
                            .font(.largeTitle.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        GoalCard(goal: goal, profile: profile, today: today, showsNavigationIndicator: false)
                        
                        //place the chart on the screen
                        projectionSection(for: goal)
                        detailRows(for: goal)
                        checkInSection(for: goal)
                        deleteButton
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(ForesightTheme.warning)
                        }
                    }
                    .foresightReadableContent()
                }
                .background(ForesightTheme.background)
                .navigationTitle(goal.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
                .sheet(isPresented: $isEditing) {
                    NavigationStack {
                        GoalEditorView(profile: profile, goal: goal, evaluationDay: evaluationDay)
                    }
                }
                .confirmationDialog("Delete this goal?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete Goal", role: .destructive) {
                        delete(goal)
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .onAppear {
                    loadReminderDraft(for: goal)
                    reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused)
                }
                .onChange(of: reminderRecords.map(\.scheduleRevision)) { _, _ in
                    loadReminderDraft(for: goal)
                }
            } else {
                ScrollView {
                    ContentUnavailableView("Goal Missing", systemImage: "questionmark.folder", description: Text("This goal is no longer available."))
                        .foresightReadableContent()
                }
                .background(ForesightTheme.background)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused)
        }
    }

    private func detailRows(for goal: FinancialGoal) -> some View {
        // Detail rows show the current profile's effect on this goal right now.
        let result = FinancialCalculator.evaluate(
            FinancialInputs(
                savingsMinor: profile.currentSavingsMinor,
                incomeMinor: profile.monthlyIncomeMinor,
                expensesMinor: profile.recurringExpensesMinor,
                targetMinor: goal.targetAmountMinor,
                evaluationDate: today,
                targetDate: goal.targetDate
            )
        )
        return VStack(alignment: .leading, spacing: 12) {
            AdaptiveValueRow(title: "Monthly capacity", value: MoneyFormatting.display(result.monthlyCapacityMinor, currencyCode: profile.preferredCurrencyCode))
            AdaptiveValueRow(title: "Remaining", value: MoneyFormatting.display(result.remainingMinor, currencyCode: profile.preferredCurrencyCode))
            AdaptiveValueRow(title: "Required each month", value: MoneyFormatting.display(result.monthlyRequiredMinor, currencyCode: profile.preferredCurrencyCode))
            AdaptiveValueRow(title: "Completion date", value: completionDateText(result.completionProjection))
            AdaptiveValueRow(title: "Deadline balance", value: MoneyFormatting.display(result.deadlineBalanceMinor, currencyCode: profile.preferredCurrencyCode))
        }
        .foresightCard()
    }

    private func projectionSection(for goal: FinancialGoal) -> some View {
        
        //create financial inputs from the users current financial profile and selected goal
        let inputs = financialInputs(for: goal)
        
        //create a projection for current savings path, target, and deadline
        let projection = FinancialProjectionBuilder.build(
            inputs: inputs,
            visibleStartMonth: visibleStartMonth
        )

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Savings Projection")
                    .font(.headline)
                Spacer(minLength: 12)
                Text(windowLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch projection {
            case .success(let projection):
                if let explanation = projection.explanation {
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                //pass the projection into the chart
                SavingsProjectionChart(
                    projection: projection,
                    currencyCode: profile.preferredCurrencyCode,
                    selectedDate: $selectedChartDate
                )
                //enable user to move between 12 month windows
                timelineControls(for: projection)
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "chart.xyaxis.line")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foresightCard()
    }

    private var windowLabel: String {
        let start = visibleStartMonth
        let end = visibleStartMonth + FinancialProjectionBuilder.defaultVisibleMonthCount
        return "Months \(start)-\(end)"
    }

    private func timelineControls(for projection: SavingsProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    visibleStartMonth = max(visibleStartMonth - FinancialProjectionBuilder.defaultVisibleMonthCount, 0)
                    selectedChartDate = nil
                } label: {
                    Image(systemName: "chevron.left.2")
                        .frame(minWidth: 44)
                }
                .accessibilityLabel("Earlier 12-month window")
                .disabled(!projection.canMoveEarlier)

                Spacer(minLength: 12)

                Button {
                    visibleStartMonth = min(
                        visibleStartMonth + FinancialProjectionBuilder.defaultVisibleMonthCount,
                        FinancialCalculator.completionMonthLimit - FinancialProjectionBuilder.defaultVisibleMonthCount
                    )
                    selectedChartDate = nil
                } label: {
                    Image(systemName: "chevron.right.2")
                        .frame(minWidth: 44)
                }
                .accessibilityLabel("Later 12-month window")
                .disabled(!projection.canMoveLater)
            }

            HStack {
                milestoneButtons(for: projection)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func milestoneButtons(for projection: SavingsProjection) -> some View {
        Group {
            Button {
                visibleStartMonth = max(FinancialCalendar.monthsWithDeposits(from: today, through: projection.deadlineDate) - 2, 0)
                selectedChartDate = projection.deadlineDate
            } label: {
                Label("Deadline", systemImage: "calendar")
            }
            .accessibilityLabel("Jump to deadline")
            .disabled(FinancialCalendar.isBeforeDay(projection.deadlineDate, today))

            Spacer(minLength: 12)

            Button {
                if let startMonth = FinancialProjectionBuilder.startMonthForMilestone(projection.baselineCompletionMonth) {
                    visibleStartMonth = startMonth
                    selectedChartDate = completionDate(from: projection.baselineResult.completionProjection)
                }
            } label: {
                Label("Completion", systemImage: "flag.checkered")
            }
            .accessibilityLabel("Jump to completion")
            .disabled(FinancialProjectionBuilder.startMonthForMilestone(projection.baselineCompletionMonth) == nil)
        }
    }

    private func financialInputs(for goal: FinancialGoal) -> FinancialInputs {
        FinancialInputs(
            savingsMinor: profile.currentSavingsMinor,
            incomeMinor: profile.monthlyIncomeMinor,
            expensesMinor: profile.recurringExpensesMinor,
            targetMinor: goal.targetAmountMinor,
            evaluationDate: today,
            targetDate: goal.targetDate
        )
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            Label("Delete Goal", systemImage: "trash")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func checkInSection(for goal: FinancialGoal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Check-In")
                .font(.headline)
            Toggle("Remind me to review this goal", isOn: reminderBinding(for: goal))
            if reminderEnabled {
                Picker("Weekday", selection: Binding(
                    get: { selectedWeekday },
                    set: { selectedWeekday = $0; saveGoalReminder(for: goal, enabled: reminderEnabled) }
                )) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                    }
                }
                DatePicker("Time", selection: Binding(
                    get: { selectedTime },
                    set: { selectedTime = $0; saveGoalReminder(for: goal, enabled: reminderEnabled) }
                ), displayedComponents: .hourAndMinute)
                Text(goalReminderStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Check-ins are optional. Foresight does not automatically track actual savings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NavigationLink {
                FinancialProfileView(mode: .editing(profile))
            } label: {
                Label("Update Financial Profile", systemImage: "person.text.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if let message = reminderCoordinator.schedulingError {
                Text(message).font(.footnote).foregroundStyle(ForesightTheme.warning)
                Button("Retry Scheduling") {
                    reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused, requestAuthorizationIfNeeded: true)
                }
            }
            if let reminderError {
                Label(reminderError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(ForesightTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foresightCard()
    }

    private func reminderBinding(for goal: FinancialGoal) -> Binding<Bool> {
        Binding(
            get: { reminderEnabled },
            set: { newValue in
                reminderEnabled = newValue
                saveGoalReminder(for: goal, enabled: newValue)
            }
        )
    }

    private func loadReminderDraft(for goal: FinancialGoal) {
        guard let record = goalReminder(for: goal) else {
            reminderEnabled = false
            selectedWeekday = 1
            selectedTime = Calendar.current.date(from: DateComponents(hour: 18, minute: 0)) ?? Date()
            return
        }
        reminderEnabled = record.isEnabled
        selectedWeekday = record.weekday
        selectedTime = Calendar.current.date(from: DateComponents(hour: record.hour, minute: record.minute)) ?? selectedTime
    }

    private func saveGoalReminder(for goal: FinancialGoal, enabled: Bool) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        do {
            _ = try ReminderStore.upsertGoalReminder(
                for: goal,
                weekday: selectedWeekday,
                hour: components.hour ?? 18,
                minute: components.minute ?? 0,
                isEnabled: enabled,
                in: modelContext
            )
            reminderError = nil
            reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused, requestAuthorizationIfNeeded: enabled)
        } catch {
            loadReminderDraft(for: goal)
            reminderError = error.localizedDescription
        }
    }

    private func goalReminder(for goal: FinancialGoal) -> ReminderRecord? {
        reminderRecords.first {
            $0.kind == .goalCheckIn && $0.sourceID == goal.id
        }
    }

    private var goalReminderStatus: String {
        guard let goal = goals.first, let reminder = goalReminder(for: goal) else { return "Off" }
        return reminderCoordinator.status(for: reminder, globallyPaused: remindersPaused)
    }

    private func delete(_ goal: FinancialGoal) {
        do {
            try FinancialProfilePolicy.deleteGoal(goal, in: modelContext)
            reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused)
            dismiss()
        } catch {
            // Roll back so a failed delete does not leave the context half-changed.
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func completionText(_ projection: GoalCompletionProjection) -> String {
        switch projection {
        case .completedNow:
            "Completed now"
        case .projected(let months, let date):
            "\(months) \(months == 1 ? "month" : "months") · \(formatted(date))"
        case .noPositiveSavingsCapacity:
            "Unavailable: no positive monthly savings capacity"
        case .beyondLimit:
            "Unavailable: beyond the 1,200-month projection limit"
        }
    }

    private func completionDateText(_ projection: GoalCompletionProjection) -> String {
        switch projection {
        case .completedNow:
            "Completed now"
        case .projected(_, let date):
            formatted(date)
        case .noPositiveSavingsCapacity:
            "Unavailable: no positive monthly savings capacity"
        case .beyondLimit:
            "Unavailable: beyond the 1,200-month projection limit"
        }
    }

    private func completionDate(from projection: GoalCompletionProjection) -> Date? {
        if case .projected(_, let date) = projection {
            return date
        }
        if case .completedNow = projection {
            return today
        }
        return nil
    }

    private func formatted(_ date: Date) -> String {
        FinancialCalendar.displayDate(fromUTCNoon: date)
            .formatted(.dateTime.day().month(.abbreviated).year())
    }
}
