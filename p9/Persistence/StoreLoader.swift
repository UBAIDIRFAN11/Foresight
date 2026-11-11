import Foundation
import Observation
import SwiftData

//this is used to open the local SwiftData database safely

@MainActor
@Observable
final class StoreLoader {
    
    //enum to define the possible loading states
    enum Phase {
        case idle //hasnt started loading
        case loading //currently loading
        case ready(ModelContainer) //successfully loaded
        case failed //could not load
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
        
        //change state to loading,
        phase = .loading
        
        //attempt to create db container, then change state to ready or failed
        await Task.yield()
        do {
            let container = try factory()
            
            //writes must be explicitly saved
            container.mainContext.autosaveEnabled = false
            
            phase = .ready(container)
        } catch {
            phase = .failed
        }
    }

    //configures the persistent db to store the 4 model types
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
