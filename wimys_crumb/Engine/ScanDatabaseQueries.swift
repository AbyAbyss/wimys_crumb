// ScanDatabaseQueries.swift
// Query + write helpers for ScanDatabase. Kept separate from the schema/init
// file so the migration code stays small and the surface area for the engine
// and UI is easy to find.

import Foundation
import GRDB

extension ScanDatabase {

    // MARK: - scans table

    /// Insert a row for an in-progress scan. Returns its assigned id.
    func startScanRow(volumeUUID: String, volumeName: String, startedAt: Date) throws -> Int64 {
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO scans (volume_uuid, volume_name, started_at)
                VALUES (?, ?, ?);
                """,
                arguments: [volumeUUID, volumeName, Int(startedAt.timeIntervalSince1970)]
            )
            return db.lastInsertedRowID
        }
    }

    /// Mark a scan completed. `totalUsed` and `totalFree` come from the volume's
    /// reported capacity (not summed from `dirs`, per plan §17 — APFS).
    func completeScanRow(id: Int64,
                         completedAt: Date,
                         totalUsed: Int64?,
                         totalFree: Int64?,
                         dirCount: Int64,
                         fileCount: Int64,
                         skippedCount: Int64) throws {
        try pool.write { db in
            try db.execute(sql: """
                UPDATE scans
                   SET completed_at = ?, total_used = ?, total_free = ?,
                       dir_count = ?, file_count = ?, skipped_count = ?
                 WHERE id = ?;
                """,
                arguments: [Int(completedAt.timeIntervalSince1970),
                            totalUsed, totalFree,
                            dirCount, fileCount, skippedCount, id]
            )
        }
    }

    /// Latest completed scan row (for the Start screen's recent-scans list).
    func latestCompletedScan() throws -> ScanRowSummary? {
        try pool.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT id, volume_uuid, volume_name, started_at, completed_at,
                       total_used, total_free, file_count
                FROM scans
                WHERE completed_at IS NOT NULL
                ORDER BY started_at DESC
                LIMIT 1;
                """)
            return row.map(ScanRowSummary.init(row:))
        }
    }

    // MARK: - dirs table

    /// Root dir id for the volume (the dir we created with parent_id = NULL at depth 0).
    func rootDirId() throws -> Int64? {
        try pool.read { db in
            try Int64.fetchOne(db, sql: """
                SELECT id FROM dirs WHERE parent_id IS NULL ORDER BY id ASC LIMIT 1;
                """)
        }
    }

    /// Children of `dirId` ordered by size (used by Overview treemap top-level
    /// and by drill-down).
    func children(of dirId: Int64, limit: Int? = nil) throws -> [DirRow] {
        try pool.read { db in
            var sql = """
                SELECT id, parent_id, name, depth, is_hidden, is_package,
                       mtime, total_size, descendant_file_count
                FROM dirs
                WHERE parent_id = ?
                ORDER BY total_size DESC
                """
            if let limit { sql += " LIMIT \(limit)" }
            return try Row.fetchAll(db, sql: sql, arguments: [dirId]).map(DirRow.init(row:))
        }
    }

    /// Direct lookup for the detail panel and breadcrumb.
    func dirNameAndParent(id: Int64) throws -> (name: String, parentId: Int64?)? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT name, parent_id FROM dirs WHERE id = ?;
                """, arguments: [id]) else { return nil }
            let name: String = row["name"]
            let parent: Int64? = row["parent_id"]
            return (name, parent)
        }
    }

    /// Biggest folders seen so far, for the Scanning screen's "biggest so far" list.
    /// During the scan, total_size hasn't been aggregated yet, so we sort by own_size.
    /// After aggregation, this method is also called by Overview for the same shape.
    func biggestSoFar(limit: Int = 6) throws -> [DirRow] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, parent_id, name, depth, is_hidden, is_package, mtime,
                       CASE WHEN total_size > 0 THEN total_size ELSE own_size END AS total_size,
                       descendant_file_count
                FROM dirs
                WHERE depth > 0
                ORDER BY 8 DESC
                LIMIT ?;
                """, arguments: [limit]).map(DirRow.init(row:))
        }
    }

    /// File type totals for Overview's by-file-type list and the Types screen.
    func fileTypeTotals() throws -> [FileTypeTotal] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT file_type, total_size, file_count
                FROM file_type_totals
                ORDER BY total_size DESC;
                """).compactMap { row in
                    guard let cat = FileTypeCategory(rawValue: row["file_type"]) else { return nil }
                    return FileTypeTotal(type: cat,
                                         totalSize: row["total_size"],
                                         fileCount: row["file_count"])
                }
        }
    }

    /// dir + file counts, used by Aggregator to fill scans.dir_count/file_count.
    func dirAndFileCounts() throws -> (dirs: Int64, files: Int64) {
        try pool.read { db in
            let dirs: Int64 = try Int64.fetchOne(db, sql:
                "SELECT COUNT(*) FROM dirs") ?? 0
            // file_count comes from the root's descendant_file_count once aggregated.
            let files: Int64 = try Int64.fetchOne(db, sql:
                "SELECT COALESCE(SUM(file_count), 0) FROM dirs") ?? 0
            return (dirs, files)
        }
    }

    // MARK: - Groups (folders bucketed by exact name across the disk)

    /// Aggregated totals per known group name. The LEFT JOIN on parent's
    /// name filters out the most common nested case (node_modules inside
    /// node_modules) so the totals don't double-count the same bytes.
    /// Deeper nesting (>1 level) is rare enough that we accept the tiny
    /// over-count rather than recursing in SQL.
    func groupAggregates(names: Set<String>) throws -> [(name: String, count: Int, total: Int64, avgAgeDays: Double)] {
        guard !names.isEmpty else { return [] }
        // Materialize once so the two IN clauses bind the exact same order.
        let nameArray = Array(names)
        let placeholders = Array(repeating: "?", count: nameArray.count).joined(separator: ",")
        let args = nameArray + nameArray
        let sql = """
            SELECT d.name,
                   COUNT(*) AS group_count,
                   SUM(d.total_size) AS group_total,
                   AVG(CASE WHEN d.mtime IS NULL THEN NULL
                            ELSE (CAST(strftime('%s','now') AS REAL) - d.mtime) / 86400.0 END)
                       AS avg_age_days
              FROM dirs d
              LEFT JOIN dirs p ON p.id = d.parent_id
             WHERE d.name IN (\(placeholders))
               AND (p.name IS NULL OR p.name NOT IN (\(placeholders)))
             GROUP BY d.name
             ORDER BY group_total DESC;
            """
        return try pool.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
                (
                    name: row["name"] as String,
                    count: row["group_count"] as Int,
                    total: row["group_total"] as Int64,
                    avgAgeDays: (row["avg_age_days"] as Double?) ?? 0
                )
            }
        }
    }

    /// All directories of the given `name` (filtered to non-nested matches
    /// per the same rule as groupAggregates). Sorted by size desc so the
    /// instance list reads top-heavy.
    func groupInstances(name: String, namesForExclusion: Set<String>) throws -> [DirRow] {
        let exclList = Array(namesForExclusion)
        let exclPlaceholders = Array(repeating: "?", count: exclList.count)
            .joined(separator: ",")
        let exclClause = exclList.isEmpty
            ? ""
            : "AND (p.name IS NULL OR p.name NOT IN (\(exclPlaceholders)))"
        // All bound values are Strings — keep the array homogeneous so
        // Swift's array-literal inference picks up DatabaseValueConvertible
        // via String's conformance without needing an explicit type.
        let args: [String] = [name] + exclList
        let sql = """
            SELECT d.id, d.parent_id, d.name, d.depth, d.is_hidden, d.is_package,
                   d.mtime, d.total_size, d.descendant_file_count
              FROM dirs d
              LEFT JOIN dirs p ON p.id = d.parent_id
             WHERE d.name = ?
               \(exclClause)
             ORDER BY d.total_size DESC;
            """
        return try pool.read { db in
            try Row.fetchAll(db, sql: sql,
                             arguments: StatementArguments(args))
                .map(DirRow.init(row:))
        }
    }

    // MARK: - Delete patch (plan §12.2)

    /// Surgically remove the rows for deleted dirs and files, then patch
    /// ancestor aggregates and file_type_totals so the next re-query
    /// returns accurate numbers without a full rescan.
    ///
    /// All operations run inside a single write transaction. If anything
    /// throws, the DB rolls back to its pre-patch state.
    func patchAfterDelete(
        dirIds: [Int64],
        files: [(dirId: Int64, name: String)]
    ) throws {
        try pool.write { db in
            // ---- Directory subtrees ----
            for dirId in dirIds {
                // Capture the dir's recursive totals BEFORE deletion so we
                // can subtract from its ancestors.
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT total_size, descendant_file_count
                      FROM dirs WHERE id = ?;
                    """, arguments: [dirId]) else { continue }
                let subtreeSize: Int64 = row["total_size"]
                let subtreeCount: Int64 = row["descendant_file_count"]

                // Subtract from every ancestor (exclusive of the dir itself
                // since that's about to be deleted).
                try Self.walkAncestors(of: dirId, db: db) { ancestorId in
                    try db.execute(sql: """
                        UPDATE dirs
                           SET total_size            = MAX(0, total_size - ?),
                               descendant_file_count = MAX(0, descendant_file_count - ?)
                         WHERE id = ?;
                        """, arguments: [subtreeSize, subtreeCount, ancestorId])
                }

                // The subtree can be tens of thousands of rows (Rust
                // `target/` is the canonical case). Materializing the
                // id list and binding it via `IN (?, ?, …)` blows past
                // SQLITE_MAX_VARIABLE_NUMBER (default ~32K) and the whole
                // transaction rolls back silently. Use the recursive CTE
                // INSIDE each statement instead — one bound parameter
                // (the root dir id) regardless of subtree size.

                // 1. file_type_totals delta — aggregate large_files within
                //    the subtree by category, then subtract per category.
                let typeRows = try Row.fetchAll(db, sql: """
                    WITH RECURSIVE subtree(id) AS (
                      SELECT ?
                      UNION ALL
                      SELECT d.id FROM dirs d JOIN subtree s ON d.parent_id = s.id
                    )
                    SELECT file_type,
                           COUNT(*) AS c,
                           COALESCE(SUM(size), 0) AS s
                      FROM large_files
                     WHERE dir_id IN (SELECT id FROM subtree)
                     GROUP BY file_type;
                    """, arguments: [dirId])
                for row in typeRows {
                    let type: Int = row["file_type"]
                    let cnt: Int64 = row["c"]
                    let sz: Int64 = row["s"]
                    try db.execute(sql: """
                        UPDATE file_type_totals
                           SET total_size = MAX(0, total_size - ?),
                               file_count = MAX(0, file_count - ?)
                         WHERE file_type = ?;
                        """, arguments: [sz, cnt, type])
                }

                // 2. Delete large_files for the subtree.
                try db.execute(sql: """
                    WITH RECURSIVE subtree(id) AS (
                      SELECT ?
                      UNION ALL
                      SELECT d.id FROM dirs d JOIN subtree s ON d.parent_id = s.id
                    )
                    DELETE FROM large_files
                     WHERE dir_id IN (SELECT id FROM subtree);
                    """, arguments: [dirId])

                // 3. Delete dirs for the subtree.
                try db.execute(sql: """
                    WITH RECURSIVE subtree(id) AS (
                      SELECT ?
                      UNION ALL
                      SELECT d.id FROM dirs d JOIN subtree s ON d.parent_id = s.id
                    )
                    DELETE FROM dirs
                     WHERE id IN (SELECT id FROM subtree);
                    """, arguments: [dirId])
            }

            // ---- Individual files ----
            for f in files {
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT size, file_type FROM large_files
                     WHERE dir_id = ? AND name = ?;
                    """, arguments: [f.dirId, f.name]) else { continue }
                let size: Int64 = row["size"]
                let type: Int = row["file_type"]

                // file_type_totals
                try db.execute(sql: """
                    UPDATE file_type_totals
                       SET total_size = MAX(0, total_size - ?),
                           file_count = MAX(0, file_count - 1)
                     WHERE file_type = ?;
                    """, arguments: [size, type])

                // Parent dir + every ancestor (inclusive of the parent dir).
                try Self.walkAncestors(of: f.dirId, db: db, inclusive: true) { id in
                    try db.execute(sql: """
                        UPDATE dirs
                           SET total_size            = MAX(0, total_size - ?),
                               descendant_file_count = MAX(0, descendant_file_count - 1)
                         WHERE id = ?;
                        """, arguments: [size, id])
                }

                try db.execute(sql:
                    "DELETE FROM large_files WHERE dir_id = ? AND name = ?;",
                    arguments: [f.dirId, f.name])
            }
        }
    }

    /// Walk the parent chain of `startId`. With `inclusive = true`, the
    /// callback also fires for `startId` itself; otherwise it starts at
    /// startId's parent.
    private static func walkAncestors(
        of startId: Int64,
        db: Database,
        inclusive: Bool = false,
        body: (Int64) throws -> Void
    ) throws {
        var current: Int64?
        if inclusive {
            current = startId
        } else {
            current = try Int64.fetchOne(db, sql:
                "SELECT parent_id FROM dirs WHERE id = ?;",
                arguments: [startId])
        }
        var safety = 0
        while let id = current {
            try body(id)
            safety += 1
            if safety > 4096 { break }   // pathological tree guard
            current = try Int64.fetchOne(db, sql:
                "SELECT parent_id FROM dirs WHERE id = ?;",
                arguments: [id])
        }
    }

    // MARK: - Suggestion target resolution

    /// All dirs with the given name. Optionally restrict to dirs older
    /// than `staleDays` (mtime in seconds-since-epoch). Used by
    /// AppModel.openSuggestion to materialize delete targets.
    func dirsByName(_ name: String, staleDays: Int? = nil) throws -> [DirRow] {
        try pool.read { db in
            if let days = staleDays {
                return try Row.fetchAll(db, sql: """
                    SELECT id, parent_id, name, depth, is_hidden, is_package,
                           mtime, total_size, descendant_file_count
                      FROM dirs
                     WHERE name = ?
                       AND mtime IS NOT NULL
                       AND (strftime('%s','now') - mtime) >= ? * 86400
                     ORDER BY total_size DESC;
                    """, arguments: [name, days]).map(DirRow.init(row:))
            }
            return try Row.fetchAll(db, sql: """
                SELECT id, parent_id, name, depth, is_hidden, is_package,
                       mtime, total_size, descendant_file_count
                  FROM dirs
                 WHERE name = ?
                 ORDER BY total_size DESC;
                """, arguments: [name]).map(DirRow.init(row:))
        }
    }

    /// Large files inside any "Downloads" directory whose mtime is
    /// older than `staleDays`. Joined for the dir id so the caller can
    /// resolve to a full file path via PathResolver.
    func oldDownloadFiles(staleDays: Int) throws -> [LargeFileRow] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT f.id, f.dir_id, f.name, f.size, f.mtime, f.ext, f.file_type
                  FROM large_files f
                  JOIN dirs d ON d.id = f.dir_id
                 WHERE d.name = 'Downloads'
                   AND f.mtime IS NOT NULL
                   AND (strftime('%s','now') - f.mtime) >= ? * 86400
                 ORDER BY f.size DESC;
                """, arguments: [staleDays]).map(LargeFileRow.init(row:))
        }
    }

    // MARK: - Large files (Types screen detail panel)

    /// Top-N largest files for a single category, ordered by size desc.
    /// The engine populates `large_files` during the walk with one row
    /// per file kept in any directory's top-N list (see plan §9).
    func largeFiles(byType type: FileTypeCategory, limit: Int = 30) throws -> [LargeFileRow] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, dir_id, name, size, mtime, ext, file_type
                  FROM large_files
                 WHERE file_type = ?
                 ORDER BY size DESC
                 LIMIT ?;
                """, arguments: [type.rawValue, limit])
                .map(LargeFileRow.init(row:))
        }
    }

    // MARK: - Top folders snapshot (History diffs)

    /// Read back the snapshot rows for any scan_id in this DB. Used by
    /// HistoryLoader to diff the two most recent scans for the
    /// growers/shrinkers panel.
    func readTopFolderSnapshots(scanId: Int64) throws -> [(path: String, totalSize: Int64)] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT path, total_size
                  FROM snapshot_top_folders
                 WHERE scan_id = ?;
                """, arguments: [scanId])
                .map { (path: $0["path"], totalSize: $0["total_size"]) }
        }
    }

    func writeTopFolderSnapshots(scanId: Int64, rows: [(path: String, totalSize: Int64)]) throws {
        // pool.write already wraps in a transaction; don't nest.
        try pool.write { db in
            for r in rows {
                try db.execute(sql: """
                    INSERT INTO snapshot_top_folders (scan_id, path, total_size)
                    VALUES (?, ?, ?);
                    """, arguments: [scanId, r.path, r.totalSize])
            }
        }
    }
}

