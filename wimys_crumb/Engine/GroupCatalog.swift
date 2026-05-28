// GroupCatalog.swift
// The set of known directory names the Groups screen aggregates across
// the disk. Plan §12 / §8.5.
//
// Two metadata bits per entry:
//   - `tagline`: short human label, used under the monospace name
//   - `devOnly`: shows a "dev" pill in the row, and lets the Stale-only
//                filter weight dev caches differently in the future.
//
// Adding a name here is enough for the Groups screen to start surfacing
// it after the next scan — no schema change required (the engine writes
// every directory name to `dirs.name`).

import Foundation

enum GroupCatalog {

    struct Entry: Sendable {
        let name: String
        let tagline: String
        let devOnly: Bool
    }

    static let entries: [Entry] = [
        Entry(name: "node_modules",     tagline: "JavaScript dependencies",     devOnly: true),
        Entry(name: ".venv",            tagline: "Python virtual environments", devOnly: true),
        Entry(name: "venv",             tagline: "Python virtual environments", devOnly: true),
        Entry(name: "__pycache__",      tagline: "Python compiled cache",       devOnly: true),
        Entry(name: "DerivedData",      tagline: "Xcode build cache",           devOnly: true),
        Entry(name: ".gradle",          tagline: "Gradle build cache",          devOnly: true),
        Entry(name: "Pods",             tagline: "CocoaPods dependencies",      devOnly: true),
        Entry(name: "target",           tagline: "Rust / Java build output",    devOnly: true),
        Entry(name: "bower_components", tagline: "Legacy JS dependencies",      devOnly: true),
        Entry(name: "Caches",           tagline: "App caches",                  devOnly: false),
        Entry(name: ".cache",           tagline: "Tool caches",                 devOnly: true),
    ]
}
