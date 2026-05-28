// ToastView.swift
// Dark (ink) capsule pinned bottom-center, sage check, message, optional action.
// Auto-dismiss (6s default, 8s for delete) handled by the caller (AppModel).

import SwiftUI

struct ToastView: View {
    let toast: Toast
    let onActionTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Check circle (sage)
            ZStack {
                Circle().fill(Color.cSage).frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(toast.message)
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(.white)
            if let action = toast.action {
                Button(action.label, action: onActionTap)
                    .buttonStyle(.plain)
                    .font(Theme.body(13, weight: .bold))
                    .foregroundStyle(Color.cHoney)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.cInk)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.cInk.opacity(0.35), radius: 30, x: 0, y: 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    ToastView(
        toast: Toast(message: "Freed 12 GB · 4 items moved to Trash",
                     action: ToastAction(label: "Undo", kind: .undoDelete),
                     duration: 8),
        onActionTap: {}
    )
    .padding()
    .background(Color.cBg)
}
