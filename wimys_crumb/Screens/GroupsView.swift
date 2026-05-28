// GroupsView.swift
// "Folders grouped by name across the disk." Bubble chart hero + list with
// expand-on-click rows. Plan §8.5.
//
// Data comes from AppModel.groups (loaded after a scan) and
// AppModel.groupsInstances (lazy-loaded on expand).

import SwiftUI

struct GroupsView: View {
    @Bindable var app: AppModel

    private var filteredGroups: [GroupRow] {
        switch app.groupsFilter {
        case .all:   return app.groups
        case .stale: return app.groups.filter { $0.avgAgeDays > 90 }
        }
    }

    private var selectedInstances: [DirRow] {
        app.groupsInstances.filter { app.groupsSelection.contains($0.id) }
    }

    private var selectedTotal: Int64 {
        selectedInstances.reduce(0) { $0 + $1.totalSize }
    }

    var body: some View {
        VStack(spacing: Spacing.cardGap) {
            bubbleCard
            listCard
        }
        .padding(.horizontal, Spacing.screenH)
        .padding(.bottom, Spacing.screenV)
    }

    // MARK: - Bubble chart card

    private var bubbleCard: some View {
        Card(pad: 20) {
            VStack(alignment: .leading, spacing: 8) {
                header
                BubbleChart(
                    groups: app.groups,
                    selected: app.expandedGroup,
                    onTap: { name in
                        app.toggleGroupExpanded(name)
                    }
                )
                .frame(height: 220)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GROUPS BY NAME")
                    .font(Theme.body(13, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.cInk)
                Text("Folders with the same name across your disk, totalled. Click a bubble to expand it below.")
                    .font(Theme.body(12))
                    .foregroundStyle(Color.cInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 540, alignment: .leading)
            }
            Spacer()
            Pill(text: "\(app.groups.count) groups · \(Fmt.bytes(totalAcrossGroups))",
                 color: .cHoney, soft: .cHoneySoft)
        }
    }

    private var totalAcrossGroups: Int64 {
        app.groups.reduce(0) { $0 + $1.total }
    }

    // MARK: - List card

    private var listCard: some View {
        Card(pad: 0) {
            VStack(spacing: 0) {
                listHeader
                Divider().overlay(Color.cLine)
                scroll
            }
        }
    }

    private var listHeader: some View {
        HStack(spacing: 10) {
            Text("\(filteredGroups.count) groups · \(Fmt.bytes(totalAcrossGroups))")
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Color.cInk)
            Spacer()
            filterButton
            if !selectedInstances.isEmpty {
                bulkDeleteButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var filterButton: some View {
        Button {
            app.groupsFilter = (app.groupsFilter == .stale) ? .all : .stale
        } label: {
            HStack(spacing: 5) {
                IconView(icon: .filter, size: 11)
                Text("Stale only\(app.groupsFilter == .stale ? " ✓" : "")")
                    .font(Theme.body(11, weight: .semibold))
            }
            .foregroundStyle(app.groupsFilter == .stale ? Color.cPaper : Color.cInk2)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(app.groupsFilter == .stale ? Color.cInk : Color.cPanel)
            )
        }
        .buttonStyle(.plain)
    }

    private var bulkDeleteButton: some View {
        Button {
            app.deleteSelectedGroupInstances()
        } label: {
            Text("Free \(Fmt.bytes(selectedTotal)) →")
                .font(Theme.body(11, weight: .bold))
                .foregroundStyle(Color.cPaper)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.cCoral))
        }
        .buttonStyle(.plain)
    }

