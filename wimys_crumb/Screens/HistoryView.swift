// HistoryView.swift
// Usage chart over time + snapshots list + growers/shrinkers panel.
// Plan §8.8.
//
// Data: app.historySummaries (one entry per completed scan, newest
// first) and app.historyDeltas (diff between the two newest scans).
// With fewer than two scans we show an honest empty state.

import SwiftUI

struct HistoryView: View {
    @Bindable var app: AppModel

    private var summaries: [HistorySummary] { app.historySummaries }
    private var hasTwoScans: Bool { summaries.count >= 2 }

    /// Chart points are oldest → newest left to right.
    private var chartPoints: [HistorySummary] {
        summaries.reversed()
    }

    var body: some View {
        VStack(spacing: Spacing.cardGap) {
            chartCard
            HStack(alignment: .top, spacing: Spacing.cardGap) {
                snapshotsCard
                    .frame(maxWidth: .infinity)
                deltasCard
                    .frame(width: 380)
            }
        }
        .padding(.horizontal, Spacing.screenH)
        .padding(.bottom, Spacing.screenV)
    }

    // MARK: - Usage chart card

    private var chartCard: some View {
        Card(pad: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DISK USAGE OVER TIME")
                            .font(Theme.body(13, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(Color.cInk)
                        Text(chartSubtitle)
                            .font(Theme.body(12))
                            .foregroundStyle(Color.cInk2)
                    }
                    Spacer()
                    if app.historyLoading {
                        ProgressView().controlSize(.small)
                    }
                }
                if summaries.isEmpty {
                    emptyChart
                } else {
                    chart.frame(height: 220)
                }
            }
        }
    }

    private var chartSubtitle: String {
        if summaries.isEmpty {
            return "History builds up as you scan over time."
        }
        if summaries.count == 1 {
            return "Run another scan to start tracking change."
        }
        let oldest = summaries.last?.startedAt
        let newest = summaries.first?.startedAt
        if let oldest, let newest {
            let days = Int(newest.timeIntervalSince(oldest) / 86_400)
            return "\(summaries.count) scans across \(days) day\(days == 1 ? "" : "s")."
        }
        return "\(summaries.count) scans recorded."
    }

    private var emptyChart: some View {
        VStack(spacing: 10) {
            IconView(icon: .clock, size: 26)
                .foregroundStyle(Color.cInk3)
            Text("No scans yet")
                .font(Theme.body(14, weight: .bold))
                .foregroundStyle(Color.cInk)
            Text("Each completed scan adds a point here.\nGrowers / shrinkers light up after the second scan.")
                .font(Theme.body(12))
                .foregroundStyle(Color.cInk2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    /// Custom SwiftUI path-based area chart — no Charts dependency.
    /// Stable across any point count; degenerate cases (1 point, all
    /// equal) render as a flat line with a single marker.
    private var chart: some View {
        let points = chartPoints
        let values = points.map(\.totalUsed)
        let minV = Double(values.min() ?? 0)
        let maxV = Double(values.max() ?? 1)
        let range = max(1, maxV - minV)

        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height - 24   // leave 24pt for x-axis label gap
            let n = max(1, points.count - 1)
            let stepX = points.count > 1 ? w / CGFloat(n) : w / 2

            // Build screen-space points.
            let coords: [CGPoint] = points.enumerated().map { (i, s) in
                let x = points.count == 1
                    ? w / 2
                    : CGFloat(i) * stepX
                let normalized = (Double(s.totalUsed) - minV) / range
                let y = h - CGFloat(normalized) * (h - 12) - 4
                return CGPoint(x: x, y: y)
            }

            ZStack(alignment: .topLeading) {
                // Area fill below the line.
                Path { p in
                    guard let first = coords.first else { return }
                    p.move(to: CGPoint(x: first.x, y: h))
                    p.addLine(to: first)
                    for c in coords.dropFirst() { p.addLine(to: c) }
                    if let last = coords.last {
                        p.addLine(to: CGPoint(x: last.x, y: h))
                    }
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color.cCoral.opacity(0.35), Color.cCoral.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line on top.
                Path { p in
                    guard let first = coords.first else { return }
                    p.move(to: first)
                    for c in coords.dropFirst() { p.addLine(to: c) }
                }
                .stroke(Color.cCoral, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))

                // End-point marker.
                if let last = coords.last {
                    Circle()
                        .fill(Color.cCoral)
                        .frame(width: 8, height: 8)
                        .position(last)
                }

                // Sparse x-axis labels — leftmost + rightmost.
                if let first = points.first, let last = points.last {
                    Text(Fmt.relative(first.startedAt))
                        .font(Theme.body(10))
                        .foregroundStyle(Color.cInk3)
                        .position(x: 0, y: h + 12)
                        .offset(x: 30)
                    Text(Fmt.relative(last.startedAt))
                        .font(Theme.body(10))
                        .foregroundStyle(Color.cInk3)
                        .position(x: w, y: h + 12)
                        .offset(x: -30)
                }
            }
        }
    }

    // MARK: - Snapshots list

    private var snapshotsCard: some View {
        Card(pad: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("SCAN HISTORY")
                        .font(Theme.body(13, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.cInk)
                    Spacer()
                    Text("\(summaries.count) scan\(summaries.count == 1 ? "" : "s")")
                        .font(Theme.body(11))
                        .foregroundStyle(Color.cInk2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider().overlay(Color.cLine)
                if summaries.isEmpty {
                    Text("Run a scan to start the timeline.")
                        .font(Theme.body(13))
                        .foregroundStyle(Color.cInk2)
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                } else {
                    snapshotList
                }
            }
        }
    }

    private var snapshotList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(summaries.enumerated()), id: \.element.id) { idx, s in
                    snapshotRow(s, previous: idx + 1 < summaries.count ? summaries[idx + 1] : nil)
                    Divider().overlay(Color.cLine)
                }
            }
        }
    }

    private func snapshotRow(_ s: HistorySummary, previous: HistorySummary?) -> some View {
        let delta: Int64? = previous.map { s.totalUsed - $0.totalUsed }
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.completedAt.map(Fmt.relative) ?? Fmt.relative(s.startedAt))
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Color.cInk)
                Text(s.volumeName)
                    .font(Theme.body(11))
                    .foregroundStyle(Color.cInk2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Fmt.bytes(s.totalUsed))
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Color.cInk)
                .frame(width: 100, alignment: .trailing)
                .monospacedDigit()

            if let d = delta {
                let positive = d >= 0
                HStack(spacing: 2) {
                    IconView(icon: positive ? .arrowup : .arrowdn, size: 10)
                    Text(Fmt.bytes(abs(d)))
                        .font(Theme.body(11, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(positive ? Color.cCoral : Color.cSage)
                .frame(width: 80, alignment: .trailing)
            } else {
                Text("—")
                    .font(Theme.body(11))
                    .foregroundStyle(Color.cInk3)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Growers / shrinkers

    private var deltasCard: some View {
        Card(pad: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("WHAT CHANGED")
                        .font(Theme.body(13, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.cInk)
                    Spacer()
                    if hasTwoScans, let prev = summaries.dropFirst().first {
                        Text("since \(Fmt.relative(prev.startedAt))")
                            .font(Theme.body(11))
                            .foregroundStyle(Color.cInk2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider().overlay(Color.cLine)

                if !hasTwoScans {
                    Text("Two scans needed to compute changes.")
                        .font(Theme.body(13))
                        .foregroundStyle(Color.cInk2)
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                } else if app.historyDeltas.isEmpty {
                    Text("No tracked folders changed size between the two most recent scans.")
                        .font(Theme.body(13))
                        .foregroundStyle(Color.cInk2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                } else {
                    deltasScroll
                }
            }
        }
    }

    private var deltasScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let growers = app.historyDeltas.filter(\.grew).prefix(6)
                let shrinkers = app.historyDeltas.filter { !$0.grew }.prefix(6)

                if !growers.isEmpty {
                    sectionLabel("Grew", color: .cCoral, icon: .arrowup)
                    ForEach(Array(growers), id: \.id) { d in
                        deltaRow(d)
                    }
                }
                if !shrinkers.isEmpty {
                    sectionLabel("Shrank", color: .cSage, icon: .arrowdn)
                        .padding(.top, growers.isEmpty ? 0 : 8)
                    ForEach(Array(shrinkers), id: \.id) { d in
                        deltaRow(d)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func sectionLabel(_ text: String, color: Color, icon: AppIcon) -> some View {
        HStack(spacing: 6) {
            IconView(icon: icon, size: 11)
                .foregroundStyle(color)
            Text(text.uppercased())
                .font(Theme.body(11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func deltaRow(_ d: TopFolderDelta) -> some View {
        HStack(spacing: 10) {
            Text(d.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.cInk2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text((d.grew ? "+" : "−") + Fmt.bytes(abs(d.delta)))
                .font(Theme.body(11, weight: .bold))
                .foregroundStyle(d.grew ? Color.cCoral : Color.cSage)
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }
}
