//
//  ContentView.swift
//  p9
//
//  Created by Ubaid on 29/9/2026.
//

// Loads the local financial profile and triggers reminder reconciliation when
// the app becomes active or system time-zone state changes.
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var reminderCoordinator: ReminderCoordinator
    @AppStorage("remindersPaused") private var remindersPaused = false
    @Environment(\.scenePhase) private var scenePhase
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
            reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused)
            await applyPendingNotificationActions()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            loadProfile()
            reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused)
            Task {
                await applyPendingNotificationActions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused)
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

    private func applyPendingNotificationActions() async {
        let payloads = await NotificationActionBridge.shared.consumePendingPayloads()
        for payload in payloads {
            guard payload.kind == .purchaseReview else { continue }
            do {
                guard let record = try ReminderStore.existing(kind: .purchaseReview, sourceID: payload.sourceID, in: modelContext),
                      record.scheduleRevision == payload.revision else {
                    continue
                }
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86_400)
                record.deliveryDate = tomorrow
                record.isEnabled = true
                record.reviewedAt = nil
                record.scheduleRevision = UUID()
                record.updatedAt = Date()
                try modelContext.save()
                reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused, requestAuthorizationIfNeeded: true)
            } catch {
                modelContext.rollback()
            }
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
        .modelContainer(for: [FinancialProfile.self, FinancialGoal.self, SavedDecision.self, ReminderRecord.self], inMemory: true)
}