    private var scroll: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredGroups.isEmpty {
                    Text(app.groups.isEmpty
                         ? "No groups found in this scan. Run a scan from Start."
                         : "No groups match the current filter.")
                        .font(Theme.body(13))
                        .foregroundStyle(Color.cInk2)
                        .padding(.vertical, 30)
                } else {
                    ForEach(Array(filteredGroups.enumerated()), id: \.element.id) { idx, group in
                        groupRow(group, colorIndex: idx)
                        Divider().overlay(Color.cLine)
                    }
                }
            }
        }
    }

    // MARK: - Group row + instances

    private func groupRow(_ group: GroupRow, colorIndex: Int) -> some View {
        let isOpen = app.expandedGroup == group.name
        let maxTotal = Double(app.groups.first?.total ?? 1)
        let frac = maxTotal > 0 ? Double(group.total) / maxTotal : 0

        return VStack(spacing: 0) {
            Button {
                app.toggleGroupExpanded(group.name)
            } label: {
                HStack(spacing: 10) {
                    IconView(icon: isOpen ? .chevdown : .chevron, size: 11)
                        .foregroundStyle(Color.cInk2)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(group.name)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.cInk)
                            if group.devOnly {
                                Pill(text: "dev", color: .cLilac, soft: .cLilacSoft)
                            }
                        }
                        Text(group.tagline)
                            .font(Theme.body(11))
                            .foregroundStyle(Color.cInk2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(group.count) folder\(group.count == 1 ? "" : "s")")
                        .font(Theme.body(12))
                        .foregroundStyle(Color.cInk2)
                        .frame(width: 90, alignment: .leading)

                    Text("avg \(Fmt.age(daysOld: group.avgAgeDays))")
                        .font(Theme.body(12))
                        .foregroundStyle(Color.cInk2)
                        .frame(width: 110, alignment: .leading)

                    ProgressBarView(
                        fraction: frac,
                        color: rowAccent(forIndex: colorIndex),
                        height: 5
                    )
                    .frame(width: 80)

                    Text(Fmt.bytes(group.total))
                        .font(Theme.display(17, weight: .bold))
                        .foregroundStyle(Color.cInk)
                        .frame(width: 100, alignment: .trailing)
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isOpen ? Color.cCoralSoft.opacity(0.35) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                instancesList
            }
        }
    }

    private func rowAccent(forIndex i: Int) -> Color {
        switch i {
        case 0: return .cCoral
        case let n where n % 2 == 0: return .cSage
        default: return .cHoney
        }
    }

    private var instancesList: some View {
        // Pre-compute the max size once per render so each instance row
        // doesn't re-read app.groupsInstances.first (which would re-render).
        let maxSize = Double(app.groupsInstances.first?.totalSize ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            selectionBar
            LazyVStack(spacing: 0) {
                ForEach(app.groupsInstances) { row in
                    instanceRow(row, maxSize: maxSize)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.leading, 48)
    }

    /// Header above the lazy list with bulk-select actions.
    /// Plan §8.5 footer's bulk delete pairs naturally with this.
    private var selectionBar: some View {
        let total = app.groupsInstances.count
        let selected = app.groupsSelection.count
        let staleCount = app.groupsInstances.reduce(into: 0) { acc, row in
            if let m = row.mtime,
               -m.timeIntervalSinceNow / 86_400.0 > 180 {
                acc += 1
            }
        }
        return HStack(spacing: 8) {
            Text("\(selected) of \(total) selected")
                .font(Theme.body(11, weight: .semibold))
                .foregroundStyle(Color.cInk2)
            Spacer()
            smallButton(label: "Select all", icon: .check) {
                app.selectAllInExpandedGroup()
            }
            if staleCount > 0 {
                smallButton(label: "Stale only (\(staleCount))", icon: .filter) {
                    app.selectStaleInExpandedGroup()
                }
            }
            if selected > 0 {
                smallButton(label: "Clear", icon: .x) {
                    app.clearGroupSelection()
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private func smallButton(label: String, icon: AppIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                IconView(icon: icon, size: 10)
                Text(label)
                    .font(Theme.body(11, weight: .semibold))
            }
            .foregroundStyle(Color.cInk)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.cPanel))
            .overlay(Capsule().strokeBorder(Color.cLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func instanceRow(_ row: DirRow, maxSize: Double) -> some View {
        let selected = app.groupsSelection.contains(row.id)
        let stale = (row.mtime.map { -$0.timeIntervalSinceNow / 86400.0 } ?? 0) > 180
        let frac = maxSize > 0 ? Double(row.totalSize) / maxSize : 0
        // Use the pre-resolved path (populated off-main on expand). Falls back
        // to the bare folder name during the brief window before the resolver
        // task finishes — better than blocking each row on a SQL walk.
        let displayPath = app.groupsInstancePaths[row.id] ?? row.name

        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selected },
                set: { newValue in
                    if newValue { app.groupsSelection.insert(row.id) }
                    else { app.groupsSelection.remove(row.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 20)

            Text(displayPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.cInk2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(stale ? "\(Fmt.ageSince(row.mtime)) · stale" : Fmt.ageSince(row.mtime))
                .font(Theme.body(11))
                .foregroundStyle(stale ? Color.cRed : Color.cInk2)
                .frame(width: 110, alignment: .leading)

            ProgressBarView(
                fraction: frac,
                color: stale ? Color.cRed : Color.cCoral,
                height: 4
            )
            .frame(width: 80)

            Text(Fmt.bytes(row.totalSize))
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Color.cInk)
                .frame(width: 90, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }
}

// MARK: - Bubble chart

/// Fixed-position bubble cluster. Radius scales with √(total/maxTotal),
/// matching the prototype's `computeBubbles` formula. Lays out up to 7
/// bubbles — extras don't render in the chart but still appear in the
/// list below.
private struct BubbleChart: View {
    let groups: [GroupRow]
    let selected: String?
    let onTap: (String) -> Void

    private static let positions: [(cx: Double, cy: Double)] = [
        (200, 130), (380,  90), (510, 165),
        (640,  95), (730, 175), (840, 105),
        (880, 195),
    ]
    private static let designWidth: Double  = 1000
    private static let designHeight: Double = 240

    var body: some View {
        GeometryReader { geo in
            let scaleX = geo.size.width / Self.designWidth
            let scaleY = geo.size.height / Self.designHeight
            let scale = min(scaleX, scaleY)
            let maxTotal = max(1, Double(groups.map(\.total).max() ?? 1))
            let shown = Array(groups.prefix(Self.positions.count))

            ZStack(alignment: .topLeading) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { idx, group in
                    let pos = Self.positions[idx]
                    let r = (18 + sqrt(Double(group.total) / maxTotal) * 80) * scale
                    let cx = pos.cx * scaleX
                    let cy = pos.cy * scaleY
                    let isSel = selected == group.name
                    Button { onTap(group.name) } label: {
                        bubble(group: group, radius: r, isSelected: isSel)
                    }
                    .buttonStyle(.plain)
                    .position(x: cx, y: cy)
                }
            }
        }
    }

    private func bubble(group: GroupRow, radius: Double, isSelected: Bool) -> some View {
        let color = bubbleColor(for: group.name)
        let isLarge = radius > 50
        return ZStack {
            Circle()
                .fill(color)
                .opacity(isSelected ? 1.0 : 0.88)
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? Color.cInk : .clear,
                                      lineWidth: isSelected ? 3 : 0)
                )
            VStack(spacing: 2) {
                Text(group.name)
                    .font(Theme.body(isLarge ? 12 : 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(Fmt.bytes(group.total))
                    .font(Theme.display(isLarge ? 17 : 12, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Color.cPaper)
            .padding(.horizontal, 6)
        }
        .frame(width: radius * 2, height: radius * 2)
    }

    /// Hash a group name to a stable color from the prototype palette so
    /// the same group keeps its color across scans.
    private func bubbleColor(for name: String) -> Color {
        let hues = Color.aHues
        var hash = 0
        for c in name.unicodeScalars { hash = (hash &* 31) &+ Int(c.value) }
        return hues[(hash & Int.max) % hues.count]
    }
}
