import SwiftUI

// Central place for app colours and repeated layout styles.
enum ForesightTheme {
    static let background = Color("ForesightBackground")
    static let surface = Color("ForesightSurface")
    static let accent = Color.accentColor
    static let accentSoft = Color("ForesightAccentSoft")
    static let decorativeCoral = Color("ForesightDecorativeCoral")
    static let primaryButtonText = Color("ForesightPrimaryButtonText")
    static let success = Color("ForesightSuccess")
    static let warning = Color("ForesightWarning")
    static let savingsSurface = Color("ForesightSavingsSurface")
    static let savingsBorder = Color("ForesightSavingsBorder")
    static let border = decorativeCoral
}

struct ForesightCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(ForesightTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ForesightTheme.border, lineWidth: 1.5)
            }
    }
}

extension View {
    func foresightCard() -> some View {
        modifier(ForesightCardModifier())
    }

    func foresightReadableContent(maxWidth: CGFloat = 720) -> some View {
        modifier(ForesightReadableContentModifier(maxWidth: maxWidth))
    }

    func foresightPrimaryAction() -> some View {
        modifier(ForesightPrimaryActionModifier())
    }
}

struct ForesightReadableContentModifier: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        // Keep wide iPad/window layouts readable instead of stretching content.
        content
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical)
    }
}

struct ForesightPrimaryActionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(ForesightTheme.accent)
            .foregroundStyle(ForesightTheme.primaryButtonText)
    }
}

struct AdaptiveValueRow: View {
    let title: String
    let value: String

    var body: some View {
        // Try a compact horizontal row first, then stack vertically when text is large.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                titleText
                Spacer(minLength: 12)
                valueText
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                titleText
                valueText
                    .multilineTextAlignment(.leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var titleText: some View {
        Text(title)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .fontWeight(.semibold)
            .fixedSize(horizontal: false, vertical: true)
    }
}
