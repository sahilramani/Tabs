//
//  ContentView.swift
//  Tabs
//
//  The home screen: lists locally-stored subscriptions and offers the two
//  on-device import paths — "Scan Screenshot" (Vision) and "Import PDF
//  Statement" (PDFKit). All scanning happens locally; see
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

    // Import flow state.
    @State private var photoItem: PhotosPickerItem?
    @State private var isShowingPDFPicker = false
    @State private var isScanning = false
    @State private var scanStatusText = ""
    @State private var scanStep = ""
    /// The in-flight scan, held so the overlay's Cancel button can stop it.
    @State private var scanTask: Task<Void, Never>?

    // Manual-add sheet state.
    @State private var isShowingAddSheet = false

    // About sheet state.
    @State private var isShowingAbout = false

    // Review sheet state. Held as a single identifiable value so the sheet has
    // a stable identity (avoids re-presentation loops from recomputed IDs).
    @State private var reviewItem: DraftsBox?

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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About Tabs")
                }
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
                        isShowingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add subscription manually")
                }
            }
            .safeAreaInset(edge: .bottom) { importBar }
            // Manual entry path.
            .sheet(isPresented: $isShowingAddSheet) {
                AddSubscriptionView()
            }
            .sheet(isPresented: $isShowingAbout) {
                AboutView()
            }
            // Keep renewal dates current: roll past-due dates forward by their
            // cycle on launch and whenever the app becomes active again. Also
            // re-check reminder permission (the user may toggle it in Settings).
            .task {
                #if DEBUG
                // Present the review sheet with sample drafts for demos and
                // App Store screenshots, without driving a real import.
                if reviewItem == nil, CommandLine.arguments.contains("--seed-review") {
                    reviewItem = DraftsBox(drafts: Self.demoReviewDrafts, source: "bank statements")
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
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                handlePickedPhoto(newItem)
            }
            // PDF path.
            .sheet(isPresented: $isShowingPDFPicker) {
                PDFDocumentPicker(
                    onPick: { urls in
                        isShowingPDFPicker = false
                        handlePickedPDFs(urls)
                    },
                    onCancel: { isShowingPDFPicker = false }
                )
                .ignoresSafeArea()
            }
            // Review path: presented once drafts exist.
            .sheet(item: $reviewItem) { box in
                ScanReviewView(drafts: box.drafts, sourceLabel: box.source)
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
                    isShowingAddSheet = true
                } label: {
                    Label("Add Manually", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Label("Your data never leaves this phone", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
            }
        } else {
            List {
                Section {
                    SpendSummaryCard(monthlyTotal: totalMonthlySpend, count: activeSubscriptions.count, currencyCode: dominantCurrencyCode)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    if remindersDisabled {
                        reminderBanner
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                Section("Subscriptions") {
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
        }
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

    // MARK: - Import bar (the two required buttons)

    private var importBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // "Scan Screenshot" → PhotosPicker (Vision OCR).
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label("Scan Screenshot", systemImage: "text.viewfinder")
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)

                // "Import PDF Statement" → UIDocumentPickerViewController (PDFKit).
                #if targetEnvironment(macCatalyst)
                // The UIKit picker can't return a folder on the Mac, so the
                // folder path goes through a real NSOpenPanel instead.
                Menu {
                    Button {
                        isShowingPDFPicker = true
                    } label: {
                        Label("Choose PDFs…", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        let urls = PDFDocumentPicker.chooseFoldersViaOpenPanel()
                        if !urls.isEmpty { handlePickedPDFs(urls) }
                    } label: {
                        Label("Choose Statement Folder…", systemImage: "folder")
                    }
                } label: {
                    Label("Import PDF", systemImage: "doc.text.magnifyingglass")
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                #else
                Button {
                    isShowingPDFPicker = true
                } label: {
                    Label("Import PDF", systemImage: "doc.text.magnifyingglass")
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                #endif
            }
            .controlSize(.large)
            .disabled(isScanning)

            // Discoverability hint for folder import.
            Text("Tip: pick a folder — subfolders are scanned too")
                .font(.caption2)
                .foregroundStyle(Theme.tertiary)

            Label("Processed 100% on-device", systemImage: "lock.shield.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                isShowingAbout = true
            } label: {
                Text(AppInfo.displayVersion)
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About Tabs, version \(AppInfo.displayVersion)")
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
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
        work: @escaping () async throws -> [ScannedSubscriptionDraft],
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
                let drafts = try await work()
                // The user may have tapped Cancel while extraction ran; don't
                // pop the review sheet for an abandoned scan.
                guard !Task.isCancelled else { return }
                reviewItem = DraftsBox(drafts: drafts, source: source)
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
    /// source label) so the sheet presents exactly when a scan produces results.
    private struct DraftsBox: Identifiable {
        let id = UUID()
        let drafts: [ScannedSubscriptionDraft]
        let source: String
    }

    #if DEBUG
    /// Sample drafts mirroring the `samples/sample-statement.pdf` detections,
    /// used by the `--seed-review` launch argument for screenshots.
    private static var demoReviewDrafts: [ScannedSubscriptionDraft] {
        func tx(_ amount: Decimal, _ rawLine: String, _ daysAgo: Double) -> ScannedTransaction {
            ScannedTransaction(amount: amount, date: .now.addingTimeInterval(-86_400 * daysAgo), rawLine: rawLine, currencyCode: "USD")
        }
        return [
            ScannedSubscriptionDraft(name: "Netflix", price: 15.49, currencyCode: "USD", transactions: [tx(15.49, "03/02 NETFLIX.COM  $15.49", 12)]),
            ScannedSubscriptionDraft(name: "Spotify", price: 11.99, currencyCode: "USD", transactions: [tx(11.99, "03/05 SPOTIFY USA  $11.99", 9)]),
            ScannedSubscriptionDraft(name: "Hulu", price: 17.99, currencyCode: "USD", transactions: [tx(17.99, "03/08 HULU 877-8244808  $17.99", 6)]),
            ScannedSubscriptionDraft(name: "iCloud+", price: 2.99, currencyCode: "USD", transactions: [tx(2.99, "03/12 ICLOUD+ APPLE.COM/BILL  $2.99", 2)]),
            ScannedSubscriptionDraft(name: "Adobe Creative Cloud", price: 54.99, currencyCode: "USD", transactions: [tx(54.99, "03/14 ADOBE CREATIVE CLOUD  $54.99", 30)]),
            ScannedSubscriptionDraft(name: "Amazon Prime", price: 139, billingCycle: .yearly, currencyCode: "USD", transactions: [tx(139, "03/15 AMAZON PRIME  $139.00", 1)]),
            ScannedSubscriptionDraft(name: "YouTube Premium", price: 13.99, currencyCode: "USD", transactions: [tx(13.99, "03/22 YOUTUBEPREMIUM  $13.99", 20)]),
            ScannedSubscriptionDraft(name: "Disney+", price: 13.99, currencyCode: "USD", transactions: [tx(13.99, "03/25 DISNEY PLUS  $13.99", 16)]),
            ScannedSubscriptionDraft(name: "Comcast Xfinity", price: 79.00, currencyCode: "USD", transactions: [tx(79.00, "03/27 COMCAST XFINITY  $79.00", 18)]),
        ]
    }
    #endif
}

/// A summary card showing combined monthly spend across all subscriptions.
private struct SpendSummaryCard: View {
    let monthlyTotal: Decimal
    let count: Int
    let currencyCode: String

    /// "N active subscriptions · $X / yr" as a single string (avoids stray gaps).
    private var meta: String {
        let noun = count == 1 ? "subscription" : "subscriptions"
        let yearly = CurrencyFormat.string(from: monthlyTotal * 12, code: currencyCode)
        return "\(count) active \(noun) · \(yearly) / yr"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .top) {
                Text("Monthly spend")
                    .font(.tabsSubhead)
                    .foregroundStyle(Theme.secondary)
                Spacer()
                // On-device privacy pill.
                Label("On-device", systemImage: "lock.shield")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.14), in: Capsule())
            }

            Text(CurrencyFormat.string(from: monthlyTotal, code: currencyCode))
                .font(.tabsCurrency())
                .foregroundStyle(Theme.label)
                .contentTransition(.numericText())

            Label(meta, systemImage: "repeat")
                .font(.tabsCaption)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.accent.opacity(0.11))
                )
                // Soft accent glow from the top-right corner.
                .overlay(alignment: .topTrailing) {
                    RadialGradient(
                        colors: [Theme.accent.opacity(0.22), .clear],
                        center: .topTrailing, startRadius: 0, endRadius: 220
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1)
        )
        // Read as one summary: "Monthly spend, $123, 8 active subscriptions…".
        .accessibilityElement(children: .combine)
    }
}

/// A row in the saved-subscriptions list. Read-only — tapping the row opens
/// `SubscriptionDetailView`, where everything (including the name) is editable.
private struct SubscriptionRow: View {
    let subscription: Subscription

    var body: some View {
        HStack(spacing: 12) {
            BrandAvatar(name: subscription.name)

            VStack(alignment: .leading, spacing: 3) {
                Text(subscription.name)
                    .font(.tabsHeadline)
                    .foregroundStyle(Theme.label)
                statusBadge
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(subscription.formattedPrice)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.label)
                    .strikethrough(!subscription.isActive, color: Theme.tertiary)
                Text(subscription.billingCycle.shortSuffix)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.vertical, 4)
        // A cancelled row reads as archived, not actionable.
        .opacity(subscription.isActive ? 1 : 0.55)
        // One element for VoiceOver: "Netflix, renews in 3 days, $15.49, /mo".
        .accessibilityElement(children: .combine)
    }

    /// Renewal proximity while active, or the cancelled date once archived.
    @ViewBuilder
    private var statusBadge: some View {
        if let cancelledAt = subscription.cancelledAt {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "xmark.circle")
                Text("Cancelled \(cancelledAt.formatted(.dateTime.month().day()))")
            }
            .font(.tabsCaption)
            .foregroundStyle(Theme.tertiary)
        } else {
            let days = subscription.daysUntilRenewal
            let text: String = {
                switch days {
                case ..<0:  return "Renewed"
                case 0:     return "Renews today"
                case 1...7: return "Renews in \(days)d"
                default:    return "Renews \(subscription.renewalDate.formatted(.dateTime.month().day()))"
                }
            }()

            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "clock")
                Text(text)
            }
            .font(.tabsCaption)
            .foregroundStyle(Theme.renewalColor(daysUntil: days))
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Subscription.self, inMemory: true)
}
