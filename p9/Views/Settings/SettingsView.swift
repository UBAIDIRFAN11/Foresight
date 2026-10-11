import SwiftUI

struct SettingsView: View {
    @Bindable var profile: FinancialProfile

    var body: some View {
        // Settings links to profile editing plus placeholder/info screens.
        List {
            Section {
                NavigationLink {
                    FinancialProfileView(mode: .editing(profile))
                } label: {
                    Label("Financial Profile", systemImage: "person.text.rectangle")
                }

                NavigationLink {
                    ProfileView()
                } label: {
                    Label("Profile", systemImage: "person.crop.circle")
                }

                NavigationLink {
                    RemindersSettingsView()
                } label: {
                    Label("Reminders", systemImage: "bell")
                }

                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .foregroundStyle(.secondary)
        }
        .scrollContentBackground(.hidden)
        .background(ForesightTheme.background)
        .navigationTitle("Settings")
    }
}
