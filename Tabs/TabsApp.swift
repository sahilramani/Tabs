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
        let samples = [
            Subscription(name: "Netflix", price: 15.49, billingCycle: .monthly, renewalDate: .now.addingTimeInterval(day * 2), source: "bank statements", currencyCode: "USD"),
            Subscription(name: "Spotify", price: 11.99, billingCycle: .monthly, renewalDate: .now.addingTimeInterval(day * 6), source: "bank statements", currencyCode: "USD"),
            Subscription(name: "iCloud+", price: 2.99, billingCycle: .monthly, renewalDate: .now.addingTimeInterval(day * 13), source: "bank statements", currencyCode: "USD"),
            Subscription(name: "Amazon Prime", price: 139, billingCycle: .yearly, renewalDate: .now.addingTimeInterval(day * 40), source: "bank statements", currencyCode: "USD"),
            Subscription(name: "Adobe Creative Cloud", price: 59.99, billingCycle: .monthly, renewalDate: .now.addingTimeInterval(day * 20), source: "bank statements", currencyCode: "USD", cancelledAt: .now.addingTimeInterval(-day * 3)),
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
