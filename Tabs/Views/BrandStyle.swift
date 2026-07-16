//
//  BrandStyle.swift
//  Tabs
//
//  Lightweight, deterministic visual styling for a brand/merchant name so the
//  UI can show a colorful monogram avatar without bundling any logos. Pure,
//  local, offline — derives color from the name's hash.
//

import SwiftUI

enum BrandStyle {

    /// A muted, premium palette (from the design handoff) so monograms sit
    /// calmly on dark glass instead of shouting. Same hash → same index, so a
    /// given brand always maps to the same hue.
    private static let palette: [Color] = [
        Color(hex: 0xE0726B), Color(hex: 0xE0A05A), Color(hex: 0xE07BA6),
        Color(hex: 0xB98AE0), Color(hex: 0x8A8FE0), Color(hex: 0x6EA6E0),
        Color(hex: 0x5CC4C0), Color(hex: 0x6FC18A), Color(hex: 0x7FD0AE),
        Color(hex: 0x69BFD6)
    ]

    /// Recognizable hues for well-known brands (per the design handoff:
    /// "Netflix red, Spotify green, iCloud+ blue…"). Keys are prefixes of the
    /// normalized merchant key; anything unlisted falls back to the stable
    /// hashed palette. Still no logos — just a familiar color.
    private static let knownHues: [(keyPrefix: String, color: Color)] = [
        ("netflix",  Color(hex: 0xDB4E45)),
        ("spotify",  Color(hex: 0x1DB954)),
        ("icloud",   Color(hex: 0x5AA2E0)),
        ("apple",    Color(hex: 0x9BA1A8)),
        ("disney",   Color(hex: 0x6E79D6)),
        ("notion",   Color(hex: 0xE0A05A)),
        ("hulu",     Color(hex: 0x9AA0A6)),
        ("adobe",    Color(hex: 0xE0564B)),
        ("amazon",   Color(hex: 0xE8A33D)),
        ("youtube",  Color(hex: 0xE05252)),
        ("dropbox",  Color(hex: 0x4C8FE0)),
        ("github",   Color(hex: 0xA48AE0)),
    ]

    /// A stable color for a brand name: a recognizable hue for brands we know,
    /// otherwise derived from the name's hash. The same name always yields the
    /// same color, so Netflix is always the same red.
    static func color(for name: String) -> Color {
        let key = RecurringChargeDetector.key(for: name)
        if let known = knownHues.first(where: { key.hasPrefix($0.keyPrefix) }) {
            return known.color
        }
        let hash = name.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }

    /// The single leading character of the name, case preserved — "Netflix"
    /// is N, "iCloud+" is i — per the handoff's one-letter monograms.
    static func monogram(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "?"
        }
        return String(first)
    }
}

/// A circular monogram avatar for a brand. Reused on the home list and the
/// review screen for visual consistency.
struct BrandAvatar: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        let tint = BrandStyle.color(for: name)
        Text(BrandStyle.monogram(for: name))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.20), in: Circle())   // fill 20% of tint
            .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1)) // border 35%
            .accessibilityHidden(true)
    }
}

extension Color {
    /// Creates an opaque sRGB color from a 0xRRGGBB integer. Used for the muted
    /// brand-avatar palette, whose exact hex values come from the design system.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
