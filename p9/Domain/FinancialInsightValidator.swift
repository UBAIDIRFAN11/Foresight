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

    // "will" plus an outcome verb in a sentence about the goal's future (target, deadline, balance,
    // completion). Such outcomes are projections, so they are described as "is projected to".
    // Scoped by sentence so certain, immediate effects ("after the purchase you will have $8,000.00
    // in savings") and conditionals ("if expenses rise, the balance will fall") stay acceptable.
    private static let futureCertainty = try? NSRegularExpression(
        pattern: #"\b(?:will|'ll)\s+(?:still\s+|not\s+|never\s+|only\s+|also\s+|easily\s+)?(?:be|have|reach|end|finish|meet|fall|stay|remain|exceed|hit|miss|achieve|succeed|grow|complete)\b"#)
    private static let futureTopics = ["target", "goal", "deadline", "balance", "completion", "on track"]

    // Instructions to change income or spending, tolerant of filler words the fixed phrases above
    // missed ("you need to either increase your income").
    private static let behaviourInstruction = try? NSRegularExpression(
        pattern: #"\byou(?:'ll)?\s+(?:would\s+)?(?:need|have|should|must|ought)\s+(?:to\s+)?(?:either\s+|also\s+|just\s+)?(?:increase|decrease|reduce|cut|raise|lower|boost)\b"#)

    // Spelled-out quantities would bypass the figure check, so prose must use the supplied digits.
    static let numberWords: Set<String> = [
        "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
        "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "million", "billion", "dozen"
    ]

    // Which rule rejected a response. Categories only, so a reason never carries generated text or figures.
    enum RejectionReason: String, Sendable {
        case emptySummary, emptyConsideration
        case summaryTooLong, considerationTooLong, combinedTooLong
        case repeatedText
        case nonASCIIDigits, link, prohibitedPhrase, spelledNumber, unsupportedFigure
        case unhedgedCertainty
        case contradictsStatus, contradictsDirection, contradictsScenario
        case oneOffPurchaseAsMonthly, forecastMisread, depositCountMisread
        case noSuggestions
    }

    // Phrases that state the opposite of a goal's verified status, matched case-insensitively.
    // Hedges such as "could fall short if expenses rise" stay acceptable for an on-track goal.
    static let onTrackContradictions = [
        "is at risk", "are at risk", "you're at risk", "not on track", "off track",
        "will not reach", "won't reach", "not projected to reach"
    ]
    static let atRiskContradictions = [
        "you are on track", "you're on track", "is on track", "are on track",
        "remains on track", "stays on track", "still on track"
    ]

    static func validate(_ generated: GeneratedFinancialInsight,
                         for request: FinancialInsightRequest) throws -> ValidatedFinancialInsight {
        let summary = generated.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let consideration = generated.keyConsideration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rejectionReason(summary: summary, consideration: consideration, request: request) == nil else {
            throw FinancialInsightFailure.unusableResponse
        }
        guard let topSuggestion = request.suggestions.first else { throw FinancialInsightFailure.unusableResponse }
        // The step text is always Foresight-authored. If the model picks a step outside this
        // scenario's options, Foresight's most relevant suggestion is used instead of
        // discarding otherwise valid prose; generated text itself is never altered.
        let suggestion = request.suggestions.first { $0.step == generated.nextStep } ?? topSuggestion
        return ValidatedFinancialInsight(summary: summary, keyConsideration: consideration, suggestion: suggestion)
    }

    // The first rule a trimmed response breaks, in the order the checks have always run; nil if acceptable.
    static func rejectionReason(summary: String, consideration: String,
                                request: FinancialInsightRequest) -> RejectionReason? {
        if summary.isEmpty { return .emptySummary }
        if consideration.isEmpty { return .emptyConsideration }
        if summary.count > summaryLimit { return .summaryTooLong }
        if consideration.count > considerationLimit { return .considerationTooLong }
        if summary.count + consideration.count > combinedLimit { return .combinedTooLong }
        if summary.caseInsensitiveCompare(consideration) == .orderedSame || repeatsSummary(consideration, summary)
            || repeatsItself(summary) {
            return .repeatedText
        }
        let figures = VerifiedFigures(request: request)
        if let reason = proseRejection(summary, figures: figures) { return reason }
        if let reason = proseRejection(consideration, figures: figures) { return reason }
        let lowered = normalized(summary + " " + consideration)
        if contradictions(for: request).contains(where: { lowered.contains($0) }) { return .contradictsStatus }
        let directions = VerifiedDirections(request: request)
        if directions.contradicts(summary) || directions.contradicts(consideration) { return .contradictsDirection }
        let scenarios = ScenarioFigures(request: request)
        if scenarios.contradicts(summary) || scenarios.contradicts(consideration) { return .contradictsScenario }
        let purchase = OneOffPurchaseCheck(request: request)
        if purchase.contradicts(summary) || purchase.contradicts(consideration) { return .oneOffPurchaseAsMonthly }
        let forecast = ForecastMeaningCheck(request: request)
        if forecast.contradicts(summary) || forecast.contradicts(consideration) { return .forecastMisread }
        if misreadsDepositCount(summary, request) || misreadsDepositCount(consideration, request) { return .depositCountMisread }
        if request.suggestions.isEmpty { return .noSuggestions }
        return nil
    }

    // Sentences of a response, for checks whose meaning depends on what else the sentence says.
    // Breaks only at punctuation followed by a space or the end, so "$1,500.00" stays whole.
    static func sentences(_ text: String) -> [String] {
        normalized(text)
            .replacingOccurrences(of: #"[.;!?](\s+|$)"#, with: "\n", options: .regularExpression)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // True when the few words before `range` negate it ("does not reduce", "doesn't change").
    static func isNegated(_ range: NSRange, in text: String) -> Bool {
        guard let swiftRange = Range(range, in: text) else { return false }
        let before = text[..<swiftRange.lowerBound].suffix(16)
        return ["not ", "n't ", "never ", "without "].contains { before.contains($0) }
    }

    private static func statesFutureCertainty(_ text: String) -> Bool {
        guard let futureCertainty else { return false }
        return sentences(text).contains { sentence in
            let words = Set(sentence.split(whereSeparator: { !$0.isLetter }).map(String.init))
            guard words.isDisjoint(with: ["if", "unless"]),
                  futureTopics.contains(where: sentence.contains) else { return false }
            return futureCertainty.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) != nil
        }
    }

    // Lowercased with typographic apostrophes straightened, so "you’ll" matches "you'll".
    static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
    }

    // A key consideration that copies a whole sentence of the summary adds nothing new.
    static func repeatsSummary(_ consideration: String, _ summary: String) -> Bool {
        let summaryText = summary.lowercased()
        return consideration.lowercased()
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { $0.count >= 20 && summaryText.contains($0) }
    }

    // "for 9 months" or "9 monthly deposits" tied to "by/before the deadline" must use the verified
    // number of deposits before the deadline; the model once used the completion duration instead.
    // Counts after the deadline ("3 more are needed after it") are not checked.
    private static let depositDuration = try? NSRegularExpression(
        pattern: #"\bfor\s+(\d+)\s+months?\b|\b(\d+)\s+(?:more\s+)?(?:monthly\s+)?deposits?\b"#)

    static func misreadsDepositCount(_ text: String, _ request: FinancialInsightRequest) -> Bool {
        guard let fact = request.facts.first(where: { $0.id == "deposits" }),
              let verified = Int(fact.value), let pattern = depositDuration else { return false }
        return sentences(text).contains { sentence in
            guard sentence.contains("by the deadline") || sentence.contains("before the deadline"),
                  !sentence.contains("after") else { return false }
            return pattern.matches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)).contains { match in
                let group = match.range(at: 1).location != NSNotFound ? 1 : 2
                guard let range = Range(match.range(at: group), in: sentence), let count = Int(sentence[range]) else { return false }
                return count != verified
            }
        }
    }

    // A summary that states the same sentence twice (greedy decoding can loop).
    static func repeatsItself(_ summary: String) -> Bool {
        let long = sentences(summary).filter { $0.count >= 20 }
        return Set(long).count < long.count
    }

    // Only goal statuses map reliably to fixed wording; purchase and forecast outcomes are
    // covered by the above/below direction check instead.
    static func contradictions(for request: FinancialInsightRequest) -> [String] {
        guard case .goal(let snapshot) = request.context else { return [] }
        switch snapshot.result.status {
        case .onTrack, .fundedNow: return onTrackContradictions
        case .atRisk, .noContributionBeforeDeadline, .pastDeadline, .nonpositiveCapacity, .completionBeyondLimit:
            return atRiskContradictions
        case .invalidInputs, .overflow: return []
        }
    }

    static func isAcceptableProse(_ text: String, figures: VerifiedFigures) -> Bool {
        proseRejection(text, figures: figures) == nil
    }

    static func proseRejection(_ text: String, figures: VerifiedFigures) -> RejectionReason? {
        // Only ASCII digits can be checked against the supplied figures.
        guard !text.unicodeScalars.contains(where: { $0.properties.numericType == .decimal && !$0.isASCII }) else { return .nonASCIIDigits }
        let lowered = normalized(text)
        // URLs and web addresses.
        guard !lowered.contains("http://"), !lowered.contains("https://"), !lowered.contains("www.") else { return .link }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return .link
        }
        guard !prohibitedPhrases.contains(where: { lowered.contains($0) }) else { return .prohibitedPhrase }
        if let behaviourInstruction,
           behaviourInstruction.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)) != nil {
            return .prohibitedPhrase
        }
        if statesFutureCertainty(text) { return .unhedgedCertainty }
        let words = lowered.split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard !words.contains(where: { numberWords.contains($0) }) else { return .spelledNumber }
        // Every quoted number must be grounded in a verified figure.
        return NumberToken.tokens(in: text).allSatisfy(figures.contains) ? nil : .unsupportedFigure
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

    static func rounded(_ value: Decimal, mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 0, mode)
        return output
    }
}

