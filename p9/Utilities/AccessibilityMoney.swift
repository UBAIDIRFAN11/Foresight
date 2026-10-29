import Foundation

// Spoken presentation only. Never round-trip this text into financial calculations.
nonisolated enum AccessibilityMoney {
    static func currencyName(_ code: String) -> String {
        CurrencyDefinition.supported.first { $0.code == code }?.name ?? code
    }

    static func spoken(_ minorUnits: Int64, currencyCode: String, locale: Locale = .current) -> String {
        let currency = CurrencyDefinition.definition(for: currencyCode)
        let divisor = pow(Decimal(10), currency.minorUnitScale)
        let amount = Decimal(minorUnits) / divisor
        let number = amount.formatted(.number
            .precision(.fractionLength(currency.minorUnitScale))
            .locale(locale))
        return "\(number) \(currencyName(currencyCode))"
    }
}
