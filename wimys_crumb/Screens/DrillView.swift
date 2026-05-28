// DrillView.swift
// Folder contents + detail panel, reached by clicking a treemap tile on
// Overview. Plan §8.4.
//
// Data comes straight from app.drillItems (populated by AppModel.drillInto).
// No tree is held in memory — each navigation step re-queries SQLite via
// AppModel.

import SwiftUI
import AppKit

struct DrillView: View {
    @Bindable var app: AppModel

    /// Currently highlighted row in the list — drives the right panel.
    /// Defaults to the largest item once data loads.
    @State private var selectedRowId: Int64? = nil

    /// Whether dot-folders are visible. Persisted via Settings (plan §8.4).
    @AppStorage(SettingsKey.allowDeletingHidden)
    private var allowHidden: Bool = false

    private var currentNode: (id: Int64, name: String)? { app.drillCrumb.last }

    /// drillItems filtered by the hidden toggle. Bulk-select operates on this
    /// list, so hidden items can't be checked while the toggle is off.
    private var visibleItems: [DirRow] {
        allowHidden ? app.drillItems : app.drillItems.filter { !$0.isHidden }
    }

    private var selectedCount: Int {
        visibleItems.filter { app.drillSelection.contains($0.id) }.count
    }

    private var selectedSize: Int64 {
        visibleItems.filter { app.drillSelection.contains($0.id) }
            .reduce(0) { $0 + $1.totalSize }
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
                .padding(.horizontal, Spacing.screenH)
                .padding(.bottom, 12)
            HStack(alignment: .top, spacing: Spacing.cardGap) {
                contentCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                detailCard
                    .frame(width: 280)
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.screenV)
        }
        .onChange(of: app.drillItems) { _, newItems in
            // Re-anchor the selection when the drill content changes
            // (entering a folder, popping a crumb, etc).
            selectedRowId = newItems.first?.id
        }
        .task {
            if selectedRowId == nil {
                selectedRowId = app.drillItems.first?.id
            }
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            IconView(icon: .drive, size: 13)
                .foregroundStyle(Color.cInk2)
            ForEach(Array(app.drillCrumb.enumerated()), id: \.offset) { idx, crumb in
                let isLast = idx == app.drillCrumb.count - 1
                Button {
                    if !isLast { app.popDrill(to: idx) }
                } label: {
                    Text(crumb.name)
                        .font(Theme.body(13, weight: isLast ? .semibold : .regular))
                        .foregroundStyle(isLast ? Color.cInk : Color.cInk2)
                }
                .buttonStyle(.plain)
                .disabled(isLast)
                if !isLast {
                    IconView(icon: .chevron, size: 10)
                        .foregroundStyle(Color.cInk3)
                }
            }
            Spacer()
            if let node = currentNode {
                Pill(text: "\(app.drillItems.count) items",
                     color: .cHoney, soft: .cHoneySoft)
                    .help("Subfolders under \(node.name)")
            }
        }
    }

    // MARK: - Content list (left)

    private var contentCard: some View {
        Card(pad: 0) {
            VStack(spacing: 0) {
                listHeader
                Divider().overlay(Color.cLine)
                rowsScroll
                Divider().overlay(Color.cLine)
                listFooter
            }
        }
    }

    private var listHeader: some View {
        HStack(spacing: 10) {
            IconView(icon: .folder, size: 16)
                .foregroundStyle(Color.cHoney)
            VStack(alignment: .leading, spacing: 1) {
                Text(currentNode?.name ?? "—")
                    .font(Theme.body(15, weight: .bold))
                    .foregroundStyle(Color.cInk)
                Text(headerSubtitle)
                    .font(Theme.body(11))
                    .foregroundStyle(Color.cInk2)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headerSubtitle: String {
        let totalSize = app.drillItems.reduce(0) { $0 + $1.totalSize }
        let n = app.drillItems.count
        return "\(n) folder\(n == 1 ? "" : "s") · \(Fmt.bytes(totalSize))"
    }

    private var rowsScroll: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if visibleItems.isEmpty {
                    Text(app.drillItems.isEmpty
                         ? "Nothing to show here."
                         : "All entries are hidden — turn on \"Allow deleting hidden\" in Settings to see them.")
                        .font(Theme.body(13))
                        .foregroundStyle(Color.cInk2)
                        .padding(.vertical, 32)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                } else {
                    let maxSize = Double(visibleItems.map(\.totalSize).max() ?? 1)
                    ForEach(visibleItems) { row in
                        rowView(row, maxSize: maxSize)
                        Divider().overlay(Color.cLine)
                    }
                }
            }
        }
    }

    private func rowView(_ row: DirRow, maxSize: Double) -> some View {
        let isSelected = selectedRowId == row.id
        let frac = maxSize > 0 ? Double(row.totalSize) / maxSize : 0
        let stale = (row.mtime.map { -$0.timeIntervalSinceNow / 86400.0 } ?? 0) > 180

        return Button {
            selectedRowId = row.id
        } label: {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { app.drillSelection.contains(row.id) },
                    set: { on in
                        if on { app.drillSelection.insert(row.id) }
                        else  { app.drillSelection.remove(row.id) }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 18)
                IconView(icon: row.isHidden ? .hidden : .folder, size: 15)
                    .foregroundStyle(rowIconColor(row, stale: stale))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Color.cInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(rowSubtitle(row, stale: stale))
                        .font(Theme.body(11))
                        .foregroundStyle(stale ? Color.cRed : Color.cInk2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ProgressBarView(
                    fraction: frac,
                    color: stale ? Color.cRed : Color.cCoral,
                    height: 5
                )
                .frame(width: 90)

                Text(Fmt.ageSince(row.mtime))
                    .font(Theme.body(11))
                    .foregroundStyle(Color.cInk2)
                    .frame(width: 70, alignment: .trailing)

                Text(Fmt.bytes(row.totalSize))
                    .font(Theme.display(13, weight: .bold))
                    .foregroundStyle(Color.cInk)
                    .frame(width: 70, alignment: .trailing)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(isSelected ? Color.cCoralSoft.opacity(0.45) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2) {
            // Double-click drills into the folder. Single-click leaves
            // selection driving the detail panel.
            app.drillInto(dirId: row.id)
        }
    }

    private func rowIconColor(_ row: DirRow, stale: Bool) -> Color {
        if row.isHidden { return Color.cInk3 }
        if stale { return Color.cRed }
        return Color.cHoney
    }

    private func rowSubtitle(_ row: DirRow, stale: Bool) -> String {
        let count = row.descendantFileCount
        var s = "\(count.formatted(.number)) item\(count == 1 ? "" : "s")"
        if stale { s += " · stale" }
        return s
    }

    private var listFooter: some View {
        HStack(spacing: 10) {
            Text(footerLabel)
                .font(Theme.body(12))
                .foregroundStyle(Color.cInk2)
            Spacer()
            if selectedCount > 0 {
                Button {
                    app.deleteSelectedDrillItems()
                } label: {
                    HStack(spacing: 6) {
                        IconView(icon: .trash, size: 11)
                        Text("Delete \(selectedCount) · \(Fmt.bytes(selectedSize))")
                            .font(Theme.body(12, weight: .bold))
                    }
                    .foregroundStyle(Color.cPaper)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.cCoral)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.cPanel)
    }

    private var footerLabel: String {
        if selectedCount > 0 {
            return "\(selectedCount) selected"
        }
        guard let node = currentNode else { return "—" }
        return "Inside \(node.name)"
    }

    // MARK: - Detail panel (right)

    private var detailCard: some View {
        Card(pad: 16) {
            VStack(alignment: .leading, spacing: 0) {
                gradientHeader
                if let row = detailRow {
                    Text(row.name)
                        .font(Theme.body(15, weight: .bold))
                        .foregroundStyle(Color.cInk)
                        .padding(.top, 12)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if let path = detailPath(for: row) {
                        Text(path)
                            .font(Theme.body(11, weight: .regular))
                            .foregroundStyle(Color.cInk2)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .padding(.bottom, 14)
                    } else {
                        Color.clear.frame(height: 10)
                    }
                    detailFacts(row)
                    detailActions(row)
                        .padding(.top, 12)
                } else {
                    Text("Click a row to see details.")
                        .font(Theme.body(12))
                        .foregroundStyle(Color.cInk2)
                        .padding(.top, 16)
                }
            }
        }
    }

    private var gradientHeader: some View {
        ZStack {
            LinearGradient(
                colors: [Color.cCoral, Color.cHoney],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            IconView(icon: .folder, size: 28)
                .foregroundStyle(Color.cPaper)
        }
        .frame(height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var detailRow: DirRow? {
        if let id = selectedRowId,
           let row = app.drillItems.first(where: { $0.id == id }) {
            return row
        }
        return app.drillItems.first
    }

    private func detailPath(for row: DirRow) -> String? {
        guard let resolver = app.pathResolver else { return nil }
        return resolver.fullPath(of: row.id)
    }

    private func detailFacts(_ row: DirRow) -> some View {
        VStack(spacing: 0) {
            fact("Size", Fmt.bytes(row.totalSize))
            fact("Items", row.descendantFileCount.formatted(.number))
            fact("Last modified", Fmt.ageSince(row.mtime))
            fact("Kind", row.isPackage ? "Package"
                       : row.isHidden  ? "Hidden folder"
                       : "Folder")
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.body(12))
                .foregroundStyle(Color.cInk2)
            Spacer()
            Text(value)
                .font(Theme.body(12, weight: .medium))
                .foregroundStyle(Color.cInk)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.cLine).frame(height: 1)
        }
    }

    private func detailActions(_ row: DirRow) -> some View {
        VStack(spacing: 6) {
            Button {
                openInFinder(row)
            } label: {
                HStack(spacing: 6) {
                    IconView(icon: .search, size: 11)
                    Text("Reveal in Finder")
                        .font(Theme.body(12, weight: .bold))
                }
                .foregroundStyle(Color.cPaper)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.cInk)
                )
            }
            .buttonStyle(.plain)

            Button {
                deleteFolder(row)
            } label: {
                HStack(spacing: 6) {
                    IconView(icon: .trash, size: 11)
                    Text("Delete this folder")
                        .font(Theme.body(12, weight: .bold))
                }
                .foregroundStyle(Color.cInk)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.cPaper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.cLine, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func deleteFolder(_ row: DirRow) {
        guard let resolver = app.pathResolver else { return }
        let path = resolver.fullPath(of: row.id)
        let isProt = DeleteService.isProtected(path,
                                               additional: app.userProtectedPaths)
        app.openDeleteSheet(targets: [DeleteTarget(
            dirId: row.id,
            fileName: nil,
            path: path,
            size: row.totalSize,
            mtime: row.mtime,
            isProtected: isProt
        )])
    }

    private func openInFinder(_ row: DirRow) {
        guard let resolver = app.pathResolver else { return }
        let path = resolver.fullPath(of: row.id)
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
