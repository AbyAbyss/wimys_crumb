// Suggestions.swift
// Rule-based "quick wins" pass over the scan database. Plan §13.
//
// Each rule is a small query that surfaces a one-line suggestion if it finds
// enough material to be worth showing. `safe` items can be deleted without
// review; `review` items need user judgement (e.g. duplicate-photo dedup —
// omitted in v1 per the plan).

import Foundation
import GRDB

enum Suggestions {

    /// Generate the quick-wins list for the current scan database.
    static func generate(db: ScanDatabase) -> [Suggestion] {
        var out: [Suggestion] = []

        // 1. Stale node_modules — dev dirs not touched in 180+ days.
        if let row = try? staleGroup(db: db, name: "node_modules", staleDays: 180) {
            if row.count > 0 && row.total > 0 {
                out.append(Suggestion(
                    id: "stale-node_modules",
                    title: "Clear \(row.count) stale node_modules",
                    detail: "JavaScript dependencies not touched in 6+ months",
                    saveBytes: row.total,
                    kind: .safe,
                    action: .staleDir(name: "node_modules", staleDays: 180)
                ))
            }
        }

        // 2. Xcode DerivedData — always safe to nuke (Xcode rebuilds on demand).
        if let row = try? group(db: db, name: "DerivedData"), row.total > 0 {
            out.append(Suggestion(
                id: "derived-data",
                title: "Xcode DerivedData",
                detail: "Safe to delete — Xcode rebuilds on demand",
                saveBytes: row.total,
                kind: .safe,
                action: .allDir(name: "DerivedData")
            ))
        }

        // 3. Large Caches directories.
        if let row = try? group(db: db, name: "Caches"), row.total >= 1_000_000_000 {
            out.append(Suggestion(
                id: "app-caches",
                title: "Clear app caches",
                detail: "\(row.count) Caches folders · apps rebuild them",
                saveBytes: row.total,
                kind: .safe,
                action: .allDir(name: "Caches")
            ))
        }

        // 4. __pycache__ dirs.
        if let row = try? group(db: db, name: "__pycache__"), row.total >= 100_000_000 {
            out.append(Suggestion(
                id: "pycache",
                title: "Remove __pycache__ directories",
                detail: "Python rebuilds these on the next run",
                saveBytes: row.total,
                kind: .safe,
                action: .allDir(name: "__pycache__")
            ))
        }

        // 5. .venv directories (Python virtual environments).
        if let row = try? staleGroup(db: db, name: ".venv", staleDays: 180), row.total > 0 {
            out.append(Suggestion(
                id: "stale-venv",
                title: "Clear \(row.count) stale .venv",
                detail: "Python venvs not touched in 6+ months",
                saveBytes: row.total,
                kind: .safe,
                action: .staleDir(name: ".venv", staleDays: 180)
            ))
        }

        // 6. Old large files in Downloads. We can find Downloads by name match
        // against `dirs` and the heaviest files under it via large_files.
        if let saved = try? oldDownloads(db: db), saved.total > 0 {
            out.append(Suggestion(
                id: "old-downloads",
                title: "Old downloads (\(saved.count) files)",
                detail: "Installers and archives > 6 months old",
                saveBytes: saved.total,
                kind: .safe,
                action: .oldDownloads(staleDays: 180)
            ))
        }

        return out.sorted { $0.saveBytes > $1.saveBytes }
    }

    // MARK: - Helpers

    private struct GroupTotal { let count: Int64; let total: Int64 }

    /// Total size + count of all dirs with the given name.
    private static func group(db: ScanDatabase, name: String) throws -> GroupTotal? {
        try db.pool.read { conn in
            let row = try Row.fetchOne(conn, sql: """
                SELECT COUNT(*) AS c, COALESCE(SUM(total_size), 0) AS s
                  FROM dirs WHERE name = ?;
                """, arguments: [name])
            guard let row else { return nil }
            return GroupTotal(count: row["c"], total: row["s"])
        }
    }

    /// Same as `group`, but only counts dirs whose mtime is older than `staleDays`.
    private static func staleGroup(db: ScanDatabase, name: String, staleDays: Int) throws -> GroupTotal? {
        try db.pool.read { conn in
            let row = try Row.fetchOne(conn, sql: """
                SELECT COUNT(*) AS c, COALESCE(SUM(total_size), 0) AS s
                  FROM dirs
                 WHERE name = ?
                   AND mtime IS NOT NULL
                   AND (strftime('%s','now') - mtime) >= ? * 86400;
                """, arguments: [name, staleDays])
            guard let row else { return nil }
            return GroupTotal(count: row["c"], total: row["s"])
        }
    }

    /// Big files inside any folder named "Downloads", older than 180 days.
    private static func oldDownloads(db: ScanDatabase) throws -> GroupTotal? {
        try db.pool.read { conn in
            let row = try Row.fetchOne(conn, sql: """
                SELECT COUNT(*) AS c, COALESCE(SUM(f.size), 0) AS s
                  FROM large_files f
                  JOIN dirs d ON d.id = f.dir_id
                 WHERE d.name = 'Downloads'
                   AND f.mtime IS NOT NULL
                   AND (strftime('%s','now') - f.mtime) >= 180 * 86400;
                """)
            guard let row else { return nil }
            return GroupTotal(count: row["c"], total: row["s"])
        }
    }
}