// MARK: - Row → model

struct ScanRowSummary {
    let id: Int64
    let volumeUUID: String
    let volumeName: String
    let startedAt: Date
    let completedAt: Date?
    let totalUsed: Int64?
    let totalFree: Int64?
    let fileCount: Int64?

    init(row: Row) {
        self.id = row["id"]
        self.volumeUUID = row["volume_uuid"]
        self.volumeName = row["volume_name"]
        self.startedAt = Date(timeIntervalSince1970: TimeInterval(row["started_at"] as Int))
        if let c = row["completed_at"] as Int? {
            self.completedAt = Date(timeIntervalSince1970: TimeInterval(c))
        } else {
            self.completedAt = nil
        }
        self.totalUsed = row["total_used"]
        self.totalFree = row["total_free"]
        self.fileCount = row["file_count"]
    }
}

extension LargeFileRow {
    init(row: Row) {
        self.id = row["id"]
        self.dirId = row["dir_id"]
        self.name = row["name"]
        self.size = row["size"]
        if let m = row["mtime"] as Int? {
            self.mtime = Date(timeIntervalSince1970: TimeInterval(m))
        } else {
            self.mtime = nil
        }
        self.ext = row["ext"] as String?
        let rawType: Int = row["file_type"]
        self.type = FileTypeCategory(rawValue: rawType) ?? .other
    }
}

extension DirRow {
    init(row: Row) {
        self.id = row["id"]
        self.parentId = row["parent_id"]
        self.name = row["name"]
        self.depth = row["depth"]
        self.isHidden = (row["is_hidden"] as Int) != 0
        self.isPackage = (row["is_package"] as Int) != 0
        if let m = row["mtime"] as Int? {
            self.mtime = Date(timeIntervalSince1970: TimeInterval(m))
        } else {
            self.mtime = nil
        }
        self.totalSize = row["total_size"]
        self.descendantFileCount = row["descendant_file_count"]
    }
}
