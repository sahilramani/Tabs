//
//  ScanReviewView.swift
//  Tabs
//
//  The human-in-the-loop step. Heuristic detection is fuzzy by nature, so the
//  user reviews, toggles, and edits drafts before anything is committed to the
//  local store. Nothing is persisted until "Save Selected" is tapped.
//

import SwiftUI
import SwiftData

struct ScanReviewView: View {
    /// The detected drafts, editable in place via toggles & steppers.
    @State var drafts: [ScannedSubscriptionDraft]

    /// Where the drafts came from, recorded on saved records for transparency.
    let sourceLabel: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Live (non-trashed) subscriptions, used to flag duplicate drafts on
    /// appear and to update-in-place on save. Trashed records are excluded — a
    /// deleted subscription isn't "tracked", so re-importing it inserts fresh
    /// rather than silently overwriting a record that's hidden in the trash.
    @Query(filter: #Predicate<Subscription> { $0.deletedAt == nil })
    private var existingSubscriptions: [Subscription]

    private var selectedCount: Int { drafts.filter(\.isSelected).count }
    private var allSelected: Bool { !drafts.isEmpty && selectedCount == drafts.count }

    /// Combined monthly-equivalent total of the currently checked rows.
    private var selectedMonthlyTotal: Decimal {
        drafts.filter(\.isSelected).reduce(Decimal(0)) { $0 + $1.monthlyEquivalentPrice }
    }

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions detected",
                        systemImage: "magnifyingglass",
                        description: Text("We couldn't find any known subscriptions in this statement. You can add them manually instead.")
                    )
                } else {
                    reviewList
                }
            }
            .navigationTitle("Review Findings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !drafts.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(allSelected ? "Deselect All" : "Select All") {
                            let newValue = !allSelected
                            for index in drafts.indices { drafts[index].isSelected = newValue }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !drafts.isEmpty { saveBar }
            }
            .onAppear(perform: markAlreadyTrackedDrafts)
        }
    }

    /// Flags drafts that already match a saved subscription and deselects them,
    /// so re-importing a statement doesn't create duplicates. A match needs both
    /// the same merchant key and a similar price, so distinct same-brand plans
    /// (e.g. several "Apple" subscriptions) aren't all flagged off the first one.
    /// The user can still re-select a flagged row to save it anyway.
    private func markAlreadyTrackedDrafts() {
        guard !existingSubscriptions.isEmpty else { return }
        var liveByKey: [String: [Subscription]] = [:]
        for record in existingSubscriptions {
            liveByKey[RecurringChargeDetector.key(for: record.name), default: []].append(record)
        }
        for index in drafts.indices where !drafts[index].isAlreadyTracked {
            let key = RecurringChargeDetector.key(for: drafts[index].name)
            let price = drafts[index].price
            if let group = liveByKey[key], group.contains(where: { Self.pricesMatch($0.price, price) }) {
                drafts[index].isAlreadyTracked = true
                drafts[index].isSelected = false
            }
        }
    }

    private var reviewList: some View {
        List {
            Section {
                ForEach($drafts) { $draft in
                    DraftRow(draft: $draft)
                }
            } header: {
                Text("\(drafts.count) potential subscription\(drafts.count == 1 ? "" : "s") found")
            } footer: {
                Text("Detected on-device from your \(sourceLabel). Prices and cycles are best-guesses — edit any field before saving.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Sticky bottom bar with the running total and the primary action.
    private var saveBar: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedCount) selected")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.label)
                    Text("\(CurrencyFormat.string(from: selectedMonthlyTotal)) / mo")
                        .font(.tabsCaption)
                        .foregroundStyle(Theme.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button {
                    saveSelected()
                } label: {
                    Text("Save Selected")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedCount == 0)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Persistence

    private func saveSelected() {
        let chosen = drafts.filter(\.isSelected)
        guard !chosen.isEmpty else { return }

        let (updates, inserts) = Self.plan(drafts: chosen, against: existingSubscriptions)

        var touched: [Subscription] = []
        // Re-importing a newer statement updates the matched live record in
        // place instead of creating a duplicate.
        for (existing, draft) in updates {
            existing.name = draft.name
            existing.price = draft.price
            existing.billingCycle = draft.billingCycle
            existing.renewalDate = draft.renewalDate
            existing.currencyCode = draft.currencyCode
            existing.charges = draft.transactions.map(ChargeRecord.init(transaction:))
            touched.append(existing)
        }
        for draft in inserts {
            let subscription = Subscription(draft: draft, source: sourceLabel)
            modelContext.insert(subscription)
            touched.append(subscription)
        }

        // Schedule/refresh local reminders off the main actor; persistence is done.
        Task {
            await NotificationManager.shared.requestAuthorization()
            for subscription in touched {
                await NotificationManager.shared.scheduleRenewalReminder(for: subscription)
            }
        }

        dismiss()
    }

    /// Decides, for each chosen draft, whether it updates an existing record or
    /// becomes a new one.
    ///
    /// A draft matches a *live* (non-trashed) record that shares its merchant
    /// key **and** has a similar price. Price is part of the identity because
    /// one brand can bill several distinct subscriptions under the same
    /// descriptor — Apple One, iCloud, and Apple Music all read as "Apple" but
    /// at very different amounts; keying on name alone would collapse them onto
    /// one record. Matching by price *band* (not exact value) still absorbs the
    /// normal drift of a single plan across statements. Each existing record is
    /// matched at most once, so several same-brand drafts map to their own rows.
    ///
    /// Pure, so the rule is unit-testable; the caller performs the inserts/updates.
    static func plan(
        drafts chosen: [ScannedSubscriptionDraft],
        against existing: [Subscription]
    ) -> (updates: [(Subscription, ScannedSubscriptionDraft)], inserts: [ScannedSubscriptionDraft]) {
        // Live records grouped by brand key; mutable so a matched record is
        // consumed and can't absorb a second draft.
        var liveByKey: [String: [Subscription]] = [:]
        for record in existing where !record.isTrashed {
            liveByKey[RecurringChargeDetector.key(for: record.name), default: []].append(record)
        }

        var updates: [(Subscription, ScannedSubscriptionDraft)] = []
        var inserts: [ScannedSubscriptionDraft] = []
        for draft in chosen {
            let key = RecurringChargeDetector.key(for: draft.name)
            if let candidates = liveByKey[key],
               let matchIndex = bestPriceMatchIndex(for: draft.price, in: candidates) {
                updates.append((candidates[matchIndex], draft))
                liveByKey[key]?.remove(at: matchIndex)
            } else {
                inserts.append(draft)
            }
        }
        return (updates, inserts)
    }

    /// Whether two prices are close enough to be the same subscription seen
    /// across two statements. The 15% band absorbs a plan's normal drift while
    /// keeping a brand's distinct price points (e.g. iCloud $2.99 vs Apple One
    /// $19.99) firmly apart.
    static func pricesMatch(_ a: Decimal, _ b: Decimal) -> Bool {
        let hi = max(a, b)
        let lo = min(a, b)
        guard hi > 0 else { return true }
        return (hi - lo) <= hi * Decimal(0.15)
    }

    /// The index of the closest-priced candidate within the price band, or nil
    /// when none is close enough.
    private static func bestPriceMatchIndex(for price: Decimal, in candidates: [Subscription]) -> Int? {
        var best: (index: Int, distance: Decimal)?
        for (index, candidate) in candidates.enumerated() where pricesMatch(candidate.price, price) {
            let distance = abs(candidate.price - price)
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }
}

/// A single editable row: checkbox + name + price + cycle.
private struct DraftRow: View {
    @Binding var draft: ScannedSubscriptionDraft
    @FocusState private var isNameFocused: Bool
    /// Drives the transactions popover (tap, not long-press — long-press fought
    /// with the name TextField and never fired reliably inside the List).
    @State private var showingTransactions = false

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            // Checkbox-style toggle — the ONLY selection control, so tapping the
            // rest of the row never unexpectedly selects/deselects.
            Button {
                draft.isSelected.toggle()
            } label: {
                Image(systemName: draft.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(draft.isSelected ? Theme.accent : Theme.tertiary)
                    .symbolEffect(.bounce, value: draft.isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Include \(draft.name)")
            .accessibilityValue(draft.isSelected ? "selected" : "not selected")

            BrandAvatar(name: draft.name, size: 32)
                .opacity(draft.isSelected ? 1 : 0.4)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                // Row 1: name, with the cycle pill anchored at the trailing
                // edge so it never competes with the price for width (it used
                // to wrap "Monthly" onto two lines).
                HStack(spacing: Theme.Space.s) {
                    TextField("Name", text: $draft.name)
                        .font(.tabsHeadline)
                        .foregroundStyle(isNameFocused ? Theme.accent : Theme.label)
                        .focused($isNameFocused)

                    Spacer(minLength: Theme.Space.s)

                    // Cycle menu styled as an accent pill. Changing it realigns
                    // the renewal date in the setter, so a draft saved as Yearly
                    // doesn't keep a monthly renewal.
                    Picker("Cycle", selection: Binding(
                        get: { draft.billingCycle },
                        set: { draft.realignRenewal(to: $0) }
                    )) {
                        ForEach(BillingCycle.allCases) { cycle in
                            Text(cycle.displayName).tag(cycle)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .font(.caption.weight(.medium))
                    .tint(Theme.accent)
                    .padding(.horizontal, 6)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .fixedSize()
                }

                // Row 2: price, qualifiers, and the charge-evidence link.
                HStack(spacing: Theme.Space.s) {
                    // Editable: detection often picks a slightly-off amount, so
                    // the price can be corrected right here before saving.
                    TextField(
                        "Price",
                        value: $draft.price,
                        format: .currency(code: draft.currencyCode ?? CurrencyFormat.code)
                    )
                    .font(.tabsSubhead)
                    .foregroundStyle(Theme.label)
                    .keyboardType(.decimalPad)
                    .fixedSize()
                    .accessibilityLabel("Price for \(draft.name)")

                    // Clarify the figure is an average when it spans charges.
                    if draft.transactionCount > 1 {
                        Text("avg\(draft.billingCycle.shortSuffix)")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondary)
                    }

                    // Duplicate guard: this merchant is already on the home list.
                    if draft.isAlreadyTracked {
                        Text("Already tracked")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.warning.opacity(0.14), in: Capsule())
                            .fixedSize()
                    }

                    // Dedicated, reliable tap target to inspect the underlying charges.
                    if !draft.transactions.isEmpty {
                        Button {
                            showingTransactions = true
                        } label: {
                            HStack(spacing: Theme.Space.xs) {
                                Text(draft.transactionCount == 1
                                     ? "1 charge"
                                     : "\(draft.transactionCount) charges")
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingTransactions) {
                            DraftTransactionsPreview(draft: draft)
                                .presentationCompactAdaptation(.popover)
                        }
                        .accessibilityLabel("View detected charges")
                    }
                }
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .opacity(draft.isSelected ? 1 : 0.55)
    }
}

/// The popup shown on long-press: every detected charge for a draft, with dates.
private struct DraftTransactionsPreview: View {
    let draft: ScannedSubscriptionDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                BrandAvatar(name: draft.name, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(draft.name).font(.tabsHeadline)
                    Text("Avg \(draft.formattedPrice) · \(draft.transactionCount) charge\(draft.transactionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }

            Divider()

            // Scrollable so a brand with many charges doesn't overflow the popover.
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(draft.transactions) { tx in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(tx.dateText)
                                    .foregroundStyle(Theme.secondary)
                                Spacer(minLength: Theme.Space.l)
                                Text(tx.formattedAmount)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.label)
                            }
                            .font(.subheadline)

                            // Raw source line — lets you spot a bad detection.
                            Text(tx.rawLine)
                                .font(.caption2.monospaced())
                                .foregroundStyle(Theme.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(Theme.Space.l)
        .frame(width: 300)
    }
}

#Preview {
    ScanReviewView(
        drafts: [
            ScannedSubscriptionDraft(
                name: "Netflix", price: 15.49,
                transactions: [
                    ScannedTransaction(amount: 15.49, date: .now.addingTimeInterval(-86_400 * 5), rawLine: "NETFLIX.COM  -15.49"),
                    ScannedTransaction(amount: 15.49, date: .now.addingTimeInterval(-86_400 * 35), rawLine: "NETFLIX.COM  -15.49"),
                    ScannedTransaction(amount: 14.99, date: .now.addingTimeInterval(-86_400 * 65), rawLine: "NETFLIX.COM  -14.99"),
                ]
            ),
            ScannedSubscriptionDraft(
                name: "Spotify", price: 11.99,
                transactions: [ScannedTransaction(amount: 11.99, date: .now, rawLine: "Spotify USA  11.99")]
            ),
            ScannedSubscriptionDraft(name: "Adobe", price: 54.99),
        ],
        sourceLabel: "PDF statement"
    )
    .modelContainer(for: Subscription.self, inMemory: true)
}
