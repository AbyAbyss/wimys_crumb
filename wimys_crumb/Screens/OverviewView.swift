// OverviewView.swift
// Top row of stat cards, then a 1.6:1 split (treemap on the left, file-type
// mini-list + quick wins on the right). Plan §8.3.
//
// All data comes from query results held on AppModel (loadOverview()).

import SwiftUI

struct OverviewView: View {
    @Bindable var app: AppModel

    var body: some View {
        VStack(spacing: Spacing.cardGap) {
            if app.shouldShowFDAPrompt {
                fdaBanner
            }
            statRow
            HStack(alignment: .top, spacing: Spacing.cardGap) {
                treemapCard
                    .frame(maxWidth: .infinity)
                VStack(spacing: Spacing.cardGap) {
                    typesCard
                    suggestionsCard
                }
                .frame(width: 380)
            }
        }
        .padding(.horizontal, Spacing.screenH)
        .padding(.bottom, Spacing.screenV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Banner shown when the scan couldn't read enough paths that the
    /// user should grant Full Disk Access. Plan §11.3.
    private var fdaBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            IconView(icon: .shield, size: 18)
                .foregroundStyle(Color.cRed)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(app.skippedCount.formatted(.number)) folders couldn't be read")
                    .font(Theme.body(14, weight: .bold))
                    .foregroundStyle(Color.cInk)
                Text("Grant Full Disk Access so Crumb sees everything on your drive. Without it, totals exclude protected areas.")
                    .font(Theme.body(12))
                    .foregroundStyle(Color.cInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack(spacing: 6) {
                Button("Open Settings") { app.openFullDiskAccessSettings() }
                    .controlSize(.small)
                Button { app.dismissFDAPrompt() } label: {
                    IconView(icon: .x, size: 11)
                        .foregroundStyle(Color.cInk2)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.cRedSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.cRed.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Stat cards

    private var statRow: some View {
        HStack(spacing: Spacing.cardGap) {
            StatCard(title: "Used", value: Fmt.bytes(app.overviewStats.used), accent: .cCoral)
            StatCard(title: "Free", value: Fmt.bytes(app.overviewStats.free), accent: .cSage)
            StatCard(title: "Items scanned",
                     value: app.overviewStats.items.formatted(.number),
                     accent: .cNavy)
            StatCardDark(
                title: app.freedBytes > 0 ? "Freed so far" : "Could free",
                value: Fmt.bytes(app.freedBytes > 0 ? app.freedBytes : app.overviewStats.couldFree),
                action: { app.goToGroups() }
            )
        }
    }

    private struct StatCard: View {
        let title: String
        let value: String
        let accent: Color
        var body: some View {
            Card(pad: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.uppercased())
                        .font(Theme.body(11, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(Color.cInk2)
                    Text(value)
                        .font(Theme.display(28, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundStyle(Color.cInk)
                        .monospacedDigit()
                    Capsule().fill(accent).frame(height: 3).frame(width: 28)
                }
            }
        }
    }

    private struct StatCardDark: View {
        let title: String
        let value: String
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.uppercased())
                        .font(Theme.body(11, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(Color.cHoney)
                    Text(value)
                        .font(Theme.display(28, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    HStack(spacing: 5) {
                        Text("Review")
                            .font(Theme.body(11, weight: .bold))
                            .foregroundStyle(Color.cHoney)
                        IconView(icon: .chevron, size: 10, weight: .bold)
                            .foregroundStyle(Color.cHoney)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.cInk)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Treemap card

    private var treemapCard: some View {
        Card(pad: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("WHERE THE SPACE GOES")
                        .font(Theme.body(13, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.cInk)
                    Spacer()
                    Text("\(app.overviewTopFolders.count) folders")
                        .font(Theme.body(12))
                        .foregroundStyle(Color.cInk2)
                }
                if app.overviewTopFolders.isEmpty {
                    Text("No scan data yet. Run a scan from Start.")
                        .font(Theme.body(13))
                        .foregroundStyle(Color.cInk3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 320)
                } else {
                    TreemapView(items: app.overviewTopFolders) { dir in
                        app.drillInto(dirId: dir.id)
                    }
                    .frame(minHeight: 360)
                }
            }
        }
    }

    // MARK: - File types mini-list

    private var typesCard: some View {
        Card(pad: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("BY FILE TYPE")
                        .font(Theme.body(13, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.cInk)
                    Spacer()
                    Button(action: { app.goToTypes() }) {
                        Text("All →")
                            .font(Theme.body(11, weight: .bold))
                            .foregroundStyle(Color.cInk2)
                    }
                    .buttonStyle(.plain)
                }
                if app.overviewTypes.isEmpty {
                    Text("—")
                        .font(Theme.body(13))
                        .foregroundStyle(Color.cInk3)
                } else {
                    let maxSize = Double(app.overviewTypes.map(\.totalSize).max() ?? 1)
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(app.overviewTypes.prefix(6)) { t in
                            HStack {
                                HStack(spacing: 7) {
                                    Circle().fill(Color.aHues[t.type.rawValue % Color.aHues.count])
                                        .frame(width: 9, height: 9)
                                    Text(t.type.displayName)
                                        .font(Theme.body(12, weight: .medium))
                                        .foregroundStyle(Color.cInk)
                                }
                                Spacer()
                                Text(Fmt.bytes(t.totalSize))
                                    .font(Theme.body(12))
                                    .foregroundStyle(Color.cInk2)
                                    .monospacedDigit()
                            }
                            ProgressBarView(
                                fraction: maxSize > 0 ? Double(t.totalSize) / maxSize : 0,
                                color: Color.aHues[t.type.rawValue % Color.aHues.count],
                                height: 4
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quick wins (suggestions)

    private var suggestionsCard: some View {
        Card(pad: 18, tintedBg: .cHoneySoft, borderColor: .cLine2) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    IconView(icon: .sparkle, size: 14)
                        .foregroundStyle(Color.cHoney)
                    Text("QUICK WINS")
                        .font(Theme.body(13, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.cInk)
                }
                if app.suggestions.isEmpty {
                    Text("Nothing obvious to clean up. Nice.")
                        .font(Theme.body(13))
                        .foregroundStyle(Color.cInk2)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(app.suggestions) { s in
                            Button {
                                app.openSuggestion(s)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(s.title)
                                            .font(Theme.body(13, weight: .semibold))
                                            .foregroundStyle(Color.cInk)
                                        Spacer()
                                        Text(Fmt.bytes(s.saveBytes))
                                            .font(Theme.body(12, weight: .semibold))
                                            .foregroundStyle(s.kind == .safe ? Color.cSage : Color.cInk2)
                                            .monospacedDigit()
                                    }
                                    Text(s.detail)
                                        .font(Theme.body(11))
                                        .foregroundStyle(Color.cInk2)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if s.id != app.suggestions.last?.id {
                                Divider().background(Color.cLine2)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    OverviewView(app: AppModel.previewOverview)
        .frame(width: 1280, height: 760)
        .background(Color.cBg)
}
