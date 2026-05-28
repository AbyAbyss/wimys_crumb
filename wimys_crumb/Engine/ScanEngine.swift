// ScanEngine.swift
// Streaming filesystem walk → SQLite. Bounded in-memory state per plan §10.
//
// HARD RULE (plan §9): no per-file Swift retention. URLs and per-file metadata
// are read inside the loop and dropped before the next iteration. Anything
// that must survive the scan goes into SQLite (or one of the bounded heaps).
//
// The actor exposes:
//   • start(root:db:volume:) -> (scanId, AsyncThrowingStream<ScanProgress, Error>)
//   • pause() / resume() / cancel()
//   • dirCount / fileCount / skippedCount (final tallies after stream completes)
//
// Cancellation and pause are checked at batch boundaries. The walk and writes
// happen inside one actor-isolated Task; await Task.yield() between yield
// points lets pause/cancel actor calls from AppModel actually land.

import Foundation

/// Files at or above this size are eligible for the per-type top-N heap.
/// Plan §10.3: starting threshold 10MB.
private let LARGE_FILE_THRESHOLD: Int64 = 10_000_000

/// Per-category cap for the top-N heap. 8 categories × 500 ≈ 4000 candidates.
private let TOP_FILES_CAP = 500

/// Flush the in-memory write buffer to SQLite every N rows.
private let WRITE_BATCH = 2000

/// Cap on emitted progress events — at most every ~100ms.
private let PROGRESS_THROTTLE_NS: UInt64 = 100_000_000

/// Yield-and-check-controls cadence inside the hot loop.
private let CONTROL_CHECK_INTERVAL = 256

