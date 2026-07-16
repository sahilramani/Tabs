//
//  BillingCycle.swift
//  Tabs
//
//  PRIVACY: This type contains pure value logic only. It performs no I/O,
//  makes no network calls, and never touches disk. All date math is local.
//

import Foundation

/// How often a subscription bills the user.
///
/// `BillingCycle` is intentionally a plain `String`-backed enum so it can be
/// persisted directly inside the SwiftData `Subscription` model and extended
/// later without a migration headache.
enum BillingCycle: String, Codable, CaseIterable, Identifiable, Sendable {
    case weekly
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    /// Human-readable label used in the UI.
    var displayName: String {
        switch self {
        case .weekly:    return "Weekly"
        case .monthly:   return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly:    return "Yearly"
        }
    }

    /// The `Calendar.Component` and amount that defines one period of this cycle.
    private var period: (component: Calendar.Component, value: Int) {
        switch self {
        case .weekly:    return (.day, 7)
        case .monthly:   return (.month, 1)
        case .quarterly: return (.month, 3)
        case .yearly:    return (.year, 1)
        }
    }

    /// Returns the next renewal date exactly one cycle after `date`.
    ///
    /// Used as a placeholder when importing from a statement, where we can infer
    /// the brand and price but not the exact next charge date.
    func nextRenewalDate(from date: Date = Date(), calendar: Calendar = .current) -> Date {
        let (component, value) = period
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    /// Multiplier that converts a single charge in this cycle into its
    /// equivalent *monthly* cost. Used for the home-screen spend summary so a
    /// $120/yr plan and a $10/mo plan compare on the same axis.
    var monthlyCostFactor: Decimal {
        switch self {
        case .weekly:    return Decimal(52) / Decimal(12)
        case .monthly:   return 1
        case .quarterly: return Decimal(1) / Decimal(3)
        case .yearly:    return Decimal(1) / Decimal(12)
        }
    }

    /// Spelled-out rate label for the detail header, e.g. "per month".
    var perLabel: String {
        switch self {
        case .weekly:    return "per week"
        case .monthly:   return "per month"
        case .quarterly: return "per quarter"
        case .yearly:    return "per year"
        }
    }

    /// Short suffix for inline price labels, e.g. "/mo".
    var shortSuffix: String {
        switch self {
        case .weekly:    return "/wk"
        case .monthly:   return "/mo"
        case .quarterly: return "/qtr"
        case .yearly:    return "/yr"
        }
    }

    /// Infers a cycle from the typical number of days between charges, using
    /// tolerant bands around each cadence (statements drift by a few days).
    /// Returns `nil` when the gap doesn't resemble any known cadence, so the
    /// caller can fall back to its own default.
    static func inferred(fromGapDays days: Int) -> BillingCycle? {
        switch days {
        case 5...10:    return .weekly
        case 24...38:   return .monthly
        case 80...100:  return .quarterly
        case 330...400: return .yearly
        default:        return nil
        }
    }
}
