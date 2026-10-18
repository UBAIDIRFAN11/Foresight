import Foundation

// Application-level checks applied to the complete model response before any prose is shown.
// The prose may quote figures, but every number must be one Foresight supplied in the request:
// the model can explain verified values but cannot introduce or calculate new ones.
// An unsuitable response is rejected whole, never edited.
nonisolated enum FinancialInsightValidator {
    static let summaryLimit = 450
    static let considerationLimit = 300
    static let combinedLimit = 700

    // Clearly affirmative certainty or advice phrases, matched case-insensitively.
    // Hedges such as "is not guaranteed" remain acceptable.
    static let prohibitedPhrases = [
        "will definitely", "definitely will", "guarantees success", "guarantees you",
        "is guaranteed", "are guaranteed", "risk-free", "risk free",
        "you should buy", "you should not buy", "you shouldn't buy", "go ahead and buy", "safe to buy",
        // Explicit behaviour instructions: Foresight's next step is chosen from scenario-specific options instead.
        "you need to increase", "you need to decrease", "you need to reduce", "you need to cut",
        "you should increase", "you should decrease", "you should reduce", "you should cut", "cut back"
    ]

    // Spelled-out quantities would bypass the figure check, so prose must use the supplied digits.
    static let numberWords: Set<String> = [
        "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
        "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "million", "billion", "dozen"
    ]

    static func validate(_ generated: GeneratedFinancialInsight,
                         for request: FinancialInsightRequest) throws -> ValidatedFinancialInsight {
        let summary = generated.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let consideration = generated.keyConsideration.trimmingCharacters(in: .whitespacesAndNewlines)
        let figures = VerifiedFigures(request: request)
        guard !summary.isEmpty, !consideration.isEmpty,
              summary.count <= summaryLimit,
              consideration.count <= considerationLimit,
              summary.count + consideration.count <= combinedLimit,
              summary.caseInsensitiveCompare(consideration) != .orderedSame,
              isAcceptableProse(summary, figures: figures),
              isAcceptableProse(consideration, figures: figures),
              let topSuggestion = request.suggestions.first else {
            throw FinancialInsightFailure.unusableResponse
        }
        // The step text is always Foresight-authored. If the model picks a step outside this
        // scenario's options, Foresight's most relevant suggestion is used instead of
        // discarding otherwise valid prose; generated text itself is never altered.
        let suggestion = request.suggestions.first { $0.step == generated.nextStep } ?? topSuggestion
        return ValidatedFinancialInsight(summary: summary, keyConsideration: consideration, suggestion: suggestion)
    }

    static func isAcceptableProse(_ text: String, figures: VerifiedFigures) -> Bool {
        // Only ASCII digits can be checked against the supplied figures.
        guard !text.unicodeScalars.contains(where: { $0.properties.numericType == .decimal && !$0.isASCII }) else { return false }
        let lowered = text.lowercased()
        // URLs and web addresses.
        guard !lowered.contains("http://"), !lowered.contains("https://"), !lowered.contains("www.") else { return false }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return false
        }
        guard !prohibitedPhrases.contains(where: { lowered.contains($0) }) else { return false }
        let words = lowered.split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard !words.contains(where: { numberWords.contains($0) }) else { return false }
        // Every quoted number must be grounded in a verified figure.
        return NumberToken.tokens(in: text).allSatisfy(figures.contains)
    }
}

// A number found in text, with whether it was written as money or as a percentage.
nonisolated struct NumberToken: Equatable, Sendable {
    enum Kind: Sendable { case money, percent, plain }
    let value: Decimal
    let kind: Kind

    // Matches "$3,000.00", "A$3,000", "¥1,000", "92%", "4,585", "2027" and "1.5".
    private static let pattern = try? NSRegularExpression(pattern: #"(\p{Sc}\s?)?(\d+(?:,\d{3})*(?:\.\d+)?)(\s?%)?"#)

    static func tokens(in text: String) -> [NumberToken] {
        guard let pattern else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            guard let numberRange = Range(match.range(at: 2), in: text),
                  let value = Decimal(string: text[numberRange].replacingOccurrences(of: ",", with: ""),
                                      locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            let kind: Kind = match.range(at: 1).location != NSNotFound ? .money
                : match.range(at: 3).location != NSNotFound ? .percent : .plain
            return NumberToken(value: value, kind: kind)
        }
    }
}

// The set of numbers a response may quote: every figure Foresight placed in the prompt.
nonisolated struct VerifiedFigures: Sendable {
    private var money: Set<Decimal> = []
    private var percent: Set<Decimal> = []
    private var all: Set<Decimal> = []

    init(request: FinancialInsightRequest) {
        let sources = request.facts.flatMap { [$0.label, $0.value] } + request.relationships
            + [request.status, request.focus, request.considerationFocus]
        for token in sources.flatMap(NumberToken.tokens) {
            all.insert(token.value)
            switch token.kind {
            case .money:
                money.insert(token.value)
                // Quoting "$1,833" for a verified "$1,833.33" is accepted; it is a rounding of a supplied figure.
                all.insert(Self.rounded(token.value, mode: .plain))
                all.insert(Self.rounded(token.value, mode: .down))
            case .percent: percent.insert(token.value)
            case .plain: break
            }
        }
    }

    func contains(_ token: NumberToken) -> Bool {
        switch token.kind {
        case .money:
            money.contains(token.value) || money.contains { Self.rounded($0, mode: .plain) == token.value || Self.rounded($0, mode: .down) == token.value }
        case .percent:
            percent.contains(token.value)
        case .plain:
            all.contains(token.value)
        }
    }

    private static func rounded(_ value: Decimal, mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 0, mode)
        return output
    }
}
