import Foundation

//cleans names and descriptions, ensures goal names aren't empty,
//and checks that goal targets are greater than zero.

enum FinancialFormValidation {
    static func cleanName(_ value: String) -> String {
        // Names are saved without accidental leading/trailing whitespace.
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func optionalDescription(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func validateGoalName(_ value: String) -> String? {
        cleanName(value).isEmpty ? "Name is required." : nil
    }

    static func validateGoalTarget(_ minorUnits: Int64) -> String? {
        minorUnits > 0 ? nil : "Goal target must be greater than zero."
    }
}
