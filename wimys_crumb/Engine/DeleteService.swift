// DeleteService.swift
// The only place that actually removes files. Plan §10.
//
// Every destructive path in the UI funnels through this service. The service
// is the second line of defense for protected paths — even if the UI somehow
// passes a protected target through, this code refuses.

import Foundation
import AppKit

enum DeleteService {

    /// What a single delete attempt produced.
    struct Outcome: Sendable {
        let removed: [DeleteTarget]
        let freedBytes: Int64
        let skipped: [DeleteTarget]
        /// For Trash deletes: original URL → URL the file landed at in Trash.
        /// Used by the toast's Undo action.
        let trashURLs: [URL: URL]
    }

    /// Compiled-in protected paths. The user can add more in Settings.
    static func systemProtectedPaths() -> [String] {
        let expand: (String) -> String = { ($0 as NSString).expandingTildeInPath }
        return [
            "/System", "/Library", "/usr", "/bin", "/sbin", "/private",
            expand("~/Library/Keychains"),
            expand("~/.ssh"),
            expand("~/.gnupg"),
        ]
    }

    /// True if `path` is, or is inside, any protected path. Compares
    /// standardized paths so trailing slashes / symlink prefixes match.
    static func isProtected(_ path: String, additional: [String] = []) -> Bool {
        let all = systemProtectedPaths() + additional
        let normalized = (path as NSString).standardizingPath
        for protectedPath in all {
            let p = (protectedPath as NSString).standardizingPath
            if normalized == p { return true }
            if normalized.hasPrefix(p + "/") { return true }
        }
        return false
    }

    /// Perform the delete. Always partitions on `isProtected` BEFORE calling
    /// FileManager — protected items are never sent to trashItem/removeItem.
    static func perform(
        _ targets: [DeleteTarget],
        kind: DeleteKind,
        userProtectedPaths: [String]
    ) -> Outcome {
        var removed: [DeleteTarget] = []
        var skipped: [DeleteTarget] = []
        var trashURLs: [URL: URL] = [:]
        var freed: Int64 = 0

        for target in targets {
            if target.isProtected || isProtected(target.path,
                                                 additional: userProtectedPaths) {
                skipped.append(target)
                continue
            }
            let url = URL(fileURLWithPath: target.path)

            switch kind {
            case .trash:
                var resultingURL: NSURL? = nil
                do {
                    try FileManager.default.trashItem(
                        at: url, resultingItemURL: &resultingURL
                    )
                    removed.append(target)
                    freed += target.size
                    if let ns = resultingURL {
                        trashURLs[url] = ns as URL
                    }
                } catch {
                    skipped.append(target)
                }
            case .forever:
                do {
                    try FileManager.default.removeItem(at: url)
                    removed.append(target)
                    freed += target.size
                } catch {
                    skipped.append(target)
                }
            }
        }

        return Outcome(
            removed: removed,
            freedBytes: freed,
            skipped: skipped,
            trashURLs: trashURLs
        )
    }

    /// Move items back from Trash to their original locations. Best-effort —
    /// if the user has emptied the Trash since the delete, the corresponding
    /// entries are silently skipped.
    static func restoreFromTrash(_ trashURLs: [URL: URL]) {
        for (original, trashed) in trashURLs {
            try? FileManager.default.moveItem(at: trashed, to: original)
        }
    }
}
