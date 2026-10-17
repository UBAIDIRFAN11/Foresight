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


    func openSavedDecision(id: UUID, revision: UUID? = nil) {
        selectedTab = .history
        historyPath = [id]
    }

    func openGoal(id: UUID, revision: UUID? = nil) {
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
        amountMinor = decision.originalPurchaseAmountMinor ?? decision.purchaseAmountMinor
        currencyCode = decision.originalPurchaseCurrencyCode ?? decision.currencyCode
        preferredGoalID = decision.goalID
    }
}

enum NotificationRouteBridge {
    @MainActor static weak var router: AppRouter? {
        didSet {
            if router != nil, let route = pendingRoute {
                pendingRoute = nil
                self.route(kind: route.kind, sourceID: route.sourceID, revision: route.revision)
            }
        }
    }
    @MainActor private static var pendingRoute: (kind: ReminderKind, sourceID: UUID, revision: UUID?)?

    @MainActor
    static func route(kind: ReminderKind, sourceID: UUID, revision: UUID?) {
        guard router != nil else {
            pendingRoute = (kind, sourceID, revision)
            return
        }
        switch kind {
        case .purchaseReview:
            router?.openSavedDecision(id: sourceID, revision: revision)
        case .goalCheckIn:
            router?.openGoal(id: sourceID, revision: revision)
        }
    }
}