// Forecast success figures (rounded percentage and path count) that belong to only one case of a
// forecast with a purchase. A clause labelled "without the purchase" that quotes a with-purchase
// figure, or the reverse, swaps the two results. Clauses naming both cases, or describing a change
// "from" one to the other, are not checked.
nonisolated struct ScenarioFigures: Sendable {
    private var baselineOnly: Set<Decimal> = []
    private var purchaseOnly: Set<Decimal> = []

    private static let clauseBreak = try? NSRegularExpression(
        pattern: #"[.;!?](\s|$)|,\s|\b(compared to|compared with|while|whereas|but|versus|vs)\b"#, options: .caseInsensitive)

    init(request: FinancialInsightRequest) {
        func values(_ id: String) -> Set<Decimal> {
            Set(request.facts.filter { $0.id == id }.flatMap { NumberToken.tokens(in: $0.value) }.map(\.value))
        }
        let baseline = values("baselineSuccess")
        let purchase = values("purchaseSuccess")
        guard !baseline.isEmpty, !purchase.isEmpty else { return }
        baselineOnly = baseline.subtracting(purchase)
        purchaseOnly = purchase.subtracting(baseline)
    }

    func contradicts(_ text: String) -> Bool {
        guard !baselineOnly.isEmpty || !purchaseOnly.isEmpty, let clauseBreak = Self.clauseBreak else { return false }
        let marked = clauseBreak.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                          withTemplate: "\n")
        return marked.split(separator: "\n").contains { clause in
            let lowered = FinancialInsightValidator.normalized(String(clause))
            let without = lowered.contains("without the purchase") || lowered.contains("without it")
            let with = lowered.contains("with the purchase") || lowered.contains("with it")
            guard without != with, !lowered.contains(" from ") else { return false }
            let quoted = NumberToken.tokens(in: String(clause)).filter { $0.kind != .money }.map(\.value)
            return quoted.contains(where: (without ? purchaseOnly : baselineOnly).contains)
        }
    }
}

