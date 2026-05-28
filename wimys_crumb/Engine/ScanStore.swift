// ScanStore.swift
// Manages the directory of per-scan SQLite databases.
// Location: ~/Library/Application Support/wimys_crumb/scans/
// Naming:   {volume_uuid}-{started_at}.sqlite (completed)
//           in-progress-{started_at}.sqlite   (active)
//
// Phase 1: directory bootstrap + listing of completed scans for the Start
// screen's "Last scans" panel. Retention, vacuum, and the in-progress rename
// flow come online with the scan engine in Phase 2.

import Foundation

struct ScanStore {

    let root: URL

    init() {
        // Application Support is in the user's domain; safe in non-sandboxed too.
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        self.root = appSupport
            .appendingPathComponent("wimys_crumb", isDirectory: true)
            .appendingPathComponent("scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: root,
                                                 withIntermediateDirectories: true)
    }

    /// Path for a new in-progress scan database. Rename to the final name on
    /// completion (Phase 2).
    func inProgressURL(startedAt: Date) -> URL {
        root.appendingPathComponent("in-progress-\(Int(startedAt.timeIntervalSince1970)).sqlite")
    }

    /// Path for a completed scan.
    func completedURL(volumeUUID: String, startedAt: Date) -> URL {
        root.appendingPathComponent("\(volumeUUID)-\(Int(startedAt.timeIntervalSince1970)).sqlite")
    }

    /// All completed scan database URLs, newest first. For the Start screen's
    /// "Last scans" list. We don't open the DBs here; the volume name is parsed
    /// from a sidecar `scans.volume_name` column lazily by the caller as needed.
    func listCompleted() -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { $0.pathExtension == "sqlite" && !$0.lastPathComponent.hasPrefix("in-progress-") }
            .sorted { lhs, rhs in
                let a = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let b = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return a > b
            }
    }

    /// Delete leftover in-progress files on launch (scans that crashed).
    func pruneOrphans() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root,
                                                       includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent.hasPrefix("in-progress-") {
            try? fm.removeItem(at: url)
            // Also clean up any sidecar SHM/WAL left by a crashed scan.
            try? fm.removeItem(at: url.appendingPathExtension("shm"))
            try? fm.removeItem(at: url.appendingPathExtension("wal"))
        }
    }

    /// Keep at most `maxPerVolume` completed scans per volume UUID. Older
    /// ones are deleted. Sidecar `-shm`/`-wal` files go with them. The
    /// latest scan per volume is always preserved regardless of cap.
    /// Plan §12.4 retention.
    func pruneOldScans(maxPerVolume: Int = 10) {
        let fm = FileManager.default
        let urls = listCompleted()                  // newest first
        var byVolume: [String: [URL]] = [:]
        for u in urls {
            // Filename is "{volumeUUID}-{startedAt}.sqlite". The last
            // dash separates the UUID from the timestamp.
            let base = u.deletingPathExtension().lastPathComponent
            guard let dash = base.lastIndex(of: "-") else { continue }
            let vol = String(base[..<dash])
            byVolume[vol, default: []].append(u)
        }
        for (_, files) in byVolume where files.count > maxPerVolume {
            for u in files.dropFirst(maxPerVolume) {
                try? fm.removeItem(at: u)
                // Sidecar files use a different scheme — same base + suffix.
                let shm = u.deletingPathExtension()
                    .appendingPathExtension("sqlite-shm")
                let wal = u.deletingPathExtension()
                    .appendingPathExtension("sqlite-wal")
                try? fm.removeItem(at: shm)
                try? fm.removeItem(at: wal)
            }
        }
    }

    /// Run `VACUUM` on each completed scan DB older than `olderThan` seconds.
    /// Vacuum reclaims free pages that accumulate as rows are deleted
    /// (e.g. by patchAfterDelete) and tightens the file on disk.
    /// Costly — call off the main thread.
    func vacuumOldDBs(olderThan: TimeInterval = 30 * 86_400) {
        let cutoff = Date().addingTimeInterval(-olderThan)
        for url in listCompleted() {
            guard let mtime = (try? url.resourceValues(
                forKeys: [.contentModificationDateKey]))?
                .contentModificationDate else { continue }
            guard mtime < cutoff else { continue }
            do {
                let db = try ScanDatabase(url: url)
                try db.pool.write { conn in
                    try conn.execute(sql: "VACUUM;")
                }
            } catch {
                NSLog("vacuum failed for \(url.lastPathComponent): \(error)")
            }
        }
    }
}
