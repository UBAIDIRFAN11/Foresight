import SwiftUI

struct SettingsView: View {
    @Bindable var profile: FinancialProfile

    var body: some View {
        // Settings links to profile, reminders, privacy controls and app information.
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
                    PrivacyView(allowsErasure: true)
                } label: {
                    Label("Privacy & Data", systemImage: "hand.raised")
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
