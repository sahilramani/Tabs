//
//  Subscription.swift
//  Tabs
//
//  PRIVACY: This is the on-device SwiftData persistence model. It lives only in
//  the app's local store. Nothing here is ever serialized to a server — there
//  is no networking layer in this app by design.
//

import Foundation
import SwiftData

/// A tracked subscription, persisted locally via SwiftData.
@Model
final class Subscription {
    /// Stable identifier, also used to correlate the scheduled local notification.
    @Attribute(.unique) var id: UUID

    var name: String

    /// Stored as `Decimal` to avoid binary floating-point rounding on money.
    var price: Decimal

    /// Backing storage for `billingCycle`. SwiftData persists the raw string;
    /// the computed `billingCycle` below provides type-safe access.
    var billingCycleRaw: String

    /// The next date this subscription is expected to renew / charge.
    var renewalDate: Date

    /// When this record was created on-device.
    var createdAt: Date

    /// Identifier of the pending `UNNotificationRequest`, if one was scheduled.
    /// Kept so we can cancel/replace the reminder if the record changes.
    var notificationIdentifier: String?

    /// Where this record came from, e.g. "Screenshot scan" or "PDF statement".
    /// Useful for letting the user know a value was heuristically detected.
    var source: String?

    /// ISO currency code for `price` (e.g. "USD", "EUR"). Optional so stores
    /// written before multi-currency support migrate cleanly; `nil` means the
    /// device currency is assumed.
    var currencyCode: String?

    /// The statement charges that supported this subscription at import time,
    /// newest first. Empty for manually added subscriptions. Defaults to `[]`
    /// so existing stores migrate without data loss.
    var charges: [ChargeRecord] = []

    /// When the user marked this subscription cancelled, or `nil` while it's
    /// still active. A cancelled record is kept (its history stays intact) but
    /// drops out of the spend total and stops reminding — the whole point of
    /// the app is helping people *cancel*, so "done with it" must not mean
    /// "delete and lose the receipt".
    var cancelledAt: Date?

    /// When the user moved this subscription to the trash, or `nil` while it's
    /// live. Trashed records are hidden from every list and the spend total but
    /// kept in the store so a delete is undoable — only emptying the trash
    /// removes them for good. Optional so existing stores migrate cleanly.
    var deletedAt: Date?

    /// How many days before `renewalDate` the local reminder fires. Persisted
    /// per subscription so each one can have its own lead time; defaults to 3
    /// (the previous app-wide behavior) so existing stores migrate unchanged.
    var reminderDaysBefore: Int = 3

    init(
        id: UUID = UUID(),
        name: String,
        price: Decimal,
        billingCycle: BillingCycle,
        renewalDate: Date,
        createdAt: Date = Date(),
        notificationIdentifier: String? = nil,
        source: String? = nil,
        currencyCode: String? = nil,
        charges: [ChargeRecord] = [],
        cancelledAt: Date? = nil,
        deletedAt: Date? = nil,
        reminderDaysBefore: Int = 3
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.billingCycleRaw = billingCycle.rawValue
        self.renewalDate = renewalDate
        self.createdAt = createdAt
        self.notificationIdentifier = notificationIdentifier
        self.source = source
        self.currencyCode = currencyCode
        self.charges = charges
        self.cancelledAt = cancelledAt
        self.deletedAt = deletedAt
        self.reminderDaysBefore = reminderDaysBefore
    }

    /// Whether this subscription is live and counted: not cancelled, not
    /// trashed. Only active records appear in the main list and the spend total.
    var isActive: Bool { cancelledAt == nil && deletedAt == nil }

    /// Whether this subscription is in the trash.
    var isTrashed: Bool { deletedAt != nil }

    /// Type-safe accessor over `billingCycleRaw`. Falls back to `.monthly`,
    /// which is also our default assumption for statement imports.
    var billingCycle: BillingCycle {
        get { BillingCycle(rawValue: billingCycleRaw) ?? .monthly }
        set { billingCycleRaw = newValue.rawValue }
    }
}

extension Subscription {
    /// This subscription's cost normalized to a monthly figure, for spend totals.
    var monthlyEquivalentPrice: Decimal {
        price * billingCycle.monthlyCostFactor
    }

    /// Currency string for the raw price in its own currency (e.g. "$15.49").
    var formattedPrice: String { CurrencyFormat.string(from: price, code: currencyCode) }

    /// Days until renewal (negative if already past).
    var daysUntilRenewal: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                        to: Calendar.current.startOfDay(for: renewalDate)).day ?? 0
    }

    /// Convenience builder that turns an approved scan draft into a model object.
    convenience init(draft: ScannedSubscriptionDraft, source: String) {
        self.init(
            name: draft.name,
            price: draft.price,
            billingCycle: draft.billingCycle,
            renewalDate: draft.renewalDate,
            source: source,
            currencyCode: draft.currencyCode,
            charges: draft.transactions.map(ChargeRecord.init(transaction:))
        )
    }

    /// Moves the record to the trash. The cancelled flag is left untouched so
    /// restoring returns it to whatever state it was in (active or cancelled).
    func moveToTrash(now: Date = Date()) { deletedAt = now }

    /// Pulls the record back out of the trash. It returns to active or
    /// cancelled depending on its preserved `cancelledAt`.
    func restoreFromTrash() { deletedAt = nil }

    /// Switches to `cycle` and recomputes `renewalDate` to match: one cycle
    /// after the most recent detected charge (or `createdAt` when there are no
    /// charges, e.g. a manually added subscription), rolled forward until it's
    /// today or later. Mirrors the import-time rule so changing the cadence by
    /// hand stays consistent with detection. Returns the new renewal date.
    @discardableResult
    func realignRenewal(to cycle: BillingCycle, now: Date = Date(), calendar: Calendar = .current) -> Date {
        billingCycle = cycle
        let anchor = charges.compactMap(\.date).max() ?? createdAt
        renewalDate = RecurringChargeDetector.nextRenewal(after: anchor, cycle: cycle, now: now, calendar: calendar)
        return renewalDate
    }

    /// Advances a past-due `renewalDate` cycle-by-cycle until it lands today or
    /// later, so the list and reminders stay meaningful across billing periods.
    ///
    /// Returns `true` if the date moved — the caller should reschedule the
    /// renewal reminder in that case.
    @discardableResult
    func rollRenewalForward(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard calendar.startOfDay(for: renewalDate) < today else { return false }
        var next = renewalDate
        // Bounded so a corrupt far-past date can't spin forever.
        for _ in 0..<1000 {
            next = billingCycle.nextRenewalDate(from: next, calendar: calendar)
            if calendar.startOfDay(for: next) >= today { break }
        }
        renewalDate = next
        return true
    }
}
