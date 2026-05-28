// Aggregator.swift
// Post-scan SQLite rollup. Once ScanEngine finishes the walk, this fills in:
//   1. total_size + descendant_file_count for every `dirs` row (bottom-up).
//   2. snapshot_top_folders rows for the History diff (top-level dir totals).
//   3. scans.completed_at + count fields.
//
// Plan §10.6. Runs in O(max_depth) SQL queries (~30), each fast given the
// idx_dirs_depth / idx_dirs_parent indexes.

import Foundation
import GRDB

enum Aggregator {

    /// Run bottom-up total_size + descendant_file_count rollups and mark the
    /// scan complete.
    static func finalize(db: ScanDatabase,
                         scanId: Int64,
                         volume: VolumeInfo,
                         maxDepth: Int,
                         dirCount: Int64,
                         fileCount: Int64,
                         skippedCount: Int64) throws {

        // ── 1. Bottom-up total_size + descendant_file_count rollup. ────────
        // For depth = max..0, set each dir's total_size to own_size + sum of
        // children's total_size, and descendant_file_count similarly. By
        // descending from leaves, children are already final when parents update.
        // pool.write already runs the block in a transaction; don't nest one.
        try db.pool.write { conn in
            for d in stride(from: maxDepth, through: 0, by: -1) {
                try conn.execute(sql: """
                    UPDATE dirs SET
                      total_size = own_size + COALESCE(
                        (SELECT SUM(total_size) FROM dirs c WHERE c.parent_id = dirs.id), 0),
                      descendant_file_count = file_count + COALESCE(
                        (SELECT SUM(descendant_file_count) FROM dirs c WHERE c.parent_id = dirs.id), 0)
                    WHERE depth = ?;
                    """, arguments: [d])
            }
        }

        // ── 2. snapshot_top_folders for the History diff. ────────────────
        // Top-level dirs (parent_id = root). We store the dir name as `path`
        // — paths are reconstructed via PathResolver elsewhere, but for
        // snapshots a stable name string is enough for the History diff.
        if let rootId = try db.rootDirId() {
            let tops = try db.children(of: rootId)
            let rows = tops.map { (path: $0.name, totalSize: $0.totalSize) }
            try db.writeTopFolderSnapshots(scanId: scanId, rows: rows)
        }

        // ── 3. Mark scan complete. ───────────────────────────────────────
        try db.completeScanRow(
            id: scanId,
            completedAt: Date(),
            totalUsed: volume.used,
            totalFree: volume.availableCapacity,
            dirCount: dirCount,
            fileCount: fileCount,
            skippedCount: skippedCount
        )
    }
}
