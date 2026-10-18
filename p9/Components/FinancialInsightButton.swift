import SwiftUI

// Consistent secondary action for opening an AI explanation. Presentation only:
// it performs no model calls and no financial logic.
struct FinancialInsightButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "sparkles")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(ForesightTheme.accent)
        .disabled(!isEnabled)
        .accessibilityHint("Opens an on-device AI explanation of this result.")
    }
}
