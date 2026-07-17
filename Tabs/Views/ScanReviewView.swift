//
//  ScanReviewView.swift
//  Tabs
//
//  The human-in-the-loop step. Heuristic detection is fuzzy by nature, so the
//  user reviews, toggles, and edits drafts before anything is committed to the
//  local store. Nothing is persisted until "Save" is tapped.
//
//  Layout per the design handoff: one inset card per candidate — selection
//  circle, editable name and price, a chip row (cycle · next renewal · charge
//  count · state badges), and an expandable statement-evidence box.
//

import SwiftUI
import SwiftData

struct ScanReviewView: View {
    /// The detected drafts, editable in place.
    @State var drafts: [ScannedSubscriptionDraft]

    /// Where the drafts came from, recorded on saved records for transparency.
    let sourceLabel: String

    /// How many source documents fed the scan, and what to call one — both
    /// only feed the caption under the title.
    var statementCount: Int = 1
    var sourceNoun: String = "statement"

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Cards whose statement-evidence box is expanded.
    @State private var expandedDraftIDs: Set<UUID> = []

    /// Live (non-trashed) subscriptions, used to flag duplicate drafts on
    /// appear and to update-in-place on save. Trashed records are excluded — a
    /// deleted subscription isn't "tracked", so re-importing it inserts fresh
    /// rather than silently overwriting a record that's hidden in the trash.
    @Query(filter: #Predicate<Subscription> { $0.deletedAt == nil })
    private var existingSubscriptions: [Subscription]

    private var selectedCount: Int { drafts.filter(\.isSelected).count }

    private var caption: String {
        ReviewCaption.text(
            candidateCount: drafts.count,
            statementCount: statementCount,
            sourceNoun: sourceNoun,
            chargeDates: drafts.flatMap { $0.transactions.compactMap(\.date) }
        )
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
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !drafts.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(selectedCount > 0 ? "Save \(selectedCount)" : "Save") {
                            saveSelected()
                        }
                        .fontWeight(.bold)
                        .disabled(selectedCount == 0)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !drafts.isEmpty { saveBar }
            }
            .onAppear(perform: markAlreadyTrackedDrafts)
        }
    }

    /// Flags drafts that already match a saved subscription, so saving updates
    /// the existing record in place instead of duplicating it. A match needs
    /// both the same merchant key and a similar price, so distinct same-brand
    /// plans (e.g. several "Apple" subscriptions) aren't all flagged off the
    /// first one. Flagged drafts stay selected — "will update" is the default.
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
            }
        }
    }

    // MARK: - List

    private var reviewList: some View {
        List {
            // One section per draft so each candidate reads as its own card.
            ForEach($drafts) { $draft in
                Section {
                    CandidateCard(
                        draft: $draft,
                        isExpanded: expandedDraftIDs.contains(draft.id),
                        onToggleEvidence: { toggleEvidence(for: draft.id) }
                    )
                } header: {
                    // The caption rides above the first card, centered.
                    if draft.id == drafts.first?.id {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity)
                            .textCase(nil)
                            .padding(.bottom, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .scrollDismissesKeyboard(.interactively)
    }

    private func toggleEvidence(for id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedDraftIDs.contains(id) {
                expandedDraftIDs.remove(id)
            } else {
                expandedDraftIDs.insert(id)
            }
        }
    }

    /// Pinned primary action: full-width capsule with the live count.
    private var saveBar: some View {
        Button {
            saveSelected()
        } label: {
            Text(selectedCount > 0
                 ? "Save \(selectedCount) subscription\(selectedCount == 1 ? "" : "s")"
                 : "Save subscriptions")
                .font(.body.weight(.bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .contentTransition(.numericText())
        }
        .background(Theme.accent.opacity(selectedCount == 0 ? 0.35 : 1), in: Capsule())
        .disabled(selectedCount == 0)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
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

// MARK: - Candidate card

/// One detected candidate: selection circle, editable name/price, chip row,
/// and (when expanded) the statement lines it was detected from.
private struct CandidateCard: View {
    @Binding var draft: ScannedSubscriptionDraft
    let isExpanded: Bool
    let onToggleEvidence: () -> Void

    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            chipRow
                .padding(.leading, 38)   // aligns under the name, past the circle
            if isExpanded, !draft.transactions.isEmpty {
                evidenceBox
                    .padding(.leading, 38)
            }
        }
        .padding(.vertical, 6)
        .opacity(draft.isSelected ? 1 : 0.55)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            // The ONLY selection control, so tapping the rest of the row never
            // unexpectedly selects/deselects.
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { draft.isSelected.toggle() }
            } label: {
                selectionCircle
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Include \(draft.name)")
            .accessibilityValue(draft.isSelected ? "selected" : "not selected")

            TextField("Name", text: $draft.name)
                .font(.headline)
                .foregroundStyle(isNameFocused ? Theme.accent : Theme.label)
                .focused($isNameFocused)

            Spacer(minLength: 8)

            TextField(
                "Price",
                value: $draft.price,
                format: .currency(code: draft.currencyCode ?? CurrencyFormat.code)
            )
            .font(.body.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Theme.label)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .fixedSize()
            .accessibilityLabel("Price for \(draft.name)")
        }
    }

    private var selectionCircle: some View {
        ZStack {
            if draft.isSelected {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
            } else {
                Circle().strokeBorder(Theme.tertiary, lineWidth: 2)
            }
        }
        .frame(width: 26, height: 26)
    }

    private var chipRow: some View {
        // Wrapping layout isn't needed — at most three chips plus one badge —
        // but keep them scrollable so long badge copy never truncates edits.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if draft.isAlreadyTracked {
                    ReviewChip(text: "Already tracked — will update", style: .warning)
                }
                if draft.amountsVary {
                    ReviewChip(text: "Amounts vary — looks one-off", style: .gray)
                }

                // Cycle chip doubles as the editor. Changing it realigns the
                // renewal date in the setter, so a draft saved as Yearly
                // doesn't keep a monthly renewal.
                Menu {
                    Picker("Cycle", selection: Binding(
                        get: { draft.billingCycle },
                        set: { draft.realignRenewal(to: $0) }
                    )) {
                        ForEach(BillingCycle.allCases) { cycle in
                            Text(cycle.displayName).tag(cycle)
                        }
                    }
                } label: {
                    ReviewChip(text: draft.billingCycle.displayName, style: .gray)
                }
                .buttonStyle(.plain)

                if !draft.transactions.isEmpty {
                    Button(action: onToggleEvidence) {
                        ReviewChip(
                            text: "\(draft.transactionCount) charge\(draft.transactionCount == 1 ? "" : "s")",
                            style: .accent
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View detected charges")
                }

                // The renewal date is the least load-bearing chip; when a
                // state badge is taking up the row, drop it rather than
                // pushing the informative chips off the card edge.
                if !draft.isAlreadyTracked && !draft.amountsVary {
                    ReviewChip(
                        text: "Next \(draft.renewalDate.formatted(.dateTime.month(.abbreviated).day()))",
                        style: .gray
                    )
                }
            }
        }
    }

    /// The statement lines this candidate was detected from — date, cleaned
    /// merchant text, and the amount, one monospaced row per charge.
    private var evidenceBox: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(draft.transactions) { transaction in
                HStack(spacing: 8) {
                    Text(Self.shortDate(transaction.date))
                        .foregroundStyle(Theme.secondary)
                    Text(RecurringChargeDetector.merchantDescription(from: transaction.rawLine))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(transaction.formattedAmount)
                        .foregroundStyle(Theme.accent)
                }
                .font(.system(size: 11, design: .monospaced))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.45))
        )
        .transition(.opacity)
    }

    private static func shortDate(_ date: Date?) -> String {
        guard let date else { return "—    " }
        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
    }
}

