import Foundation

nonisolated enum MoneyParseError: LocalizedError, Equatable {
    case empty
    case containsSymbolOrGrouping
    case malformed
    case excessivePrecision
    case negative
    case overflow

    var errorDescription: String? {
        switch self {
        case .empty: "Enter an amount."
        case .containsSymbolOrGrouping: "Use digits and one decimal separator only."
        case .malformed: "Enter a valid amount."
        case .excessivePrecision: "Too many decimal places for this currency."
        case .negative: "Amounts cannot be negative."
        case .overflow: "Amount is too large."
        }
    }
}

nonisolated enum MoneyFormatting {
    static func parseMinorUnits(_ text: String, currency: CurrencyDefinition) throws -> Int64 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MoneyParseError.empty }
        guard !trimmed.contains("-") else { throw MoneyParseError.negative }
        guard trimmed.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else {
            throw MoneyParseError.containsSymbolOrGrouping
        }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { throw MoneyParseError.malformed }
        guard let whole = Int64(parts[0]) else { throw MoneyParseError.overflow }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= currency.minorUnitScale else { throw MoneyParseError.excessivePrecision }

        let scale = pow10(currency.minorUnitScale)
        let wholeResult = whole.multipliedReportingOverflow(by: scale)
        guard !wholeResult.overflow else { throw MoneyParseError.overflow }
        let wholeMinor = wholeResult.partialValue
        let paddedFraction = fraction.padding(toLength: currency.minorUnitScale, withPad: "0", startingAt: 0)
        let fractionMinor = Int64(paddedFraction).map { $0 } ?? 0
        let total = wholeMinor.addingReportingOverflow(fractionMinor)
        guard !total.overflow else { throw MoneyParseError.overflow }
        return total.partialValue
    }

    static func display(_ minorUnits: Int64, currencyCode: String, includeCode: Bool = false) -> String {
        let currency = CurrencyDefinition.definition(for: currencyCode)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.code
        formatter.locale = Locale(identifier: currency.localeIdentifier)
        formatter.minimumFractionDigits = currency.minorUnitScale
        formatter.maximumFractionDigits = currency.minorUnitScale
        let divisor = Decimal(pow10(currency.minorUnitScale))
        let amount = Decimal(minorUnits) / divisor
        let number = NSDecimalNumber(decimal: amount)
        let formatted = formatter.string(from: number) ?? "\(currency.code) \(number)"
        return includeCode ? "\(formatted) \(currency.code)" : formatted
    }

    static func editableText(_ minorUnits: Int64, currencyCode: String) -> String {
        let currency = CurrencyDefinition.definition(for: currencyCode)
        if currency.minorUnitScale == 0 {
            return String(minorUnits)
        }
        let scale = pow10(currency.minorUnitScale)
        let whole = minorUnits / scale
        let fraction = abs(minorUnits % scale)
        return "\(whole)." + String(format: "%0\(currency.minorUnitScale)lld", fraction)
    }

    static func minorUnitsToMajorString(_ minorUnits: Int64, currencyCode: String) -> String {
        editableText(minorUnits, currencyCode: currencyCode)
    }

    static func pow10(_ exponent: Int) -> Int64 {
        guard exponent > 0 else { return 1 }
        return (0..<exponent).reduce(Int64(1)) { result, _ in result * 10 }
    }
}
