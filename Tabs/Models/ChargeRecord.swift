//
//  ChargeRecord.swift
//  Tabs
//
//  PRIVACY: A persisted copy of the statement evidence behind a saved
//  subscription. Stored only inside the local SwiftData store, never uploaded.
//

import Foundation

/// One detected charge that supported a saved subscription — kept so the
/// detail screen can show *why* a subscription exists and what it actually
/// cost over time. Codable so SwiftData can persist it inline on the model.
struct ChargeRecord: Codable, Hashable, Identifiable {
    var id: UUID

    /// The charge amount (positive `Decimal`).
    var amount: Decimal

    /// The transaction date parsed from the statement, if one was found.
    var date: Date?

    /// The raw statement line this charge came from.
    var rawLine: String

    /// ISO currency code detected for this charge. `nil` decodes for records
    /// written before multi-currency support; the device currency is assumed.
    var currencyCode: String?

    init(id: UUID = UUID(), amount: Decimal, date: Date? = nil, rawLine: String, currencyCode: String? = nil) {
        self.id = id
        self.amount = amount
        self.date = date
        self.rawLine = rawLine
        self.currencyCode = currencyCode
    }

    /// Currency-formatted amount in its detected currency.
    var formattedAmount: String { CurrencyFormat.string(from: amount, code: currencyCode) }

    /// Human-readable date, or a placeholder when none was detected.
    var dateText: String {
        guard let date else { return "Undated" }
        return date.formatted(.dateTime.year().month().day())
    }
}

extension ChargeRecord {
    /// Builds a persistable record from a transient scan transaction.
    init(transaction: ScannedTransaction) {
        self.init(
            amount: transaction.amount,
            date: transaction.date,
            rawLine: transaction.rawLine,
            currencyCode: transaction.currencyCode
        )
    }
}
