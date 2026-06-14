//
//  AddSubscriptionView.swift
//  Tabs
//
//  Manual entry — the companion to statement scanning. Some subscriptions
//  never show up on the statements you import (family plans, gift cards,
//  annual charges outside the imported window), so the user can always add
//  one by hand.
//
//  PRIVACY: writes a record to the local SwiftData store and schedules a
//  local reminder. Nothing else.
//

import SwiftUI
import SwiftData

struct AddSubscriptionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var price: Decimal?
    @State private var billingCycle: BillingCycle = .monthly
    @State private var renewalDate = BillingCycle.monthly.nextRenewalDate()

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && (price ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Subscription") {
                    HStack(spacing: Theme.Space.m) {
                        BrandAvatar(name: trimmedName.isEmpty ? "?" : trimmedName, size: 44)
                        TextField("Name (e.g. Netflix)", text: $name)
                            .font(.tabsHeadline)
                            .textInputAutocapitalization(.words)
                    }
                }

                Section {
                    HStack {
                        Text("Price")
                        Spacer()
                        TextField(
                            CurrencyFormat.string(from: 9.99),
                            value: $price,
                            format: .currency(code: CurrencyFormat.code)
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    }

                    Picker("Billing cycle", selection: $billingCycle) {
                        ForEach(BillingCycle.allCases) { cycle in
                            Text(cycle.displayName).tag(cycle)
                        }
                    }
                    // Picking a cycle implies a different horizon; reset the
                    // default date suggestion. (Runs before any manual tweak
                    // matters much — the date field is right below.)
                    .onChange(of: billingCycle) { _, newCycle in
                        renewalDate = newCycle.nextRenewalDate()
                    }

                    DatePicker(
                        "Next renewal",
                        selection: $renewalDate,
                        in: Calendar.current.startOfDay(for: .now)...,
                        displayedComponents: .date
                    )
                } header: {
                    Text("Billing")
                } footer: {
                    if billingCycle != .monthly, let price, price > 0 {
                        Text("≈ \(CurrencyFormat.string(from: price * billingCycle.monthlyCostFactor)) / mo")
                    }
                }
            }
            .navigationTitle("Add Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let price, canSave else { return }
        let subscription = Subscription(
            name: trimmedName,
            price: price,
            billingCycle: billingCycle,
            renewalDate: renewalDate,
            source: nil,  // manual entry — no statement provenance
            currencyCode: CurrencyFormat.deviceCode
        )
        modelContext.insert(subscription)

        Task {
            await NotificationManager.shared.requestAuthorization()
            await NotificationManager.shared.scheduleRenewalReminder(for: subscription)
        }

        dismiss()
    }
}

#Preview {
    AddSubscriptionView()
        .modelContainer(for: Subscription.self, inMemory: true)
}
