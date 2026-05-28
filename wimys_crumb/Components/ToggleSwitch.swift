// ToggleSwitch.swift
// Custom 36x20 capsule, 16x16 knob, accent when on, `line2` off.
// Plan §5.4 — do NOT use stock SwiftUI Toggle styling.

import SwiftUI

struct ToggleSwitch: View {
    @Binding var isOn: Bool
    var onColor: Color = .cCoral
    var offColor: Color = .cLine2

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? onColor : offColor)
                    .frame(width: 36, height: 20)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 2)
                    .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isOn ? "On" : "Off"))
    }
}

#Preview {
    struct PreviewWrap: View {
        @State var a = true
        @State var b = false
        var body: some View {
            HStack(spacing: 18) {
                ToggleSwitch(isOn: $a)
                ToggleSwitch(isOn: $b)
                ToggleSwitch(isOn: .constant(true), onColor: .cSage)
            }
        }
    }
    return PreviewWrap().padding().background(Color.cBg)
}
