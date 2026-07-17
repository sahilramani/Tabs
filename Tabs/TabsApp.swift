//
//  TabsApp.swift
//  Tabs
//
//  App entry point. Sets up the local-only SwiftData container.
//
//  PRIVACY: The `ModelContainer` is configured with on-device storage and
//  CloudKit explicitly disabled — subscription data stays on this device.
//

import SwiftUI
import SwiftData

@main
struct TabsApp: App {

    /// A single, app-wide SwiftData container backed by local disk only.
    let modelContainer: ModelContainer = TabsApp.makeContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if DEBUG
                // Populate a demo dataset when launched with `--seed-demo`
                // (used for App Store screenshots and UI tests). Never runs in
                // Release; never touches a store that already has data.
                .onAppear(perform: seedDemoDataIfRequested)
                #endif
        }
        .modelContainer(modelContainer)
    }

    #if DEBUG
    private func seedDemoDataIfRequested() {
        guard CommandLine.arguments.contains("--seed-demo") else { return }
        let context = modelContainer.mainContext
        guard (try? context.fetchCount(FetchDescriptor<Subscription>())) == 0 else { return }

        let day: TimeInterval = 86_400

        // A few months of detected charges so the detail screen shows the
        // statement evidence behind a subscription (used for demos/screenshots).
        func monthly(_ amount: Decimal, _ merchant: String, months: Int) -> [ChargeRecord] {
            (1...months).map { i in
                ChargeRecord(
                    amount: amount,
                    date: .now.addingTimeInterval(-day * 30 * Double(i)),
                    rawLine: merchant,
                    currencyCode: "USD"
                )
            }
        }

        // Mirrors the design handoff's home screen: five active rows (Netflix
        // inside the ≤3-day accent window) plus one cancelled.
        let samples = [
            Subscription(name: "Netflix", price: 15.49, billingCycle: .monthly, renewalDate: .now.addingTimeInterval(day * 3), source: "bank statements", currencyCode: "USD",
                         charges: monthly(15.49, "03/15 NETFLIX.COM CA  $15.49", months: 4)),
            Subscription(name: "Spotify", price: 11.99, billingCycle: .monthly, renewalDate: .now.addingTimeInterval(day * 5), source: "bank statements", currencyCode: "USD",
                         charges: monthly(11.99, "03/05 SPOTIFY USA  $11.99", months: 3)),
            Subscription(name: "iCloud+", price: 2.99, billingCycle: .monthly, renewalDate: .now.addingTimeInterval(day * 11), source: "bank statements", currencyCode: "USD",
                         charges: monthly(2.99, "03/12 ICLOUD+ APPLE.COM/BILL  $2.99", months: 3)),
            Subscription(name: "Disney+", price: 13.99, billingCycle: .monthly, renewalDate: .now.addingTimeInterval(day * 16), source: "bank statements", currencyCode: "USD",
                         charges: monthly(13.99, "03/25 DISNEY PLUS  $13.99", months: 3)),
            Subscription(name: "Notion", price: 8.00, billingCycle: .monthly, renewalDate: .now.addingTimeInterval(day * 19), source: "bank statements", currencyCode: "USD",
                         charges: monthly(8.00, "03/28 NOTION LABS  $8.00", months: 3)),
            Subscription(name: "Hulu", price: 17.99, billingCycle: .monthly, renewalDate: .now.addingTimeInterval(-day * 30), source: "bank statements", currencyCode: "USD",
                         charges: monthly(17.99, "03/08 HULU 877-8244808  $17.99", months: 2),
                         cancelledAt: .now.addingTimeInterval(-day * 34)),
        ]
        samples.forEach { context.insert($0) }
    }
    #endif

    /// Builds the on-device store. If the existing store can't be opened — a
    /// schema it can't migrate, or on-disk corruption — the local file is
    /// removed and recreated rather than crash-looping on every launch. The
    /// only data lost is the local subscription list, which the user can
    /// rebuild by re-importing statements; nothing was ever off-device.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Subscription.self])
        // `cloudKitDatabase: .none` keeps data strictly on-device — no iCloud sync.
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Recovery: drop the unreadable store and try once more.
            destroyStore(at: configuration.url)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                // A second failure on a freshly-cleared path means an in-memory
                // fallback is the only way to keep the app usable this session.
                let memoryOnly = ModelConfiguration(
                    schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
                )
                guard let container = try? ModelContainer(for: schema, configurations: [memoryOnly]) else {
                    fatalError("Failed to create even an in-memory ModelContainer: \(error)")
                }
                return container
            }
        }
    }

    /// Removes the SwiftData store file and its SQLite sidecars.
    private static func destroyStore(at url: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            try? fileManager.removeItem(at: sidecar)
        }
    }
}
