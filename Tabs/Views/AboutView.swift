//
//  AboutView.swift
//  Tabs
//
//  About screen: what the app is, the version/build it's running, and its
//  privacy stance. Reachable from the home screen's info button and version
//  footer.
//
//  PRIVACY: static content only. The one outbound link opens the developer's
//  website in the browser when the user taps it.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let developerURL = URL(string: "https://www.sahilramani.com")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.xl) {
                    header
                    privacyCard
                    detailList
                }
                .padding(Theme.Space.l)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Space.s) {
            BrandAvatar(name: "Tabs", size: 72)

            HStack(spacing: Theme.Space.s) {
                Text("Tabs")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.label)
                StageBadge()
            }

            Text("Keeps tabs on your subscriptions.")
                .font(.tabsSubhead)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)

            Text(AppInfo.displayVersion)
                .font(.tabsCaption)
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.l)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Label("Private by design", systemImage: "lock.shield.fill")
                .font(.tabsHeadline)
                .foregroundStyle(Theme.accent)

            privacyRow("Statements are scanned and stored entirely on this device.")
            privacyRow("No networking layer, no analytics, no tracking.")
            privacyRow("No iCloud sync — your data never leaves your phone.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1)
        )
    }

    private func privacyRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.tabsCaption)
                .foregroundStyle(Theme.secondary)
        }
    }

    private var detailList: some View {
        VStack(spacing: 0) {
            infoRow("Version", AppInfo.version)
            divider
            infoRow("License", "MIT")
            divider
            Link(destination: developerURL) {
                HStack {
                    Text("Developer")
                        .foregroundStyle(Theme.label)
                    Spacer()
                    Text("sahilramani.com")
                        .foregroundStyle(Theme.accent)
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiary)
                }
                .font(.tabsSubhead)
                .padding(.vertical, Theme.Space.m)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.bgElevated)
        )
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.label)
            Spacer()
            Text(value).foregroundStyle(Theme.secondary).monospacedDigit()
        }
        .font(.tabsSubhead)
        .padding(.vertical, Theme.Space.m)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
    }
}

#Preview {
    AboutView()
}
