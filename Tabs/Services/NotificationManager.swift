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

    /// How many days before the renewal date to fire the reminder.
    var leadTimeDays: Int = 3

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

        // Fire `leadTimeDays` before renewal — but never in the past.
        let fireDate = Calendar.current.date(
            byAdding: .day, value: -leadTimeDays, to: subscription.renewalDate
        ) ?? subscription.renewalDate
        let triggerDate = max(fireDate, Date().addingTimeInterval(5))

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
