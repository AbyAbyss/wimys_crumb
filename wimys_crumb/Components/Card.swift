// Card.swift
// paper bg, 1px line border, radius 16, hairline shadow (0 1px 0 line).
// `tintedBg` overrides the paper bg (e.g. Quick Wins uses honeySoft).

import SwiftUI

struct Card<Content: View>: View {
    var pad: CGFloat = Spacing.cardPad
    var tintedBg: Color? = nil
    var borderColor: Color = .cLine
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(pad)
            .background((tintedBg ?? .cPaper))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            // hairline drop shadow approximating `box-shadow: 0 1px 0 line`
            .shadow(color: .cLine.opacity(0.7), radius: 0, x: 0, y: 1)
    }
}

#Preview {
    Card {
        Text("Hello, crumb.").font(Theme.body(14))
    }
    .padding()
    .frame(width: 320, height: 120)
    .background(Color.cBg)
}
