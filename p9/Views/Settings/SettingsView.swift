import SwiftUI

struct SettingsView: View {
    @Bindable var profile: FinancialProfile

    var body: some View {
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
