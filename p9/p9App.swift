//
//  p9App.swift
//  p9
//
//  Created by Ubaid on 29/9/2026.
//

import SwiftUI
import SwiftData

@main
struct p9App: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([FinancialProfile.self, FinancialGoal.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            modelContainer.mainContext.autosaveEnabled = false
        } catch {
            fatalError("Unable to create Foresight model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}
