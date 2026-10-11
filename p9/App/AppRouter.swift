// Coordinates cross-tab navigation for reminders and saved-decision re-evaluation.
// Notification taps use this router to open the correct History, Goal, or Simulator flow.
import Foundation
import Combine

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: MainTabView.AppTab = .home
    @Published var goalPath: [UUID] = []
    @Published var historyPath: [UUID] = []
    @Published var simulatorPrefill: SimulatorPrefill?

    private var handledNotificationTokens = Set<String>()

    func openSavedDecision(id: UUID, revision: UUID? = nil) {
        let token = "decision-\(id.uuidString)-\(revision?.uuidString ?? "default")"
        guard handledNotificationTokens.insert(token).inserted else { return }
        selectedTab = .history
        historyPath = [id]
    }

    func openGoal(id: UUID, revision: UUID? = nil) {
        let token = "goal-\(id.uuidString)-\(revision?.uuidString ?? "default")"
        guard handledNotificationTokens.insert(token).inserted else { return }
        selectedTab = .goals
        goalPath = [id]
    }

    func prefillSimulator(_ prefill: SimulatorPrefill) {
        selectedTab = .simulator
        simulatorPrefill = prefill
    }

    func consumeSimulatorPrefill(token: UUID) {
        guard simulatorPrefill?.token == token else { return }
        simulatorPrefill = nil
    }
}

struct SimulatorPrefill: Equatable {
    let token: UUID
    let purchaseName: String
    let amountMinor: Int64
    let currencyCode: String
    let preferredGoalID: UUID?

    init(decision: SavedDecision) {
        token = UUID()
        purchaseName = decision.purchaseName
        amountMinor = decision.purchaseAmountMinor
        currencyCode = decision.currencyCode
        preferredGoalID = decision.goalID
    }
}

enum NotificationRouteBridge {
    @MainActor static weak var router: AppRouter?

    @MainActor
    static func route(kind: ReminderKind, sourceID: UUID, revision: UUID?) {
        switch kind {
        case .purchaseReview:
            router?.openSavedDecision(id: sourceID, revision: revision)
        case .goalCheckIn:
            router?.openGoal(id: sourceID, revision: revision)
        }
    }
}
