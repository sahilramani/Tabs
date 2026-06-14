//
//  Theme.swift
//  Tabs — drop-in design-token layer from the Claude Design handoff.
//
//  Compiles on iOS 17+. The semantic colors are backed by named color sets in
//  Assets.xcassets (generated alongside this file). The accent is "Vital Green"
//  — calm, decisive, "in the green" — used only where the user acts.
//
//  PRIVACY: purely presentational. No I/O, no network.
//

import SwiftUI

enum Theme {

    // MARK: - Color (semantic roles, backed by named color sets)
    static let accent        = Color("AccentPrimary")     // Vital Green
    static let accentPressed = Color("AccentPressed")
    static let bgBase        = Color("BackgroundBase")
    static let bgElevated    = Color("BackgroundElevated")
    static let glassFill     = Color("GlassFill")
    static let glassBorder   = Color("GlassBorder")
    static let label         = Color("LabelPrimary")
    static let secondary     = Color("LabelSecondary")
    static let tertiary      = Color("LabelTertiary")
    static let separator     = Color("SeparatorGlass")
    static let success       = Color("Success")
    static let warning       = Color("Warning")
    static let destructive   = Color("Destructive")

    // MARK: - Spacing (8-pt scale)
    enum Space {
        static let xs:   CGFloat = 4
        static let s:    CGFloat = 8
        static let m:    CGFloat = 12
        static let l:    CGFloat = 16
        static let xl:   CGFloat = 20
        static let xxl:  CGFloat = 24
        static let xxxl: CGFloat = 32
    }
    static let screenMargin: CGFloat = 16

    // MARK: - Corner radius (continuous)
    enum Radius {
        static let control: CGFloat = 12
        static let card:    CGFloat = 20
        static let sheet:   CGFloat = 38
    }
}

// MARK: - Typography (SF Pro)
extension Font {
    static let tabsLargeTitle = Font.largeTitle.bold()            // 34 / 700
    static let tabsTitle2     = Font.title2.bold()                // 22 / 700
    static let tabsHeadline   = Font.headline                     // 17 / 600
    static let tabsBody       = Font.body                         // 17 / 400
    static let tabsSubhead    = Font.subheadline.weight(.medium)  // 15 / 500
    static let tabsCaption    = Font.caption                      // 12 / 400

    /// Currency — rounded design + monospaced digits so totals don't jitter.
    /// Anchored to the Large Title text style so it tracks Dynamic Type
    /// instead of pinning at a fixed point size.
    static func tabsCurrency() -> Font {
        .system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    }
}

// MARK: - "Liquid Glass" surface
//
//  On iOS 26 this uses the real Liquid Glass material (`glassEffect`); on iOS
//  17–18 it falls back to `.regularMaterial` + a 1pt highlight hairline.
//
//  The `#if compiler(>=6.2)` gate means the `glassEffect` call is only *compiled*
//  by the Xcode 26 toolchain (Swift 6.2), which ships the iOS 26 SDK. Older
//  Xcode versions compile only the material fallback, so the project builds on
//  any toolchain while still adopting Liquid Glass when the SDK supports it.
extension View {
    @ViewBuilder
    func tabsGlass(_ radius: CGFloat = Theme.Radius.card) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.tabsMaterialGlass(radius)
        }
        #else
        self.tabsMaterialGlass(radius)
        #endif
    }

    /// Material fallback used on iOS 17–18 (and on pre-Xcode-26 toolchains).
    @ViewBuilder
    private func tabsMaterialGlass(_ radius: CGFloat) -> some View {
        self
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.glassBorder, lineWidth: 1)
            )
    }
}

// MARK: - Renewal proximity → semantic color (used by SubscriptionRow)
extension Theme {
    static func renewalColor(daysUntil days: Int) -> Color {
        switch days {
        case ..<0:  return Theme.secondary    // Renewed
        case 0:     return Theme.destructive   // Renews today
        case 1...7: return Theme.warning       // Renews in N days
        default:    return Theme.secondary     // future date
        }
    }
}
