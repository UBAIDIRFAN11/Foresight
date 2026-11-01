import Foundation

//defines supported currencies and their decimal precision.

nonisolated struct CurrencyDefinition: Identifiable, Hashable, Sendable {
    
    //the currency's 3-letter identifier, e.g. "AUD"
    let code: String
    
    //human readable name (needed for disp in currency picker)
    let name: String
    
    //no. d.p supported by that currency
    let minorUnitScale: Int
    
    //determines formatting convention used when disp that currency
    let localeIdentifier: String

    var id: String { code }

    //e.g. "Australian Dollar (AUD)"
    var displayName: String { "\(name) (\(code))" }

    //simulator uses this arr to populate currency picker
    static let supported: [CurrencyDefinition] = [
        .init(code: "AUD", name: "Australian Dollar", minorUnitScale: 2, localeIdentifier: "en_AU"),
        .init(code: "USD", name: "US Dollar", minorUnitScale: 2, localeIdentifier: "en_US"),
        .init(code: "EUR", name: "Euro", minorUnitScale: 2, localeIdentifier: "en_IE"),
        .init(code: "GBP", name: "British Pound", minorUnitScale: 2, localeIdentifier: "en_GB"),
        .init(code: "NZD", name: "New Zealand Dollar", minorUnitScale: 2, localeIdentifier: "en_NZ"),
        .init(code: "CAD", name: "Canadian Dollar", minorUnitScale: 2, localeIdentifier: "en_CA"),
        .init(code: "JPY", name: "Japanese Yen", minorUnitScale: 0, localeIdentifier: "ja_JP")
    ]

    
    //searches for matching currency definition, falls back to first supported currency when no match found.
    static func definition(for code: String) -> CurrencyDefinition {
        supported.first { $0.code == code } ?? supported[0]
    }
}
