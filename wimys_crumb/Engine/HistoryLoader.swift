// HistoryLoader.swift
// Reads scan summaries from every completed .sqlite file under the
// scans/ directory + diffs the two most recent for growers/shrinkers.
//
// Each scan lives in its own database file, so we open them one at a
// time, pull the small scan-row + (for the two newest) the top-folder
// snapshot. Costs scale with file count, not file size — opening a 30 MB
// DB to read one row is fast.
//
// All work runs off the main actor (called from a detached Task in
// AppModel.loadHistory).

import Foundation

enum HistoryLoader {

    /// All completed scans, newest first.
    static func loadSummaries(from store: ScanStore) -> [HistorySummary] {
        store.listCompleted().compactMap { url in
            guard let db = try? ScanDatabase(url: url) else { return nil }
            guard let summary = try? db.latestCompletedScan() else { return nil }
            return HistorySummary(
                dbURL: url,
                volumeUUID: summary.volumeUUID,
                volumeName: summary.volumeName,
                startedAt: summary.startedAt,
                completedAt: summary.completedAt,
                totalUsed: summary.totalUsed ?? 0,
                totalFree: summary.totalFree,
                fileCount: summary.fileCount
            )
        }
    }

    /// Diff top folders between the two most recent scans. Returns
    /// growers + shrinkers ordered by absolute delta desc. Empty when
    /// fewer than two scans exist or either lacks a top-folder snapshot.
    static func computeDeltas(summaries: [HistorySummary]) -> [TopFolderDelta] {
        guard summaries.count >= 2 else { return [] }
        let newer = summaries[0]
        let older = summaries[1]
        return diffSnapshots(
            newerURL: newer.dbURL,
            olderURL: older.dbURL
        )
    }

    private static func diffSnapshots(newerURL: URL, olderURL: URL) -> [TopFolderDelta] {
        guard
            let newerDB = try? ScanDatabase(url: newerURL),
            let olderDB = try? ScanDatabase(url: olderURL),
            let newerScan = try? newerDB.latestCompletedScan(),
            let olderScan = try? olderDB.latestCompletedScan(),
            let newerRows = try? newerDB.readTopFolderSnapshots(scanId: newerScan.id),
            let olderRows = try? olderDB.readTopFolderSnapshots(scanId: olderScan.id)
        else { return [] }

        let olderMap = Dictionary(uniqueKeysWithValues:
            olderRows.map { ($0.path, $0.totalSize) })
        let newerMap = Dictionary(uniqueKeysWithValues:
            newerRows.map { ($0.path, $0.totalSize) })

        // Union of paths from both sides. Missing on one side counts as 0.
        let paths = Set(olderMap.keys).union(newerMap.keys)
        let deltas: [TopFolderDelta] = paths.map { path in
            TopFolderDelta(
                path: path,
                previousSize: olderMap[path] ?? 0,
                currentSize: newerMap[path] ?? 0
            )
        }
        return deltas
            .filter { $0.delta != 0 }
            .sorted { abs($0.delta) > abs($1.delta) }
    }
}
