// BrandBar.swift
// Logo + tab strip + Rescan + drive picker + cog.
// Matches `IAppBar` in proto-shell.jsx and `AppBar` in a-base.jsx.
//
// Tabs hidden on .start and .scanning. Overview tab stays active for both
// .overview and .drill. Cog tinted coral when Settings is open.

import SwiftUI

struct BrandBar: View {
    @Bindable var app: AppModel

    var body: some View {
        HStack(spacing: 18) {
            // Logo
            Button(action: { app.goToStart() }) {
                HStack(spacing: 10) {
                    CrumbMark()
                    Text("crumb")
                        .font(Theme.display(22, weight: .heavy))
                        .tracking(-0.4)
                        .foregroundStyle(Color.cInk)
                }
            }
            .buttonStyle(.plain)

            // Tabs (hidden on Start and Scanning)
            if app.screen != .start && app.screen != .scanning {
                TabStrip(app: app).padding(.leading, 6)
            }

            Spacer(minLength: 0)

            // Rescan (hidden on Start/Scanning)
            if app.screen != .start && app.screen != .scanning {
                Button(action: { app.rescan() }) {
                    HStack(spacing: 7) {
                        IconView(icon: .refresh, size: 13)
                        Text("Rescan")
                            .font(Theme.body(12, weight: .semibold))
                    }
                    .foregroundStyle(Color.cInk2)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.cPaper)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .strokeBorder(Color.cLine, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Drive picker
            HStack(spacing: 8) {
                IconView(icon: .drive, size: 15, weight: .medium)
                Text(app.currentVolume?.name ?? "Macintosh HD")
                    .font(Theme.body(13, weight: .medium))
                IconView(icon: .chevdown, size: 13, weight: .bold)
            }
            .foregroundStyle(Color.cInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.cPaper)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(Color.cLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))

            // Settings cog
            Button(action: { app.openSettings() }) {
                IconView(icon: .cog, size: 17)
                    .foregroundStyle(app.screen == .settings ? Color.cCoral : Color.cInk2)
                    .frame(width: 38, height: 38)
                    .background(app.screen == .settings ? Color.cCoralSoft : Color.cPaper)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .strokeBorder(Color.cLine, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }
}

// MARK: - Crumb mark (coral square + dot trio)

private struct CrumbMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.cCoral)
                .frame(width: 32, height: 32)
            Circle().fill(Color.cHoney)
                .frame(width: 8, height: 8)
                .offset(x: -6, y: -6)
            Circle().fill(Color.cPaper)
                .frame(width: 6, height: 6)
                .offset(x: 6, y: 6)
            Circle().fill(Color.cHoneySoft)
                .frame(width: 4, height: 4)
                .offset(x: 8, y: -2)
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Tab strip

private struct TabStrip: View {
    @Bindable var app: AppModel

    private struct Tab: Identifiable {
        let id: TabKind
        let label: String
    }

    private enum TabKind { case overview, groups, types, history }

    private let tabs: [Tab] = [
        Tab(id: .overview, label: "Overview"),
        Tab(id: .groups,   label: "Groups"),
        Tab(id: .types,    label: "File types"),
        Tab(id: .history,  label: "History"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button(action: { tap(tab.id) }) {
                    Text(tab.label)
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(isActive(tab.id) ? Color.cPaper : Color.cInk2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(isActive(tab.id) ? Color.cInk : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.cPaper)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.cLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func isActive(_ t: TabKind) -> Bool {
        switch t {
        case .overview: return app.screen == .overview || app.screen == .drill
        case .groups:   return app.screen == .groups
        case .types:    return app.screen == .types
        case .history:  return app.screen == .history
        }
    }

    private func tap(_ t: TabKind) {
        switch t {
        case .overview: app.goToOverview()
        case .groups:   app.goToGroups()
        case .types:    app.goToTypes()
        case .history:  app.goToHistory()
        }
    }
}

#Preview {
    BrandBar(app: AppModel.previewOverview)
        .background(Color.cBg)
        .frame(width: 1200)
}
