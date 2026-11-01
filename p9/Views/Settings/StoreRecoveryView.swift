import SwiftUI
import SwiftData

struct StoreRecoveryView: View {
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(ForesightTheme.accent)
                    .accessibilityHidden(true)
                Text("Your local data couldn’t be opened")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Foresight hasn’t deleted or reset your financial records.")
                Text("Check that your device has available storage, then try again. If the problem continues, restart the app or your device.")
                Button("Try Again", action: retry)
                    .foresightPrimaryAction()
                Text("Reinstalling is a last resort and may delete your local financial data. Contact support before removing the app if you need to keep your records.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let contactURL = PrivacyPolicy.contactURL {
                    Link("Contact Support", destination: contactURL)
                }
            }
            .foresightReadableContent()
        }
        .background(ForesightTheme.background)
    }
}

/// The app's single container is attached only after it opens successfully.
struct StoreRootView: View {
    @Bindable var loader: StoreLoader
    @Bindable var dataController: AppDataController
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var reminderCoordinator: ReminderCoordinator

    var body: some View {
        Group {
            switch loader.phase {
            case .idle, .loading:
                ProgressView("Opening Foresight")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ForesightTheme.background)
            case .failed:
                StoreRecoveryView { Task { await loader.load() } }
            case .ready(let container):
                readyContent(container: container)
                    .modelContainer(container)
                    .environment(dataController)
                    .task {
                        NotificationRouteBridge.router = router
                        NotificationActionBridge.shared.configure(context: container.mainContext, coordinator: reminderCoordinator)
                        await dataController.retryCleanup(coordinator: reminderCoordinator)
                    }
            }
        }
        .task { await loader.load() }
    }

    @ViewBuilder
    private func readyContent(container: ModelContainer) -> some View {
        switch dataController.phase {
        case .ready:
            ContentView()
                .id(dataController.generation)
                .alert("Privacy & Data", isPresented: Binding(
                    get: { dataController.notice != nil },
                    set: { if !$0 { dataController.notice = nil } }
                )) {
                    Button("OK") { dataController.notice = nil }
                } message: {
                    Text(dataController.notice ?? "")
                }
        case .erasing, .cleaningNotifications:
            ProgressView(dataController.phase == .erasing ? "Erasing local data" : "Clearing notifications")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ForesightTheme.background)
        case .cleanupRequired:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Notification cleanup needed")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(dataController.notice ?? "A previous reset was interrupted. Clear remaining notifications before continuing. This will not delete any additional financial records.")
                    Button("Try Again") {
                        Task { await dataController.retryCleanup(coordinator: reminderCoordinator) }
                    }
                    .foresightPrimaryAction()
                    Button("Open Notification Settings") { reminderCoordinator.openSystemSettings() }
                }
                .foresightReadableContent()
            }
            .background(ForesightTheme.background)
        }
    }
}
