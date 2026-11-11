import SwiftUI
import SwiftData

//Decides what the user sees while the database opens, and handles data-reset states.

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
            
            //show loading state when in idle/loading
            switch loader.phase {
            case .idle, .loading:
                ProgressView("Opening Foresight")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ForesightTheme.background)
            
            //show StoreRecoveryView when failed to load db, with a retry btn.
            case .failed:
                StoreRecoveryView { Task { await loader.load() } }
                
            //The actual app content, provided data cleanup isn't in progress
            case .ready(let container):
                readyContent(container: container)
                    .modelContainer(container) //gives the interface access to SwiftData
                    .environment(dataController) //make data controller available to child views
                    .task {
                        //connect notification navigation
                        NotificationRouteBridge.router = router
                        
                        //connect notif actions to db
                        NotificationActionBridge.shared.configure(context: container.mainContext, coordinator: reminderCoordinator)
                        await dataController.retryCleanup(coordinator: reminderCoordinator)
                    }
            }
        }
        .task { await loader.load() }
    }

    
    //handles the data controller's states: normal operation, erasing data, cleaning notifications, or requiring another cleanup attempt.
    @ViewBuilder
    private func readyContent(container: ModelContainer) -> some View {
        
        //disp based on current state
        switch dataController.phase {
            
        //normal state: show the app
        case .ready:
            
            //disp app's normal interface
            ContentView()
                .id(dataController.generation)
            
                //create alert, connect its visibility to dataController.notice
                .alert("Privacy & Data", isPresented: Binding(
                    
                    //returns true if notice exists, making the alert appear
                    get: { dataController.notice != nil },
                    
                    //when alert is dismissed ($0 becomes false), clear notice by setting it to nil
                    set: { if !$0 { dataController.notice = nil } }
                )) {
                    Button("OK") { dataController.notice = nil }
                } message: {
                    Text(dataController.notice ?? "")
                }
            
        //disp loading indicator with text (text depends on which state)
        case .erasing, .cleaningNotifications:
            ProgressView(dataController.phase == .erasing ? "Erasing local data" : "Clearing notifications")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ForesightTheme.background)
            
        //disp recovery screen when notification cleanup is incomplete.
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
