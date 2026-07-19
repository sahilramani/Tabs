//
//  ContentView.swift
//  Tabs
//
//  The home screen: total monthly spend plus every locally-stored
//  subscription, sorted by soonest renewal. The floating add button opens the
//  import sheet — screenshot scan (Vision), PDF/folder import (PDFKit), or
//  manual entry. All scanning happens locally; see
//  `LocalStatementScannerService`.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    /// Saved subscriptions, soonest renewal first — the app's job is to catch
    /// what's about to charge, so the most actionable rows sit at the top.
    @Query(sort: \Subscription.renewalDate, order: .forward)
    private var subscriptions: [Subscription]

    /// The on-device scanner. Stateless, so a single shared instance is fine.
    private let scanner = LocalStatementScannerService()

    /// Re-checks past-due renewal dates when the app returns to the foreground.
    @Environment(\.scenePhase) private var scenePhase

    // Import flow state. The sheet picks a path; the matching picker is
    // presented from here once the sheet has dismissed.
    @State private var isShowingImportSheet = false
    @State private var pendingImportAction: ImportAction?
    @State private var isShowingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isShowingPDFPicker = false
    @State private var isShowingFolderPicker = false
    @State private var isScanning = false
    @State private var scanStatusText = ""
    @State private var scanStep = ""
    /// The in-flight scan, held so the overlay's Cancel button can stop it.
    @State private var scanTask: Task<Void, Never>?

    // Manual-add sheet state.
    @State private var isShowingAddSheet = false

    // About sheet state (gear button).
    @State private var isShowingAbout = false

    // Review sheet state. Held as a single identifiable value so the sheet has
    // a stable identity (avoids re-presentation loops from recomputed IDs).
    @State private var reviewItem: DraftsBox?

    #if DEBUG
    /// The `--seed-*` arguments fire once per launch. `.task` re-runs whenever
    /// this view reappears (e.g. popping back from a detail push), which would
    /// otherwise re-present the demo screen forever.
    @State private var hasSeededLaunchScreen = false
    /// Subscription pushed by `--seed-detail`.
    @State private var seededDetail: Subscription?
    #endif

    // Error alert state.
    @State private var errorMessage: String?

    /// True when the user denied notification permission, so renewal reminders
    /// silently won't fire — surfaced as a banner with a path to Settings.
    @State private var remindersDisabled = false

    @Environment(\.openURL) private var openURL

    /// Active (non-cancelled) subscriptions; the spend total counts only these.
    private var activeSubscriptions: [Subscription] {
        subscriptions.filter(\.isActive)
    }

    /// Cancelled subscriptions, kept for their history. Most-recently cancelled
    /// first so the latest action sits at the top of the archive. Trashed
    /// records are excluded — they live in the Trash, not the archive.
    private var cancelledSubscriptions: [Subscription] {
        subscriptions.filter { $0.cancelledAt != nil && !$0.isTrashed }
            .sorted { ($0.cancelledAt ?? .distantPast) > ($1.cancelledAt ?? .distantPast) }
    }

    /// Records in the trash. Used only to badge and enable the Trash entry; the
    /// Trash screen runs its own query.
    private var trashedSubscriptions: [Subscription] {
        subscriptions.filter(\.isTrashed)
    }

    /// Combined monthly-equivalent spend across active subscriptions only.
    private var totalMonthlySpend: Decimal {
        activeSubscriptions.reduce(Decimal(0)) { $0 + $1.monthlyEquivalentPrice }
    }

    /// The currency to render the spend total in: the most common one among
    /// active subscriptions, falling back to the device currency. (Without
    /// live FX — which would breach the no-network rule — a mixed-currency
    /// total is a plain numeric sum; this at least labels it sensibly.)
    private var dominantCurrencyCode: String {
        let codes = activeSubscriptions.compactMap(\.currencyCode)
        guard !codes.isEmpty else { return CurrencyFormat.deviceCode }
        return Dictionary(grouping: codes, by: { $0 })
            .max { $0.value.count < $1.value.count }?.key ?? CurrencyFormat.deviceCode
    }

    var body: some View {
        NavigationStack {
            ZStack {
                subscriptionList
                if isScanning { scanningOverlay }
            }
            .overlay(alignment: .bottomTrailing) {
                addButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 30)
                    .opacity(isScanning ? 0 : 1)
            }
            // Folders and PDFs can also be dragged in from Finder (Catalyst)
            // or another app (iPad). Decoded via NSItemProvider's file-url
            // representation — the typed `dropDestination(for: URL.self)`
            // never fired for Finder drags.
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard !isScanning, !providers.isEmpty else { return false }
                Task {
                    var urls: [URL] = []
                    for provider in providers {
                        if let url = await Self.fileURL(from: provider) { urls.append(url) }
                    }
                    if !urls.isEmpty { handlePickedPDFs(urls) }
                }
                return true
            }
            .navigationTitle("Tabs")
            .toolbar {
                if !trashedSubscriptions.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            TrashView()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Trash, \(trashedSubscriptions.count) items")
                    }
                }
                if #available(iOS 26.0, *) {
                    // The badge carries its own pill, so drop the toolbar's
                    // shared glass background behind it — no bubble-in-bubble.
                    ToolbarItem(placement: .topBarTrailing) {
                        StageBadge()
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        StageBadge()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAbout = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings and about")
                }
            }
            // Import sheet: picks a path, then the matching picker presents
            // from here once the sheet is gone.
            .sheet(isPresented: $isShowingImportSheet, onDismiss: performPendingImportAction) {
                ImportSheetView { action in
                    pendingImportAction = action
                }
            }
            // Manual entry path.
            .sheet(isPresented: $isShowingAddSheet) {
                AddSubscriptionView()
            }
            .sheet(isPresented: $isShowingAbout) {
                AboutView()
            }
            #if DEBUG
            // Programmatic push for `--seed-detail`; the rows themselves use
            // plain destination-builder links, which can't be driven from code.
            .navigationDestination(item: $seededDetail) { subscription in
                SubscriptionDetailView(subscription: subscription)
            }
            #endif
            // Keep renewal dates current: roll past-due dates forward by their
            // cycle on launch and whenever the app becomes active again. Also
            // re-check reminder permission (the user may toggle it in Settings).
            .task {
                #if DEBUG
                if !hasSeededLaunchScreen {
                    hasSeededLaunchScreen = true
                    seedLaunchScreen()
                }
                #endif
                rollOverdueRenewals()
                await refreshReminderPermission()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    rollOverdueRenewals()
                    Task { await refreshReminderPermission() }
                }
            }
            // Image path: PhotosPicker binds a selected item; we load its data
            // and hand it to Vision.
            .photosPicker(
                isPresented: $isShowingPhotoPicker,
                selection: $photoItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                handlePickedPhoto(newItem)
            }
            // PDF path — just PDFs; the folder path presents its own picker so
            // each import-sheet entry does one obvious thing.
            .sheet(isPresented: $isShowingPDFPicker) {
                PDFDocumentPicker(
                    contentTypes: [.pdf],
                    onPick: { urls in
                        isShowingPDFPicker = false
                        handlePickedPDFs(urls)
                    },
                    onCancel: { isShowingPDFPicker = false }
                )
                .ignoresSafeArea()
            }
            // Folder path.
            .sheet(isPresented: $isShowingFolderPicker) {
                PDFDocumentPicker(
                    contentTypes: [.folder],
                    onPick: { urls in
                        isShowingFolderPicker = false
                        handlePickedPDFs(urls)
                    },
                    onCancel: { isShowingFolderPicker = false }
                )
                .ignoresSafeArea()
            }
            // Review path: presented once drafts exist.
            .sheet(item: $reviewItem) { box in
                ScanReviewView(
                    drafts: box.drafts,
                    sourceLabel: box.source,
                    statementCount: box.statementCount,
                    sourceNoun: box.sourceNoun
                )
            }
            .alert(
                "Couldn't Import",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                presenting: errorMessage
            ) { _ in
                // Every failure path can still reach manual entry, so the
                // alert is never a dead end.
                Button("Add Manually") {
                    errorMessage = nil
                    // Defer so the sheet doesn't race the alert's dismissal.
                    DispatchQueue.main.async { isShowingAddSheet = true }
                }
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    // MARK: - Floating add button

    /// The 60 pt circular entry point to the import sheet — Liquid Glass on
    /// iOS 26, a plain accent circle earlier.
    private var addButton: some View {
        Button {
            isShowingImportSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 60, height: 60)
        }
        .modifier(AddButtonStyle())
        .disabled(isScanning)
        .accessibilityLabel("Add subscriptions")
    }

    // MARK: - Subscriptions list

    @ViewBuilder
    private var subscriptionList: some View {
        if subscriptions.isEmpty {
            ContentUnavailableView {
                Label("No subscriptions yet", systemImage: "creditcard.trianglebadge.exclamationmark")
            } description: {
                Text("Scan a screenshot or import a PDF bank statement to find subscriptions — all processed privately on your device.")
            } actions: {
                Button {
                    isShowingImportSheet = true
                } label: {
                    Label("Add Subscriptions", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Label("Your data never leaves this phone", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
            }
        } else {
            List {
                Section {
                    // A hair of leading inset keeps the first glyph clear of
                    // the row's clipping edge (0 shaved the "M" off MONTHLY).
                    spendHeader
                        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 16, trailing: 4))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    if remindersDisabled {
                        reminderBanner
                            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 12, trailing: 4))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                Section("Active") {
                    ForEach(activeSubscriptions) { subscription in
                        NavigationLink {
                            SubscriptionDetailView(subscription: subscription)
                        } label: {
                            SubscriptionRow(subscription: subscription)
                        }
                        // Soft cancel (keeps history) leads; trashing trails —
                        // it's reversible from the Trash, so no confirmation.
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                moveToTrash(subscription)
                            } label: {
                                Label("Trash", systemImage: "trash")
                            }
                            Button {
                                cancelSubscription(subscription)
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle")
                            }
                            .tint(Theme.warning)
                        }
                    }
                }

                if !cancelledSubscriptions.isEmpty {
                    Section("Cancelled") {
                        ForEach(cancelledSubscriptions) { subscription in
                            NavigationLink {
                                SubscriptionDetailView(subscription: subscription)
                            } label: {
                                SubscriptionRow(subscription: subscription)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    moveToTrash(subscription)
                                } label: {
                                    Label("Trash", systemImage: "trash")
                                }
                                Button {
                                    reactivateSubscription(subscription)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(Theme.accent)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            // Keep the last row clear of the floating add button.
            .contentMargins(.bottom, 96, for: .scrollContent)
        }
    }

    // MARK: - Spend header

    /// The plain, left-aligned spend summary: caption, big tabular figure with
    /// the cents dimmed, and the active count in the accent color.
    private var spendHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MONTHLY SPEND")
                .font(.footnote.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.secondary)

            Text(Self.dimmedCents(CurrencyFormat.string(from: totalMonthlySpend, code: dominantCurrencyCode)))
                .font(.system(size: 56, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())

            Text("across \(activeSubscriptions.count) active subscription\(activeSubscriptions.count == 1 ? "" : "s")")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Read as one summary: "Monthly spend, $84.97, across 7 active…".
        .accessibilityElement(children: .combine)
    }

    /// Dims everything from the decimal separator on (".97") to 35% so the
    /// dollars carry the visual weight, per the design handoff.
    private static func dimmedCents(_ formatted: String) -> AttributedString {
        var attributed = AttributedString(formatted)
        let separator = Locale.current.decimalSeparator ?? "."
        if let range = attributed.range(of: separator, options: .backwards) {
            attributed[range.lowerBound..<attributed.endIndex].foregroundColor = Theme.label.opacity(0.35)
        }
        return attributed
    }

    /// Shown when notification permission is denied: renewal reminders won't
    /// fire, with a one-tap path to the system settings to turn them back on.
    private var reminderBanner: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Renewal reminders are off")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.label)
                Text("Turn on notifications to get a heads-up before you're charged.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: Theme.Space.s)
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Button("Settings") { openURL(settingsURL) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Theme.accent)
            }
        }
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.warning.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// Refreshes the reminder-disabled banner from the live permission state.
    private func refreshReminderPermission() async {
        let enabled = await NotificationManager.shared.remindersEnabled()
        // Only nag when there's actually something to remind about.
        remindersDisabled = !enabled && !activeSubscriptions.isEmpty
    }

    // MARK: - Renewal upkeep

    /// Rolls any past-due renewal date forward by its billing cycle and
    /// reschedules that subscription's reminder, so the app stays accurate
    /// across billing periods instead of going stale after the first cycle.
    /// Cancelled subscriptions are left frozen at their last renewal.
    private func rollOverdueRenewals() {
        let moved = activeSubscriptions.filter { $0.rollRenewalForward() }
        guard !moved.isEmpty else { return }
        Task {
            for subscription in moved {
                await NotificationManager.shared.scheduleRenewalReminder(for: subscription)
            }
        }
    }

    // MARK: - Lifecycle actions

    /// Soft-cancel: keep the record and its history, drop it from the spend
    /// total, and stop reminding. Reversible via Restore.
    private func cancelSubscription(_ subscription: Subscription) {
        subscription.cancelledAt = .now
        NotificationManager.shared.cancelReminder(for: subscription)
    }

    /// Restore a cancelled subscription: roll its renewal up to the present and
    /// reschedule the reminder.
    private func reactivateSubscription(_ subscription: Subscription) {
        subscription.cancelledAt = nil
        subscription.rollRenewalForward()
        let restored = subscription
        Task {
            await NotificationManager.shared.requestAuthorization()
            await NotificationManager.shared.scheduleRenewalReminder(for: restored)
        }
    }

    /// Move to the trash: hide it from every list and stop reminding, but keep
    /// the record so it can be restored. Permanent deletion happens in Trash.
    private func moveToTrash(_ subscription: Subscription) {
        subscription.moveToTrash()
        NotificationManager.shared.cancelReminder(for: subscription)
    }

    // MARK: - Import routing

    /// Presents whichever picker the import sheet chose, after the sheet has
    /// fully dismissed (presenting during dismissal drops the presentation).
    private func performPendingImportAction() {
        guard let action = pendingImportAction else { return }
        pendingImportAction = nil
        switch action {
        case .scanScreenshot:
            isShowingPhotoPicker = true
        case .importPDF:
            isShowingPDFPicker = true
        case .importFolder:
            #if targetEnvironment(macCatalyst)
            // The UIKit picker can't return a folder on the Mac; use a real
            // NSOpenPanel instead (runs its own modal loop, so no sheet state).
            let urls = PDFDocumentPicker.chooseFoldersViaOpenPanel()
            if !urls.isEmpty { handlePickedPDFs(urls) }
            #else
            isShowingFolderPicker = true
            #endif
        case .addManually:
            isShowingAddSheet = true
        }
    }

    // MARK: - Loading state

    private var scanningOverlay: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: Theme.Space.l) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)

                Text(scanStatusText.isEmpty ? "Reading your statement privately…" : scanStatusText)
                    .font(.tabsSubhead)
                    .foregroundStyle(Theme.label)
                    .multilineTextAlignment(.center)

                // Thin indeterminate accent track.
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(height: 4)

                // Rotating, reassuring step caption.
                Text(scanStep)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .id(scanStep)

                Label("Nothing is uploaded", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)

                Button("Cancel") { scanTask?.cancel() }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Theme.secondary)
                    .padding(.top, Theme.Space.xs)
            }
            .padding(Theme.Space.xxl)
            .frame(maxWidth: 256)
            .tabsGlass(26)
            // Soft enough to read as elevation in light mode, not a blot.
            .shadow(color: .black.opacity(0.3), radius: 24, y: 6)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scanning statement on device")
        .accessibilityAddTraits(.updatesFrequently)
        // Cycle the step caption while scanning.
        .task(id: isScanning) {
            guard isScanning else { return }
            let steps = [
                "Opening your statement",
                "Reading text on-device",
                "Matching recurring charges",
                "Almost done"
            ]
            var index = 0
            while !Task.isCancelled && isScanning {
                withAnimation(.easeInOut(duration: 0.3)) { scanStep = steps[index] }
                index = (index + 1) % steps.count
                try? await Task.sleep(for: .seconds(1.1))
            }
        }
    }

    // MARK: - Import handlers

    /// Decodes a dragged item's file URL. Finder/Files drags deliver
    /// `public.file-url` as either a URL or its data representation.
    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem) {
        runScan(source: "screenshot") {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw StatementScanError.invalidImage
            }
            return try await scanner.scanImage(data: data)
        } cleanup: {
            photoItem = nil
        }
    }

    private func handlePickedPDFs(_ urls: [URL]) {
        // The selection may include folders, so a count of picked items is
        // misleading — use a generic label that reads well for one or many.
        runScan(source: "bank statements") {
            try await scanner.scanPDFs(at: urls)
        }
    }

    /// Shared async runner: shows the loading state, runs `work` off the main
    /// thread, then either presents the review sheet or surfaces an error.
    private func runScan(
        source: String,
        work: @escaping () async throws -> ScanBatch,
        cleanup: (() -> Void)? = nil
    ) {
        withAnimation { isScanning = true }
        scanStatusText = "Reading your \(source) privately…"

        scanTask = Task {
            defer {
                withAnimation { isScanning = false }
                scanTask = nil
                cleanup?()
            }
            do {
                let batch = try await work()
                // The user may have tapped Cancel while extraction ran; don't
                // pop the review sheet for an abandoned scan.
                guard !Task.isCancelled else { return }
                reviewItem = DraftsBox(
                    drafts: batch.drafts, source: source,
                    statementCount: batch.statementCount, sourceNoun: batch.sourceNoun
                )
            } catch is CancellationError {
                return
            } catch let error as StatementScanError {
                guard !Task.isCancelled else { return }
                errorMessage = error.errorDescription
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Sheet item plumbing

    /// `.sheet(item:)` needs an `Identifiable`. We box the drafts (plus their
    /// source label and scan metadata) so the sheet presents exactly when a
    /// scan produces results.
    private struct DraftsBox: Identifiable {
        let id = UUID()
        let drafts: [ScannedSubscriptionDraft]
        let source: String
        let statementCount: Int
        let sourceNoun: String
    }

    #if DEBUG
    /// Presents a screen straight from a launch argument, for demos and
    /// screenshots, without driving a real import:
    ///
    /// - `--seed-review` presents the review sheet with sample drafts.
    /// - `--seed-import` presents the import sheet.
    /// - `--seed-detail` pushes the soonest-renewing active subscription,
    ///   so it needs `--seed-demo` (or a real store) to have anything to show.
    private func seedLaunchScreen() {
        let arguments = CommandLine.arguments
        if arguments.contains("--seed-review"), reviewItem == nil {
            reviewItem = DraftsBox(
                drafts: Self.demoReviewDrafts, source: "bank statements",
                statementCount: 3, sourceNoun: "statement"
            )
        }
        if arguments.contains("--seed-import") {
            isShowingImportSheet = true
        }
        if arguments.contains("--seed-detail") {
            // `subscriptions` is queried sorted by renewal date, so this is the
            // top row of the Active section.
            seededDetail = activeSubscriptions.first
        }
    }

    /// Sample drafts mirroring the design handoff's review screen, used by the
    /// `--seed-review` launch argument for demos and screenshots.
    private static var demoReviewDrafts: [ScannedSubscriptionDraft] {
        func day(_ month: Int, _ day: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day))!
        }
        func tx(_ amount: Decimal, _ month: Int, _ dayOfMonth: Int, _ rawLine: String) -> ScannedTransaction {
            ScannedTransaction(amount: amount, date: day(month, dayOfMonth), rawLine: rawLine, currencyCode: "USD")
        }
        return [
            ScannedSubscriptionDraft(name: "Netflix", price: 15.49, currencyCode: "USD", transactions: [
                tx(15.49, 6, 15, "06/15 NETFLIX.COM CA  $15.49"),
                tx(15.49, 5, 15, "05/15 NETFLIX.COM CA  $15.49"),
                tx(15.49, 4, 15, "04/15 NETFLIX.COM CA  $15.49"),
                tx(15.49, 3, 15, "03/15 NETFLIX.COM CA  $15.49"),
            ]),
            ScannedSubscriptionDraft(name: "Adobe Creative Cloud", price: 22.99, currencyCode: "USD", transactions: [
                tx(22.99, 6, 22, "06/22 ADOBE CREATIVE CLOUD  $22.99"),
                tx(22.99, 5, 22, "05/22 ADOBE CREATIVE CLOUD  $22.99"),
                tx(22.99, 4, 22, "04/22 ADOBE CREATIVE CLOUD  $22.99"),
            ]),
            ScannedSubscriptionDraft(name: "Spotify", price: 11.99, currencyCode: "USD", transactions: [
                tx(11.99, 6, 5, "06/05 SPOTIFY USA  $11.99"),
                tx(11.99, 5, 5, "05/05 SPOTIFY USA  $11.99"),
            ]),
            ScannedSubscriptionDraft(name: "Shell Oil", price: 42.13, currencyCode: "USD", isSelected: false, transactions: [
                tx(42.13, 6, 12, "06/12 SHELL OIL 57444 MOUNTAIN VIEW  $42.13"),
                tx(51.72, 5, 14, "05/14 SHELL OIL 57444 MOUNTAIN VIEW  $51.72"),
                tx(38.10, 4, 11, "04/11 SHELL OIL 57444 MOUNTAIN VIEW  $38.10"),
            ], amountsVary: true),
        ]
    }
    #endif
}

