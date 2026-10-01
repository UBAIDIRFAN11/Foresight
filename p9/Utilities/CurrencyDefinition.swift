import Foundation

nonisolated struct CurrencyDefinition: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let minorUnitScale: Int
    let localeIdentifier: String

    var id: String { code }

    static let supported: [CurrencyDefinition] = [
        .init(code: "AUD", name: "Australian Dollar", minorUnitScale: 2, localeIdentifier: "en_AU"),
        .init(code: "USD", name: "US Dollar", minorUnitScale: 2, localeIdentifier: "en_US"),
        .init(code: "EUR", name: "Euro", minorUnitScale: 2, localeIdentifier: "en_IE"),
        .init(code: "GBP", name: "British Pound", minorUnitScale: 2, localeIdentifier: "en_GB"),
        .init(code: "NZD", name: "New Zealand Dollar", minorUnitScale: 2, localeIdentifier: "en_NZ"),
        .init(code: "CAD", name: "Canadian Dollar", minorUnitScale: 2, localeIdentifier: "en_CA"),
        .init(code: "JPY", name: "Japanese Yen", minorUnitScale: 0, localeIdentifier: "ja_JP")
    ]

    static func definition(for code: String) -> CurrencyDefinition {
        supported.first { $0.code == code } ?? supported[0]
    }
}
