import Foundation
import SwiftData

@MainActor
enum FinancialProfilePolicy {
    static func fetchProfiles(in context: ModelContext) throws -> [FinancialProfile] {
        var descriptor = FetchDescriptor<FinancialProfile>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward)
            ]
        )
        descriptor.fetchLimit = 50
        return try context.fetch(descriptor)
    }

    static func selectedProfile(from profiles: [FinancialProfile]) -> FinancialProfile? {
        profiles.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.createdAt < $1.createdAt
        }.first
    }

    static func createProfileIfStillMissing(_ profile: FinancialProfile, in context: ModelContext) throws -> FinancialProfile {
        let existing = try fetchProfiles(in: context)
        if let selected = selectedProfile(from: existing) {
            return selected
        }
        context.insert(profile)
        do {
            try context.save()
            return profile
        } catch {
            context.rollback()
            throw error
        }
    }
}
