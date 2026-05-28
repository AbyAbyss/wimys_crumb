// DeleteSheet.swift
// Modal confirmation sheet for delete actions. Plan §8.6.
//
// Layout: trash-icon header → "Delete N items?" + bytes-to-free → protected
// banner (if any) → target list (struck-through for protected rows) →
// Trash/Forever radio pair → Cancel + Confirm.

import SwiftUI

struct DeleteSheet: View {
    @Bindable var app: AppModel

    private var targets: [DeleteTarget] { app.deleteTargets }

    private struct Split {
        let allowed: [DeleteTarget]
        let blocked: [DeleteTarget]
        var allowedTotal: Int64 {
            allowed.reduce(0) { $0 + $1.size }
        }
    }

    private var split: Split {
        var allowed: [DeleteTarget] = []
        var blocked: [DeleteTarget] = []
        for t in targets {
            let isProt = t.isProtected
                || DeleteService.isProtected(t.path,
                                             additional: app.userProtectedPaths)
            if isProt { blocked.append(t) } else { allowed.append(t) }
        }
        return Split(allowed: allowed, blocked: blocked)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.36)
                .ignoresSafeArea()
                .onTapGesture { app.closeDeleteSheet() }
            sheet
                .frame(width: 580)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.cPaper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.cLine2, lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.cInk.opacity(0.25), radius: 40, x: 0, y: 20)
        }
    }

    // MARK: - Sheet content

    private var sheet: some View {
        VStack(spacing: 0) {
            header
            if !split.blocked.isEmpty {
                protectedBanner
                    .padding(.horizontal, 26)
                    .padding(.bottom, 16)
            }
            targetList
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.cCoralSoft)
                IconView(icon: .trash, size: 18)
                    .foregroundStyle(Color.cCoral)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(Theme.display(22, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.cInk)
                Text(headerSubtitle)
                    .font(Theme.body(13))
                    .foregroundStyle(Color.cInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var headerTitle: String {
        let n = targets.count
        return "Delete \(n) item\(n == 1 ? "" : "s")?"
    }

    private var headerSubtitle: String {
        var s = "Frees about \(Fmt.bytes(split.allowedTotal))."
        if !split.blocked.isEmpty {
            let m = split.blocked.count
            s += " \(m) protected item\(m == 1 ? "" : "s") will be skipped."
        }
        return s
    }

    private var protectedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            IconView(icon: .shield, size: 14)
                .foregroundStyle(Color.cRed)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("System protected paths excluded.")
                    .font(Theme.body(12, weight: .bold))
                    .foregroundStyle(Color.cRed)
                Text("These are part of macOS and could break apps or boot — we'll skip them.")
                    .font(Theme.body(12))
                    .foregroundStyle(Color.cInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.cRedSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.cRed.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Target list

    private var targetList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(targets) { t in
                    targetRow(t)
                    Divider().overlay(Color.cLine)
                }
            }
        }
        .frame(maxHeight: 220)
        .background(Color.cPanel)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.cLine).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.cLine).frame(height: 1)
        }
    }

    private func targetRow(_ t: DeleteTarget) -> some View {
        let isProt = t.isProtected
            || DeleteService.isProtected(t.path, additional: app.userProtectedPaths)
        return HStack(spacing: 10) {
            IconView(icon: isProt ? .shield : .trash, size: 12)
                .foregroundStyle(isProt ? Color.cRed : Color.cInk2)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color.cInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isProt {
                    Text("Skipped — system protected")
                        .font(Theme.body(10.5))
                        .foregroundStyle(Color.cRed)
                }
            }
            Spacer()
            Text(Fmt.ageSince(t.mtime))
                .font(Theme.body(11))
                .foregroundStyle(Color.cInk2)
                .frame(width: 80, alignment: .trailing)
            Text(Fmt.bytes(t.size))
                .font(Theme.display(14, weight: .bold))
                .foregroundStyle(Color.cInk)
                .strikethrough(isProt)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 10)
        .opacity(isProt ? 0.55 : 1)
        .background(isProt ? Color.cRedSoft.opacity(0.4) : Color.clear)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                kindRadio(kind: .trash,
                          title: "Move to Trash",
                          sub: "recoverable from Finder")
                kindRadio(kind: .forever,
                          title: "Delete forever",
                          sub: "no undo")
            }
            HStack(spacing: 10) {
                Spacer()
                Button {
                    app.closeDeleteSheet()
                } label: {
                    Text("Cancel")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Color.cInk2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Button {
                    app.confirmDelete()
                } label: {
                    Text(confirmLabel)
                        .font(Theme.body(13, weight: .bold))
                        .foregroundStyle(Color.cPaper)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(split.allowed.isEmpty
                                      ? Color.cLine
                                      : Color.cCoral)
                        )
                }
                .buttonStyle(.plain)
                .disabled(split.allowed.isEmpty)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    private var confirmLabel: String {
        let n = split.allowed.count
        guard n > 0 else { return "Nothing to do" }
        let verb = app.deleteKind == .trash ? "Move" : "Delete"
        return "\(verb) \(n) · free \(Fmt.bytes(split.allowedTotal))"
    }

    private func kindRadio(kind: DeleteKind, title: String, sub: String) -> some View {
        let on = app.deleteKind == kind
        return Button {
            app.deleteKind = kind
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(on ? Color.cCoral : Color.cLine2, lineWidth: 2)
                        .frame(width: 16, height: 16)
                    if on {
                        Circle()
                            .fill(Color.cCoral)
                            .frame(width: 8, height: 8)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Color.cInk)
                    Text(sub)
                        .font(Theme.body(11))
                        .foregroundStyle(Color.cInk2)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on ? Color.cCoralSoft.opacity(0.4) : Color.cPaper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(on ? Color.cCoral : Color.cLine,
                                          lineWidth: on ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
