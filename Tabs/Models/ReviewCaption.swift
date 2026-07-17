//
//  ReviewCaption.swift
//  Tabs
//
//  Builds the review screen's under-title caption, e.g.
//  "4 candidates · from 3 statements, Mar–Jun". Pure string logic so it's
//  unit-testable; the view just renders the result.
//
//  PRIVACY: string formatting only. No I/O.
//

import Foundation

enum ReviewCaption {

    /// The caption under the Review title: how many candidates were found,
    /// how many source documents fed the scan, and — when the charges carry
    /// dates — the month window they span.
    static func text(
        candidateCount: Int,
        statementCount: Int,
        sourceNoun: String,
        chargeDates: [Date],
        calendar: Calendar = .current
    ) -> String {
        let candidates = "\(candidateCount) candidate\(candidateCount == 1 ? "" : "s")"
        let sources = "from \(statementCount) \(sourceNoun)\(statementCount == 1 ? "" : "s")"
        guard let window = windowLabel(for: chargeDates, calendar: calendar) else {
            return "\(candidates) · \(sources)"
        }
        return "\(candidates) · \(sources), \(window)"
    }

    /// "Mar–Jun" for a same-year span, "Nov 2025–Feb 2026" across years,
    /// "Mar" when everything lands in one month, `nil` with no dated charges.
    static func windowLabel(for dates: [Date], calendar: Calendar = .current) -> String? {
        guard let first = dates.min(), let last = dates.max() else { return nil }

        let firstComponents = calendar.dateComponents([.year, .month], from: first)
        let lastComponents = calendar.dateComponents([.year, .month], from: last)

        let month = monthFormatter(calendar: calendar)
        if firstComponents == lastComponents {
            return month.string(from: first)
        }
        if firstComponents.year == lastComponents.year {
            return "\(month.string(from: first))–\(month.string(from: last))"
        }
        let monthYear = monthYearFormatter(calendar: calendar)
        return "\(monthYear.string(from: first))–\(monthYear.string(from: last))"
    }

    private static func monthFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }

    private static func monthYearFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMM y")
        return formatter
    }
}
