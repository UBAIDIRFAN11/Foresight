import Foundation
import SwiftData

//stores user's main financial situation:
// -curr savings
// -monthly income
// -recurring expenses
// -perferred currency

@Model
final class FinancialProfile {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var currentSavingsMinor: Int64
    var monthlyIncomeMinor: Int64
    var recurringExpensesMinor: Int64
    var preferredCurrencyCode: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        currentSavingsMinor: Int64,
        monthlyIncomeMinor: Int64,
        recurringExpensesMinor: Int64,
        preferredCurrencyCode: String = "AUD"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.currentSavingsMinor = currentSavingsMinor
        self.monthlyIncomeMinor = monthlyIncomeMinor
        self.recurringExpensesMinor = recurringExpensesMinor
        self.preferredCurrencyCode = preferredCurrencyCode
    }
}
