// PathResolver.swift
// Reconstructs a full path for a `dirs.id` by walking the parent chain. Backed
// by a small LRU cache (~1000 entries) — the same folder renders repeatedly in
// drill / groups / file-type panels.
//
// Important: this is called only when a row is actually displayed, not during
// the scan walk. The walk never reconstructs full paths.

import Foundation

final class PathResolver {

    private let db: ScanDatabase
    private let capacity: Int

    // LRU as an ordered dict approximation: dict for lookup, ordered keys for eviction.
    private var cache: [Int64: String] = [:]
    private var order: [Int64] = []

    init(db: ScanDatabase, capacity: Int = 1000) {
        self.db = db
        self.capacity = capacity
    }

    /// Returns the full reconstructed path for `dirId`, or "/" if the id resolves
    /// to nothing (defensive — shouldn't happen post-scan).
    func fullPath(of dirId: Int64) -> String {
        if let hit = cache[dirId] {
            // touch
            if let idx = order.firstIndex(of: dirId) {
                order.remove(at: idx)
                order.append(dirId)
            }
            return hit
        }

        var parts: [String] = []
        var current: Int64? = dirId
        while let id = current {
            // try? flattens nested optionals (SE-0230): dirNameAndParent returns
            // an optional tuple, so the result here is one level deep, not two.
            guard let row = try? db.dirNameAndParent(id: id) else { break }
            parts.insert(row.name, at: 0)
            current = row.parentId
        }
        // Root row's name is "/" — assemble without a leading slash duplication.
        let joined: String
        if parts.first == "/" {
            joined = "/" + parts.dropFirst().joined(separator: "/")
        } else {
            joined = "/" + parts.joined(separator: "/")
        }

        // Insert with LRU eviction.
        cache[dirId] = joined
        order.append(dirId)
        if order.count > capacity {
            let evict = order.removeFirst()
            cache.removeValue(forKey: evict)
        }
        return joined
    }

    func clear() {
        cache.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }
}
