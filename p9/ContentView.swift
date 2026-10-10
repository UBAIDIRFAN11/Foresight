//
//  ContentView.swift
//  p9
//
//  Created by Ubaid on 29/9/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var loadState: LoadState = .loading

    var body: some View {
        //ContentView decides whether the app should show onboarding,
        // the main tabs, or a loading/error state.
        Group {
            
            //if data is loading, show loading state
            switch loadState {
            case .loading:
                ProgressView("Loading Foresight")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ForesightTheme.background)
            //if loading fails, show error/retry screen
            case .failed(let message):
                ScrollView {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(ForesightTheme.warning)
                        Text("Foresight could not open your local data.")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry") {
                            loadProfile()
                        }
                        .foresightPrimaryAction()
                    }
                    .foresightReadableContent()
                    .frame(maxWidth: .infinity, minHeight: 400)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ForesightTheme.background)
                
            //if no profile exists, show onboarding screen
            case .needsProfile:
                FinancialProfileView(mode: .onboarding) { profile in
                    loadState = .ready(profile: profile, duplicateCount: 0)
                }
                
            //if profile already exists, open maintabview
            case .ready(let profile, let duplicateCount):
                MainTabView(profile: profile, duplicateProfileCount: duplicateCount)
            }
        }
        .task {
            loadProfile()
        }
    }

    private func loadProfile() {
        do {
            let profiles = try FinancialProfilePolicy.fetchProfiles(in: modelContext)
            // The app uses one selected profile. If duplicates exist, they are preserved
            // but the earliest profile is used for the main experience.
            if let selected = FinancialProfilePolicy.selectedProfile(from: profiles) {
                loadState = .ready(profile: selected, duplicateCount: max(profiles.count - 1, 0))
            } else {
                loadState = .needsProfile
            }
        } catch {
            loadState = .failed(message: error.localizedDescription)
        }
    }
}

private enum LoadState {
    case loading
    case failed(message: String)
    case needsProfile
    case ready(profile: FinancialProfile, duplicateCount: Int)
}

#Preview {
    ContentView()
        .modelContainer(for: [FinancialProfile.self, FinancialGoal.self, SavedDecision.self], inMemory: true)
}
