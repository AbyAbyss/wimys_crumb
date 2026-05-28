// ProgressBarView.swift
// Rounded track in `line`, colored fill. Mirrors `Bar` from a-base.jsx.

import SwiftUI

struct ProgressBarView: View {
    var fraction: Double        // 0...1
    var color: Color = .cCoral
    var height: CGFloat = 6
    var track: Color = .cLine

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(track)
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

#Preview {
    VStack(spacing: 12) {
        ProgressBarView(fraction: 0.28)
        ProgressBarView(fraction: 0.62, color: .cHoney, height: 10)
        ProgressBarView(fraction: 0.91, color: .cSage, height: 4)
    }
    .padding()
    .frame(width: 360)
    .background(Color.cBg)
}
