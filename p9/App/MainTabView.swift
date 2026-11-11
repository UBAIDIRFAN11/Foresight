import SwiftUI

//This file's job is to decide which major section of the app the user is looking at, provide the bottom tab bar, and coordinate movement between those sections. Also binds tab/navigation state to AppRouter so reminders can open saved decisions, goals, or simulator prefill requests.

struct MainTabView: View {
    enum AppTab {
        case home
        case goals
        case simulator
        case history
        case settings
    }

    //financial profile is passed into the whole app, as several parts of the app need access to it.
    @Bindable var profile: FinancialProfile
    let duplicateProfileCount: Int
    let evaluationDay: Date
    @EnvironmentObject private var router: AppRouter
    // When Home opens the simulator, this carries the focused goal across tabs.
    @State private var simulatorGoalID: UUID?
    @State private var simulatorGoalRequestID: UUID?
    // Confirmation for the most recent successful save; cleared when History moves away from it.
    @State private var savedNotice: SavedDecisionNotice?

    var body: some View {
        
        //create bottom tab bar
        TabView(selection: $router.selectedTab) {
            NavigationStack {
                HomeView(
                    profile: profile,
                    duplicateProfileCount: duplicateProfileCount,
                    evaluationDay: evaluationDay,
                    onEvaluatePurchase: { goalID in
                        //jump straight to Simulator with Home's focused goal selected.
                        simulatorGoalID = goalID
                        simulatorGoalRequestID = UUID()
                        router.selectedTab = .simulator
                    }
                )
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(AppTab.home)

            NavigationStack(path: $router.goalPath) {
                GoalsView(profile: profile, evaluationDay: evaluationDay)
            }
            .tabItem {
                Label("Goals", systemImage: "flag")
            }
            .tag(AppTab.goals)

            NavigationStack {
                SimulatorView(
                    profile: profile,
                    evaluationDay: evaluationDay,
                    initialGoalID: simulatorGoalID,
                    goalSelectionRequestID: simulatorGoalRequestID,
                    prefill: router.simulatorPrefill,
                    onPrefillConsumed: { token in
                        router.consumeSimulatorPrefill(token: token)
                    }
                ) { decision in
                    // Open the record that was just saved, replacing any older History detail,
                    // and confirm the save on that screen.
                    router.openSavedDecision(id: decision.evaluationID)
                    let notice = SavedDecisionNotice(decision: decision)
                    savedNotice = notice
                    AccessibilityNotification.Announcement(notice.message).post()
                }
            }
            .tabItem {
                Label("Simulator", systemImage: "briefcase")
            }
            .tag(AppTab.simulator)

            NavigationStack(path: $router.historyPath) {
                HistoryView(savedNotice: visibleSavedNotice, onDismissSavedNotice: { savedNotice = nil })
            }
            .tabItem {
                Label("History", systemImage: "folder")
            }
            .tag(AppTab.history)

            NavigationStack {
                SettingsView(profile: profile)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .tint(ForesightTheme.accent)
        .onChange(of: router.selectedTab) { _, _ in clearSavedNoticeIfNotApplicable() }
        .onChange(of: router.historyPath) { _, _ in clearSavedNoticeIfNotApplicable() }
    }

    private var visibleSavedNotice: SavedDecisionNotice? {
        guard let savedNotice, savedNotice.applies(selectedTab: router.selectedTab, historyPath: router.historyPath) else { return nil }
        return savedNotice
    }

    private func clearSavedNoticeIfNotApplicable() {
        // Leaving History or navigating away from the saved record ends the confirmation.
        if let savedNotice, !savedNotice.applies(selectedTab: router.selectedTab, historyPath: router.historyPath) {
            self.savedNotice = nil
        }
    }
}
