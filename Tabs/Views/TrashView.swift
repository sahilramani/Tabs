//
//  TrashView.swift
//  Tabs
//
//  The trash: subscriptions the user deleted are kept here instead of being
//  removed outright, so a delete is undoable. Restoring returns a record to the
//  main list; emptying the trash is the only thing that removes it for good.
//
//  PRIVACY: operates only on the local SwiftData store and the local
//  notification center. No I/O leaves the device.
//

import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Trashed records only. The query keeps this screen in sync as items are
    /// restored or permanently deleted.
    @Query(filter: #Predicate<Subscription> { $0.deletedAt != nil })
    private var trashed: [Subscription]

    @State private var isShowingEmptyConfirmation = false

    /// Most-recently trashed first.
    private var sortedTrashed: [Subscription] {
        trashed.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var body: some View {
        Group {
            if sortedTrashed.isEmpty {
                ContentUnavailableView {
                    Label("Trash is empty", systemImage: "trash")
                } description: {
                    Text("Deleted subscriptions land here. Restore them anytime, or empty the trash to remove them for good.")
                }
            } else {
                List {
                    Section {
                        ForEach(sortedTrashed) { subscription in
                            TrashRow(subscription: subscription)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        permanentlyDelete(subscription)
                                    } label: {
                                        Label("Delete", systemImage: "trash.fill")
                                    }
                                    Button {
                                        restore(subscription)
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(Theme.accent)
                                }
                        }
                    } footer: {
                        Text("Items here don't count toward your spend and won't remind you. Restoring brings a subscription back; emptying the trash deletes it permanently.")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Trash")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !sortedTrashed.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Empty", role: .destructive) {
                        isShowingEmptyConfirmation = true
                    }
                    .tint(Theme.destructive)
                }
            }
        }
        // Emptying the trash is the one irreversible step here, so it confirms.
        .confirmationDialog(
            "Empty the trash?",
            isPresented: $isShowingEmptyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(sortedTrashed.count) Permanently", role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text("This permanently removes every subscription in the trash, along with its detected charges. This can't be undone.")
        }
        // Once the trash is empty there's nothing left to manage — pop back.
        .onChange(of: sortedTrashed.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }

    /// Pull a record out of the trash. If it lands back in an active state,
    /// roll its renewal up to the present and resume reminders; a record that
    /// was cancelled before trashing returns to the cancelled archive untouched.
    private func restore(_ subscription: Subscription) {
        subscription.restoreFromTrash()
        guard subscription.isActive else { return }
        subscription.rollRenewalForward()
        let restored = subscription
        Task {
            await NotificationManager.shared.requestAuthorization()
            await NotificationManager.shared.scheduleRenewalReminder(for: restored)
        }
    }

    /// Remove a single record for good.
    private func permanentlyDelete(_ subscription: Subscription) {
        NotificationManager.shared.cancelReminder(for: subscription)
        modelContext.delete(subscription)
    }

    /// Remove everything currently in the trash for good.
    private func emptyTrash() {
        for subscription in trashed {
            NotificationManager.shared.cancelReminder(for: subscription)
            modelContext.delete(subscription)
        }
    }
}

/// A trashed subscription: dimmed, struck-through price, with the date it was
/// removed. Read-only — actions are on the swipe.
private struct TrashRow: View {
    let subscription: Subscription

    var body: some View {
        HStack(spacing: 12) {
            BrandAvatar(name: subscription.name)

            VStack(alignment: .leading, spacing: 3) {
                Text(subscription.name)
                    .font(.tabsHeadline)
                    .foregroundStyle(Theme.label)
                if let deletedAt = subscription.deletedAt {
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: "trash")
                        Text("Deleted \(deletedAt.formatted(.dateTime.month().day()))")
                    }
                    .font(.tabsCaption)
                    .foregroundStyle(Theme.tertiary)
                }
            }

            Spacer()

            Text(subscription.formattedPrice)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .strikethrough(true, color: Theme.tertiary)
        }
        .padding(.vertical, 4)
        .opacity(0.7)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Subscription.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let sample = Subscription(
        name: "Disney+", price: 13.99, billingCycle: .monthly,
        renewalDate: .now.addingTimeInterval(86_400 * 10),
        source: "bank statements", deletedAt: .now.addingTimeInterval(-86_400 * 2)
    )
    container.mainContext.insert(sample)

    return NavigationStack {
        TrashView()
    }
    .modelContainer(container)
}
