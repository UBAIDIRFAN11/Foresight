import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class StoreLoader {
    enum Phase {
        case idle
        case loading
        case ready(ModelContainer)
        case failed
    }

    private(set) var phase: Phase = .idle
    private let factory: @MainActor () throws -> ModelContainer

    init(factory: (@MainActor () throws -> ModelContainer)? = nil) {
        self.factory = factory ?? StoreLoader.makeContainer
    }

    func load() async {
        switch phase {
        case .loading, .ready: return
        case .idle, .failed: break
        }
        phase = .loading
        // Give SwiftUI an opportunity to display progress before opening the store.
        await Task.yield()
        do {
            let container = try factory()
            container.mainContext.autosaveEnabled = false
            phase = .ready(container)
        } catch {
            // Never delete the store, expose its path, or log financial data.
            phase = .failed
        }
    }

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([FinancialProfile.self, FinancialGoal.self, SavedDecision.self, ReminderRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Launch-only fault simulation; absent from Release builds.
    static func launchFactory() -> @MainActor () throws -> ModelContainer {
#if DEBUG
        var failuresRemaining = ProcessInfo.processInfo.arguments.contains("-HD2FailStoreOnce") ? 1 : 0
        return {
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw CocoaError(.fileReadUnknown)
            }
            return try makeContainer()
        }
#else
        return makeContainer
#endif
    }
}
