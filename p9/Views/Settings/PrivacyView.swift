import SwiftUI
import SwiftData

struct PrivacyView: View {
    var allowsErasure = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppDataController.self) private var dataController
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var reminderCoordinator: ReminderCoordinator
    @State private var confirmsErasure = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy & Data")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Effective \(PrivacyPolicy.effectiveDate)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if allowsErasure {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Manage local data")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text("Remove your financial profile, goals, saved history and reminders from this app.")
                        Button("Erase All Data", role: .destructive) { confirmsErasure = true }
                            .buttonStyle(.bordered)
                            .accessibilityHint("Opens a confirmation. Nothing is erased until you confirm.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foresightCard()
                }
                ForEach(PrivacyPolicy.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(section.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let frankfurterURL = URL(string: "https://frankfurter.dev/") {
                    Link("Frankfurter Privacy Information", destination: frankfurterURL)
                }
                if let contactURL = PrivacyPolicy.contactURL {
                    Link("Contact Privacy Support", destination: contactURL)
                }
            }
            .foresightReadableContent()
        }
        .background(ForesightTheme.background)
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !allowsErasure {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert("Erase all local data?", isPresented: $confirmsErasure) {
            Button("Cancel", role: .cancel) {}
            Button("Erase All Data", role: .destructive) {
                Task {
                    await dataController.erase(in: modelContext, coordinator: reminderCoordinator, router: router)
                }
            }
        } message: {
            Text("This permanently removes your profile, every goal, saved history, reminder settings and local app records, and clears pending and delivered reminders. This cannot be undone. Existing device backups are not erased.")
        }
    }
}
