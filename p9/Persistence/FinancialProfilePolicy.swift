import Foundation
import SwiftData

//Handles profile selection, creation, focus preferences and goal deletion safely.

@MainActor
enum FinancialProfilePolicy {
    
    //this function is called when the user changes their preferred focus goal.
    static func saveFocusPreference(
        _ id: UUID?, for profile: FinancialProfile, in context: ModelContext,
        save: (() throws -> Void)? = nil
    ) throws {
        let previousID = profile.preferredFocusGoalID
        profile.preferredFocusGoalID = id
        do {
            if let save { try save() } else { try context.save() }
        } catch {
            context.rollback()
            profile.preferredFocusGoalID = previousID
            throw error
        }
    }

    static func deleteGoal(
        _ goal: FinancialGoal, in context: ModelContext,
        save: (() throws -> Void)? = nil
    ) throws {
        let profiles = try context.fetch(FetchDescriptor<FinancialProfile>())
        let previousPreferences = profiles.map { ($0, $0.preferredFocusGoalID) }
        do {
            for profile in profiles where profile.preferredFocusGoalID == goal.id {
                profile.preferredFocusGoalID = nil
            }
            
            //fetch and delete the associated reminders
            let reminders = try context.fetch(FetchDescriptor<ReminderRecord>())
            for reminder in reminders where reminder.kind == .goalCheckIn && reminder.sourceID == goal.id {
                context.delete(reminder)
            }
            context.delete(goal)
            if let save { try save() } else { try context.save() }
        } catch {
            context.rollback()
            // Restore values held by mounted views as well as rolling back storage.
            for (profile, id) in previousPreferences { profile.preferredFocusGoalID = id }
            throw error
        }
    }

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
        // If duplicate profiles exist, choose deterministically so app startup
        // always lands on the same profile.
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
            // Keep the context clean if creating the profile fails.
            context.rollback()
            throw error
        }
    }
}
