import Foundation

enum GoalPriority: Int, CaseIterable, Identifiable {
    case low = 0
    case medium = 1
    case high = 2

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

// Home's temporary selection is independent of the persisted default.
struct HomeFocusSelection {
    var selectedID: UUID?

    mutating func reconcile(sortedIDs: [UUID], preferredID: UUID?) {
        guard let selectedID, sortedIDs.contains(selectedID) else {
            applyDefault(sortedIDs: sortedIDs, preferredID: preferredID)
            return
        }
    }

    mutating func applyDefault(sortedIDs: [UUID], preferredID: UUID?) {
        selectedID = preferredID.flatMap { sortedIDs.contains($0) ? $0 : nil } ?? sortedIDs.first
    }
}
