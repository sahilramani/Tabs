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

    /// A stable color derived from the brand name. The same name always yields
    /// the same hue, so Netflix is always the same color.
    static func color(for name: String) -> Color {
        let hash = name.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }

    /// One or two uppercase initials for the monogram.
    static func monogram(for name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
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
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
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
