// DonutView.swift
// Ring via Circle().trim. Configurable size, stroke, color, track, centered label.
// Used on Start screen drives.

import SwiftUI

struct DonutView<Center: View>: View {
    var fraction: Double             // 0...1
    var size: CGFloat = 120
    var stroke: CGFloat = 14
    var color: Color = .cCoral
    var track: Color = .cLine
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        DonutView(fraction: 0.61, size: 56, stroke: 7) {
            Text("61%").font(Theme.body(11, weight: .bold)).foregroundStyle(Color.cInk)
        }
        DonutView(fraction: 0.91, size: 56, stroke: 7, color: .cRed) {
            Text("91%").font(Theme.body(11, weight: .bold)).foregroundStyle(Color.cInk)
        }
        DonutView(fraction: 0.36, size: 120, stroke: 14) {
            VStack(spacing: 2) {
                Text("36%").font(Theme.display(28))
                Text("used").font(Theme.body(11)).foregroundStyle(Color.cInk2)
            }
        }
    }
    .padding()
    .background(Color.cBg)
}
