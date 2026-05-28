// BoundedMinHeap.swift
// Tiny capped min-heap. Used by ScanEngine to keep the top-N largest files
// per file-type category in O(log N) per file. Capacity 500 × 8 categories =
// 4000 entries total, well within the engine's ~500KB heap budget.
//
// "Bounded" means: when full, a new item replaces the heap's smallest only if
// the new item is larger. The collected items are NOT sorted; the caller is
// responsible for ordering on extraction.

import Foundation

struct BoundedMinHeap<T: Comparable> {
    private(set) var items: [T] = []
    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        items.reserveCapacity(capacity + 1)
    }

    var count: Int { items.count }
    var isFull: Bool { items.count >= capacity }

    /// Returns the current minimum (root) without removing it.
    var min: T? { items.first }

    /// Insert if not full; otherwise replace the min iff `item > min`.
    mutating func consider(_ item: T) {
        if items.count < capacity {
            items.append(item)
            siftUp(items.count - 1)
        } else if let head = items.first, item > head {
            items[0] = item
            siftDown(0)
        }
    }

    // MARK: - Heap operations

    private mutating func siftUp(_ index: Int) {
        var i = index
        while i > 0 {
            let parent = (i - 1) / 2
            if items[i] < items[parent] {
                items.swapAt(i, parent)
                i = parent
            } else { break }
        }
    }

    private mutating func siftDown(_ index: Int) {
        var i = index
        let n = items.count
        while true {
            let l = 2 * i + 1
            let r = 2 * i + 2
            var smallest = i
            if l < n && items[l] < items[smallest] { smallest = l }
            if r < n && items[r] < items[smallest] { smallest = r }
            if smallest == i { break }
            items.swapAt(i, smallest)
            i = smallest
        }
    }
}