/// The floating add button's chrome: Liquid Glass on iOS 26, a plain accent
/// circle with a soft shadow on iOS 17–18 (and on pre-Xcode-26 toolchains).
private struct AddButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Theme.accent)
        } else {
            fallback(content: content)
        }
        #else
        fallback(content: content)
        #endif
    }

    private func fallback(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Circle().fill(Theme.accent))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}

/// A row in the saved-subscriptions list. Read-only — tapping the row opens
/// `SubscriptionDetailView`, where everything (including the name) is editable.
private struct SubscriptionRow: View {
    let subscription: Subscription

    var body: some View {
        HStack(spacing: 12) {
            BrandAvatar(name: subscription.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .font(.headline)
                    .foregroundStyle(Theme.label)
                subtitle
                    .font(.footnote)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(subscription.formattedPrice)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.label)
                    .strikethrough(!subscription.isActive, color: Theme.tertiary)
                if subscription.isActive, subscription.billingCycle != .monthly {
                    Text(subscription.billingCycle.shortSuffix)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        // A cancelled row reads as archived, not actionable.
        .opacity(subscription.isActive ? 1 : 0.55)
        // One element for VoiceOver: "Netflix, renews in 3 days, $15.49".
        .accessibilityElement(children: .combine)
    }

    /// Renewal proximity while active — in the accent color when it's ≤3 days
    /// out (the "act now" window) — or the cancelled date once archived.
    @ViewBuilder
    private var subtitle: some View {
        if let cancelledAt = subscription.cancelledAt {
            Text("Cancelled \(cancelledAt.formatted(.dateTime.month(.abbreviated).day()))")
                .foregroundStyle(Theme.tertiary)
        } else {
            let days = subscription.daysUntilRenewal
            switch days {
            case ..<0:
                Text("Renewed")
                    .foregroundStyle(Theme.secondary)
            case 0:
                Text("Renews today")
                    .foregroundStyle(Theme.accent)
            case 1...3:
                Text("Renews in \(days) day\(days == 1 ? "" : "s")")
                    .foregroundStyle(Theme.accent)
            default:
                Text("Renews \(subscription.renewalDate.formatted(.dateTime.month(.abbreviated).day()))")
                    .foregroundStyle(Theme.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Subscription.self, inMemory: true)
}
