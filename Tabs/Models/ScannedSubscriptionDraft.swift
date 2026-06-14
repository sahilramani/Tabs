//
//  ScannedSubscriptionDraft.swift
//  Tabs
//
//  PRIVACY: A draft is an in-memory, transient value produced entirely by
//  on-device text parsing. It is never written to disk or sent anywhere until
//  the user explicitly approves it in the review screen.
//

import Foundation

/// A single detected charge that contributed to a draft — its amount, the date
/// we parsed from the statement line (if any), and the raw source line.
struct ScannedTransaction: Identifiable, Hashable {
    let id = UUID()

    /// The charge amount (positive `Decimal`).
    var amount: Decimal

    /// The transaction date parsed from the statement, if one was found.
    var date: Date?

    /// The raw statement line this charge came from.
    var rawLine: String

    /// ISO currency code detected from the line's symbol (e.g. "USD", "EUR").
    /// `nil` when no symbol was present — the device currency is assumed.
    var currencyCode: String?

    /// Currency-formatted amount in its detected currency.
    var formattedAmount: String { CurrencyFormat.string(from: amount, code: currencyCode) }

    /// Human-readable date, or a placeholder when none was detected.
    var dateText: String {
        guard let date else { return "Undated" }
        return date.formatted(.dateTime.year().month().day())
    }
}

/// A *candidate* subscription detected by the local statement scanner.
///
/// Drafts are what the review UI binds to. The user confirms (and can edit)
/// them before any are committed to the SwiftData store.
struct ScannedSubscriptionDraft: Identifiable, Hashable {
    let id = UUID()

    /// The detected brand / merchant name (e.g. "Netflix").
    var name: String

    /// The representative price shown in the UI: the **average** of all detected
    /// charges for this brand (so multiple months show a typical monthly figure,
    /// not a sum). Stored as `Decimal` for monetary accuracy.
    var price: Decimal

    /// Defaults to `.monthly` for statement imports per product requirements.
    var billingCycle: BillingCycle = .monthly

    /// ISO currency code for `price`, detected from the statement (e.g. "EUR").
    /// `nil` falls back to the device currency.
    var currencyCode: String?

    /// Placeholder renewal date — one cycle from "today" at detection time.
    var renewalDate: Date

    /// Whether the user has this row checked for saving. Defaults to on so the
    /// common case ("save everything I found") is one tap.
    var isSelected: Bool = true

    /// Every charge we detected for this brand, newest first. Surfaced in the
    /// long-press popup so the user can verify the average against the source.
    var transactions: [ScannedTransaction] = []

    /// Set by the review screen when a saved subscription with the same
    /// merchant key already exists — shown as a badge and deselected by
    /// default so re-importing a statement doesn't create duplicates.
    var isAlreadyTracked: Bool = false

    init(
        name: String,
        price: Decimal,
        billingCycle: BillingCycle = .monthly,
        currencyCode: String? = nil,
        renewalDate: Date? = nil,
        isSelected: Bool = true,
        transactions: [ScannedTransaction] = []
    ) {
        self.name = name
        self.price = price
        self.billingCycle = billingCycle
        self.currencyCode = currencyCode
        self.renewalDate = renewalDate ?? billingCycle.nextRenewalDate(from: Date())
        self.isSelected = isSelected
        self.transactions = transactions
    }

    /// Currency-formatted average price for display, in its detected currency.
    var formattedPrice: String { CurrencyFormat.string(from: price, code: currencyCode) }

    /// Cost normalized to a monthly figure (for the review-screen running total).
    var monthlyEquivalentPrice: Decimal { price * billingCycle.monthlyCostFactor }

    /// How many charges fed the average. 1 means a single detection.
    var transactionCount: Int { transactions.count }

    /// The most recent raw line, kept for the existing "From:" hint.
    var matchedLine: String? { transactions.first?.rawLine }
}
