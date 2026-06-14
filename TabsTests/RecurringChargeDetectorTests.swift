//
//  RecurringChargeDetectorTests.swift
//  TabsTests
//
//  Unit tests for the generic recurring-charge detector and its supporting
//  date/cycle math. All fixtures are synthetic statement text; no I/O.
//

import XCTest
@testable import Tabs

final class RecurringChargeDetectorTests: XCTestCase {

    private var detector: RecurringChargeDetector!

    override func setUp() {
        super.setUp()
        detector = RecurringChargeDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Builds a Date at local midnight from explicit components, so cycle and
    /// renewal tests are deterministic and never depend on "now".
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    // MARK: - moneyValues(in:)

    func testMoneyValuesParsesSymbolsNegativesAndThousandsSeparators() {
        let values = RecurringChargeDetector.moneyValues(
            in: "Coffee $4.50 then 1,299.00 and a credit of -15.99"
        )
        XCTAssertEqual(values, [
            Decimal(string: "4.50")!,
            Decimal(string: "1299.00")!,
            Decimal(string: "15.99")!,
        ])
        // Negatives come back as positive magnitudes.
        XCTAssertTrue(values.allSatisfy { $0 > 0 })
    }

    func testMoneyValuesIgnoresDatesAndWholeDollarAmounts() {
        // Dates have no two-decimal tail; whole dollars lack the required cents.
        XCTAssertTrue(RecurringChargeDetector.moneyValues(in: "01/05/2026 ref 123456").isEmpty)
        XCTAssertTrue(RecurringChargeDetector.moneyValues(in: "2026-01-05 statement").isEmpty)
        XCTAssertTrue(RecurringChargeDetector.moneyValues(in: "Pay $10 now").isEmpty)
    }

    // MARK: - drafts(from:) end-to-end

    func testDraftsDetectsRecurringNetflixChargesAsSingleMonthlyDraft() throws {
        let statement = """
        2026-01-05 NETFLIX.COM 15.49
        2026-02-05 NETFLIX.COM 15.49
        2026-03-05 NETFLIX.COM 16.49
        2026-01-07 AMAZON MKTPLACE PMTS 45.00
        """

        let drafts = detector.drafts(from: statement)

        XCTAssertEqual(drafts.count, 1)
        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(draft.name, "Netflix")
        XCTAssertEqual(draft.billingCycle, .monthly)
        XCTAssertEqual(draft.transactionCount, 3)
        // Price is the average of all charges, rounded to two decimal places:
        // (15.49 + 15.49 + 16.49) / 3 = 15.8233… → 15.82.
        XCTAssertEqual(draft.price, Decimal(string: "15.82")!)
        // Renewal is derived from the last charge but always rolled forward to
        // today or later, so never assert an absolute date here.
        XCTAssertGreaterThanOrEqual(draft.renewalDate, today)
    }

    func testDraftsInfersYearlyCycleFromTwoChargesAYearApart() throws {
        let statement = """
        2024-06-15 ACME STREAMING SUBSCRIPTION 99.00
        2025-06-15 ACME STREAMING SUBSCRIPTION 99.00
        """

        let drafts = detector.drafts(from: statement)

        XCTAssertEqual(drafts.count, 1)
        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(draft.billingCycle, .yearly)
        XCTAssertEqual(draft.transactionCount, 2)
        XCTAssertGreaterThanOrEqual(draft.renewalDate, today)
    }

    func testDraftsExcludesMarketplaceAndTransferLines() {
        let statement = """
        2026-01-03 AMAZON MKTPLACE PMTS 23.45
        2026-01-04 ZELLE TRANSFER TO JANE 50.00
        2026-01-08 ONLINE TRANSFER TO SAVINGS 200.00
        """

        XCTAssertTrue(detector.drafts(from: statement).isEmpty)
    }

    func testDraftsSkipsSingleUnknownMerchantWithoutSubscriptionHint() {
        // One charge, unknown brand, no subscription cue → not a subscription.
        let drafts = detector.drafts(from: "2026-03-01 CORNER COFFEE SHOP 4.75")
        XCTAssertTrue(drafts.isEmpty)
    }

    func testDraftsKeepsSingleChargeWhenLineCarriesSubscriptionHint() throws {
        let drafts = detector.drafts(from: "2026-03-01 CORNER COFFEE CLUB MEMBERSHIP 4.75")

        XCTAssertEqual(drafts.count, 1)
        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(draft.name, "Corner Coffee Club")
        // A single dated charge can't reveal a cadence → monthly fallback.
        XCTAssertEqual(draft.billingCycle, .monthly)
    }

    func testDraftsDedupesIdenticalChargesWithSameDateAndAmount() throws {
        // Overlapping statement imports repeat the exact same line.
        let statement = """
        2026-03-05 SPOTIFY USA 11.99
        2026-03-05 SPOTIFY USA 11.99
        """

        let drafts = detector.drafts(from: statement)

        XCTAssertEqual(drafts.count, 1)
        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(draft.name, "Spotify")
        XCTAssertEqual(draft.transactionCount, 1)
        XCTAssertEqual(draft.price, Decimal(string: "11.99")!)
    }

    // MARK: - friendlyName(from:) / key(for:)

    func testFriendlyNameStripsNoiseTokensAndTitleCases() {
        // POS prefix, long digit runs, and trailing COM are all noise.
        XCTAssertEqual(RecurringChargeDetector.friendlyName(from: "POS 12345678 HULU COM"), "Hulu")
        // Caps at the first three meaningful tokens.
        XCTAssertEqual(
            RecurringChargeDetector.friendlyName(from: "ADOBE CREATIVE CLOUD EXTRA WORDS"),
            "Adobe Creative Cloud"
        )
    }

    func testKeyForNormalizesDisplayNames() {
        // Lowercased, letters and digits only.
        XCTAssertEqual(RecurringChargeDetector.key(for: "Netflix.com"), "netflixcom")
        XCTAssertEqual(RecurringChargeDetector.key(for: "HBO Max"), "hbomax")
        // Capped at 16 characters for stable grouping.
        XCTAssertEqual(
            RecurringChargeDetector.key(for: "Acme Streaming Subscription"),
            "acmestreamingsub"
        )
    }

    // MARK: - BillingCycle.inferred(fromGapDays:)

    func testBillingCycleInferredBandEdges() {
        XCTAssertNil(BillingCycle.inferred(fromGapDays: 4))
        XCTAssertEqual(BillingCycle.inferred(fromGapDays: 5), .weekly)
        XCTAssertEqual(BillingCycle.inferred(fromGapDays: 10), .weekly)
        XCTAssertNil(BillingCycle.inferred(fromGapDays: 11))

        XCTAssertNil(BillingCycle.inferred(fromGapDays: 23))
        XCTAssertEqual(BillingCycle.inferred(fromGapDays: 24), .monthly)
        XCTAssertEqual(BillingCycle.inferred(fromGapDays: 38), .monthly)
        XCTAssertNil(BillingCycle.inferred(fromGapDays: 39))

        XCTAssertNil(BillingCycle.inferred(fromGapDays: 79))
        XCTAssertEqual(BillingCycle.inferred(fromGapDays: 80), .quarterly)
        XCTAssertEqual(BillingCycle.inferred(fromGapDays: 100), .quarterly)
        XCTAssertNil(BillingCycle.inferred(fromGapDays: 101))

        XCTAssertNil(BillingCycle.inferred(fromGapDays: 329))
        XCTAssertEqual(BillingCycle.inferred(fromGapDays: 330), .yearly)
        XCTAssertEqual(BillingCycle.inferred(fromGapDays: 400), .yearly)
        XCTAssertNil(BillingCycle.inferred(fromGapDays: 401))
    }

    // MARK: - inferredCycle(fromDates:)

    func testInferredCycleUsesMedianGapBetweenDistinctDays() {
        let monthly = RecurringChargeDetector.inferredCycle(
            fromDates: [date(2026, 1, 5), date(2026, 2, 5), date(2026, 3, 5)]
        )
        XCTAssertEqual(monthly, .monthly)

        let weekly = RecurringChargeDetector.inferredCycle(
            fromDates: [date(2026, 3, 1), date(2026, 3, 8)]
        )
        XCTAssertEqual(weekly, .weekly)

        // Fewer than two distinct dated charges → no inference.
        XCTAssertNil(RecurringChargeDetector.inferredCycle(fromDates: [date(2026, 3, 1)]))
        XCTAssertNil(RecurringChargeDetector.inferredCycle(fromDates: []))
    }

    // MARK: - nextRenewal(after:cycle:now:)

    func testNextRenewalRollsPastChargeDatesForwardBeyondNow() {
        let calendar = Calendar.current
        let now = date(2025, 6, 15)

        // An old anchor rolls month-by-month until it lands on or after "now".
        let rolled = RecurringChargeDetector.nextRenewal(
            after: date(2020, 1, 1), cycle: .monthly, now: now, calendar: calendar
        )
        XCTAssertGreaterThanOrEqual(rolled, calendar.startOfDay(for: now))
        XCTAssertTrue(calendar.isDate(rolled, inSameDayAs: date(2025, 7, 1)))

        // A recent anchor is simply one cycle later — no extra rolling.
        let upcoming = RecurringChargeDetector.nextRenewal(
            after: date(2025, 7, 1), cycle: .monthly, now: now, calendar: calendar
        )
        XCTAssertTrue(calendar.isDate(upcoming, inSameDayAs: date(2025, 8, 1)))
    }

    // MARK: - Subscription.rollRenewalForward

    func testRollRenewalForwardAdvancesPastDateAndReturnsTrue() {
        let calendar = Calendar.current
        let now = date(2025, 6, 15)
        let subscription = Subscription(
            name: "Netflix",
            price: Decimal(string: "15.49")!,
            billingCycle: .monthly,
            renewalDate: date(2025, 3, 10)
        )

        let moved = subscription.rollRenewalForward(now: now, calendar: calendar)

        XCTAssertTrue(moved)
        // Mar 10 → Apr 10 → May 10 → Jun 10 (< Jun 15) → Jul 10.
        XCTAssertTrue(calendar.isDate(subscription.renewalDate, inSameDayAs: date(2025, 7, 10)))
        XCTAssertGreaterThanOrEqual(
            calendar.startOfDay(for: subscription.renewalDate),
            calendar.startOfDay(for: now)
        )
    }

    func testRollRenewalForwardLeavesFutureDateUntouchedAndReturnsFalse() {
        let calendar = Calendar.current
        let now = date(2025, 6, 15)
        let futureRenewal = date(2025, 12, 25)
        let subscription = Subscription(
            name: "Spotify",
            price: Decimal(string: "11.99")!,
            billingCycle: .monthly,
            renewalDate: futureRenewal
        )

        let moved = subscription.rollRenewalForward(now: now, calendar: calendar)

        XCTAssertFalse(moved)
        XCTAssertEqual(subscription.renewalDate, futureRenewal)
    }

    // MARK: - Real-statement regressions
    //
    // Fixtures below are sanitized versions of layouts that broke the detector
    // against real bank exports: Apple Card's cash-back column, Chase's
    // running-balance register, statement summary furniture, and OCR shrapnel.

    func testDraftsSplitsOneMerchantIntoPriceClusters() throws {
        // Two different subscriptions billed under the same APPLE.COM/BILL
        // descriptor must come back as two drafts, not one nonsense average.
        let statement = """
        01/27/2026 APPLE.COM/BILL ONE APPLE PARK WAY CUPERTINO 95014 CA USA 3% $0.39 $12.99
        02/27/2026 APPLE.COM/BILL ONE APPLE PARK WAY CUPERTINO 95014 CA USA 3% $0.39 $12.99
        03/27/2026 APPLE.COM/BILL ONE APPLE PARK WAY CUPERTINO 95014 CA USA 3% $0.39 $12.99
        01/19/2026 APPLE.COM/BILL ONE APPLE PARK WAY CUPERTINO 95014 CA USA 3% $0.09 $2.99
        02/19/2026 APPLE.COM/BILL ONE APPLE PARK WAY CUPERTINO 95014 CA USA 3% $0.09 $2.99
        03/19/2026 APPLE.COM/BILL ONE APPLE PARK WAY CUPERTINO 95014 CA USA 3% $0.09 $2.99
        """

        let drafts = detector.drafts(from: statement)

        XCTAssertEqual(drafts.count, 2)
        // Same name, sorted by price descending within it.
        XCTAssertEqual(drafts.map(\.name), ["Apple", "Apple"])
        XCTAssertEqual(drafts[0].price, Decimal(string: "12.99")!)
        XCTAssertEqual(drafts[1].price, Decimal(string: "2.99")!)
        XCTAssertEqual(drafts[0].billingCycle, .monthly)
        XCTAssertEqual(drafts[1].billingCycle, .monthly)
        XCTAssertEqual(drafts[0].transactionCount, 3)
    }

    func testChargeAmountHandlesCashbackAndRunningBalanceLayouts() {
        // Apple Card: "rate, reward, charge" — the charge is the LAST value.
        XCTAssertEqual(
            RecurringChargeDetector.chargeAmount(
                in: "11/15/2025 APPLE.COM/BILL CUPERTINO CA USA 3% $1.80 $59.99",
                min: Decimal(string: "0.5")!, max: 2000
            ),
            Decimal(string: "59.99")!
        )
        // Bank register: charge first, trailing running balance ignored.
        XCTAssertEqual(
            RecurringChargeDetector.chargeAmount(
                in: "03/30 Card Purchase 03/27 Dart Coffee CO Santa Barbara CA Card 7939 - 22.80 398.91",
                min: Decimal(string: "0.5")!, max: 2000
            ),
            Decimal(string: "22.80")!
        )
    }

    func testFirstDateNeverReturnsFutureDatesForYearlessCharges() throws {
        // NSDataDetector resolves yearless dates like "12/31" forward; charges
        // are always in the past, so the detector must roll them back.
        let now = Date()
        let parsed = RecurringChargeDetector.firstDate(in: "12/31 PURCHASE COFFEE 13.99", now: now)
        let unwrapped = try XCTUnwrap(parsed)
        XCTAssertLessThanOrEqual(unwrapped, now)
    }

    func testIsJunkMerchantNameRejectsBoilerplateAndOCRShrapnel() {
        // Statement furniture.
        XCTAssertTrue(RecurringChargeDetector.isJunkMerchantName("New Balance"))
        XCTAssertTrue(RecurringChargeDetector.isJunkMerchantName("Total Daily Cash"))
        XCTAssertTrue(RecurringChargeDetector.isJunkMerchantName("We Will Debit"))
        // OCR-shredded header ("Date De sc r ipti on").
        XCTAssertTrue(RecurringChargeDetector.isJunkMerchantName("Date De Sc"))
        // Real merchants survive.
        XCTAssertFalse(RecurringChargeDetector.isJunkMerchantName("Netflix"))
        XCTAssertFalse(RecurringChargeDetector.isJunkMerchantName("Whole Foods"))
    }

    func testGapsAreRegularAcceptsSchedulesToleratesOneSkipRejectsJitter() {
        // Clean monthly schedule.
        XCTAssertTrue(RecurringChargeDetector.gapsAreRegular(
            days: [date(2026, 1, 5), date(2026, 2, 5), date(2026, 3, 5)]
        ))
        // One missing statement month (gap ≈ 2× median) is tolerated.
        XCTAssertTrue(RecurringChargeDetector.gapsAreRegular(
            days: [date(2026, 1, 5), date(2026, 2, 5), date(2026, 3, 5), date(2026, 5, 5)]
        ))
        // A restaurant habit: recurs, but with jittery spacing.
        XCTAssertFalse(RecurringChargeDetector.gapsAreRegular(
            days: [date(2026, 1, 1), date(2026, 1, 4), date(2026, 1, 20), date(2026, 2, 18)]
        ))
    }

    func testDraftsRejectsUnknownMerchantWithVaryingAmounts() {
        // Recurs on a near-monthly rhythm, but every bill differs — groceries,
        // not a subscription.
        let statement = """
        2026-01-05 SUNNYVALE SPICE BAZAAR 42.17
        2026-02-04 SUNNYVALE SPICE BAZAAR 58.90
        2026-03-06 SUNNYVALE SPICE BAZAAR 47.33
        """

        XCTAssertTrue(detector.drafts(from: statement).isEmpty)
    }

    func testDraftsKeepsUnknownMerchantWithExactRegularCharges() throws {
        // Unknown brand, no cue — but the exact same price on a clean monthly
        // schedule behaves like a subscription.
        let statement = """
        2026-01-12 SCOUTS HOUSE DUES 32.23
        2026-02-12 SCOUTS HOUSE DUES 32.23
        2026-03-12 SCOUTS HOUSE DUES 32.23
        """

        let drafts = detector.drafts(from: statement)

        XCTAssertEqual(drafts.count, 1)
        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(draft.billingCycle, .monthly)
        XCTAssertEqual(draft.price, Decimal(string: "32.23")!)
    }

    func testDraftsIgnoresUndatedSummaryLines() {
        // Boilerplate recurs on every statement but carries no date — it must
        // never become a "monthly subscription".
        let statement = """
        New Balance $1,681.29
        Previous Balance $1,338.77
        Minimum Payment Due $25.00
        Total Daily Cash $45.20
        Apple Card Monthly Installments $74.91
        """

        XCTAssertTrue(detector.drafts(from: statement).isEmpty)
    }

    func testDraftsDropsLoneOversizedChargeEvenForKnownBrands() {
        // A $1,246 one-off (hardware) from a brand whose subscription costs
        // $19.99 must not surface as a $1,246/mo subscription.
        let oneOff = "11/28 PURCHASE ZWIFT INC. LONG BEACH CA $1,246.24"
        XCTAssertTrue(detector.drafts(from: oneOff).isEmpty)

        // The plausibly-priced single charge from the same brand still passes.
        let subscription = "11/28 PURCHASE ZWIFT INC. LONG BEACH CA $19.99"
        XCTAssertEqual(detector.drafts(from: subscription).count, 1)
    }

    func testDraftsKeepsAmazonPrimeRenewalButNotMarketplaceOrders() throws {
        let statement = """
        2026-02-11 AMAZON PRIME XY12AB34 AMZN.COM/BILL WA 151.68
        2026-02-13 AMAZON MKTPLACE PMTS AB98ZZ11 AMZN.COM/BILL WA 23.45
        """

        let drafts = detector.drafts(from: statement)

        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(try XCTUnwrap(drafts.first).name, "Amazon Prime")
    }

    // MARK: - Currency

    func testCurrencyCodeDetectedFromSymbol() {
        XCTAssertEqual(RecurringChargeDetector.currencyCode(in: "01/05 NETFLIX €12.99"), "EUR")
        XCTAssertEqual(RecurringChargeDetector.currencyCode(in: "01/05 SPOTIFY £9.99"), "GBP")
        XCTAssertEqual(RecurringChargeDetector.currencyCode(in: "01/05 HULU $13.24"), "USD")
        // No symbol → nil, so the UI falls back to the device currency.
        XCTAssertNil(RecurringChargeDetector.currencyCode(in: "01/05 HULU 13.24"))
    }

    func testMoneyValuesParsesEuroAndPoundSymbols() {
        XCTAssertEqual(
            RecurringChargeDetector.moneyValues(in: "NETFLIX €12.99 charge"),
            [Decimal(string: "12.99")!]
        )
        XCTAssertEqual(
            RecurringChargeDetector.moneyValues(in: "SPOTIFY £9.99 monthly"),
            [Decimal(string: "9.99")!]
        )
    }

    func testDraftsCarryDetectedCurrencyThroughToTheModel() throws {
        // A euro-denominated Netflix run should produce a EUR draft, and the
        // saved Subscription should inherit that currency.
        let statement = """
        2026-01-05 NETFLIX.COM €12.99
        2026-02-05 NETFLIX.COM €12.99
        2026-03-05 NETFLIX.COM €12.99
        """

        let draft = try XCTUnwrap(detector.drafts(from: statement).first)
        XCTAssertEqual(draft.currencyCode, "EUR")
        XCTAssertEqual(draft.transactions.first?.currencyCode, "EUR")

        let subscription = Subscription(draft: draft, source: "PDF statement")
        XCTAssertEqual(subscription.currencyCode, "EUR")
        XCTAssertEqual(subscription.charges.first?.currencyCode, "EUR")
    }

    // MARK: - Renewal rollover continuity

    func testRollRenewalForwardLandsOnExactCycleBoundary() {
        // A yearly subscription two years overdue should roll to a future date
        // that's still on its original day-of-year, not drift.
        let calendar = Calendar.current
        let now = date(2026, 6, 15)
        let subscription = Subscription(
            name: "Amazon Prime",
            price: Decimal(string: "151.68")!,
            billingCycle: .yearly,
            renewalDate: date(2024, 3, 10)
        )

        XCTAssertTrue(subscription.rollRenewalForward(now: now, calendar: calendar))
        // 2024-03-10 → 2025 → 2026 → 2027-03-10 (first on/after 2026-06-15).
        XCTAssertTrue(calendar.isDate(subscription.renewalDate, inSameDayAs: date(2027, 3, 10)))
    }

    // MARK: - realignRenewal(to:) — cycle change moves the renewal

    func testRealignRenewalAnchorsOnLatestChargeWhenCycleChanges() {
        let calendar = Calendar.current
        let now = date(2026, 6, 13)
        // A detected monthly Amazon Prime with charges through Mar 15.
        let subscription = Subscription(
            name: "Amazon Prime",
            price: Decimal(string: "151.68")!,
            billingCycle: .monthly,
            renewalDate: date(2026, 6, 15),
            charges: [
                ChargeRecord(amount: 151.68, date: date(2026, 1, 15), rawLine: "AMAZON PRIME 151.68"),
                ChargeRecord(amount: 151.68, date: date(2026, 3, 15), rawLine: "AMAZON PRIME 151.68"),
                ChargeRecord(amount: 151.68, date: date(2026, 2, 15), rawLine: "AMAZON PRIME 151.68"),
            ]
        )

        subscription.realignRenewal(to: .yearly, now: now, calendar: calendar)

        XCTAssertEqual(subscription.billingCycle, .yearly)
        // Latest charge is Mar 15, 2026 → +1yr → Mar 15, 2027 (first on/after now).
        XCTAssertTrue(calendar.isDate(subscription.renewalDate, inSameDayAs: date(2027, 3, 15)))
        XCTAssertGreaterThanOrEqual(
            calendar.startOfDay(for: subscription.renewalDate), calendar.startOfDay(for: now)
        )
    }

    func testRealignRenewalToMonthlyRollsForwardPastNow() {
        let calendar = Calendar.current
        let now = date(2026, 6, 13)
        let subscription = Subscription(
            name: "Amazon Prime", price: 151.68, billingCycle: .yearly,
            renewalDate: date(2027, 3, 15),
            charges: [ChargeRecord(amount: 151.68, date: date(2026, 3, 15), rawLine: "AMAZON PRIME 151.68")]
        )

        subscription.realignRenewal(to: .monthly, now: now, calendar: calendar)

        // Mar 15 → Apr 15 → May 15 → Jun 15 (first on/after Jun 13).
        XCTAssertTrue(calendar.isDate(subscription.renewalDate, inSameDayAs: date(2026, 6, 15)))
    }

    func testRealignRenewalFallsBackToCreatedAtWhenNoCharges() {
        let calendar = Calendar.current
        let now = date(2026, 6, 13)
        // Manually added subscription: no charge evidence, so the creation date
        // anchors the new cadence.
        let subscription = Subscription(
            name: "Gym", price: 40, billingCycle: .monthly,
            renewalDate: date(2026, 6, 20), createdAt: date(2025, 1, 1)
        )

        subscription.realignRenewal(to: .yearly, now: now, calendar: calendar)

        // Jan 1, 2025 → 2026 (< now) → 2027-01-01 (first on/after Jun 13, 2026).
        XCTAssertTrue(calendar.isDate(subscription.renewalDate, inSameDayAs: date(2027, 1, 1)))
    }

    // MARK: - Cancel / archive state

    func testNewSubscriptionIsActiveByDefault() {
        let subscription = Subscription(
            name: "Netflix", price: 15.49, billingCycle: .monthly, renewalDate: date(2026, 7, 1)
        )
        XCTAssertTrue(subscription.isActive)
        XCTAssertNil(subscription.cancelledAt)
    }

    func testMarkingCancelledFlipsActiveState() {
        let subscription = Subscription(
            name: "Hulu", price: 13.24, billingCycle: .monthly, renewalDate: date(2026, 7, 1)
        )
        subscription.cancelledAt = date(2026, 6, 12)
        XCTAssertFalse(subscription.isActive)
    }

    // MARK: - ScanReviewView.plan — insert vs update on save

    func testPlanTreatsDraftAsNewWhenOnlyMatchIsTrashed() {
        // Re-importing a statement after deleting the subscription must add it
        // back, not silently overwrite the hidden trashed record.
        let trashed = Subscription(
            name: "Amazon Prime", price: 151.68, billingCycle: .monthly,
            renewalDate: date(2026, 7, 1), deletedAt: date(2026, 6, 14)
        )
        let draft = ScannedSubscriptionDraft(name: "Amazon Prime", price: 151.68)

        let plan = ScanReviewView.plan(drafts: [draft], against: [trashed])

        XCTAssertTrue(plan.updates.isEmpty)
        XCTAssertEqual(plan.inserts.count, 1)
        XCTAssertEqual(plan.inserts.first?.name, "Amazon Prime")
    }

    func testPlanUpdatesDraftMatchingLiveRecordInPlace() {
        let live = Subscription(
            name: "Netflix", price: 15.49, billingCycle: .monthly, renewalDate: date(2026, 7, 1)
        )
        let draft = ScannedSubscriptionDraft(name: "Netflix", price: 16.49)

        let plan = ScanReviewView.plan(drafts: [draft], against: [live])

        XCTAssertTrue(plan.inserts.isEmpty)
        XCTAssertEqual(plan.updates.count, 1)
        XCTAssertTrue(plan.updates.first?.0 === live)   // same record, updated in place
    }

    func testPlanInsertsBrandNewDraft() {
        let draft = ScannedSubscriptionDraft(name: "Spotify", price: 11.99)

        let plan = ScanReviewView.plan(drafts: [draft], against: [])

        XCTAssertEqual(plan.inserts.count, 1)
        XCTAssertTrue(plan.updates.isEmpty)
    }

    func testPlanSeparatesSameBrandDraftsByPrice() {
        // One "Apple" record exists at $12.99. Re-importing surfaces two Apple
        // drafts at different prices: the matching one updates in place, the
        // other ($2.99 iCloud) is a distinct subscription and must be inserted —
        // not collapsed onto the same record.
        let appleOne = Subscription(
            name: "Apple", price: Decimal(string: "12.99")!, billingCycle: .monthly,
            renewalDate: date(2026, 7, 1)
        )
        let drafts = [
            ScannedSubscriptionDraft(name: "Apple", price: Decimal(string: "12.99")!),
            ScannedSubscriptionDraft(name: "Apple", price: Decimal(string: "2.99")!),
        ]

        let plan = ScanReviewView.plan(drafts: drafts, against: [appleOne])

        XCTAssertEqual(plan.updates.count, 1)
        XCTAssertEqual(plan.inserts.count, 1)
        XCTAssertTrue(plan.updates.first?.0 === appleOne)
        XCTAssertEqual(plan.updates.first?.1.price, Decimal(string: "12.99")!)
        XCTAssertEqual(plan.inserts.first?.price, Decimal(string: "2.99")!)
    }

    func testPlanMatchesEachSameBrandDraftToItsOwnRecord() {
        // Two distinct Apple plans already tracked; re-import maps each draft to
        // its own record, never doubling one up.
        let icloud = Subscription(name: "Apple", price: Decimal(string: "2.99")!,
                                  billingCycle: .monthly, renewalDate: date(2026, 7, 1))
        let appleOne = Subscription(name: "Apple", price: Decimal(string: "12.99")!,
                                    billingCycle: .monthly, renewalDate: date(2026, 7, 1))
        let drafts = [
            ScannedSubscriptionDraft(name: "Apple", price: Decimal(string: "12.99")!),
            ScannedSubscriptionDraft(name: "Apple", price: Decimal(string: "2.99")!),
        ]

        let plan = ScanReviewView.plan(drafts: drafts, against: [icloud, appleOne])

        XCTAssertEqual(plan.updates.count, 2)
        XCTAssertTrue(plan.inserts.isEmpty)
        // $12.99 draft → appleOne; $2.99 draft → icloud.
        XCTAssertTrue(plan.updates.contains { $0.0 === appleOne && $0.1.price == Decimal(string: "12.99")! })
        XCTAssertTrue(plan.updates.contains { $0.0 === icloud && $0.1.price == Decimal(string: "2.99")! })
    }

    func testPlanTreatsModestPriceDriftOfOnePlanAsSameSubscription() {
        // A single plan whose price ticked up between statements still dedupes.
        let netflix = Subscription(name: "Netflix", price: Decimal(string: "15.49")!,
                                   billingCycle: .monthly, renewalDate: date(2026, 7, 1))
        let draft = ScannedSubscriptionDraft(name: "Netflix", price: Decimal(string: "16.49")!)

        let plan = ScanReviewView.plan(drafts: [draft], against: [netflix])

        XCTAssertEqual(plan.updates.count, 1)
        XCTAssertTrue(plan.inserts.isEmpty)
    }

    // MARK: - Trash / restore

    func testMoveToTrashHidesFromActiveAndMarksTrashed() {
        let subscription = Subscription(
            name: "Netflix", price: 15.49, billingCycle: .monthly, renewalDate: date(2026, 7, 1)
        )
        XCTAssertTrue(subscription.isActive)

        subscription.moveToTrash(now: date(2026, 6, 14))

        XCTAssertTrue(subscription.isTrashed)
        XCTAssertFalse(subscription.isActive)
        XCTAssertEqual(subscription.deletedAt, date(2026, 6, 14))
    }

    func testRestoreFromTrashReturnsActiveSubscriptionToActive() {
        let subscription = Subscription(
            name: "Spotify", price: 11.99, billingCycle: .monthly,
            renewalDate: date(2026, 7, 1), deletedAt: date(2026, 6, 14)
        )
        XCTAssertTrue(subscription.isTrashed)

        subscription.restoreFromTrash()

        XCTAssertFalse(subscription.isTrashed)
        XCTAssertTrue(subscription.isActive)
        XCTAssertNil(subscription.deletedAt)
    }

    func testRestoreFromTrashKeepsCancelledRecordCancelled() {
        // A record cancelled before it was trashed must come back cancelled,
        // not active — trashing doesn't erase its archived state.
        let subscription = Subscription(
            name: "Hulu", price: 13.24, billingCycle: .monthly, renewalDate: date(2026, 7, 1),
            cancelledAt: date(2026, 6, 1), deletedAt: date(2026, 6, 14)
        )

        subscription.restoreFromTrash()

        XCTAssertFalse(subscription.isTrashed)
        XCTAssertFalse(subscription.isActive)
        XCTAssertEqual(subscription.cancelledAt, date(2026, 6, 1))
    }

    func testCancelledSubscriptionRestoresToActive() {
        let subscription = Subscription(
            name: "Spotify", price: 11.99, billingCycle: .monthly,
            renewalDate: date(2026, 7, 1), cancelledAt: date(2026, 6, 1)
        )
        XCTAssertFalse(subscription.isActive)

        subscription.cancelledAt = nil
        XCTAssertTrue(subscription.isActive)
    }
}
