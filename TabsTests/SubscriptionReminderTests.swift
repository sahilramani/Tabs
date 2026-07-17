//
//  SubscriptionReminderTests.swift
//  TabsTests
//
//  Reminder lead-time: the persisted per-subscription offset and the pure
//  fire-date math used by NotificationManager. No I/O — the notification
//  center itself is never touched here.
//

import XCTest
@testable import Tabs

final class SubscriptionReminderTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components)!
    }

    func testReminderDaysBeforeDefaultsToThree() {
        let subscription = Subscription(
            name: "Netflix", price: 15.49, billingCycle: .monthly, renewalDate: .now
        )
        XCTAssertEqual(subscription.reminderDaysBefore, 3)
    }

    func testFireDateIsLeadDaysBeforeRenewal() {
        let renewal = date(2026, 7, 19)
        let now = date(2026, 7, 1)
        let fire = NotificationManager.fireDate(for: renewal, daysBefore: 3, now: now)
        XCTAssertEqual(
            Calendar.current.startOfDay(for: fire),
            Calendar.current.startOfDay(for: date(2026, 7, 16))
        )
    }

    func testFireDateNeverInThePast() {
        let renewal = date(2026, 7, 19)
        let now = date(2026, 7, 18)   // the 3-days-before moment is already gone
        let fire = NotificationManager.fireDate(for: renewal, daysBefore: 3, now: now)
        XCTAssertGreaterThan(fire, now)
    }

    func testZeroDaysMeansRenewalDay() {
        let renewal = date(2026, 7, 19)
        let now = date(2026, 7, 1)
        let fire = NotificationManager.fireDate(for: renewal, daysBefore: 0, now: now)
        XCTAssertEqual(
            Calendar.current.startOfDay(for: fire),
            Calendar.current.startOfDay(for: renewal)
        )
    }
}
