// Settings screen for reminder status, global pause, permission recovery, and
// disabling saved purchase or goal reminders.
import SwiftUI
import SwiftData

struct RemindersSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var reminderCoordinator: ReminderCoordinator
    @AppStorage("remindersPaused") private var remindersPaused = false
    @Query(sort: [SortDescriptor(\ReminderRecord.updatedAt, order: .reverse)]) private var reminders: [ReminderRecord]
    @Query private var decisions: [SavedDecision]
    @Query private var goals: [FinancialGoal]
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Toggle("Pause All Reminders", isOn: $remindersPaused)
                AdaptiveValueRow(title: "Permission", value: reminderCoordinator.deliverySettings.summary)
                if reminderCoordinator.deliverySettings.permissionState == .denied {
                    Button {
                        reminderCoordinator.openSystemSettings()
                    } label: {
                        Label("Open iOS Settings", systemImage: "gearshape")
                    }
                }
            } footer: {
                Text("Paused reminders stay saved locally and are restored when you resume them. Foresight stores reminder intent; iOS pending notifications are rebuilt from that saved state.")
            }

            Section("Configured Reminders") {
                if reminders.isEmpty {
                    ContentUnavailableView("No Reminders", systemImage: "bell", description: Text("Purchase review and goal check-in reminders will appear here."))
                } else {
                    ForEach(reminders) { reminder in
                        reminderRow(reminder)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(ForesightTheme.warning)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ForesightTheme.background)
        .navigationTitle("Reminders")
        .onAppear {
            reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused)
        }
        .onChange(of: remindersPaused) { _, _ in
            reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused)
        }
    }

    private func reminderRow(_ reminder: ReminderRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(rowTitle(for: reminder), systemImage: reminder.kind == .purchaseReview ? "cart" : "flag")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Text(status(for: reminder))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(for: reminder))
            }
            Text(scheduleText(for: reminder))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if reminder.isEnabled {
                Button(role: .destructive) {
                    cancel(reminder)
                } label: {
                    Label("Disable Reminder", systemImage: "bell.slash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func rowTitle(for reminder: ReminderRecord) -> String {
        switch reminder.kind {
        case .purchaseReview:
            decisions.first { $0.evaluationID == reminder.sourceID }?.purchaseName ?? "Deleted saved decision"
        case .goalCheckIn:
            goals.first { $0.id == reminder.sourceID }?.name ?? "Deleted goal"
        }
    }

    private func scheduleText(for reminder: ReminderRecord) -> String {
        switch reminder.kind {
        case .purchaseReview:
            if let date = reminder.deliveryDate {
                return "Review on \(date.formatted(date: .abbreviated, time: .shortened))"
            }
            return "No delivery date set"
        case .goalCheckIn:
            let weekday = Calendar.current.weekdaySymbols[max(min(reminder.weekday, 7), 1) - 1]
            let date = Calendar.current.date(from: DateComponents(hour: reminder.hour, minute: reminder.minute)) ?? Date()
            return "Every \(weekday) at \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    private func status(for reminder: ReminderRecord) -> String {
        if reminder.isReviewed {
            return "Reviewed"
        }
        if !reminder.isEnabled {
            return "Off"
        }
        if remindersPaused {
            return "Paused"
        }
        if reminderCoordinator.deliverySettings.permissionState == .denied {
            return "Blocked"
        }
        if reminderCoordinator.scheduledRequestIDs.contains(reminder.requestIdentifier) {
            return "Scheduled"
        }
        return "Saved"
    }

    private func statusColor(for reminder: ReminderRecord) -> Color {
        switch status(for: reminder) {
        case "Scheduled": return ForesightTheme.success
        case "Blocked": return ForesightTheme.warning
        default: return .secondary
        }
    }

    private func cancel(_ reminder: ReminderRecord) {
        do {
            try ReminderStore.cancel(reminder, in: modelContext)
            errorMessage = nil
            reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
