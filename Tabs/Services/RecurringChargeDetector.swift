//
//  RecurringChargeDetector.swift
//  Tabs
//
//  PRIVACY: Pure on-device string processing. No network, no disk, no logging.
//
//  A *generic* recurring-charge detector. Unlike a fixed brand list, this parses
//  every statement line into (date, merchant, amount), groups by merchant, drops
//  obvious non-subscription lines, and surfaces likely subscriptions. The brand
//  catalog is used only to (a) clean up names for merchants we recognize and
//  (b) boost confidence — it is no longer a gate.
//
//  Heuristics are deliberately conservative to limit false positives, and the
//  knobs at the top are the place to tune precision/recall.
//

import Foundation

struct RecurringChargeDetector {

    let catalog: SubscriptionKeywordCatalog

    // MARK: - Tunables
    /// Ignore amounts below this — auth holds, taxes, and OCR fragments like $0.09.
    var minAmount: Decimal = 0.50
    /// Ignore amounts above this — running balances / totals, not consumer subs.
    var maxAmount: Decimal = 2000
    /// A *single* charge above this is treated as a one-off purchase even for
    /// a catalog brand (e.g. a $1,246 Zwift trainer vs. the $19.99 app sub).
    /// Recurring charges of any size still pass.
    var maxSingleChargeAmount: Decimal = 300

    init(catalog: SubscriptionKeywordCatalog = SubscriptionKeywordCatalog()) {
        self.catalog = catalog
    }

    // MARK: - Entry point

    /// Turns a blob of statement text into subscription drafts.
    ///
    /// Pipeline: parse lines → group by merchant → split each merchant into
    /// *amount clusters* (a merchant can carry several subscriptions at
    /// different price points, e.g. Apple One + iCloud both as
    /// "APPLE.COM/BILL") → gate each cluster → one draft per surviving cluster.
    func drafts(from text: String) -> [ScannedSubscriptionDraft] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Parse each line into a candidate charge.
        var order: [String] = []
        var groups: [String: [Charge]] = [:]
        for line in lines {
            guard let charge = charge(from: line) else { continue }
            if groups[charge.key] == nil { order.append(charge.key) }
            groups[charge.key, default: []].append(charge)
        }

        // Build a draft per amount cluster that clears the subscription bar.
        let drafts: [ScannedSubscriptionDraft] = order.flatMap { key -> [ScannedSubscriptionDraft] in
            guard let group = groups[key] else { return [] }

            return Self.amountClusters(in: dedupe(group)).compactMap { cluster in
                // A cluster is either a likely subscription (selected draft), a
                // recurring-but-varying near miss (deselected, badged draft for
                // the user to judge), or noise (dropped).
                let amountsVary: Bool
                if isLikelySubscription(cluster) {
                    amountsVary = false
                } else if isRecurringButVarying(cluster) {
                    amountsVary = true
                } else {
                    return nil
                }

                let transactions = cluster
                    .map { ScannedTransaction(amount: $0.amount, date: $0.date, rawLine: $0.rawLine, currencyCode: $0.currencyCode) }
                    .sorted { Self.recency($0) > Self.recency($1) }   // newest first

                // Use the real charge dates when we have them: the gap between
                // charges reveals the cycle, and the last charge anchors the
                // next renewal far better than "one month from scan day".
                let dates = transactions.compactMap(\.date)
                let cycle = Self.inferredCycle(fromDates: dates) ?? .monthly
                let renewalDate = dates.max().map { Self.nextRenewal(after: $0, cycle: cycle) }

                return ScannedSubscriptionDraft(
                    name: cluster.first?.displayName ?? key,
                    price: Self.average(transactions.map(\.amount)),
                    billingCycle: cycle,
                    currencyCode: Self.dominantCurrency(in: cluster),
                    renewalDate: renewalDate,
                    isSelected: !amountsVary,
                    transactions: transactions,
                    amountsVary: amountsVary
                )
            }
        }

