//
//  SubscriptionDetailView.swift
//  Tabs
//
//  Detail + edit screen for a saved subscription. Scan detection is fuzzy, so
//  everything it guessed — price, cycle, renewal date — is editable here, and
//  the statement charges that justified the subscription are shown as evidence.
//
//  PRIVACY: edits a local SwiftData record in place. No I/O beyond the local
//  store and the local notification center.
//

import SwiftUI
import SwiftData

struct SubscriptionDetailView: View {
    @Bindable var subscription: Subscription

    @Environment(\.dismiss) private var dismiss

    /// Set when leaving via trash so `onDisappear` doesn't reschedule a reminder
    /// for a record we just pulled out of tracking.
    @State private var isDeleted = false
    /// Snapshot of the billing-relevant fields when this screen appeared, so
    /// the reminder is only re-scheduled on the way out if something changed.
    @State private var entrySnapshot: BillingSnapshot?

    /// The fields whose change should re-bake the renewal reminder.
    private struct BillingSnapshot: Equatable {
        let name: String
        let price: Decimal
        let cycleRaw: String
        let renewalDate: Date
    }
    private var currentSnapshot: BillingSnapshot {
        BillingSnapshot(
            name: subscription.name, price: subscription.price,
            cycleRaw: subscription.billingCycleRaw, renewalDate: subscription.renewalDate
        )
    }

    var body: some View {
        Form {
            if let cancelledAt = subscription.cancelledAt {
                Section {
                    Label(
                        "Cancelled \(cancelledAt.formatted(date: .abbreviated, time: .omitted))",
                        systemImage: "xmark.circle.fill"
                    )
                    .foregroundStyle(Theme.tertiary)

                    Button {
                        restore()
                    } label: {
                        Label("Restore Subscription", systemImage: "arrow.uturn.backward")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Kept for your records. Restoring resumes reminders and counts it toward your monthly spend again.")
                }
            }

            Section {
                HStack(spacing: Theme.Space.m) {
                    BrandAvatar(name: subscription.name, size: 44)
                    TextField("Name", text: $subscription.name)
                        .font(.tabsHeadline)
                }
            }

            Section {
                HStack {
                    Text("Price")
                    Spacer()
                    TextField(
                        "Price",
                        value: $subscription.price,
                        format: .currency(code: subscription.currencyCode ?? CurrencyFormat.code)
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.label)
                }

                // Recompute the renewal date in the setter so picking a new
                // cycle always realigns it — more reliable than observing the
                // change after the fact.
                Picker("Billing cycle", selection: Binding(
                    get: { subscription.billingCycle },
                    set: { subscription.realignRenewal(to: $0) }
                )) {
                    ForEach(BillingCycle.allCases) { cycle in
                        Text(cycle.displayName).tag(cycle)
                    }
                }

                DatePicker(
                    "Next renewal",
                    selection: $subscription.renewalDate,
                    in: Calendar.current.startOfDay(for: .now)...,
                    displayedComponents: .date
                )
            } header: {
                Text("Billing")
            } footer: {
                if subscription.billingCycle != .monthly {
                    Text("≈ \(CurrencyFormat.string(from: subscription.monthlyEquivalentPrice, code: subscription.currencyCode)) / mo")
                }
            }

            if !subscription.charges.isEmpty {
                Section {
                    ForEach(subscription.charges) { charge in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(charge.dateText)
                                    .foregroundStyle(Theme.secondary)
                                Spacer()
                                Text(charge.formattedAmount)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.label)
                            }
                            .font(.subheadline)

                            // Raw statement line — evidence for this charge.
                            Text(charge.rawLine)
                                .font(.caption2.monospaced())
                                .foregroundStyle(Theme.tertiary)
                                .lineLimit(1)
                        }
                    }
                } header: {
                    Text("Detected charges")
                } footer: {
                    Text("The statement lines this subscription was detected from.")
                }
            }

            Section {
                if subscription.isActive {
                    Button {
                        markCancelled()
                    } label: {
                        Label("Mark as Cancelled", systemImage: "xmark.circle")
                    }
                }
                Button("Move to Trash", role: .destructive) {
                    moveToTrash()
                }
            } footer: {
                Text(provenance)
            }
        }
        .navigationTitle(subscription.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if entrySnapshot == nil { entrySnapshot = currentSnapshot }
        }
        // Re-bake the pending reminder on the way out, but only when the record
        // is still active and a billing field actually changed — no churn on a
        // plain look-and-back.
        .onDisappear {
            guard !isDeleted, subscription.isActive, entrySnapshot != currentSnapshot else { return }
            let subscription = subscription
            Task { await NotificationManager.shared.scheduleRenewalReminder(for: subscription) }
        }
    }

    /// "Detected from your bank statements · Added Jun 10, 2026"-style footer.
    private var provenance: String {
        let added = "Added \(subscription.createdAt.formatted(.dateTime.month().day().year()))"
        guard let source = subscription.source else { return added }
        return "Detected from your \(source) · \(added)"
    }

    /// Move to the trash and return to the list. The record is kept and stays
    /// restorable from Trash; we cancel its pending reminder and leave.
    private func moveToTrash() {
        isDeleted = true
        subscription.moveToTrash()
        NotificationManager.shared.cancelReminder(for: subscription)
        dismiss()
    }

    /// Soft-cancel and return to the list. The `isActive` guard in
    /// `onDisappear` keeps it from rescheduling the reminder we just cancelled.
    private func markCancelled() {
        subscription.cancelledAt = .now
        NotificationManager.shared.cancelReminder(for: subscription)
        dismiss()
    }

    /// Restore in place: clear the cancelled flag, roll the renewal up to the
    /// present, reschedule, and reset the change baseline.
    private func restore() {
        subscription.cancelledAt = nil
        subscription.rollRenewalForward()
        entrySnapshot = currentSnapshot
        let restored = subscription
        Task {
            await NotificationManager.shared.requestAuthorization()
            await NotificationManager.shared.scheduleRenewalReminder(for: restored)
        }
    }
}

#Preview {
    NavigationStack {
        SubscriptionDetailView(
            subscription: Subscription(
                name: "Netflix",
                price: 15.49,
                billingCycle: .monthly,
                renewalDate: .now.addingTimeInterval(86_400 * 12),
                source: "bank statements",
                charges: [
                    ChargeRecord(amount: 15.49, date: .now.addingTimeInterval(-86_400 * 18), rawLine: "NETFLIX.COM  -15.49"),
                    ChargeRecord(amount: 15.49, date: .now.addingTimeInterval(-86_400 * 48), rawLine: "NETFLIX.COM  -15.49"),
                ]
            )
        )
    }
    .modelContainer(for: Subscription.self, inMemory: true)
}
