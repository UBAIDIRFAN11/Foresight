import SwiftUI

// Only explicit attempts increment attempt. Live input errors must not use this
// focused summary until editing finishes, so typing never causes repeated speech.
struct AccessibleErrorSummary: View {
    let message: String
    var fieldName: String? = nil
    let attempt: Int
    var recover: (() -> Void)? = nil
    @AccessibilityFocusState private var isErrorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fieldName.map { "\($0): \(message)" } ?? message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ForesightTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($isErrorFocused)
            if let fieldName, let recover {
                Button("Edit \(fieldName)", action: recover)
                    .buttonStyle(.bordered)
            }
        }
        .task(id: attempt) {
            // Let the summary enter the accessibility tree, including on an
            // identical repeated submission. Cancellation prevents stale focus.
            isErrorFocused = false
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            isErrorFocused = true
        }
    }
}
