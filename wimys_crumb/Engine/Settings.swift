// Settings.swift
// User preferences via @AppStorage, plus protected paths.
// The system protected set is COMPILED IN and non-removable (plan §12.1).

import Foundation
import SwiftUI

// MARK: - Safety toggle keys (used by @AppStorage in views)

enum SettingsKey {
    static let protectSystemPaths  = "settings.protectSystemPaths"
    static let protectActiveProjs  = "settings.protectActiveProjects"
    static let confirmLargeDeletes = "settings.confirmLargeDeletes"
    static let alwaysSnapshotFirst = "settings.alwaysSnapshotFirst"
    static let allowDeletingHidden = "settings.allowDeletingHidden"
    static let userProtectedPaths  = "settings.userProtectedPaths"  // JSON [String]
    static let scheduledScanEnabled = "settings.scheduledScanEnabled"
    static let scheduledScanFreqDays = "settings.scheduledScanFreqDays"
    static let scheduledOnlyOnPower = "settings.scheduledOnlyOnPower"
}

// MARK: - Protected paths

struct ProtectedPath: Identifiable, Hashable, Sendable {
    let path: String
    let isSystem: Bool
    var id: String { path }
}

enum ProtectedPaths {

    /// Compiled-in, non-removable system protected paths. Plan §12.1.
    static let system: [String] = [
        "/System",
        "/Library",
        "/usr",
        "/bin",
        "/sbin",
        "/private",
        // User-domain locks (resolve at consult time)
        "~/Library/Keychains",
        "~/.ssh",
        "~/.gnupg",
    ]

    /// All protected paths (system + user-added). Order: system first.
    static func all() -> [ProtectedPath] {
        let sys = system.map { ProtectedPath(path: $0, isSystem: true) }
        let user = loadUserPaths().map { ProtectedPath(path: $0, isSystem: false) }
        return sys + user
    }

    static func loadUserPaths() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.userProtectedPaths),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    static func saveUserPaths(_ paths: [String]) {
        let data = (try? JSONEncoder().encode(paths)) ?? Data()
        UserDefaults.standard.set(data, forKey: SettingsKey.userProtectedPaths)
    }

    /// Resolve a path that may contain `~` to an absolute filesystem path.
    static func resolve(_ p: String) -> String {
        (p as NSString).expandingTildeInPath
    }

    /// True iff `candidate` is, or is inside, any protected path.
    /// Used by the delete UI; the service repeats this check as a second line
    /// of defence (plan §12.1).
    static func isProtected(_ candidate: String) -> Bool {
        let target = resolve(candidate)
        let normalized = target.hasSuffix("/") ? String(target.dropLast()) : target
        for prot in all() {
            let p = resolve(prot.path)
            let pn = p.hasSuffix("/") ? String(p.dropLast()) : p
            if normalized == pn { return true }
            if normalized.hasPrefix(pn + "/") { return true }
        }
        return false
    }
}
