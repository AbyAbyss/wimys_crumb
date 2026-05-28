// TypesView.swift
// "By file type" screen. Stacked bar across all 8 categories + grid of
// type cards (left) + detail panel listing the heaviest files in the
// focused category (right). Plan §8.7.
//
// Aggregates come from app.overviewTypes (loaded after each scan). The
// detail panel's heaviest-files list is lazy: tapping a card / segment
// fires loadTypeFiles via app.selectFileType.

import SwiftUI

struct TypesView: View {
    @Bindable var app: AppModel

    private var totalSize: Int64 {
        app.overviewTypes.reduce(0) { $0 + $1.totalSize }
    }

    /// All 8 categories merged with their totals so empty buckets still
    /// render (with size 0) in stable order.
    private var allCategories: [FileTypeTotal] {
        let dict = Dictionary(uniqueKeysWithValues:
            app.overviewTypes.map { ($0.type, $0) })
        return FileTypeCategory.allCases.map { cat in
            dict[cat] ?? FileTypeTotal(type: cat, totalSize: 0, fileCount: 0)
        }
    }

    private var selected: FileTypeCategory {
        // Default to the largest category on first appearance.
        app.typesSelected ?? allCategories
            .max { $0.totalSize < $1.totalSize }?.type ?? .other
    }

    private var selectedTotal: FileTypeTotal {
        allCategories.first(where: { $0.type == selected })
            ?? FileTypeTotal(type: selected, totalSize: 0, fileCount: 0)
    }

    var body: some View {
        VStack(spacing: Spacing.cardGap) {
            stackedBarCard
            HStack(alignment: .top, spacing: Spacing.cardGap) {
                gridCard
                    .frame(maxWidth: .infinity)
                detailCard
                    .frame(width: 380)
            }
        }
        .padding(.horizontal, Spacing.screenH)
        .padding(.bottom, Spacing.screenV)
        .task {
            // Load the initial category's heaviest files if needed.
            if app.typesTopFiles.isEmpty {
                app.selectFileType(selected)
            }
        }
    }

    // MARK: - Stacked bar hero