actor ScanEngine {

    // MARK: - Lightweight value types kept inside the actor

    /// One open directory. Holds rolling aggregates. ~120 bytes per frame.
    /// pathStack rarely exceeds depth ~50 → a few KB.
    private struct StackFrame {
        let id: Int64
        let parentId: Int64?
        let name: String
        let depth: Int
        let mtime: Date?
        let isHidden: Bool
        let isPackage: Bool
        var ownSize: Int64 = 0
        var fileCount: Int64 = 0
        var childDirCount: Int64 = 0
        var perTypeCounts: [Int64] = Array(repeating: 0, count: FileTypeCategory.allCases.count)
    }

    /// One `dirs` row to insert. Final form — pushed only when its frame pops.
    private struct DirRowInsert {
        let id: Int64
        let parentId: Int64?
        let name: String
        let depth: Int
        let mtime: Date?
        let isHidden: Bool
        let isPackage: Bool
        let ownSize: Int64
        let fileCount: Int64
        let childDirCount: Int64
    }

    /// Large-file candidate. Comparable on size for the min-heap. ~80B.
    private struct LargeFileCandidate: Comparable {
        let dirId: Int64
        let name: String
        let size: Int64
        let mtime: Date?
        let ext: String?
        let type: FileTypeCategory

        static func < (a: Self, b: Self) -> Bool { a.size < b.size }
        static func == (a: Self, b: Self) -> Bool { a.size == b.size }
    }

    // MARK: - State

    private(set) var isPaused = false
    private(set) var isCancelled = false

    private(set) var dirCount: Int64 = 0
    private(set) var fileCount: Int64 = 0
    private(set) var skippedCount: Int64 = 0

    /// Running scan id from `scans` table — used by Aggregator post-walk.
    private(set) var scanId: Int64 = 0
    private(set) var rootId: Int64 = 0

    // MARK: - Control

    func pause()  { isPaused = true }
    func resume() { isPaused = false }
    func cancel() { isCancelled = true }

    var maxDepthSeen: Int = 0    // exposed for Aggregator (bottom-up loop bound)

    // MARK: - Entry point

    struct StartResult {
        let scanId: Int64
        let rootId: Int64
        let progress: AsyncThrowingStream<ScanProgress, Error>
    }

    func start(root: URL, db: ScanDatabase, volume: VolumeInfo) throws -> StartResult {
        // Reset state for a new scan (the actor is reusable).
        isPaused = false
        isCancelled = false
        dirCount = 0
        fileCount = 0
        skippedCount = 0
        maxDepthSeen = 0

        let started = Date()
        scanId = try db.startScanRow(volumeUUID: volume.id,
                                     volumeName: volume.name,
                                     startedAt: started)

        let stream = AsyncThrowingStream<ScanProgress, Error> { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await self.runWalk(root: root, db: db, continuation: continuation)
            }
        }
        return StartResult(scanId: scanId, rootId: rootId, progress: stream)
    }

    // MARK: - The walk

    private func runWalk(root: URL,
                         db: ScanDatabase,
                         continuation: AsyncThrowingStream<ScanProgress, Error>.Continuation) async {

        // Buffers (kept actor-local; sent to SQLite at batch boundaries).
        var dirInserts: [DirRowInsert] = []
        dirInserts.reserveCapacity(WRITE_BATCH)
        var topHeaps: [BoundedMinHeap<LargeFileCandidate>] =
            (0..<FileTypeCategory.allCases.count).map { _ in BoundedMinHeap(capacity: TOP_FILES_CAP) }
        var globalTypeTotals: [(size: Int64, count: Int64)] =
            Array(repeating: (0, 0), count: FileTypeCategory.allCases.count)
        var pathStack: [StackFrame] = []
        pathStack.reserveCapacity(64)

        // Monotonic id allocator. Roots come from `dirs.id` autoincrement, but
        // we manage ids explicitly so we don't need INSERT-then-UPDATE round-trips.
        var nextId: Int64 = 1

        // Push the root frame (the enumerator does NOT yield the root URL itself).
        let rootValues = try? root.resourceValues(forKeys: [
            .contentModificationDateKey, .isHiddenKey
        ])
        let rootName: String = root.path == "/" ? "/" : root.lastPathComponent
        let rootFrame = StackFrame(
            id: nextId,
            parentId: nil,
            name: rootName,
            depth: 0,
            mtime: rootValues?.contentModificationDate,
            isHidden: rootValues?.isHidden ?? false,
            isPackage: false
        )
        rootId = nextId
        nextId += 1
        pathStack.append(rootFrame)

        // Resource keys we read per entry. Plan §10.1.
        let resKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isHiddenKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .nameKey,
        ]
        let resKeySet = Set(resKeys)

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: resKeys,
            options: [.skipsPackageDescendants, .producesRelativePathURLs],
            errorHandler: { _, _ in
                // Traversal errors (subdirs we can't enter). We can't bump the
                // actor's skippedCount from this sync closure without an await.
                // The per-entry `try? values` path covers permission failures
                // we DO reach, which is the typical Full-Disk-Access case.
                return true
            }
        ) else {
            continuation.finish(throwing: NSError(domain: "ScanEngine", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not enumerate \(root.path)"]))
            return
        }

        // For depth computation. URL.path gives an absolute path; root is the
        // user-selected scan root. Depth = # of "/" segments below root.
        let rootPath = root.standardizedFileURL.path

        var lastProgressEmit: DispatchTime = .now()
        var processedSinceYield = 0

        // Insert the root row itself when we leave it at the end (single dir flush
        // path keeps things uniform).

        // ── walk ───────────────────────────────────────────────────────────
        loop: while let next = enumerator.nextObject() {
            guard let url = next as? URL else { continue }

            // Resource values. Failures (permissions, dangling links) increment
            // skippedCount and we move on. Don't escape early — keep walking.
            guard let values = try? url.resourceValues(forKeys: resKeySet) else {
                skippedCount += 1
                continue
            }

            // Skip symlinks (cycles / double counting). Plan §10.1.
            if values.isSymbolicLink == true { continue }

            // Depth = path-component delta from root. Using `.path` allocates a
            // String per call but is dropped before the next iteration.
            let entryPath = url.standardizedFileURL.path
            let depth = depthBetween(rootPath: rootPath, entryPath: entryPath)
            if depth < 1 { continue }   // defensive: shouldn't happen

            // Pop frames we've left behind.
            while pathStack.count > depth {
                let popped = pathStack.removeLast()
                dirInserts.append(DirRowInsert(
                    id: popped.id, parentId: popped.parentId, name: popped.name,
                    depth: popped.depth, mtime: popped.mtime,
                    isHidden: popped.isHidden, isPackage: popped.isPackage,
                    ownSize: popped.ownSize, fileCount: popped.fileCount,
                    childDirCount: popped.childDirCount
                ))
                if dirInserts.count >= WRITE_BATCH {
                    try? flushDirs(&dirInserts, db: db)
                }
            }

            let isDir = values.isDirectory ?? false

            if isDir {
                // Push a new frame. Parent is current top.
                let parent = pathStack.last
                let name = values.name ?? url.lastPathComponent
                let frame = StackFrame(
                    id: nextId,
                    parentId: parent?.id,
                    name: name,
                    depth: depth,
                    mtime: values.contentModificationDate,
                    isHidden: values.isHidden ?? false,
                    isPackage: values.isPackage ?? false
                )
                nextId += 1
                pathStack.append(frame)
                // Bump parent's childDirCount.
                if pathStack.count >= 2 {
                    pathStack[pathStack.count - 2].childDirCount += 1
                }
                dirCount += 1
                if depth > maxDepthSeen { maxDepthSeen = depth }
            } else {
                // File. Update top-of-stack counters; consider for large_files.
                guard pathStack.indices.contains(depth - 1) else {
                    skippedCount += 1
                    continue
                }
                let size = Int64(values.totalFileAllocatedSize ?? 0)
                let name = values.name ?? url.lastPathComponent
                let ext = (name as NSString).pathExtension.lowercased()
                let category = FileTypeClassifier.category(forExtension: ext.isEmpty ? nil : ext)
                let catIdx = category.rawValue

                pathStack[depth - 1].ownSize += size
                pathStack[depth - 1].fileCount += 1
                pathStack[depth - 1].perTypeCounts[catIdx] += 1

                globalTypeTotals[catIdx].size += size
                globalTypeTotals[catIdx].count += 1

                if size >= LARGE_FILE_THRESHOLD {
                    let candidate = LargeFileCandidate(
                        dirId: pathStack[depth - 1].id,
                        name: name,
                        size: size,
                        mtime: values.contentModificationDate,
                        ext: ext.isEmpty ? nil : ext,
                        type: category
                    )
                    topHeaps[catIdx].consider(candidate)
                }

                fileCount += 1
            }

            processedSinceYield += 1
            if processedSinceYield >= CONTROL_CHECK_INTERVAL {
                processedSinceYield = 0
                await Task.yield()
                if isCancelled { break loop }
                // Honor pause without busy-spinning.
                while isPaused && !isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                if isCancelled { break loop }

                // Throttled progress emission.
                let now = DispatchTime.now()
                if now.uptimeNanoseconds - lastProgressEmit.uptimeNanoseconds >= PROGRESS_THROTTLE_NS {
                    lastProgressEmit = now
                    let currentPath = pathStack.dropFirst().map(\.name).joined(separator: "/")
                    let displayPath = currentPath.isEmpty ? rootPath : ("/" + currentPath)
                    // Indeterminate progress (we don't know total files up-front).
                    // Use a sigmoid-ish approximation off filesScanned; the
                    // Scanning UI also shows a raw file count so this is fine.
                    let approx = approximateFraction(filesScanned: fileCount)
                    continuation.yield(ScanProgress(
                        fraction: approx,
                        filesScanned: fileCount,
                        currentPath: displayPath,
                        etaSeconds: nil
                    ))
                }
            }
        }

        // ── End of walk ──────────────────────────────────────────────────
        // On cancellation: drop buffers, don't flush, don't aggregate (plan §10.7).
        if isCancelled {
            dirInserts.removeAll(keepingCapacity: false)
            continuation.finish()
            return
        }

        // Pop remaining frames (children-first → parents).
        while !pathStack.isEmpty {
            let popped = pathStack.removeLast()
            dirInserts.append(DirRowInsert(
                id: popped.id, parentId: popped.parentId, name: popped.name,
                depth: popped.depth, mtime: popped.mtime,
                isHidden: popped.isHidden, isPackage: popped.isPackage,
                ownSize: popped.ownSize, fileCount: popped.fileCount,
                childDirCount: popped.childDirCount
            ))
        }
        // Final flushes.
        do {
            try flushDirs(&dirInserts, db: db)
            try flushLargeFiles(topHeaps, db: db)
            try flushTypeTotals(globalTypeTotals, db: db)
        } catch {
            continuation.finish(throwing: error)
            return
        }

        // Final progress event at 1.0.
        continuation.yield(ScanProgress(
            fraction: 1.0,
            filesScanned: fileCount,
            currentPath: "Done",
            etaSeconds: 0
        ))
        continuation.finish()
    }

    // MARK: - Flush helpers (single writer; one transaction per batch)

    // `db.pool.write { ... }` already wraps the block in a transaction
    // (committed on success, rolled back on throw). Don't add a nested
    // `inTransaction` inside — SQLite rejects nested transactions.

    private func flushDirs(_ buffer: inout [DirRowInsert], db: ScanDatabase) throws {
        guard !buffer.isEmpty else { return }
        let rows = buffer
        buffer.removeAll(keepingCapacity: true)
        try db.pool.write { conn in
            for r in rows {
                try conn.execute(sql: """
                    INSERT INTO dirs
                      (id, parent_id, name, depth, is_hidden, is_package, mtime,
                       own_size, file_count, child_dir_count,
                       total_size, descendant_file_count)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0);
                    """,
                    arguments: [
                        r.id, r.parentId, r.name, r.depth,
                        r.isHidden ? 1 : 0, r.isPackage ? 1 : 0,
                        r.mtime.map { Int($0.timeIntervalSince1970) },
                        r.ownSize, r.fileCount, r.childDirCount
                    ]
                )
            }
        }
    }

    private func flushLargeFiles(_ heaps: [BoundedMinHeap<LargeFileCandidate>],
                                 db: ScanDatabase) throws {
        var rows: [LargeFileCandidate] = []
        for h in heaps { rows.append(contentsOf: h.items) }
        guard !rows.isEmpty else { return }
        try db.pool.write { conn in
            for r in rows {
                try conn.execute(sql: """
                    INSERT INTO large_files
                      (dir_id, name, size, mtime, ext, file_type)
                    VALUES (?, ?, ?, ?, ?, ?);
                    """,
                    arguments: [
                        r.dirId, r.name, r.size,
                        r.mtime.map { Int($0.timeIntervalSince1970) },
                        r.ext, r.type.rawValue
                    ]
                )
            }
        }
    }

    private func flushTypeTotals(_ totals: [(size: Int64, count: Int64)],
                                 db: ScanDatabase) throws {
        try db.pool.write { conn in
            for (idx, t) in totals.enumerated() where t.count > 0 || t.size > 0 {
                try conn.execute(sql: """
                    INSERT INTO file_type_totals (file_type, total_size, file_count)
                    VALUES (?, ?, ?);
                    """,
                    arguments: [idx, t.size, t.count]
                )
            }
        }
    }

    // MARK: - Helpers

    nonisolated private func depthBetween(rootPath: String, entryPath: String) -> Int {
        guard entryPath.hasPrefix(rootPath) else { return 0 }
        let tail = entryPath.dropFirst(rootPath.count)
        var count = 0
        var inSeg = false
        for ch in tail {
            if ch == "/" {
                inSeg = false
            } else if !inSeg {
                inSeg = true
                count += 1
            }
        }
        return count
    }

    nonisolated private func approximateFraction(filesScanned: Int64) -> Double {
        // 5M files ≈ 1.0; 500K ≈ 0.5; 50K ≈ 0.18. Logarithmic feel.
        let f = Double(filesScanned)
        let approx = log10(max(1.0, f)) / log10(5_000_000)
        return Swift.min(0.99, Swift.max(0.01, approx))
    }
}