// Which side of the target Foresight placed each amount on, read from its own relationship text
// ("$300.00 above the target", "$1,000.00 below it"). Prose that puts the same amount on the
// other side, such as calling a surplus a shortfall, contradicts a verified result.
nonisolated struct VerifiedDirections: Sendable {
    enum Side: Sendable { case above, below }
    private var sides: [Decimal: Set<Side>] = [:]

    // An amount immediately followed by above, below or short. "short" reads as below the target.
    private static let pattern = try? NSRegularExpression(
        pattern: #"\p{Sc}\s?(\d+(?:,\d{3})*(?:\.\d+)?)\s+(above|below|short)\b"#, options: .caseInsensitive)

    // Amounts that are only ever a gap from the target, never a supplied figure in their own right.
    private var gapsOnly: Set<Decimal> = []

    // "balance of $14.95" / "balance is $14.95": the amount is read as the balance itself.
    private static let amountAsBalance = try? NSRegularExpression(
        pattern: #"\bbalances?\s+(?:of|is|was|at|stands\s+at)\s+\p{Sc}\s?(\d+(?:,\d{3})*(?:\.\d+)?)"#, options: .caseInsensitive)

    init(request: FinancialInsightRequest) {
        for text in request.relationships + [request.considerationFocus] {
            for (value, side) in Self.claims(in: text) {
                // A rounding of a verified amount carries the same side.
                for key in [value, VerifiedFigures.rounded(value, mode: .plain), VerifiedFigures.rounded(value, mode: .down)] {
                    sides[key, default: []].insert(side)
                }
            }
        }
        let factAmounts = Set(request.facts.flatMap { NumberToken.tokens(in: $0.value) }.map(\.value))
        gapsOnly = Set(sides.keys).subtracting(factAmounts)
    }

    func contradicts(_ text: String) -> Bool {
        let wrongSide = Self.claims(in: text).contains { value, side in
            // Only amounts Foresight placed on exactly one side can be checked unambiguously.
            guard let verified = sides[value], verified.count == 1 else { return false }
            return !verified.contains(side)
        }
        return wrongSide || readsGapAsBalance(text)
    }

    // A gap from the target quoted as the balance itself: "the median balance of $14.95" when the
    // median is $14.95 below the target. "balance is $14.95 below the target" stays acceptable.
    private func readsGapAsBalance(_ text: String) -> Bool {
        guard !gapsOnly.isEmpty, let pattern = Self.amountAsBalance else { return false }
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).contains { match in
            guard let numberRange = Range(match.range(at: 1), in: text),
                  let value = Decimal(string: text[numberRange].replacingOccurrences(of: ",", with: ""),
                                      locale: Locale(identifier: "en_US_POSIX")),
                  gapsOnly.contains(value) else { return false }
            let following = text[numberRange.upperBound...].lowercased().trimmingCharacters(in: .whitespaces)
            return !["above", "below", "short", "more", "less", "over", "under"].contains { following.hasPrefix($0) }
        }
    }

    private static func claims(in text: String) -> [(Decimal, Side)] {
        guard let pattern else { return [] }
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let numberRange = Range(match.range(at: 1), in: text),
                  let wordRange = Range(match.range(at: 2), in: text),
                  let value = Decimal(string: text[numberRange].replacingOccurrences(of: ",", with: ""),
                                      locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            return (value, text[wordRange].lowercased() == "above" ? .above : .below)
        }
    }
}

// A purchase is a one-off cost: it lowers current savings once and never changes monthly income,
// expenses or capacity. Rejects prose that says it reduces capacity ("reduces your savings capacity")
// or quotes its cost as a monthly amount ("$500.00 each month"). Wording that attributes the amount
// to capacity, income or expenses is allowed; a matching verified monthly figure only excuses the
// amount when the wording does not attribute it to the purchase.
nonisolated struct OneOffPurchaseCheck: Sendable {
    private var costs: Set<Decimal> = []
    private var monthlyAmounts: Set<Decimal> = []

    private static let capacityChange = try? NSRegularExpression(pattern:
        #"\b(?:reduc|lower|decreas|cut|shrink|drop)\w*\s+(?:your\s+|the\s+)?(?:monthly\s+)?(?:savings\s+)?(?:capacity|income|expenses)\b|\b(?:reduc|lower|decreas|cut)\w*\s+(?:your\s+|the\s+)?monthly\s+savings\b|\bcapacity\s+(?:is\s+|would\s+be\s+)?(?:reduced|lowered|cut|falls|drops|decreases|shrinks)\b"#)
    private static let amountPerMonth = try? NSRegularExpression(pattern:
        #"\p{Sc}\s?(\d+(?:,\d{3})*(?:\.\d+)?)(?:\s+[a-z']+){0,3}?\s+(?:each|per|a|every)\s+month\b|\p{Sc}\s?(\d+(?:,\d{3})*(?:\.\d+)?)\s+monthly\b"#)

    init(request: FinancialInsightRequest) {
        for fact in request.facts {
            let amounts = NumberToken.tokens(in: fact.value).filter { $0.kind == .money }.map(\.value)
            if fact.id == "cost" {
                for amount in amounts {
                    costs.formUnion([amount, VerifiedFigures.rounded(amount, mode: .plain), VerifiedFigures.rounded(amount, mode: .down)])
                }
            } else if fact.label.lowercased().contains("month") {
                monthlyAmounts.formUnion(amounts)
            }
        }
    }

    func contradicts(_ text: String) -> Bool {
        guard !costs.isEmpty else { return false }
        let lowered = FinancialInsightValidator.normalized(text)
        let range = NSRange(lowered.startIndex..., in: lowered)
        if let capacityChange = Self.capacityChange, capacityChange.matches(in: lowered, range: range)
            .contains(where: { !FinancialInsightValidator.isNegated($0.range, in: lowered) }) {
            return true
        }
        guard let amountPerMonth = Self.amountPerMonth else { return false }
        return amountPerMonth.matches(in: lowered, range: range).contains { match in
            let group = match.range(at: 1).location != NSNotFound ? 1 : 2
            guard let numberRange = Range(match.range(at: group), in: lowered),
                  let matchRange = Range(match.range, in: lowered),
                  let value = Decimal(string: lowered[numberRange].replacingOccurrences(of: ",", with: ""),
                                      locale: Locale(identifier: "en_US_POSIX")),
                  costs.contains(value) else { return false }
            // "$1,500.00 monthly capacity" or "capacity is $1,500.00 each month" describes capacity,
            // not the purchase, even when the cost happens to be the same amount.
            let before = lowered[..<matchRange.lowerBound].suffix(30)
            let after = lowered[matchRange.upperBound...].trimmingCharacters(in: .whitespaces)
            if before.contains("capacity") || ["capacity", "savings capacity", "income", "expenses"].contains(where: after.hasPrefix) {
                return false
            }
            // A matching verified monthly figure (such as the extra monthly saving) only excuses the
            // amount when nearby wording does not attribute it to the purchase itself.
            let window = lowered[..<matchRange.upperBound].suffix(40)
            let namesPurchase = ["purchase", "cost", "buy", "paying", "pay for"].contains(where: window.contains)
            return namesPurchase || !monthlyAmounts.contains(value)
        }
    }
}

// Monte Carlo results are shares of simulated paths; P10/P50/P90 are balances. Rejects prose that
// calls a percentile balance a chance or probability, or that presents a success percentage as a
// deterministic projection in the same sentence ("projected to reach the goal with an 80% success
// rate"). Negated wording such as "balances, not chances" stays acceptable.
nonisolated struct ForecastMeaningCheck: Sendable {
    private var successPercentages: Set<Decimal> = []
    private var isForecast = false

    private static let percentileAsChance = try? NSRegularExpression(pattern:
        #"\b(?:p10|p50|p90|median|percentile)\b[^.;]{0,40}?\b(?:chances?|probabilit(?:y|ies)|likelihood|odds)\b|\b(?:chances?|probabilit(?:y|ies)|likelihood|odds)\b[^.;]{0,20}?\b(?:p10|p50|p90)\b"#)
    // A goal outcome described as a projection. In a forecast the outcome is a share of simulated
    // paths, so this is only valid for the single "as entered" projection, which is exempt.
    private static let projectedOutcome = try? NSRegularExpression(pattern:
        #"\b(?:projected|expected|on track)\s+to\s+(?:succeed|fail|reach|meet|achieve|miss|hit|fall\s+short)\b"#)
    private static let projectionWords = ["projected", "expected to", "on track"]

    init(request: FinancialInsightRequest) {
        guard case .forecast = request.context else { return }
        isForecast = true
        for fact in request.facts where fact.id == "baselineSuccess" || fact.id == "purchaseSuccess" {
            successPercentages.formUnion(NumberToken.tokens(in: fact.value).filter { $0.kind == .percent }.map(\.value))
        }
    }

    func contradicts(_ text: String) -> Bool {
        guard isForecast else { return false }
        let lowered = FinancialInsightValidator.normalized(text)
        if let percentileAsChance = Self.percentileAsChance, percentileAsChance.matches(in: lowered, range: NSRange(lowered.startIndex..., in: lowered))
            .contains(where: { match in
                guard let range = Range(match.range, in: lowered) else { return false }
                let phrase = lowered[range]
                return !phrase.contains(" not ") && !phrase.contains("n't ")
            }) {
            return true
        }
        return FinancialInsightValidator.sentences(text).contains { sentence in
            guard !sentence.contains("as entered") else { return false }
            if let projectedOutcome = Self.projectedOutcome,
               projectedOutcome.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) != nil {
                return true
            }
            // "Success is projected to be 41%": a share of paths presented as a projection.
            return Self.projectionWords.contains(where: sentence.contains)
                && NumberToken.tokens(in: sentence).contains { $0.kind == .percent && successPercentages.contains($0.value) }
        }
    }
}