    private var stackedBarCard: some View {
        Card(pad: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DISK BY FILE TYPE")
                            .font(Theme.body(13, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(Color.cInk)
                        Text("Click a segment or a card below to see the heaviest files in that bucket.")
                            .font(Theme.body(12))
                            .foregroundStyle(Color.cInk2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 540, alignment: .leading)
                    }
                    Spacer()
                    Pill(text: "\(Fmt.bytes(totalSize)) scanned",
                         color: .cHoney, soft: .cHoneySoft)
                }
                stackedBar
                    .frame(height: 56)
            }
        }
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(allCategories) { item in
                    let w = totalSize > 0
                        ? CGFloat(Double(item.totalSize) / Double(totalSize)) * geo.size.width
                        : geo.size.width / CGFloat(FileTypeCategory.allCases.count)
                    barSegment(item, width: w)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.cLine, lineWidth: 1)
        )
    }

    private func barSegment(_ item: FileTypeTotal, width: CGFloat) -> some View {
        let color = Color.aHues[item.type.rawValue % Color.aHues.count]
        let isSel = selected == item.type
        return Button {
            app.selectFileType(item.type)
        } label: {
            ZStack(alignment: .topLeading) {
                color.opacity(isSel ? 1.0 : 0.86)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.type.displayName)
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(Color.cPaper)
                        .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 0)
                    Text(Fmt.bytes(item.totalSize))
                        .font(Theme.body(11, weight: .semibold))
                        .foregroundStyle(Color.cPaper.opacity(0.92))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .lineLimit(1)
                .opacity(width > 36 ? 1 : 0)  // hide labels in thin slices
            }
            .frame(width: max(0, width))
            .overlay(
                Rectangle()
                    .strokeBorder(isSel ? Color.cInk : .clear, lineWidth: 3)
                    .padding(2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Type grid (left)

    private var gridCard: some View {
        Card(pad: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(allCategories) { item in
                    typeCardButton(item)
                }
            }
        }
    }

    private func typeCardButton(_ item: FileTypeTotal) -> some View {
        let isSel = selected == item.type
        let color = Color.aHues[item.type.rawValue % Color.aHues.count]
        let pct = totalSize > 0
            ? Double(item.totalSize) / Double(totalSize)
            : 0
        return Button {
            app.selectFileType(item.type)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    iconTile(for: item.type, color: color, large: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.type.displayName)
                            .font(Theme.body(14, weight: .bold))
                            .foregroundStyle(Color.cInk)
                        Text("\(item.fileCount.formatted(.number)) files · \(Int((pct * 100).rounded()))%")
                            .font(Theme.body(11))
                            .foregroundStyle(Color.cInk2)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(Fmt.bytes(item.totalSize))
                        .font(Theme.display(17, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Color.cInk)
                        .monospacedDigit()
                }
                ProgressBarView(
                    fraction: min(1, pct * 3),  // ×3 so smaller categories still register
                    color: color,
                    height: 5
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSel ? Color.cCoralSoft.opacity(0.4) : Color.cPaper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSel ? Color.cCoral : Color.cLine,
                                          lineWidth: isSel ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func iconTile(for type: FileTypeCategory, color: Color, large: Bool) -> some View {
        let icon: AppIcon = {
            switch type {
            case .video:     return .video
            case .photos:    return .photo
            case .code:      return .code
            case .apps:      return .app
            case .documents: return .doc
            case .music:     return .music
            case .archives:  return .archive
            case .other:     return .other
            }
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.18))
            IconView(icon: icon, size: large ? 16 : 13)
                .foregroundStyle(color)
        }
        .frame(width: large ? 32 : 22, height: large ? 32 : 22)
    }

    // MARK: - Detail panel (right)

    private var detailCard: some View {
        Card(pad: 0) {
            VStack(spacing: 0) {
                detailHeader
                Divider().overlay(Color.cLine)
                if app.typesTopFiles.isEmpty {
                    Text("No files tracked in this category.\n\nThe scanner keeps the top files per directory; tiny files don't appear here individually but still count toward totals.")
                        .font(Theme.body(12))
                        .foregroundStyle(Color.cInk2)
                        .lineSpacing(3)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    filesScroll
                }
                Divider().overlay(Color.cLine)
                detailFooter
            }
        }
    }

    private var detailHeader: some View {
        let color = Color.aHues[selected.rawValue % Color.aHues.count]
        return HStack(spacing: 10) {
            iconTile(for: selected, color: color, large: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(selected.displayName)
                    .font(Theme.display(20, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.cInk)
                Text("\(Fmt.bytes(selectedTotal.totalSize)) · \(selectedTotal.fileCount.formatted(.number)) files")
                    .font(Theme.body(11))
                    .foregroundStyle(Color.cInk2)
            }
            Spacer()
        }
        .padding(16)
        .background(color.opacity(0.10))
    }

    private var filesScroll: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(app.typesTopFiles) { row in
                    fileRow(row)
                    Divider().overlay(Color.cLine)
                }
            }
        }
    }

    private func fileRow(_ row: LargeFileRow) -> some View {
        let stale = (row.mtime.map { -$0.timeIntervalSinceNow / 86400.0 } ?? 0) > 180
        let resolver = app.pathResolver
        let where_ = resolver?.fullPath(of: row.dirId) ?? "—"
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Color.cInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(where_)\(stale ? " · stale" : "")")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(stale ? Color.cRed : Color.cInk2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.bytes(row.size))
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Color.cInk)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var detailFooter: some View {
        HStack(spacing: 8) {
            Button {
                app.cleanStaleTypeFiles()
            } label: {
                HStack(spacing: 6) {
                    IconView(icon: .sparkle, size: 11)
                    Text("Clean stale \(selected.displayName.lowercased())")
                        .font(Theme.body(12, weight: .bold))
                }
                .foregroundStyle(Color.cPaper)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.cCoral)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.cPanel)
    }
}
