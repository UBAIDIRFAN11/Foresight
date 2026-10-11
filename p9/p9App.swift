//
//  p9App.swift
//  p9
//
//  Created by Ubaid on 29/9/2026.
//

// App entry point: registers SwiftData models, notification delegate, and shared
// reminder/router objects used across the tab-based UI.
import SwiftUI
import SwiftData

@main
struct p9App: App {
    @UIApplicationDelegateAdaptor(ForesightAppDelegate.self) private var appDelegate
    @StateObject private var router = AppRouter()
    @StateObject private var reminderCoordinator = ReminderCoordinator(notificationClient: SystemNotificationClient())
    private let modelContainer: ModelContainer

    init() {
        do {
            //creates SwiftData ModelContainer. it register: FinancialProfile, FinancialGoal, SavedDecision persistant models.
            let schema = Schema([FinancialProfile.self, FinancialGoal.self, SavedDecision.self, ReminderRecord.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])

            modelContainer.mainContext.autosaveEnabled = false
        } catch {
            fatalError("Unable to create Foresight model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .environmentObject(router)
                .environmentObject(reminderCoordinator)
                .task {
                    await MainActor.run {
                        NotificationRouteBridge.router = router
                    }
                }
        }
    }
}
