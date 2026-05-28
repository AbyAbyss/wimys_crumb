// IconView.swift
// Lightweight wrapper around SF Symbols approximating the prototype's icon set.
// The prototype defined inline SVG paths in shared.jsx; on macOS we use the
// closest SF Symbol so the app stays native. Mapping is centralized here so a
// later pass can swap to bundled SVG art without touching call sites.

import SwiftUI

enum AppIcon: String {
    case folder, drive, search, trash, shield, clock, sparkle, cog
    case chevron, chevdown, chart, arrowup, arrowdn, plus, x, close
    case video, photo, code, music, doc, archive, app, other, hidden
    case refresh, download, play, pause, check, warn, filter, grid, list

    /// SF Symbol name backing this icon.
    var systemName: String {
        switch self {
        case .folder:    return "folder"
        case .drive:     return "internaldrive"
        case .search:    return "magnifyingglass"
        case .trash:     return "trash"
        case .shield:    return "shield"
        case .clock:     return "clock"
        case .sparkle:   return "sparkles"
        case .cog:       return "gearshape"
        case .chevron:   return "chevron.right"
        case .chevdown:  return "chevron.down"
        case .chart:     return "chart.bar"
        case .arrowup:   return "arrow.up"
        case .arrowdn:   return "arrow.down"
        case .plus:      return "plus"
        case .x, .close: return "xmark"
        case .video:     return "film"
        case .photo:     return "photo"
        case .code:      return "chevron.left.forwardslash.chevron.right"
        case .music:     return "music.note"
        case .doc:       return "doc"
        case .archive:   return "archivebox"
        case .app:       return "square.grid.2x2"
        case .other:     return "questionmark.circle"
        case .hidden:    return "eye"
        case .refresh:   return "arrow.clockwise"
        case .download:  return "arrow.down.to.line"
        case .play:      return "play.fill"
        case .pause:     return "pause.fill"
        case .check:     return "checkmark"
        case .warn:      return "exclamationmark.triangle"
        case .filter:    return "line.3.horizontal.decrease"
        case .grid:      return "square.grid.2x2"
        case .list:      return "list.bullet"
        }
    }
}

struct IconView: View {
    let icon: AppIcon
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold

    var body: some View {
        Image(systemName: icon.systemName)
            .font(.system(size: size, weight: weight))
    }
}

#Preview {
    HStack(spacing: 12) {
        IconView(icon: .drive)
        IconView(icon: .folder)
        IconView(icon: .search)
        IconView(icon: .cog)
        IconView(icon: .refresh)
        IconView(icon: .trash)
        IconView(icon: .sparkle)
    }
    .padding()
    .foregroundStyle(Color.cInk)
    .background(Color.cBg)
}
