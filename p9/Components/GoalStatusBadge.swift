import SwiftUI

struct GoalStatusBadge: View {
    let result: FinancialCalculationResult

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var title: String {
        switch result.status {
        case .fundedNow, .onTrack:
            "On Track"
        default:
            "At Risk"
        }
    }

    private var icon: String {
        switch result.status {
        case .fundedNow, .onTrack:
            "checkmark.circle"
        default:
            "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch result.status {
        case .fundedNow, .onTrack:
            ForesightTheme.success
        default:
            ForesightTheme.warning
        }
    }
}
