import SwiftUI

struct SettingsView: View {
    @Bindable var profile: FinancialProfile

    var body: some View {
        // Settings links to profile editing plus placeholder/info screens.
        List {
            Section {
                NavigationLink {
                    ProfileView(profile: profile)
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
            .foregroundStyle(.primary)
        }
        .scrollContentBackground(.hidden)
        .background(ForesightTheme.background)
        .navigationTitle("Settings")
    }
}
