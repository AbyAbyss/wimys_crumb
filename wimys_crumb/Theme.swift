// Theme.swift
// Honey palette, typography, and design tokens.
//
// Colors are taken verbatim from `project/a-base.jsx`.
// Fonts: real font files (Bricolage Grotesque, Geist, Geist Mono) belong in
// Resources/Fonts/. Without them macOS substitutes the system font; this is the
// agreed Phase 1 fallback. The display/body/mono helpers reference the bundled
// PostScript names; if those names resolve, the bundled fonts are used.

import SwiftUI
import AppKit
import CoreText

// MARK: - Color tokens

extension Color {
    // Surfaces
    static let cBg        = Color(hex: 0xFBF6EC)
    static let cPaper     = Color(hex: 0xFFFFFF)
    static let cPanel     = Color(hex: 0xF4ECDA)

    // Text
    static let cInk       = Color(hex: 0x2A2118)
    static let cInk2      = Color(hex: 0x7C6F5F)
    static let cInk3      = Color(hex: 0xB5A48E)

    // Lines
    static let cLine      = Color(hex: 0xE8DFCC)
    static let cLine2     = Color(hex: 0xD7C9AA)

    // Accents
    static let cCoral     = Color(hex: 0xE55934)
    static let cCoralSoft = Color(hex: 0xFDE3DA)
    static let cHoney     = Color(hex: 0xF3B95F)
    static let cHoneySoft = Color(hex: 0xFBE9C6)
    static let cSage      = Color(hex: 0x5FA37C)
    static let cSageSoft  = Color(hex: 0xD8ECDD)
    static let cLilac     = Color(hex: 0x9E8FCF)
    static let cLilacSoft = Color(hex: 0xE8E2F5)
    static let cNavy      = Color(hex: 0x2C3E66)
    static let cNavySoft  = Color(hex: 0xD9DFEB)
    static let cRed       = Color(hex: 0xC9412A)
    static let cRedSoft   = Color(hex: 0xF6D9D2)

    /// Visualization hue ring — used in order for treemap tiles, file types, legends.
    /// From `A_HUES` in a-base.jsx.
    static let aHues: [Color] = [
        .cCoral, .cHoney, .cSage, .cLilac, .cNavy,
        Color(hex: 0xD86A8A), Color(hex: 0x7BAFD4),
    ]

    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Spacing, radius, shadow

enum Radius {
    static let card: CGFloat = 16
    static let button: CGFloat = 10
    static let chip: CGFloat = 8
    static let pill: CGFloat = 999   // capsule
}

enum Spacing {
    static let screenH: CGFloat = 20
    static let screenV: CGFloat = 20
    static let cardGap: CGFloat = 14
    static let cardPad: CGFloat = 18
}

enum Shadows {
    // Hairline shadow for cards: 0 1px 0 line
    static func card() -> some View { EmptyView() } // applied via .overlay/.border in Card itself
}

// MARK: - Typography

enum Theme {
    // PostScript names of the bundled font families. If the file isn't present,
    // SwiftUI falls back to the system font automatically.
    static let displayFamily = "Bricolage Grotesque"
    static let bodyFamily    = "Geist"
    static let monoFamily    = "Geist Mono"

    /// Display / heading font — Bricolage Grotesque.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom(displayFamily, size: size).weight(weight)
    }

    /// Body / UI font — Geist.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(bodyFamily, size: size).weight(weight)
    }

    /// Monospace font — Geist Mono. Used for paths.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(monoFamily, size: size).weight(weight)
    }

    /// Register any font files dropped into the Resources/Fonts/ bundle directory
    /// at app launch. Safe to call when the directory is empty.
    static func registerFonts() {
        guard let resURL = Bundle.main.resourceURL else { return }
        let fontsDir = resURL.appendingPathComponent("Fonts", isDirectory: true)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: fontsDir,
                                                       includingPropertiesForKeys: nil) else {
            return
        }
        let fontExts: Set<String> = ["ttf", "otf", "ttc"]
        let urls = entries.filter { fontExts.contains($0.pathExtension.lowercased()) }
        guard !urls.isEmpty else { return }
        // `CTFontManagerRegisterFontURLs` (macOS 10.15+) replaces the deprecated
        // `…FontsForURLs`. The trailing `nil` is the optional completion handler.
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}
