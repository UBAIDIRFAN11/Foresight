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
        Group {
            switch loadState {
            case .loading:
                ProgressView("Loading Foresight")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ForesightTheme.background)
            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(ForesightTheme.warning)
                    Text("Foresight could not open your local data.")
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        loadProfile()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ForesightTheme.background)
            case .needsProfile:
                FinancialProfileView(mode: .onboarding) { profile in
                    loadState = .ready(profile: profile, duplicateCount: 0)
                }
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
        .modelContainer(for: [FinancialProfile.self, FinancialGoal.self], inMemory: true)
}
