// Pill.swift
// capsule, ~3x9 padding, 11px / 600 weight.
// Two modes: soft (tinted bg, colored text) and solid (colored bg, paper text).

import SwiftUI

struct Pill: View {
    var text: String
    var color: Color = .cHoney
    var soft: Color = .cHoneySoft
    var solid: Bool = false
    /// Optional small leading dot — used by the "Ready to scan" / "Scanning" pills.
    var leadingDot: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if leadingDot {
                Circle()
                    .fill(solid ? .cPaper : color)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(Theme.body(11, weight: .semibold))
                .tracking(0.2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(solid ? color : soft)
        .foregroundStyle(solid ? .cPaper : color)
        .clipShape(Capsule())
    }
}

#Preview {
    HStack(spacing: 12) {
        Pill(text: "Ready to scan", color: .cCoral, soft: .cPaper, leadingDot: true)
        Pill(text: "almost full", color: .cRed, soft: .cRedSoft)
        Pill(text: "live", color: .cHoney, soft: .cHoneySoft)
        Pill(text: "system", color: .cRed, solid: true)
    }
    .padding()
    .background(Color.cBg)
}
