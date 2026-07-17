//
//  ReviewCaptionTests.swift
//  TabsTests
//
//  The review screen's under-title caption: candidate count, source count,
//  and the month window the charges span. Pure string building, no I/O.
//

import XCTest
@testable import Tabs

final class ReviewCaptionTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testCaptionWithWindow() {
        let caption = ReviewCaption.text(
            candidateCount: 4, statementCount: 3, sourceNoun: "statement",
            chargeDates: [date(2026, 3, 15), date(2026, 6, 15), date(2026, 4, 2)]
        )
        XCTAssertEqual(caption, "4 candidates · from 3 statements, Mar–Jun")
    }

    func testSingularEverything() {
        let caption = ReviewCaption.text(
            candidateCount: 1, statementCount: 1, sourceNoun: "screenshot",
            chargeDates: [date(2026, 3, 2)]
        )
        XCTAssertEqual(caption, "1 candidate · from 1 screenshot, Mar")
    }

    func testNoDatesOmitsWindow() {
        let caption = ReviewCaption.text(
            candidateCount: 2, statementCount: 1, sourceNoun: "statement",
            chargeDates: []
        )
        XCTAssertEqual(caption, "2 candidates · from 1 statement")
    }

    func testCrossYearWindowKeepsYears() {
        let caption = ReviewCaption.text(
            candidateCount: 2, statementCount: 4, sourceNoun: "statement",
            chargeDates: [date(2025, 11, 3), date(2026, 2, 11)]
        )
        XCTAssertEqual(caption, "2 candidates · from 4 statements, Nov 2025–Feb 2026")
    }

    func testSameMonthCollapsesToOneLabel() {
        let caption = ReviewCaption.text(
            candidateCount: 3, statementCount: 1, sourceNoun: "statement",
            chargeDates: [date(2026, 3, 2), date(2026, 3, 28)]
        )
        XCTAssertEqual(caption, "3 candidates · from 1 statement, Mar")
    }
}
