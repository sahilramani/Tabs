//
//  AppInfo.swift
//  Tabs
//
//  Single source of truth for the app's version and release stage, read from
//  the bundle (the values come from MARKETING_VERSION / CURRENT_PROJECT_VERSION
//  in the build settings). Surfaced in the UI so testers always know exactly
//  which build they're looking at.
//

import SwiftUI

enum AppInfo {
    /// Marketing version, e.g. "0.1.0" (CFBundleShortVersionString).
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Pre-release stage. While Tabs is pre-1.0 it ships as an alpha; flip this
    /// to `nil` (or update it) as the app matures toward a stable release.
    static let stage: String? = "alpha"

    /// Compact version label for footers, e.g. "v0.1.0 · alpha".
    static var displayVersion: String {
        let base = "v\(version)"
        guard let stage else { return base }
        return "\(base) · \(stage)"
    }
}

/// A small pill that marks the app as a pre-release build. Hidden once
/// `AppInfo.stage` is cleared, so removing the alpha label is a one-line change.
struct StageBadge: View {
    var body: some View {
        if let stage = AppInfo.stage {
            Text(stage.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.warning)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.warning.opacity(0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.warning.opacity(0.35), lineWidth: 1))
                .accessibilityLabel("\(stage) build")
        }
    }
}
