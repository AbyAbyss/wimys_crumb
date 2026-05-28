// UIModels.swift
// Plain Sendable value types — UI-facing query result shapes.
// There is no in-memory scan tree (see plan §9). These types are produced by
// SQLite queries (or MockData for previews/empty states).

import Foundation

// MARK: - File type classification

/// 8 categories used across the app (file types screen, treemap legends).
/// Encoded as Int in SQLite to match `large_files.file_type` and `file_type_totals.file_type`.
enum FileTypeCategory: Int, CaseIterable, Sendable, Identifiable {
    case video = 0
    case photos = 1
    case code = 2
    case apps = 3
    case documents = 4
    case music = 5
    case archives = 6
    case other = 7

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .video: return "Video"
        case .photos: return "Photos"
        case .code: return "Code"
        case .apps: return "Apps"
        case .documents: return "Documents"
        case .music: return "Music"
        case .archives: return "Archives"
        case .other: return "Other"
        }
    }
}

// MARK: - Directories

/// One directory row, joined to the totals we care about for lists.
struct DirRow: Identifiable, Hashable, Sendable {
    let id: Int64
    let parentId: Int64?
    let name: String
    let depth: Int
    let isHidden: Bool
    let isPackage: Bool
    let mtime: Date?
    let totalSize: Int64
    let descendantFileCount: Int64
}

// MARK: - Groups (e.g. all node_modules)

struct GroupRow: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let tagline: String
    let count: Int
    let total: Int64
    let avgAgeDays: Double
    let devOnly: Bool
}

// MARK: - File types

struct FileTypeTotal: Identifiable, Hashable, Sendable {
    var id: FileTypeCategory { type }
    let type: FileTypeCategory
    let totalSize: Int64
    let fileCount: Int64
}

struct LargeFileRow: Identifiable, Hashable, Sendable {
    let id: Int64
    let dirId: Int64
    let name: String
    let size: Int64
    let mtime: Date?
    let ext: String?
    let type: FileTypeCategory
}

// MARK: - Scanning

struct ScanProgress: Sendable {
    var fraction: Double        // 0...1
    var filesScanned: Int64
    var currentPath: String
    var etaSeconds: Int?
}

// MARK: - History

struct Snapshot: Identifiable, Hashable, Sendable {
    let id: Int64
    let volumeUUID: String
    let volumeName: String
    let startedAt: Date
    let completedAt: Date?
    let totalUsed: Int64?
    let fileCount: Int64?
}

/// One historical scan's worth of summary — what the History screen
/// charts + lists. Sourced by HistoryLoader from each per-scan SQLite
/// file; the id is the file URL since the per-scan `scans.id` repeats
/// across files.
struct HistorySummary: Identifiable, Hashable, Sendable {
    var id: URL { dbURL }
    let dbURL: URL
    let volumeUUID: String
    let volumeName: String
    let startedAt: Date
    let completedAt: Date?
    let totalUsed: Int64
    let totalFree: Int64?
    let fileCount: Int64?
}

/// One row in the growers/shrinkers diff between the two most recent
/// scans. `previousSize` is from the older scan; `currentSize` from
/// the newer. Negative delta = shrank.
struct TopFolderDelta: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let previousSize: Int64
    let currentSize: Int64
    var delta: Int64 { currentSize - previousSize }
    var grew: Bool { delta >= 0 }
}

// MARK: - Delete

struct DeleteTarget: Identifiable, Hashable, Sendable {
    var id: String { path }
    /// For directories: the dir's own id. For files: the parent dir's
    /// id (needed by patchAfterDelete to locate the large_files row).
    let dirId: Int64?
    /// nil for directories; set to the file's last-path-component for
    /// individual files. Lets patchAfterDelete match large_files rows.
    let fileName: String?
    let path: String
    let size: Int64
    let mtime: Date?
    let isProtected: Bool

    var isFile: Bool { fileName != nil }
}

enum DeleteKind: Sendable { case trash, forever }

// MARK: - Toast

struct Toast: Identifiable, Sendable {
    let id = UUID()
    let message: String
    let action: ToastAction?
    let duration: TimeInterval
}

struct ToastAction: Sendable {
    let label: String
    let kind: Kind
    enum Kind: Sendable { case undoDelete }
}

// MARK: - Suggestions

struct Suggestion: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let saveBytes: Int64
    let kind: Kind
    /// How to resolve the targets when the user clicks this suggestion.
    /// `.review` means there's no concrete delete set — the click just
    /// surfaces a toast. Optional so existing call sites that don't
    /// care about actionability still compile.
    let action: SuggestionAction?

    enum Kind: Sendable, Hashable { case safe, review }
}

enum SuggestionAction: Sendable, Hashable {
    /// All directories with `name` whose mtime is older than `staleDays`.
    case staleDir(name: String, staleDays: Int)
    /// All directories with `name` regardless of age.
    case allDir(name: String)
    /// Large files inside any "Downloads" directory older than `staleDays`.
    case oldDownloads(staleDays: Int)
    /// Suggestion describes a judgement call — no canonical delete set.
    case review
}

// MARK: - Volumes (Start screen)

struct VolumeInfo: Identifiable, Hashable, Sendable {
    /// Use the volume UUID when available; otherwise the resolved path string.
    let id: String
    let name: String
    let kind: VolumeKind
    let totalCapacity: Int64
    let availableCapacity: Int64
    let url: URL

    var used: Int64 { max(0, totalCapacity - availableCapacity) }
    var fractionUsed: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(used) / Double(totalCapacity)
    }
    var isAlmostFull: Bool { fractionUsed > 0.85 }
}

enum VolumeKind: Sendable, Hashable {
    case `internal`, external, usb, network, removable

    var label: String {
        switch self {
        case .internal: return "internal"
        case .external: return "external"
        case .usb: return "usb"
        case .network: return "network"
        case .removable: return "removable"
        }
    }
}

// MARK: - Recent scan (Start screen "Last scans")

struct RecentScan: Identifiable, Hashable, Sendable {
    let id: URL                  // database file URL
    let volumeName: String
    let startedAt: Date
    let totalUsed: Int64?
}

// MARK: - Format helpers (mirror shared.jsx fmtBytes / fmtAge)

enum Fmt {
    static func bytes(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1e12 { return String(format: "%.2f TB", b / 1e12) }
        if b >= 1e9  { return String(format: "%.1f GB", b / 1e9) }
        if b >= 1e6  { return String(format: "%.0f MB", b / 1e6) }
        if b >= 1e3  { return String(format: "%.0f KB", b / 1e3) }
        return "\(bytes) B"
    }

    static func age(daysOld days: Double) -> String {
        if days < 1 { return "today" }
        if days < 7 { return "\(Int(days))d ago" }
        if days < 60 { return "\(Int((days / 7).rounded()))w ago" }
        if days < 365 { return "\(Int((days / 30).rounded()))mo ago" }
        return String(format: "%.1fy ago", days / 365)
    }

    static func ageSince(_ date: Date?) -> String {
        guard let date else { return "—" }
        let days = -date.timeIntervalSinceNow / 86400.0
        return age(daysOld: max(0, days))
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
