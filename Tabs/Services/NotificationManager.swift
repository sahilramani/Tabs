//
//  NotificationManager.swift
//  Tabs
//
//  PRIVACY: Uses only `UNUserNotificationCenter`. Local notifications are
//  scheduled and delivered entirely by the OS on-device. No push tokens, no
//  remote server, no APNs registration.
//

import Foundation
import UserNotifications

/// Schedules on-device reminders before a subscription renews.
///
/// `@MainActor`-isolated so the `Subscription` SwiftData model (which is not
/// `Sendable` and is bound to the main actor) is never passed across an actor
/// boundary — this keeps the type clean under strict concurrency checking.
/// `UNUserNotificationCenter`'s own `async` calls offload their work internally,
/// so main-actor isolation here costs nothing.
@MainActor
final class NotificationManager {

    static let shared = NotificationManager()
    private init() {}

    /// The moment a reminder should fire: `daysBefore` days ahead of the
    /// renewal, clamped so it never lands in the past. Pure, `nonisolated`
    /// (no notification-center state), and unit-tested.
    nonisolated static func fireDate(
        for renewalDate: Date,
        daysBefore: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let target = calendar.date(byAdding: .day, value: -daysBefore, to: renewalDate) ?? renewalDate
        return max(target, now.addingTimeInterval(5))
    }

    /// Requests notification permission. Safe to call repeatedly.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Authorization failures are non-fatal: the subscription is still
            // saved, the user just won't get a local reminder.
            return false
        }
    }

    /// Whether reminders would actually fire. `false` only when the user has
    /// explicitly denied permission — `.notDetermined` returns `true` so we
    /// don't nag before the first save has even asked.
    func remindersEnabled() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus != .denied
    }

    /// Schedules a local renewal reminder for `subscription` and stores the
    /// request identifier back on the model so it can be cancelled/replaced.
    func scheduleRenewalReminder(for subscription: Subscription) async {
        let center = UNUserNotificationCenter.current()

        // Replace any existing reminder for this subscription.
        if let existing = subscription.notificationIdentifier {
            center.removePendingNotificationRequests(withIdentifiers: [existing])
        }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming renewal"
        content.body = "\(subscription.name) renews soon (\(subscription.formattedPrice)). Cancel it now if you don't need it."
        content.sound = .default

        // Fire the subscription's own lead time before renewal — never in the past.
        let triggerDate = Self.fireDate(
            for: subscription.renewalDate, daysBefore: subscription.reminderDaysBefore
        )

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let identifier = subscription.id.uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            subscription.notificationIdentifier = identifier
        } catch {
            // Non-fatal — keep the saved subscription even if scheduling failed.
        }
    }

    /// Cancels a previously scheduled reminder.
    func cancelReminder(for subscription: Subscription) {
        guard let identifier = subscription.notificationIdentifier else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
        subscription.notificationIdentifier = nil
    }
}
