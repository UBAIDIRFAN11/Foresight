// Decides whether a user-initiated currency change can be applied straight away or must
// be confirmed first because it would clear amounts the user has typed.
import Foundation

/// One monetary draft field that a currency change would clear.
struct CurrencyAmountField: Equatable {
    let title: String
    let text: String

    /// Any non-whitespace text counts, including "0", malformed or half-typed amounts.
    var hasContent: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// A staged currency change waiting for confirmation, with the context it was based on.
struct CurrencyChangeRequest: Equatable {
    let id = UUID()
    var contextID: UUID? = nil
    let originalCurrencyCode: String
    let requestedCurrencyCode: String
    let fields: [CurrencyAmountField]

    /// Titles of the fields that currently hold text and would lose it.
    var affectedFieldTitles: [String] { fields.filter(\.hasContent).map(\.title) }

    var requestedCurrency: CurrencyDefinition { CurrencyDefinition.definition(for: requestedCurrencyCode) }

    /// Confirmation is only honoured if nothing it was based on has changed since it was staged.
    func isStillValid(currentCurrencyCode: String, fields currentFields: [CurrencyAmountField], isLocked: Bool,
                      contextID currentContextID: UUID? = nil) -> Bool {
        !isLocked && contextID == currentContextID && currentCurrencyCode == originalCurrencyCode && currentFields == fields
    }

    /// Spoken/visible description of what confirming would clear.
    func message(draftNote: String) -> String {
        let titles = affectedFieldTitles.formatted(.list(type: .and))
        return "Switching to \(requestedCurrency.displayName) clears \(titles). \(draftNote)"
    }
}

enum CurrencyChangeDecision: Equatable {
    /// The requested currency is already selected, or currency changes are locked.
    case ignore
    /// Nothing typed would be lost, so the change can happen immediately.
    case applyImmediately
    /// Typed amounts would be cleared; ask first.
    case confirm(CurrencyChangeRequest)

    static func evaluate(currentCurrencyCode: String, requestedCurrencyCode: String,
                         fields: [CurrencyAmountField], isLocked: Bool) -> CurrencyChangeDecision {
        guard !isLocked, currentCurrencyCode != requestedCurrencyCode else { return .ignore }
        guard fields.contains(where: \.hasContent) else { return .applyImmediately }
        return .confirm(CurrencyChangeRequest(originalCurrencyCode: currentCurrencyCode,
                                              requestedCurrencyCode: requestedCurrencyCode, fields: fields))
    }
}
