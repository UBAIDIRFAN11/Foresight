import Foundation

//converts foreign currency into preferred currency using exchange rate data supplied by Frankfurter API

nonisolated enum CurrencyConversion {
    
    //sourceMinor: purchase amount is orig. currency's minor units
    //source: orig. currency def
    //destination: profile preferred currency def
    //rate: exchange rate returned by frankfurter
    //availableSavings: user's savings in their profile's preferred currency minor units
    static func convert(
        _ sourceMinor: Int64, from source: CurrencyDefinition, to destination: CurrencyDefinition,
        rate: Decimal, availableSavings: Int64
    ) throws -> Int64 {
        
        //validate amount and rate
        guard sourceMinor > 0 else { throw PurchaseImpactError.invalidPurchaseAmount }
        guard !rate.isNaN, rate > 0 else { throw ExchangeRateError.invalidResponse }
        
        //perform the conversion
        var sourceValue = Decimal(sourceMinor)
        var sourceScale = Decimal(MoneyFormatting.pow10(source.minorUnitScale))
        var destinationScale = Decimal(MoneyFormatting.pow10(destination.minorUnitScale))
        var rate = rate
        var major = Decimal(), converted = Decimal(), minor = Decimal()
        
        //converted units = source units * rate
        guard NSDecimalDivide(&major, &sourceValue, &sourceScale, .plain) == .noError,
              NSDecimalMultiply(&converted, &major, &rate, .plain) == .noError,
              NSDecimalMultiply(&minor, &converted, &destinationScale, .plain) == .noError else {
            throw PurchaseImpactError.arithmeticOverflow
        }
        // Round exactly once, at the destination minor unit. Positive halves round up.
        var rounded = Decimal()
        NSDecimalRound(&rounded, &minor, 0, .plain)
        guard !rounded.isNaN, rounded <= Decimal(Int64.max) else { throw PurchaseImpactError.arithmeticOverflow }
        guard rounded >= 1 else { throw PurchaseImpactError.invalidPurchaseAmount }
        
        //affordability check is performed using the converted purcahse amount and the user's savings in the same currency
        guard rounded <= Decimal(availableSavings) else { throw PurchaseImpactError.insufficientSavings }
        
        //converted amount is returned at int64 minor units, ready for the purchase-impact calculation
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    // Conservative bounds avoid fractional-minor-unit endpoints. Exact entry still
    // accepts affordable values outside this convenience slider's narrower range.
    static func sliderBounds(
        from source: CurrencyDefinition, to destination: CurrencyDefinition,
        rate: Decimal, availableSavings: Int64
    ) -> ClosedRange<Int64>? {
        guard availableSavings > 0, !rate.isNaN, rate > 0 else { return nil }
        let factor = rate * Decimal(MoneyFormatting.pow10(destination.minorUnitScale)) / Decimal(MoneyFormatting.pow10(source.minorUnitScale))
        guard !factor.isNaN, factor > 0 else { return nil }
        var lower = Decimal(1) / factor
        var upper = Decimal(availableSavings) / factor
        guard !lower.isNaN, !upper.isNaN else { return nil }
        var roundedLower = Decimal(), roundedUpper = Decimal()
        NSDecimalRound(&roundedLower, &lower, 0, .up)
        NSDecimalRound(&roundedUpper, &upper, 0, .down)
        roundedLower = max(1, roundedLower)
        roundedUpper = min(Decimal(Int64.max), roundedUpper)
        guard roundedLower <= roundedUpper else { return nil }
        let minimum = NSDecimalNumber(decimal: roundedLower).int64Value
        let maximum = NSDecimalNumber(decimal: roundedUpper).int64Value
        guard (try? convert(minimum, from: source, to: destination, rate: rate, availableSavings: availableSavings)) != nil,
              (try? convert(maximum, from: source, to: destination, rate: rate, availableSavings: availableSavings)) != nil else { return nil }
        return minimum...maximum
    }
}
