//
//  CurrencyFormat.swift
//  Tabs
//
//  Small, shared currency formatting helper so views and models don't repeat
//  the locale-currency dance. Pure formatting — no I/O, no network.
//

import Foundation

enum CurrencyFormat {
    /// The device's current currency code, defaulting to USD if unavailable.
    /// Used as the fallback when a record carries no detected currency.
    static var deviceCode: String { Locale.current.currency?.identifier ?? "USD" }

    /// Back-compat alias used by the manual-entry and detail screens.
    static var code: String { deviceCode }

    /// Formats a `Decimal` as a currency string in `code` (e.g. "$15.49",
    /// "€9,99"), defaulting to the device currency when `code` is nil. The
    /// *grouping and symbol placement* still follow the user's locale; only
    /// the currency itself is pinned, so a `$` charge never renders as `€`.
    static func string(from amount: Decimal, code: String? = nil) -> String {
        amount.formatted(.currency(code: code ?? deviceCode))
    }
}
