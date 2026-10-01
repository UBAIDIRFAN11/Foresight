import SwiftUI

enum ForesightTheme {
    static let background = Color("ForesightBackground")
    static let surface = Color("ForesightSurface")
    static let accent = Color.accentColor
    static let accentSoft = Color(red: 1.0, green: 0.88, blue: 0.82)
    static let success = Color(red: 0.31, green: 0.55, blue: 0.22)
    static let warning = Color(red: 0.93, green: 0.22, blue: 0.16)
    static let border = Color.accentColor.opacity(0.88)
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
}
