import SwiftUI

//This file's job is to decide which major section of the app the user is looking at, provide the bottom tab bar, and coordinate movement between those sections.

struct MainTabView: View {
    private enum AppTab {
        case home
        case goals
        case simulator
        case history
        case settings
    }

    //financial profile is passed into the whole app, as several parts of the app need access to it.
    @Bindable var profile: FinancialProfile
    let duplicateProfileCount: Int
    @State private var selectedTab: AppTab = .home
    // When Home opens the simulator, this carries the focused goal across tabs.
    @State private var simulatorGoalID: UUID?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(
                    profile: profile,
                    duplicateProfileCount: duplicateProfileCount,
                    onEvaluatePurchase: { goalID in
                        //jump straight to Simulator with Home's focused goal selected.
                        simulatorGoalID = goalID
                        selectedTab = .simulator
                    }
                )
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(AppTab.home)

            NavigationStack {
                GoalsView(profile: profile)
            }
            .tabItem {
                Label("Goals", systemImage: "flag")
            }
            .tag(AppTab.goals)

            NavigationStack {
                SimulatorView(profile: profile, initialGoalID: simulatorGoalID) { _ in
                    //successful save should take the user to their saved history.
                    selectedTab = .history
                }
            }
            .tabItem {
                Label("Simulator", systemImage: "briefcase")
            }
            .tag(AppTab.simulator)

            NavigationStack {
                HistoryView()
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
    }
}
