import Foundation

nonisolated struct ExchangeRate: Equatable, Sendable {
    let base: String
    let quote: String
    let rate: Decimal
    let observationDate: Date
    let fetchedAt: Date

    var rateString: String { NSDecimalNumber(decimal: rate).stringValue }
}

nonisolated struct PurchaseConversion: Equatable, Sendable {
    let originalAmountMinor: Int64
    let exchangeRate: ExchangeRate
}

nonisolated enum ExchangeRateError: LocalizedError, Equatable {
    case unavailablePair
    case service(Int)
    case invalidResponse
    case connection
    case timeout

    var errorDescription: String? {
        switch self {
        case .unavailablePair: "This currency pair is unavailable. Choose another currency or retry."
        case .service(let status): "The exchange-rate service returned HTTP \(status). Please retry."
        case .invalidResponse: "The exchange-rate service returned invalid data. Please retry."
        case .connection: "Could not connect to the exchange-rate service. Check your connection and retry."
        case .timeout: "The exchange-rate request timed out. Please retry."
        }
    }
}

nonisolated struct FrankfurterClient: Sendable {
    let session: URLSession
    var now: @Sendable () -> Date = Date.init

    init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    func fetchRate(from base: String, to quote: String) async throws -> ExchangeRate? {
        guard CurrencyDefinition.supported.contains(where: { $0.code == base }),
              CurrencyDefinition.supported.contains(where: { $0.code == quote }) else {
            throw ExchangeRateError.unavailablePair
        }
        guard base != quote else { return nil }
        guard let url = URL(string: "https://api.frankfurter.dev/v2/rate/\(base)/\(quote)") else {
            throw ExchangeRateError.invalidResponse
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? ExchangeRateError.timeout : ExchangeRateError.connection
        } catch {
            throw ExchangeRateError.connection
        }
        guard let http = response as? HTTPURLResponse else { throw ExchangeRateError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 || http.statusCode == 422 { throw ExchangeRateError.unavailablePair }
            throw ExchangeRateError.service(http.statusCode)
        }
        let value: RateResponse
        do { value = try JSONDecoder().decode(RateResponse.self, from: data) }
        catch { throw ExchangeRateError.invalidResponse }
        let fetchedAt = now()
        guard value.base == base, value.quote == quote,
              !value.rate.isNaN, value.rate > 0,
              let date = Self.observationDay(value.date),
              date <= FinancialCalendar.utcNoon(for: fetchedAt, in: FinancialCalendar.gregorianUTC) else {
            throw ExchangeRateError.invalidResponse
        }
        return ExchangeRate(base: base, quote: quote, rate: value.rate, observationDate: date, fetchedAt: fetchedAt)
    }

    private static func observationDay(_ text: String) -> Date? {
        guard text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
        let fields = text.split(separator: "-").compactMap { Int($0) }
        guard fields.count == 3, fields[0] > 0, (1...12).contains(fields[1]), (1...31).contains(fields[2]) else { return nil }
        let date = FinancialCalendar.utcNoon(year: fields[0], month: fields[1], day: fields[2])
        let components = FinancialCalendar.civilComponents(date)
        guard components.year == fields[0], components.month == fields[1], components.day == fields[2] else { return nil }
        return date
    }

    private struct RateResponse: Decodable {
        let date: String
        let base: String
        let quote: String
        let rate: Decimal
    }
}
