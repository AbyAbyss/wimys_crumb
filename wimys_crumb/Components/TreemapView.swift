// TreemapView.swift
// Two-row treemap: top 3 dirs in the top row, the rest in the bottom row.
// Row heights are proportional to their total size sums; within a row, tiles
// flex by size. Colors from A_HUES.

import SwiftUI

struct TreemapView: View {
    let items: [DirRow]
    /// Names that are considered protected (showed with a shield).
    var protectedNames: Set<String> = ["System", "Library", "private", "usr", "bin", "sbin"]
    var onTap: ((DirRow) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let (top, rest) = split(items)
            let heights = rowHeights(h: geo.size.height, top: top, rest: rest)

            VStack(spacing: 4) {
                if !top.isEmpty {
                    TreemapRow(items: top, hueOffset: 0,
                               protectedNames: protectedNames, onTap: onTap)
                        .frame(height: heights.top)
                }
                if !rest.isEmpty {
                    TreemapRow(items: rest, hueOffset: top.count,
                               protectedNames: protectedNames, onTap: onTap)
                        .frame(height: heights.rest)
                }
            }
        }
    }

    private func split(_ items: [DirRow]) -> (top: [DirRow], rest: [DirRow]) {
        let sorted = items.sorted { $0.totalSize > $1.totalSize }
        if sorted.count <= 3 { return (sorted, []) }
        return (Array(sorted.prefix(3)), Array(sorted.dropFirst(3)))
    }

    private func totalSize(_ rows: [DirRow]) -> Int64 {
        rows.reduce(0) { $0 + $1.totalSize }
    }

    /// Heights proportional to size sums, with a 48pt floor so neither row
    /// collapses to unselectable. Pulled out of `body` because `var body` is a
    /// ViewBuilder and can't host bare assignment-style `if` statements.
    private func rowHeights(h: CGFloat, top: [DirRow], rest: [DirRow])
        -> (top: CGFloat, rest: CGFloat) {
        let topSum = totalSize(top)
        let restSum = totalSize(rest)
        let combined = Swift.max(Int64(1), topSum + restSum)
        let frac = CGFloat(topSum) / CGFloat(combined)
        var topH = h * frac
        var restH = h - topH
        if !top.isEmpty && topH < 48 { topH = 48; restH = h - 48 }
        if !rest.isEmpty && restH < 48 { restH = 48; topH = h - 48 }
        return (topH, restH)
    }
}

private struct TreemapRow: View {
    let items: [DirRow]
    let hueOffset: Int
    let protectedNames: Set<String>
    var onTap: ((DirRow) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let total = max(1, items.reduce(Int64(0)) { $0 + $1.totalSize })
            let w = geo.size.width
            HStack(spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, dir in
                    let frac = Double(dir.totalSize) / Double(total)
                    let color = Color.aHues[(hueOffset + idx) % Color.aHues.count]
                    let isProtected = protectedNames.contains(dir.name)
                    TreemapTile(dir: dir, color: color, isProtected: isProtected)
                        .frame(width: max(40, w * frac))
                        .onTapGesture { onTap?(dir) }
                }
            }
        }
    }
}

private struct TreemapTile: View {
    let dir: DirRow
    let color: Color
    let isProtected: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(dir.name)
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if isProtected {
                        IconView(icon: .shield, size: 11)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Text(Fmt.bytes(dir.totalSize))
                    .font(Theme.body(11))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(10)
        }
    }
}

#Preview {
    TreemapView(items: MockData.topFolders)
        .frame(width: 720, height: 360)
        .padding()
        .background(Color.cBg)
}
