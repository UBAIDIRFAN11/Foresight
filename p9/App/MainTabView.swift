import SwiftUI

struct MainTabView: View {
    private enum AppTab {
        case home
        case goals
        case simulator
        case history
        case settings
    }

    @Bindable var profile: FinancialProfile
    let duplicateProfileCount: Int
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(
                    profile: profile,
                    duplicateProfileCount: duplicateProfileCount,
                    onEvaluatePurchase: {
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
                SimulatorView(profile: profile)
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
