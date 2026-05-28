// MockData.swift
// Used only for SwiftUI previews and the pre-first-scan empty state.
// Mirrors `shared.jsx` so previews match the prototype.

import Foundation

enum MockData {
    // MARK: - Volumes (matches DRIVES in shared.jsx)
    static let drives: [VolumeInfo] = [
        VolumeInfo(id: "mac", name: "Macintosh HD", kind: .internal,
                   totalCapacity: 1_000_000_000_000,
                   availableCapacity: 388_000_000_000,
                   url: URL(fileURLWithPath: "/")),
        VolumeInfo(id: "tm", name: "Time Machine", kind: .external,
                   totalCapacity: 4_000_000_000_000,
                   availableCapacity: 1_160_000_000_000,
                   url: URL(fileURLWithPath: "/Volumes/Time Machine")),
        VolumeInfo(id: "usb", name: "Sandisk 64GB", kind: .usb,
                   totalCapacity: 64_000_000_000,
                   availableCapacity: 6_000_000_000,
                   url: URL(fileURLWithPath: "/Volumes/Sandisk")),
    ]

    // MARK: - Top folders (TOP_FOLDERS)
    static let topFolders: [DirRow] = [
        DirRow(id: 1, parentId: nil, name: "Users/lina",  depth: 0, isHidden: false, isPackage: false,
               mtime: daysAgo(2),  totalSize: 412_000_000_000, descendantFileCount: 1_240_321),
        DirRow(id: 2, parentId: nil, name: "Applications",depth: 0, isHidden: false, isPackage: false,
               mtime: daysAgo(12), totalSize:  78_000_000_000, descendantFileCount: 8_230),
        DirRow(id: 3, parentId: nil, name: "System",      depth: 0, isHidden: false, isPackage: false,
               mtime: daysAgo(28), totalSize:  42_000_000_000, descendantFileCount: 92_410),
        DirRow(id: 4, parentId: nil, name: "Library",     depth: 0, isHidden: false, isPackage: false,
               mtime: daysAgo(4),  totalSize:  36_000_000_000, descendantFileCount: 220_411),
        DirRow(id: 5, parentId: nil, name: "opt",         depth: 0, isHidden: false, isPackage: false,
               mtime: daysAgo(18), totalSize:  24_000_000_000, descendantFileCount: 18_230),
        DirRow(id: 6, parentId: nil, name: "private",     depth: 0, isHidden: false, isPackage: false,
               mtime: daysAgo(30), totalSize:  12_000_000_000, descendantFileCount: 6_320),
        DirRow(id: 7, parentId: nil, name: "Volumes",     depth: 0, isHidden: false, isPackage: false,
               mtime: daysAgo(1),  totalSize:   8_000_000_000, descendantFileCount: 320),
    ]

    // MARK: - Groups (GROUPS)
    static let groups: [GroupRow] = [
        GroupRow(name: "node_modules",            tagline: "JavaScript dependencies",
                 count: 18,  total: 41_200_000_000, avgAgeDays: 240, devOnly: true),
        GroupRow(name: ".venv",                   tagline: "Python virtual environments",
                 count: 12,  total:  8_600_000_000, avgAgeDays: 180, devOnly: true),
        GroupRow(name: "DerivedData",             tagline: "Xcode build cache",
                 count:  6,  total: 14_800_000_000, avgAgeDays:  22, devOnly: true),
        GroupRow(name: "__pycache__",             tagline: "Python compiled cache",
                 count: 220, total:  1_400_000_000, avgAgeDays:  90, devOnly: true),
        GroupRow(name: "Caches",                  tagline: "App caches (Safari, Slack, …)",
                 count: 34,  total: 12_100_000_000, avgAgeDays:   3, devOnly: false),
    ]

    // MARK: - File type totals (FILE_TYPES)
    static let fileTypes: [FileTypeTotal] = [
        FileTypeTotal(type: .video,     totalSize: 168_000_000_000, fileCount:   1_320),
        FileTypeTotal(type: .photos,    totalSize: 112_000_000_000, fileCount:  28_410),
        FileTypeTotal(type: .code,      totalSize:  96_000_000_000, fileCount: 920_411),
        FileTypeTotal(type: .apps,      totalSize:  78_000_000_000, fileCount:     412),
        FileTypeTotal(type: .documents, totalSize:  28_000_000_000, fileCount:   8_210),
        FileTypeTotal(type: .music,     totalSize:  22_000_000_000, fileCount:   4_120),
        FileTypeTotal(type: .archives,  totalSize:  18_000_000_000, fileCount:     220),
        FileTypeTotal(type: .other,     totalSize:  90_000_000_000, fileCount:  84_210),
    ]

    // MARK: - Suggestions (SUGGESTIONS)
    static let suggestions: [Suggestion] = [
        Suggestion(id: "trash",     title: "Empty Trash",
                   detail: "412 items · last emptied 9 days ago",
                   saveBytes:  6_000_000_000, kind: .safe,
                   action: .allDir(name: ".Trash")),
        Suggestion(id: "stale-nm", title: "Clear 14 stale node_modules",
                   detail: "Projects not touched in 6+ months",
                   saveBytes: 24_000_000_000, kind: .safe,
                   action: .staleDir(name: "node_modules", staleDays: 180)),
        Suggestion(id: "old-dl",    title: "Old downloads (88 files)",
                   detail: "Installer .dmg, .zip > 6mo old",
                   saveBytes:  4_800_000_000, kind: .safe,
                   action: .oldDownloads(staleDays: 180)),
        Suggestion(id: "dup-photos",title: "Duplicate photos",
                   detail: "412 near-identical shots",
                   saveBytes:  7_200_000_000, kind: .review,
                   action: .review),
        Suggestion(id: "xcode-dd",  title: "Xcode DerivedData",
                   detail: "Safe to delete — Xcode rebuilds on demand",
                   saveBytes: 14_800_000_000, kind: .safe,
                   action: .allDir(name: "DerivedData")),
    ]

    // MARK: - Live scan paths (SCAN_PATHS)
    static let scanPaths = [
        "~/Library/Application Support/Slack/Cache",
        "~/Developer/dashboard-v2/node_modules/@types",
        "~/Library/Caches/com.apple.Safari",
        "~/Movies/family-2023.mov",
        "~/Photos Library.photoslibrary/originals",
        "~/Developer/api-server/.git/objects",
        "~/Downloads/Xcode_15.2.xip",
    ]

    private static func daysAgo(_ d: Int) -> Date {
        Date().addingTimeInterval(-Double(d) * 86_400)
    }
}