// MARK: - Chip

/// A small rounded badge used across the review cards. 12/600, radius 7.
private struct ReviewChip: View {
    enum Style { case gray, accent, warning }

    let text: String
    var style: Style = .gray

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .fixedSize()
    }

    private var foreground: Color {
        switch style {
        case .gray:    return Theme.secondary
        case .accent:  return Theme.accent
        case .warning: return Theme.warning
        }
    }

    private var background: Color {
        switch style {
        case .gray:    return Color(uiColor: .tertiarySystemFill)
        case .accent:  return Theme.accent.opacity(0.14)
        case .warning: return Theme.warning.opacity(0.16)
        }
    }
}

#Preview {
    ScanReviewView(
        drafts: [
            ScannedSubscriptionDraft(
                name: "Netflix", price: 15.49,
                transactions: [
                    ScannedTransaction(amount: 15.49, date: .now.addingTimeInterval(-86_400 * 5), rawLine: "05/15 NETFLIX.COM CA  -15.49", currencyCode: "USD"),
                    ScannedTransaction(amount: 15.49, date: .now.addingTimeInterval(-86_400 * 35), rawLine: "06/15 NETFLIX.COM CA  -15.49", currencyCode: "USD"),
                ]
            ),
            ScannedSubscriptionDraft(
                name: "Spotify", price: 11.99,
                transactions: [ScannedTransaction(amount: 11.99, date: .now, rawLine: "Spotify USA  11.99")]
            ),
            ScannedSubscriptionDraft(
                name: "Shell Oil", price: 42.13, isSelected: false,
                transactions: [ScannedTransaction(amount: 42.13, date: .now, rawLine: "05/02 SHELL OIL 5744  42.13")],
                amountsVary: true
            ),
        ],
        sourceLabel: "PDF statement",
        statementCount: 3
    )
    .modelContainer(for: Subscription.self, inMemory: true)
}
