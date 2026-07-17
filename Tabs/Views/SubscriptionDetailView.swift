//
//  SubscriptionDetailView.swift
//  Tabs
//
//  Detail + edit screen for a saved subscription. Scan detection is fuzzy, so
//  everything it guessed — name, price, cycle, renewal date — is editable
//  here, and the statement charges that justified the subscription are one
//  tap away as evidence.
//
//  Layout per the design handoff: centered monogram header with a status
//  chip, one card of editable billing rows, one card of provenance, then
//  Cancel/Restore and Delete as their own centered rows.
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

    // Edit affordances.
    @State private var isShowingRenameAlert = false
    @State private var draftName = ""
    @State private var isShowingPriceAlert = false
    @State private var draftPrice: Decimal?
    @State private var isShowingDeleteConfirmation = false

    /// Reminder lead times offered in the picker, in days before renewal.
    private static let reminderOptions = [0, 1, 2, 3, 5, 7]

    /// The fields whose change should re-bake the renewal reminder.
    private struct BillingSnapshot: Equatable {
        let name: String
        let price: Decimal
        let cycleRaw: String
        let renewalDate: Date
        let reminderDaysBefore: Int
    }
    private var currentSnapshot: BillingSnapshot {
        BillingSnapshot(
            name: subscription.name, price: subscription.price,
            cycleRaw: subscription.billingCycleRaw, renewalDate: subscription.renewalDate,
            reminderDaysBefore: subscription.reminderDaysBefore
        )
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            billingCard
            provenanceCard
            actionRows
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    draftName = subscription.name
                    isShowingRenameAlert = true
                }
            }
        }
        .alert("Rename Subscription", isPresented: $isShowingRenameAlert) {
            TextField("Name", text: $draftName)
            Button("Save") {
                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { subscription.name = trimmed }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Price", isPresented: $isShowingPriceAlert) {
            TextField(
                "Price",
                value: $draftPrice,
                format: .currency(code: subscription.currencyCode ?? CurrencyFormat.code)
            )
            .keyboardType(.decimalPad)
            Button("Save") {
                if let draftPrice, draftPrice > 0 { subscription.price = draftPrice }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete Subscription?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Subscription", role: .destructive) { moveToTrash() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("It moves to the Trash — you can restore it from there.")
        }
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            BrandAvatar(name: subscription.name, size: 76)

            Text(subscription.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.label)
                .multilineTextAlignment(.center)

            Text(rateLine)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)

            statusChip
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// "$15.49 per month · $185.88 a year" — the yearly equivalent gives the
    /// real cost of keeping it. Yearly plans show the monthly equivalent
    /// instead, which is the more surprising number in that direction.
    private var rateLine: String {
        let price = "\(subscription.formattedPrice) \(subscription.billingCycle.perLabel)"
        if subscription.billingCycle == .yearly {
            let monthly = CurrencyFormat.string(from: subscription.monthlyEquivalentPrice, code: subscription.currencyCode)
            return "\(price) · ≈ \(monthly) a month"
        }
        let yearly = CurrencyFormat.string(from: subscription.monthlyEquivalentPrice * 12, code: subscription.currencyCode)
        return "\(price) · \(yearly) a year"
    }

    @ViewBuilder
    private var statusChip: some View {
        if let cancelledAt = subscription.cancelledAt {
            chip(
                dot: Theme.tertiary,
                text: "Cancelled \(cancelledAt.formatted(.dateTime.month(.abbreviated).day()))",
                foreground: Theme.secondary,
                background: Color(uiColor: .tertiarySystemFill)
            )
        } else {
            chip(
                dot: Theme.accent,
                text: "Active · renews \(renewalPhrase)",
                foreground: Theme.accent,
                background: Theme.accent.opacity(0.14)
            )
        }
    }

    private var renewalPhrase: String {
        let days = subscription.daysUntilRenewal
        switch days {
        case ..<0:  return subscription.renewalDate.formatted(.dateTime.month(.abbreviated).day())
        case 0:     return "today"
        case 1:     return "tomorrow"
        case 2...7: return "in \(days) days"
        default:    return subscription.renewalDate.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func chip(dot: Color, text: String, foreground: Color, background: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
    }

    // MARK: - Billing card

    private var billingCard: some View {
        Section {
            // Price → alert with a currency field.
            Button {
                draftPrice = subscription.price
                isShowingPriceAlert = true
            } label: {
                valueRow("Price", value: subscription.formattedPrice, chevron: true)
            }

            // Recompute the renewal date in the setter so picking a new cycle
            // always realigns it — more reliable than observing after the fact.
            Menu {
                Picker("Billing cycle", selection: Binding(
                    get: { subscription.billingCycle },
                    set: { subscription.realignRenewal(to: $0) }
                )) {
                    ForEach(BillingCycle.allCases) { cycle in
                        Text(cycle.displayName).tag(cycle)
                    }
                }
            } label: {
                valueRow("Billing cycle", value: subscription.billingCycle.displayName, chevron: true)
            }

            DatePicker(
                "Next renewal",
                selection: $subscription.renewalDate,
                in: Calendar.current.startOfDay(for: .now)...,
                displayedComponents: .date
            )
            .tint(Theme.accent)

            Menu {
                Picker("Reminder", selection: $subscription.reminderDaysBefore) {
                    ForEach(Self.reminderOptions, id: \.self) { days in
                        Text(Self.reminderLabel(days)).tag(days)
                    }
                }
            } label: {
                valueRow("Reminder", value: Self.reminderLabel(subscription.reminderDaysBefore), chevron: true)
            }
        } footer: {
            if subscription.billingCycle != .monthly {
                Text("≈ \(CurrencyFormat.string(from: subscription.monthlyEquivalentPrice, code: subscription.currencyCode)) / mo")
            }
        }
    }

    private static func reminderLabel(_ days: Int) -> String {
        switch days {
        case 0:  return "On renewal day"
        case 1:  return "1 day before"
        default: return "\(days) days before"
        }
    }

    private func valueRow(_ label: String, value: String, chevron: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.label)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.secondary)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Provenance card

    /// Where this record came from: when it was first seen and the statement
    /// charges behind it. Manually added subscriptions just show their date.
    private var provenanceCard: some View {
        Section {
            if let firstCharge = subscription.charges.compactMap(\.date).min() {
                valueRow(
                    "First detected",
                    value: firstCharge.formatted(.dateTime.month(.abbreviated).year()),
                    chevron: false
                )
            } else {
                valueRow(
                    "Added",
                    value: subscription.createdAt.formatted(.dateTime.month(.abbreviated).year()),
                    chevron: false
                )
            }

            if !subscription.charges.isEmpty {
                NavigationLink {
                    ChargesListView(subscription: subscription)
                } label: {
                    HStack {
                        Text("Matched charges")
                            .foregroundStyle(Theme.label)
                        Spacer()
                        Text("\(subscription.charges.count)")
                            .foregroundStyle(Theme.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionRows: some View {
        Section {
            if subscription.isActive {
                Button {
                    markCancelled()
                } label: {
                    Text("Cancel Subscription")
                        .font(.headline)
                        .foregroundStyle(Theme.warning)
                        .frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    restore()
                } label: {
                    Text("Restore Subscription")
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                }
            }
        }

        Section {
            Button {
                isShowingDeleteConfirmation = true
            } label: {
                Text("Delete Subscription")
                    .font(.headline)
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            VStack(spacing: 4) {
                Text("Cancelling keeps the history and stops the reminder. Everything stays on this iPhone.")
                Text(provenance)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
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

// MARK: - Matched charges

/// The statement lines a subscription was detected from — the evidence view
/// pushed from the "Matched charges" row.
private struct ChargesListView: View {
    let subscription: Subscription

    var body: some View {
        List {
            Section {
                ForEach(subscription.charges) { charge in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(charge.dateText)
                                .foregroundStyle(Theme.secondary)
                            Spacer()
                            Text(charge.formattedAmount)
                                .monospacedDigit()
                                .foregroundStyle(Theme.accent)
                        }
                        .font(.subheadline)

                        // Raw statement line — evidence for this charge.
                        Text(charge.rawLine)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.tertiary)
                            .lineLimit(1)
                    }
                }
            } footer: {
                Text("The statement lines this subscription was detected from.")
            }
        }
        .navigationTitle("Matched Charges")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SubscriptionDetailView(
            subscription: Subscription(
                name: "Netflix",
                price: 15.49,
                billingCycle: .monthly,
                renewalDate: .now.addingTimeInterval(86_400 * 3),
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