        return drafts.sorted {
            let name = $0.name.localizedCaseInsensitiveCompare($1.name)
            if name != .orderedSame { return name == .orderedAscending }
            return $0.price > $1.price
        }
    }

    // MARK: - Line → charge

    private struct Charge {
        let key: String          // merchant grouping key
        let displayName: String  // friendly name shown in the UI
        let amount: Decimal
        let date: Date?
        let rawLine: String
        let currencyCode: String?
    }

    private func charge(from line: String) -> Charge? {
        // 1. Drop obvious non-subscription lines up front.
        guard !catalog.isExcluded(line) else { return nil }

        let isKnown = catalog.knownDisplayName(in: line) != nil
        let date = Self.firstDate(in: line)

        // 2. Real transaction lines carry a date; statement boilerplate
        //    ("New Balance $1,681.29", "Minimum Payment Due $25.00") almost
        //    never does. Undated lines pass only for catalog brands or lines
        //    with an explicit subscription cue.
        guard date != nil || isKnown || catalog.hasSubscriptionHint(line) else { return nil }

        // 3. Pick the charge amount.
        guard let amount = Self.chargeAmount(in: line, min: minAmount, max: maxAmount) else { return nil }

        // 4. Merchant name: prefer the curated catalog name, else derive one.
        let description = Self.merchantDescription(from: line)
        guard description.count >= 3 else { return nil }
        let displayName = catalog.knownDisplayName(in: line) ?? Self.friendlyName(from: description)
        guard !displayName.isEmpty else { return nil }

        // 5. Reject names with no merchant signal — statement vocabulary
        //    ("New Balance", "Total Daily Cash") or OCR shrapnel ("Date De
        //    Sc") — those are summary/disclosure lines, not merchants.
        guard isKnown || !Self.isJunkMerchantName(displayName) else { return nil }

        return Charge(
            key: Self.key(for: displayName),
            displayName: displayName,
            amount: amount,
            date: date,
            rawLine: line,
            currencyCode: Self.currencyCode(in: line)
        )
    }

    /// The currency a cluster's charges agree on (its most common detected
    /// code), or `nil` when none carried a symbol — in which case the UI
    /// falls back to the device currency.
    private static func dominantCurrency(in cluster: [Charge]) -> String? {
        let codes = cluster.compactMap(\.currencyCode)
        guard !codes.isEmpty else { return nil }
        return Dictionary(grouping: codes, by: { $0 })
            .max { $0.value.count < $1.value.count }?.key
    }

    /// Whether one *amount cluster* of a merchant's charges looks like a
    /// subscription.
    ///
    /// Catalog brands and explicit subscription cues ("RECURRING",
    /// "MEMBERSHIP") qualify outright — except a lone charge that's too big to
    /// be a plausible subscription (hardware bought from a brand we know).
    ///
    /// Anything else must *behave* like a subscription: ≥3 charges on ≥3
    /// distinct days, near-identical amounts, and near-identical spacing that
    /// matches a known billing cadence. Real statements showed why each leg is
    /// required — a weekly restaurant habit recurs but with varying bills and
    /// jittery gaps; Amazon orders cluster in amount but land on random days.
    private func isLikelySubscription(_ cluster: [Charge]) -> Bool {
        let known = cluster.contains { catalog.knownDisplayName(in: $0.rawLine) != nil }
        let hinted = cluster.contains { catalog.hasSubscriptionHint($0.rawLine) }
        if known || hinted {
            if cluster.count == 1, let only = cluster.first {
                return only.amount <= maxSingleChargeAmount
            }
            return true
        }

        let days = Set(cluster.compactMap { $0.date.map { Calendar.current.startOfDay(for: $0) } })
        guard cluster.count >= 3, days.count >= 3 else { return false }

        // Subscriptions bill an exact price; meals and groceries don't.
        guard Self.amountsAreStable(cluster.map(\.amount)) else { return false }

        return Self.inferredCycle(fromDates: Array(days)) != nil
            && Self.gapsAreRegular(days: Array(days))
    }

    /// Whether a cluster's amounts are tight enough to be one billed price:
    /// max spread within 10% of the low amount (or $1 for small prices).
    private static func amountsAreStable(_ amounts: [Decimal]) -> Bool {
        guard let lo = amounts.min(), let hi = amounts.max() else { return false }
        return hi - lo <= max(lo * Decimal(0.1), 1)
    }

    /// The near miss worth surfacing: an unknown merchant that charges on a
    /// *regular, recognizable cadence* but with *varying amounts* — a monthly
    /// gas fill-up, not Netflix. Fails `isLikelySubscription` only on the
    /// amount-stability leg, so the review screen shows it deselected with an
    /// "Amounts vary" badge instead of hiding it entirely. Catalog brands and
    /// hinted lines never take this path (they already pass outright).
    private func isRecurringButVarying(_ cluster: [Charge]) -> Bool {
        let days = Set(cluster.compactMap { $0.date.map { Calendar.current.startOfDay(for: $0) } })
        guard cluster.count >= 3, days.count >= 3,
              !Self.amountsAreStable(cluster.map(\.amount))
        else { return false }

        return Self.inferredCycle(fromDates: Array(days)) != nil
            && Self.gapsAreRegular(days: Array(days))
    }

    /// True when the spacing between charge days is regular enough to be a
    /// billing schedule: every gap within 30% of the median gap, or of twice
    /// the median (one skipped/missing statement month is tolerated).
    static func gapsAreRegular(days: [Date], calendar: Calendar = .current) -> Bool {
        let sorted = Set(days.map { calendar.startOfDay(for: $0) }).sorted()
        let gaps = zip(sorted.dropFirst(), sorted).compactMap {
            calendar.dateComponents([.day], from: $1, to: $0).day
        }.map { Double($0) }
        guard gaps.count >= 2 else { return true }   // one gap is trivially regular

        let median = gaps.sorted()[gaps.count / 2]
        guard median > 0 else { return false }
        return gaps.allSatisfy { gap in
            abs(gap - median) <= median * 0.3 || abs(gap - median * 2) <= median * 0.6
        }
    }

    /// Splits a merchant's charges into clusters of similar amounts, so two
    /// subscriptions billed under one descriptor (Apple One $12.99 + iCloud
    /// $2.99, both "APPLE.COM/BILL") become separate drafts instead of one
    /// nonsense average.
    ///
    /// Chain-linked: sorted by amount, a charge joins the current cluster when
    /// it's within 25% of the cluster's last amount (or within $2 for small
    /// prices). 25% absorbs utility-style drift (Comcast $61–$76) while
    /// splitting genuinely different price points ($2.99 vs $12.99).
    private static func amountClusters(in charges: [Charge]) -> [[Charge]] {
        guard !charges.isEmpty else { return [] }
        let sorted = charges.sorted { $0.amount < $1.amount }

        var clusters: [[Charge]] = []
        var current: [Charge] = [sorted[0]]
        for charge in sorted.dropFirst() {
            let previous = current.last!.amount
            let tolerance = max(previous * Decimal(0.25), 2)
            if charge.amount - previous <= tolerance {
                current.append(charge)
            } else {
                clusters.append(current)
                current = [charge]
            }
        }
        clusters.append(current)
        return clusters
    }

    // MARK: - Aggregation helpers

    /// Drops exact duplicate charges (same date + amount) so overlapping
    /// statements don't double-count a month.
    private func dedupe(_ group: [Charge]) -> [Charge] {
        var seen = Set<String>()
        return group.filter { c in
            let k = "\(c.date?.timeIntervalSince1970 ?? -1)|\(c.amount)|\(c.date == nil ? c.rawLine : "")"
            return seen.insert(k).inserted
        }
    }

    private static func average(_ amounts: [Decimal]) -> Decimal {
        guard !amounts.isEmpty else { return 0 }
        var quotient = amounts.reduce(Decimal(0), +) / Decimal(amounts.count)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, 2, .plain)
        return rounded
    }

    private static func recency(_ tx: ScannedTransaction) -> TimeInterval {
        tx.date?.timeIntervalSince1970 ?? -.greatestFiniteMagnitude
    }

    // MARK: - Cycle & renewal inference

    /// Infers the billing cycle from the median gap between successive distinct
    /// charge days. Median (not mean) so one OCR-mangled date can't skew the
    /// result. Returns `nil` with fewer than two dated charges or when the gap
    /// matches no known cadence.
    static func inferredCycle(fromDates dates: [Date], calendar: Calendar = .current) -> BillingCycle? {
        let days = Set(dates.map { calendar.startOfDay(for: $0) }).sorted()
        guard days.count >= 2 else { return nil }

        let gaps = zip(days.dropFirst(), days).compactMap {
            calendar.dateComponents([.day], from: $1, to: $0).day
        }
        guard !gaps.isEmpty else { return nil }

        let median = gaps.sorted()[gaps.count / 2]
        return BillingCycle.inferred(fromGapDays: median)
    }

    /// The next renewal strictly derived from the statement: one cycle after
    /// the most recent charge, rolled forward until it's today or later (old
    /// statements would otherwise predict a renewal in the past).
    static func nextRenewal(
        after lastCharge: Date,
        cycle: BillingCycle,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        var next = cycle.nextRenewalDate(from: lastCharge, calendar: calendar)
        // Bounded so a wildly wrong parsed date can't spin forever.
        var hops = 0
        while calendar.startOfDay(for: next) < today && hops < 1000 {
            next = cycle.nextRenewalDate(from: next, calendar: calendar)
            hops += 1
        }
        return next
    }

    // MARK: - Text parsing primitives

    /// Money like `$9.99`, `-15.99`, `1,299.00`, `€12.99`, `£10.00`. Two
    /// decimals required so we never match dates or reference numbers. The
    /// optional currency symbol is captured so the charge keeps its currency;
    /// the number format stays US-grouped (`1,234.56`) — decimal-comma
    /// statements are a separate, deeper parsing problem left for later.
    private static let moneyRegex = try! NSRegularExpression(
        pattern: #"[-–−]?\s?[$€£]?\s?\d{1,3}(?:,\d{3})*\.\d{2}\b"#
    )

    /// Detects the currency a line's amounts are in, from its symbol. `$` is
    /// treated as USD (the common case; CAD/AUD/etc. are indistinguishable by
    /// symbol alone). Returns `nil` when no symbol is present so the caller can
    /// fall back to the device currency.
    static func currencyCode(in line: String) -> String? {
        if line.contains("€") { return "EUR" }
        if line.contains("£") { return "GBP" }
        if line.contains("$") { return "USD" }
        return nil
    }

    /// All money values on a line, in order, as positive `Decimal`s.
    static func moneyValues(in line: String) -> [Decimal] {
        let range = NSRange(line.startIndex..., in: line)
        return moneyRegex.matches(in: line, range: range).compactMap { match in
            guard let r = Range(match.range, in: line) else { return nil }
            let cleaned = line[r].filter { $0.isNumber || $0 == "." }
            return Decimal(string: cleaned)
        }
    }

    /// Matches a cash-back percentage token like "3%" (Apple Card layout).
    private static let percentRegex = try! NSRegularExpression(pattern: #"\d+(\.\d+)?%"#)

    /// The actual charge amount on a line.
    ///
    /// Default: the *first* in-range money value — bank registers (Chase,
    /// BofA) print the charge first and trail it with a running balance.
    /// Cash-back layouts invert this: Apple Card prints "3% $0.39 $12.99"
    /// (rate, reward, charge), so when a percent token is present the charge
    /// is the *last* in-range value instead.
    static func chargeAmount(in line: String, min: Decimal, max: Decimal) -> Decimal? {
        let inRange = moneyValues(in: line).filter { $0 >= min && $0 <= max }
        guard !inRange.isEmpty else { return nil }
        let hasPercent = percentRegex.firstMatch(
            in: line, range: NSRange(line.startIndex..., in: line)
        ) != nil
        return hasPercent ? inRange.last : inRange.first
    }

    private static let dateDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

    /// First date anywhere in the line (handles 02/03/26, 2026-02-03, "Feb 3").
    ///
    /// Statement charges are always in the past, but `NSDataDetector` resolves
    /// yearless dates like "03/31" *forward* (e.g. to next year), which would
    /// wreck cadence inference. Any parsed date in the future is rolled back a
    /// year.
    static func firstDate(in line: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let detector = dateDetector,
              let date = detector.firstMatch(
                  in: line, range: NSRange(line.startIndex..., in: line)
              )?.date
        else { return nil }

        if date > now, let adjusted = calendar.date(byAdding: .year, value: -1, to: date) {
            return adjusted
        }
        return date
    }

    /// Strips dates, money, and long digit runs (phone/card/reference numbers)
    /// and collapses whitespace, leaving the merchant text.
    static func merchantDescription(from line: String) -> String {
        var s = line
        let full = NSRange(s.startIndex..., in: s)
        s = moneyRegex.stringByReplacingMatches(in: s, range: full, withTemplate: " ")
        s = s.replacingOccurrences(of: #"\b\d{4}-\d{2}-\d{2}\b"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b\d{1,2}[/-]\d{1,2}([/-]\d{2,4})?\b"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b\d{3,}\b"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tokens that carry no brand meaning; used to trim derived names.
    private static let noiseTokens: Set<String> = [
        "com", "inc", "llc", "ltd", "corp", "co", "the",
        "http", "https", "www", "usa", "us",
        "bill", "billing", "autopay", "recurring", "purchase", "pos",
        "des", "id", "ppd", "ccd", "web", "ach", "tst",
        "card", "checkcard", "debit", "credit", "sp", "sq", "amzn",
        "paypal", "pp", "ref", "trans", "transaction",
    ]

    /// Vocabulary that only ever appears in statement furniture — balances,
    /// totals, summaries, disclosures. A derived name made *entirely* of these
    /// (e.g. "New Balance", "Total Daily Cash", "We Will Debit") is a summary
    /// line, not a merchant.
    private static let statementVocabulary: Set<String> = [
        "new", "previous", "beginning", "ending", "current", "total", "balance",
        "payment", "payments", "purchases", "credits", "fees", "fee", "charges",
        "charged", "amount", "due", "date", "minimum", "interest", "apr", "aprs",
        "cash", "advance", "advances", "daily", "monthly", "annual", "period",
        "statement", "account", "summary", "transactions", "installment",
        "installments", "financed", "remaining", "available", "limit", "rewards",
        "points", "percentage", "yield", "rate", "deducted", "debited",
        "debit", "debits", "credit",
        "we", "will", "your", "you", "and", "for", "of", "or", "more", "keep",
        "otherwise", "next", "post", "trans", "issued", "by", "column", "on",
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct",
        "nov", "dec", "january", "february", "march", "april", "june", "july",
        "august", "september", "october", "november", "december",
    ]

    /// True when a derived name carries no real merchant signal: every token
    /// is statement furniture ("New Balance"), or nothing substantive remains
    /// after OCR shredded the line ("Date De Sc" from "Date De sc r ipti on").
    /// A real merchant name has at least one non-vocabulary token of 3+
    /// letters.
    static func isJunkMerchantName(_ name: String) -> Bool {
        let tokens = name.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        return !tokens.contains { $0.count >= 3 && !statementVocabulary.contains($0) }
    }

    /// True for register/reference codes like "B27gp2dj1", "F16328", or
    /// "8230509AQEHMVAL6Y" — tokens mixing several digits into letters carry
    /// no brand meaning and would otherwise split one merchant into dozens of
    /// "different" ones (each Amazon order has a unique code).
    private static func looksLikeReferenceCode(_ token: String) -> Bool {
        let digits = token.filter(\.isNumber).count
        let letters = token.filter(\.isLetter).count
        return digits >= 2 && letters >= 1
    }

    /// Derives a human-ish name from a cleaned description: the first couple of
    /// meaningful tokens, title-cased. Imperfect by nature — the review UI lets
    /// the user rename — but good enough to recognize a merchant.
    static func friendlyName(from description: String) -> String {
        let tokens = description
            .split { $0 == " " || $0 == "*" || $0 == "#" }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,-_/")) }
            .filter { !$0.isEmpty }

        var kept: [String] = []
        for token in tokens {
            let lower = token.lowercased()
            let letters = token.filter { $0.isLetter }.count
            // Reference codes are skipped outright — they appear *between*
            // meaningful tokens ("Mcdonald's F16328 Mountain View").
            if Self.looksLikeReferenceCode(token) { continue }
            // Skip pure noise / near-numeric tokens; once we have a name, stop.
            if noiseTokens.contains(lower) || letters < 2 {
                if kept.isEmpty { continue } else { break }
            }
            kept.append(token)
            if kept.count == 3 { break }
        }
        return Self.titleCased(kept.joined(separator: " "))
    }

    static func titleCased(_ s: String) -> String {
        s.split(separator: " ")
            .map { word -> String in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + String(lower.dropFirst())
            }
            .joined(separator: " ")
    }

    /// Stable grouping key from a display name (letters/digits, capped length).
    static func key(for displayName: String) -> String {
        let alnum = displayName.lowercased().filter { $0.isLetter || $0.isNumber }
        return String(alnum.prefix(16))
    }
}
