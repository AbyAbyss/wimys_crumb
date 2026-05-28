// AppModel.swift
// Single observable app model. Holds navigation + UI state + action methods.
// IMPORTANT (plan §7): holds NO scan tree. Lists are query result caches and
// are refreshed by re-querying after data-changing operations.

import Foundation
import Observation
import AppKit
import SwiftUI
import IOKit.ps

enum Screen: Hashable {
    case start, scanning, overview, drill, groups, types, history, settings
}

@MainActor
@Observable
final class AppModel {

    // MARK: - Navigation
    var screen: Screen = .start
    var currentVolume: VolumeInfo? = nil

    // MARK: - Volumes (for Start screen)
    var volumes: [VolumeInfo] = []
    var recentScans: [RecentScan] = []

    // MARK: - Scan state (live during scanning)
    var scanProgress: Double = 0       // 0...1
    var isScanning: Bool = false
    var isPaused: Bool = false
    var currentScanPath: String = ""
    var filesScanned: Int64 = 0
    var etaSeconds: Int? = nil
    /// Count of paths the scan couldn't read (permission denied). Drives
    /// the FDA banner on Overview when above `fdaPromptThreshold`.
    var skippedCount: Int64 = 0
    /// Tap-to-dismiss state for the FDA prompt — once the user clicks
    /// "Open Settings" or x's the banner, we stop showing it for the
    /// session even if the next scan still skips paths.
    var fdaPromptDismissed: Bool = false
    static let fdaPromptThreshold: Int64 = 50

    // Updated periodically during scan; cleared on Overview load.
    var biggestSoFar: [DirRow] = []

    // MARK: - Overview state (refreshed by query after scan / delete)
    var overviewTopFolders: [DirRow] = []
    var overviewTypes: [FileTypeTotal] = []
    var suggestions: [Suggestion] = []
    var overviewStats = OverviewStats()

    // MARK: - Drill / Groups / Types / History — populated in later phases.
    var drillCrumb: [(id: Int64, name: String)] = []
    var drillItems: [DirRow] = []
    /// Multi-select set for the Drill list footer's bulk delete button.
    var drillSelection: Set<Int64> = []

    // MARK: - Groups
    enum GroupsFilter: Sendable { case all, stale }
    var groups: [GroupRow] = []
    var expandedGroup: String? = nil
    var groupsInstances: [DirRow] = []      // children of the currently expanded group
    var groupsSelection: Set<Int64> = []    // selected dirIds across instances
    var groupsFilter: GroupsFilter = .all

    // MARK: - File types (Types screen)
    /// Currently focused category in the Types screen detail panel.
    /// nil = first category in `overviewTypes` is shown on first load.
    var typesSelected: FileTypeCategory? = nil
    /// Heaviest files for `typesSelected`, lazy-loaded.
    var typesTopFiles: [LargeFileRow] = []

    // MARK: - History
    var historySummaries: [HistorySummary] = []
    var historyDeltas: [TopFolderDelta] = []
    var historyLoading: Bool = false

    // MARK: - Delete sheet
    var deleteSheetOpen: Bool = false
    var deleteTargets: [DeleteTarget] = []
    var deleteKind: DeleteKind = .trash

    /// User-configurable protected paths (plan §11.2 Settings).
    /// Phase 5 wires the Settings UI; for now this stays empty so only
    /// the compiled-in system list is enforced.
    var userProtectedPaths: [String] = []

    // MARK: - Toast
    var toast: Toast? = nil

    // MARK: - Session totals
    var freedBytes: Int64 = 0

    // MARK: - Active scan resources
    private(set) var currentDb: ScanDatabase? = nil
    private var currentEngine: ScanEngine? = nil
    private var scanTask: Task<Void, Never>? = nil
    private var biggestPollTask: Task<Void, Never>? = nil

    var pathResolver: PathResolver? {
        currentDb.map { PathResolver(db: $0) }
    }

    // MARK: - Services
    private let scanStore = ScanStore()

    // MARK: - Init
    init() {
        scanStore.pruneOrphans()
        scanStore.pruneOldScans()              // plan §12.4 retention
        refreshVolumes()
        refreshRecentScans()
        currentVolume = volumes.first { $0.url == URL(fileURLWithPath: "/") } ?? volumes.first
        userProtectedPaths = ProtectedPaths.loadUserPaths()
        // Vacuum old DBs off-main — slow file IO, no UI dependencies.
        let store = scanStore
        Task.detached { store.vacuumOldDBs() }
        // Kick the scheduled scan check after Start has had a chance to
        // render. The delay also gives the user a moment to see what's
        // about to happen rather than the app diving straight in.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.runScheduledScanIfDue()
        }
    }

    /// If the schedule says we're due (and a scan isn't already running),
    /// kick one off on the current volume. Called once shortly after
    /// app launch.
    func runScheduledScanIfDue() {
        guard !isScanning else { return }
        let enabled = UserDefaults.standard.bool(forKey: SettingsKey.scheduledScanEnabled)
        guard enabled else { return }
        let freqDays = max(1, UserDefaults.standard.integer(forKey: SettingsKey.scheduledScanFreqDays))
        let onlyOnPower = UserDefaults.standard.bool(forKey: SettingsKey.scheduledOnlyOnPower)
        if onlyOnPower && !isOnPower() {
            return
        }
        guard let volume = currentVolume else { return }
        // Compare against most recent scan's mtime (file modification time
        // of its .sqlite file).
        let due: Bool
        if let lastScan = recentScans.first {
            let elapsedDays = -lastScan.startedAt.timeIntervalSinceNow / 86_400.0
            due = elapsedDays >= Double(freqDays)
        } else {
            due = true   // never scanned — definitely due
        }
        guard due else { return }
        showToast("Scheduled scan starting…", duration: 4)
        startScan(volume: volume)
    }

    /// True when the Mac is on AC power. Used by the "only when plugged
    /// in" scheduled-scan option.
    private func isOnPower() -> Bool {
        // IOPSCopyPowerSourcesInfo gives us battery state in CFDictionary
        // form; we just need to know if there's at least one AC source.
        // Returns true on desktops (no battery) too, which is correct.
        // Importing IOKit only when needed keeps the import surface tight.
        let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue()
            as? [CFTypeRef] ?? []
        for s in sources {
            if let desc = IOPSGetPowerSourceDescription(info, s)?.takeUnretainedValue()
                as? [String: AnyObject],
               let state = desc[kIOPSPowerSourceStateKey] as? String,
               state == kIOPSACPowerValue {
                return true
            }
        }
        // No battery source found at all → likely a desktop. Treat as plugged in.
        return sources.isEmpty
    }

    /// Re-read the user-added protected paths from UserDefaults. Call
    /// this after the Settings UI adds or removes an entry so the
    /// in-memory copy DeleteService consults stays current.
    func refreshUserProtectedPaths() {
        userProtectedPaths = ProtectedPaths.loadUserPaths()
    }

    // MARK: - Navigation methods

    func goToStart() {
        cancelScan(silent: true)
        scanProgress = 0
        currentScanPath = ""
        screen = .start
    }

    func goToOverview()  { resetDrillState(); screen = .overview }
    func goToGroups()    { resetDrillState(); screen = .groups }
    func goToTypes()     { resetDrillState(); screen = .types }
    func goToHistory()   {
        resetDrillState()
        screen = .history
        // Lazy-load if we haven't yet — opens each historical .sqlite file
        // off the main thread and refreshes the view when ready.
        if historySummaries.isEmpty && !historyLoading { loadHistory() }
    }
    func openSettings()  { screen = .settings }

    /// Clear breadcrumb when leaving Drill so the next drill starts fresh.
    /// Settings doesn't reset (user often opens it mid-drill).
    private func resetDrillState() {
        drillCrumb = []
        drillItems = []
        drillSelection = []
    }

    /// Open the delete sheet with everything currently checked in the
    /// Drill list footer.
    func deleteSelectedDrillItems() {
        guard let resolver = pathResolver else { return }
        let chosen = drillItems.filter { drillSelection.contains($0.id) }
        let targets = chosen.map { row -> DeleteTarget in
            let path = resolver.fullPath(of: row.id)
            return DeleteTarget(
                dirId: row.id,
                fileName: nil,
                path: path,
                size: row.totalSize,
                mtime: row.mtime,
                isProtected: DeleteService.isProtected(
                    path, additional: userProtectedPaths
                )
            )
        }
        openDeleteSheet(targets: targets)
    }

    /// Drill into a directory. If we're entering Drill from Overview, the
    /// volume root is pushed onto the crumb first so the user can click
    /// it to return. Items load synchronously off the in-memory SQLite —
    /// each query is a few hundred rows max and runs in ~ms.
    func drillInto(dirId: Int64) {
        guard let db = currentDb else { return }
        do {
            if drillCrumb.isEmpty {
                let rootId = try db.rootDirId() ?? 1
                let rootName = (try? db.dirNameAndParent(id: rootId))?.name
                    ?? currentVolume?.name
                    ?? "/"
                drillCrumb = [(id: rootId, name: rootName)]
                // Don't push the same id twice (clicking root in the treemap).
                if dirId != rootId {
                    let info = try db.dirNameAndParent(id: dirId)
                    let name = info?.name ?? "—"
                    drillCrumb.append((id: dirId, name: name))
                }
            } else {
                let info = try db.dirNameAndParent(id: dirId)
                let name = info?.name ?? "—"
                drillCrumb.append((id: dirId, name: name))
            }
            let currentId = drillCrumb.last?.id ?? dirId
            drillItems = try db.children(of: currentId)
            screen = .drill
        } catch {
            showToast("Couldn't open folder: \(error.localizedDescription)")
        }
    }

    /// Pop the breadcrumb back to a given index (inclusive). Index 0 —
    /// the volume root — routes back to Overview rather than rendering
    /// the root's children in Drill (which would just duplicate the
    /// treemap).
    func popDrill(to index: Int) {
        guard let db = currentDb, index >= 0, index < drillCrumb.count else { return }
        if index == 0 {
            drillCrumb = []
            drillItems = []
            screen = .overview
            return
        }
        drillCrumb = Array(drillCrumb.prefix(index + 1))
        if let last = drillCrumb.last {
            drillItems = (try? db.children(of: last.id)) ?? []
        }
    }

    /// Trigger a fresh scan of the currently-selected drive.
    func rescan() {
        if let v = currentVolume { startScan(volume: v) }
    }

    // MARK: - Toast helpers
    func showToast(_ message: String, duration: TimeInterval = 6, action: ToastAction? = nil) {
        toast = Toast(message: message, action: action, duration: duration)
    }

    func dismissToast() { toast = nil }

    // MARK: - Full Disk Access

    /// Banner is visible on Overview when this is true.
    var shouldShowFDAPrompt: Bool {
        !fdaPromptDismissed && skippedCount >= Self.fdaPromptThreshold
    }

    /// Deep-link to System Settings → Privacy & Security → Full Disk Access
    /// and remember the dismissal so the banner doesn't reappear this session.
    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
        fdaPromptDismissed = true
    }

    /// Dismiss the FDA banner without opening Settings.
    func dismissFDAPrompt() {
        fdaPromptDismissed = true
    }

    // MARK: - Delete actions

    /// Present the delete confirmation sheet with the given pre-populated
    /// targets. Caller is responsible for marking `isProtected` correctly;
    /// DeleteService applies the same check defensively.
    func openDeleteSheet(targets: [DeleteTarget]) {
        guard !targets.isEmpty else { return }
        deleteTargets = targets
        deleteKind = .trash
        deleteSheetOpen = true
    }

    func closeDeleteSheet() {
        deleteSheetOpen = false
        deleteTargets = []
    }

    /// Run the delete via DeleteService. On success: prune the affected
    /// rows from the on-screen lists, fire a toast, and (for Trash) wire
    /// an Undo action. The SQLite tree on disk is left stale — the next
    /// rescan reconciles. Acceptable for v1 (noted in plan §10).
    func confirmDelete() {
        let outcome = DeleteService.perform(
            deleteTargets,
            kind: deleteKind,
            userProtectedPaths: userProtectedPaths
        )

        // Patch the SQLite tree (plan §12.2). Required so the next
        // re-query doesn't bring deleted rows back. Run synchronously
        // since it's a small write inside an existing open DB and the
        // UI is already mid-transition to its post-delete state.
        if !outcome.removed.isEmpty, let db = currentDb {
            let removedDirRows = outcome.removed.filter { !$0.isFile }
            let removedFileRows = outcome.removed.filter { $0.isFile }
            let dirIds = removedDirRows.compactMap(\.dirId)
            let files: [(dirId: Int64, name: String)] = removedFileRows.compactMap { t in
                guard let did = t.dirId, let name = t.fileName else { return nil }
                return (did, name)
            }
            do {
                try db.patchAfterDelete(dirIds: dirIds, files: files)
            } catch {
                NSLog("patchAfterDelete failed: \(error)")
            }
        }

        // Update on-screen state immediately so the UI feels responsive.
        if !outcome.removed.isEmpty {
            freedBytes += outcome.freedBytes
            // Only DIRECTORY targets contribute their own id to the
            // removal set — file targets' dirId points to the file's
            // parent, which we don't want to remove from drill lists.
            let removedDirIds = Set(outcome.removed
                .filter { !$0.isFile }
                .compactMap(\.dirId))

            drillItems.removeAll { removedDirIds.contains($0.id) }
            drillSelection.subtract(removedDirIds)
            overviewTopFolders.removeAll { removedDirIds.contains($0.id) }
            groupsInstances.removeAll { removedDirIds.contains($0.id) }
            groupsSelection.subtract(removedDirIds)
            // Pop any drill crumb segments that just disappeared.
            drillCrumb.removeAll { removedDirIds.contains($0.id) }
            // Types screen's heaviest-files list — filter by full path
            // (large_files don't have dirIds we can hit directly).
            let removedPaths = Set(outcome.removed.map(\.path))
            if !removedPaths.isEmpty, let resolver = pathResolver {
                typesTopFiles.removeAll { row in
                    let dir = resolver.fullPath(of: row.dirId)
                    let full = dir.hasSuffix("/") ? dir + row.name : dir + "/" + row.name
                    return removedPaths.contains(full)
                }
            }

            // Adjust Used / Could-free totals optimistically. The next
            // rescan will replace these with authoritative numbers.
            overviewStats.used = max(0, overviewStats.used - outcome.freedBytes)
            overviewStats.free = overviewStats.free + outcome.freedBytes
        }

        let n = outcome.removed.count
        let freed = Fmt.bytes(outcome.freedBytes)
        if n == 0 && !outcome.skipped.isEmpty {
            showToast("Nothing deleted — all targets were protected.")
        } else if deleteKind == .trash {
            let trashURLs = outcome.trashURLs
            showToast(
                "Freed \(freed) · \(n) item\(n == 1 ? "" : "s") moved to Trash",
                duration: 8,
                action: trashURLs.isEmpty ? nil : ToastAction(
                    label: "Undo", kind: .undoDelete
                )
            )
            // Hold onto the trash URLs until the toast either runs Undo
            // or dismisses. WimysCrumbApp's toast view reads this back.
            pendingTrashURLs = trashURLs
        } else {
            showToast("Freed \(freed) · \(n) item\(n == 1 ? "" : "s") deleted")
        }

        closeDeleteSheet()
    }

    /// Run the most recent Trash delete's undo, if any. Called from the
    /// toast's Undo action handler in the view layer.
    func runPendingUndo() {
        DeleteService.restoreFromTrash(pendingTrashURLs)
        pendingTrashURLs = [:]
        showToast("Items restored from Trash. Rescan to see them in the tree.")
    }

    @ObservationIgnored private var pendingTrashURLs: [URL: URL] = [:]

    // MARK: - Scan lifecycle

    func startScan(volume: VolumeInfo) {
        currentVolume = volume
        cancelScan(silent: true)

        scanProgress = 0
        isScanning = true
        isPaused = false
        currentScanPath = volume.url.path
        filesScanned = 0
        etaSeconds = nil
        biggestSoFar = []
        screen = .scanning

        // Open a fresh database for this scan at its final path. We skip the
        // in-progress→final rename for Phase 2 to avoid invalidating GRDB's
        // open file handle. A crash mid-scan leaves a partial file; the next
        // launch's pruneOrphans cleans up anything still labelled in-progress
        // from older builds, but otherwise partial files just look like very
        // small recent scans.
        let started = Date()
        let dbURL = scanStore.completedURL(volumeUUID: volume.id, startedAt: started)
        let db: ScanDatabase
        do {
            db = try ScanDatabase(url: dbURL)
        } catch {
            isScanning = false
            showToast("Couldn't open scan database: \(error.localizedDescription)")
            screen = .start
            return
        }
        currentDb = db

        let engine = ScanEngine()
        currentEngine = engine

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let start = try await engine.start(root: volume.url, db: db, volume: volume)

                // Background poller for biggest-so-far while the engine runs.
                // Detached so the sync GRDB read doesn't block MainActor.
                self.biggestPollTask = Task.detached { [weak self] in
                    while !Task.isCancelled {
                        if let rows = try? db.biggestSoFar(limit: 6) {
                            await MainActor.run { self?.biggestSoFar = rows }
                        }
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }

                // Consume progress events.
                for try await update in start.progress {
                    self.scanProgress = update.fraction
                    self.filesScanned = update.filesScanned
                    self.currentScanPath = update.currentPath
                    self.etaSeconds = update.etaSeconds
                }

                self.biggestPollTask?.cancel()
                self.biggestPollTask = nil

                // If user cancelled mid-scan, drop the half-built database
                // and exit cleanly (no toast — they initiated the cancel).
                if await engine.isCancelled {
                    self.isScanning = false
                    self.cleanupCancelledDatabase()
                    return
                }

                // Aggregate.
                let maxDepth = await engine.maxDepthSeen
                let dirCount = await engine.dirCount
                let fileCount = await engine.fileCount
                let skippedCount = await engine.skippedCount
                let scanId = await engine.scanId
                try Aggregator.finalize(
                    db: db,
                    scanId: scanId,
                    volume: volume,
                    maxDepth: maxDepth,
                    dirCount: dirCount,
                    fileCount: fileCount,
                    skippedCount: skippedCount
                )

                self.isScanning = false
                // Record skipped count + reset the FDA banner's dismissal
                // so the prompt re-appears for the new scan's verdict.
                self.skippedCount = skippedCount
                self.fdaPromptDismissed = false
                self.loadOverview()
                self.loadGroups()
                self.loadHistory()
                self.refreshRecentScans()
                self.screen = .overview
                self.showToast("Scan complete · \(Fmt.bytes(volume.used)) used")
            } catch is CancellationError {
                // User-initiated cancel — silently clean up.
                self.isScanning = false
                self.cleanupCancelledDatabase()
            } catch {
                self.isScanning = false
                self.showToast("Scan failed: \(error.localizedDescription)")
                self.screen = .start
            }
        }
    }

    func pauseScan() {
        guard let engine = currentEngine else { return }
        isPaused = true
        Task { await engine.pause() }
    }

    func resumeScan() {
        guard let engine = currentEngine else { return }
        isPaused = false
        Task { await engine.resume() }
    }

    func cancelScan(silent: Bool = false) {
        guard let engine = currentEngine else { return }
        Task { await engine.cancel() }
        biggestPollTask?.cancel()
        scanTask?.cancel()
        biggestPollTask = nil
        scanTask = nil
        currentEngine = nil
        isScanning = false
        if !silent { screen = .start }
    }

    private func cleanupCancelledDatabase() {
        guard let db = currentDb else { return }
        currentDb = nil
        try? FileManager.default.removeItem(at: db.url)
    }

    // MARK: - Groups loader / expand

    /// Run after a scan completes. Aggregates the known group names
    /// (node_modules etc) across the whole tree using one SQL query.
    func loadGroups() {
        guard let db = currentDb else { return }
        do {
            let names = Set(GroupCatalog.entries.map(\.name))
            let aggs = try db.groupAggregates(names: names)
            self.groups = aggs.map { agg in
                let cat = GroupCatalog.entries.first(where: { $0.name == agg.name })
                return GroupRow(
                    name: agg.name,
                    tagline: cat?.tagline ?? "",
                    count: agg.count,
                    total: agg.total,
                    avgAgeDays: agg.avgAgeDays,
                    devOnly: cat?.devOnly ?? false
                )
            }
            self.expandedGroup = nil
            self.groupsInstances = []
            self.groupsSelection = []
        } catch {
            showToast("Couldn't load groups: \(error.localizedDescription)")
        }
    }

    /// Toggle a group open in the list. On open, fetches its instances
    /// from SQLite (filtered to non-nested matches, same rule as the
    /// aggregate query).
    func toggleGroupExpanded(_ name: String) {
        guard let db = currentDb else { return }
        if expandedGroup == name {
            expandedGroup = nil
            groupsInstances = []
            return
        }
        do {
            let names = Set(GroupCatalog.entries.map(\.name))
            let rows = try db.groupInstances(name: name, namesForExclusion: names)
            expandedGroup = name
            groupsInstances = rows
        } catch {
            showToast("Couldn't expand group: \(error.localizedDescription)")
        }
    }

    /// Bulk delete the currently-selected group instances. The selection
    /// is by `dirId`; we materialize the targets here using PathResolver.
    func deleteSelectedGroupInstances() {
        guard !groupsSelection.isEmpty,
              let resolver = pathResolver else { return }
        let chosen = groupsInstances.filter { groupsSelection.contains($0.id) }
        let targets = chosen.map { row -> DeleteTarget in
            let path = resolver.fullPath(of: row.id)
            return DeleteTarget(
                dirId: row.id,
                fileName: nil,
                path: path,
                size: row.totalSize,
                mtime: row.mtime,
                isProtected: DeleteService.isProtected(
                    path, additional: userProtectedPaths
                )
            )
        }
        openDeleteSheet(targets: targets)
    }

    // MARK: - Suggestions (Quick Wins click handler)

    /// Resolve a Suggestion's `action` into a concrete delete target set
    /// and open the confirmation sheet. For `.review` suggestions there's
    /// no canonical target; we show a toast that names the case so the
    /// user knows where to dig in manually.
    func openSuggestion(_ s: Suggestion) {
        guard let db = currentDb, let resolver = pathResolver else { return }
        guard let action = s.action else {
            showToast(s.title + " — open from the relevant tab to review.")
            return
        }
        do {
            switch action {
            case .review:
                showToast(s.title + " — needs review; nothing automatic.")
            case .staleDir(let name, let days):
                let rows = try db.dirsByName(name, staleDays: days)
                openDeleteSheet(targets: rows.map { dirTarget($0, resolver: resolver) })
            case .allDir(let name):
                let rows = try db.dirsByName(name, staleDays: nil)
                openDeleteSheet(targets: rows.map { dirTarget($0, resolver: resolver) })
            case .oldDownloads(let days):
                let files = try db.oldDownloadFiles(staleDays: days)
                openDeleteSheet(targets: files.map { fileTarget($0, resolver: resolver) })
            }
        } catch {
            showToast("Couldn't resolve targets: \(error.localizedDescription)")
        }
    }

    private func dirTarget(_ row: DirRow, resolver: PathResolver) -> DeleteTarget {
        let path = resolver.fullPath(of: row.id)
        return DeleteTarget(
            dirId: row.id,
            fileName: nil,
            path: path,
            size: row.totalSize,
            mtime: row.mtime,
            isProtected: DeleteService.isProtected(path, additional: userProtectedPaths)
        )
    }

    private func fileTarget(_ row: LargeFileRow, resolver: PathResolver) -> DeleteTarget {
        let dirPath = resolver.fullPath(of: row.dirId)
        let filePath = dirPath.hasSuffix("/")
            ? dirPath + row.name
            : dirPath + "/" + row.name
        return DeleteTarget(
            dirId: row.dirId,
            fileName: row.name,
            path: filePath,
            size: row.size,
            mtime: row.mtime,
            isProtected: DeleteService.isProtected(filePath, additional: userProtectedPaths)
        )
    }

    // MARK: - File types (Types screen)

    /// Set the focused category and load its heaviest files.
    func selectFileType(_ type: FileTypeCategory) {
        typesSelected = type
        loadTypeFiles(for: type)
    }

    /// Lazy-load the top files for a given category. No-op if the
    /// database isn't open.
    func loadTypeFiles(for type: FileTypeCategory) {
        guard let db = currentDb else { return }
        do {
            typesTopFiles = try db.largeFiles(byType: type, limit: 30)
        } catch {
            showToast("Couldn't load files: \(error.localizedDescription)")
        }
    }

    /// Open the delete sheet pre-loaded with stale (>180d) files in the
    /// currently-shown category. Files are reconstructed to full paths
    /// via PathResolver. Used by the Types screen's "Clean stale" CTA.
    func cleanStaleTypeFiles() {
        guard let resolver = pathResolver else { return }
        let cutoffSeconds: TimeInterval = 180 * 86_400
        let stale = typesTopFiles.filter { row in
            guard let m = row.mtime else { return false }
            return -m.timeIntervalSinceNow > cutoffSeconds
        }
        let targets = stale.map { row -> DeleteTarget in
            let dirPath = resolver.fullPath(of: row.dirId)
            let filePath = dirPath.hasSuffix("/")
                ? dirPath + row.name
                : dirPath + "/" + row.name
            return DeleteTarget(
                dirId: row.dirId,
                fileName: row.name,
                path: filePath,
                size: row.size,
                mtime: row.mtime,
                isProtected: DeleteService.isProtected(
                    filePath, additional: userProtectedPaths
                )
            )
        }
        if targets.isEmpty {
            showToast("No stale files in this category.")
        } else {
            openDeleteSheet(targets: targets)
        }
    }

    // MARK: - History

    /// Read every completed scan's summary off the main thread, then
    /// hop back to update the @Observable state. Cheap per file (one
    /// row read), but cumulative — running async keeps the History tab
    /// from janking when it first appears.
    func loadHistory() {
        let store = scanStore
        historyLoading = true
        Task.detached { [weak self] in
            let summaries = HistoryLoader.loadSummaries(from: store)
            let deltas = HistoryLoader.computeDeltas(summaries: summaries)
            await MainActor.run {
                guard let self else { return }
                self.historySummaries = summaries
                self.historyDeltas = deltas
                self.historyLoading = false
            }
        }
    }

    // MARK: - Overview loader (plan §7.1: query, don't cache the tree)

    func loadOverview() {
        guard let db = currentDb, let volume = currentVolume else { return }
        do {
            let rootId = try db.rootDirId() ?? 1
            let tops = try db.children(of: rootId, limit: 12)
            let types = try db.fileTypeTotals()
            let suggs = Suggestions.generate(db: db)
            let counts = try db.dirAndFileCounts()
            let couldFree = suggs.reduce(Int64(0)) { $0 + $1.saveBytes }
            self.overviewTopFolders = tops
            self.overviewTypes = types
            self.suggestions = suggs
            self.overviewStats = OverviewStats(
                used: volume.used,
                free: volume.availableCapacity,
                items: counts.files,
                couldFree: couldFree
            )
        } catch {
            // Best effort — leave previous overview state.
            showToast("Couldn't load overview: \(error.localizedDescription)")
        }
    }

    // MARK: - Volume enumeration

    func refreshVolumes() {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeUUIDStringKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsLocalKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        let infos: [VolumeInfo] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let free  = Int64(values.volumeAvailableCapacity ?? 0)
            guard total > 0 else { return nil }

            let name = values.volumeName ?? url.lastPathComponent
            let uuid = values.volumeUUIDString ?? url.path
            let kind: VolumeKind = {
                if values.volumeIsInternal == true { return .internal }
                if values.volumeIsRemovable == true || values.volumeIsEjectable == true {
                    return .removable
                }
                return .external
            }()

            return VolumeInfo(id: uuid,
                              name: name,
                              kind: kind,
                              totalCapacity: total,
                              availableCapacity: free,
                              url: url)
        }
        volumes = infos.sorted { lhs, _ in
            lhs.url == URL(fileURLWithPath: "/")
        }
    }

    func refreshRecentScans() {
        recentScans = scanStore.listCompleted().prefix(5).map { url in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return RecentScan(id: url, volumeName: url.deletingPathExtension().lastPathComponent,
                              startedAt: date, totalUsed: nil)
        }
    }

    // MARK: - Folder picker (Start screen "Pick a specific folder…")

    func pickFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            let total = (try? url.resourceValues(forKeys: [.volumeTotalCapacityKey]))?
                .volumeTotalCapacity ?? 0
            let free = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?
                .volumeAvailableCapacity ?? 0
            let synthetic = VolumeInfo(
                id: url.path,
                name: url.lastPathComponent,
                kind: .external,
                totalCapacity: Int64(total),
                availableCapacity: Int64(free),
                url: url
            )
            startScan(volume: synthetic)
        }
    }
}

// MARK: - Overview stats summary

struct OverviewStats: Sendable {
    var used: Int64 = 0
    var free: Int64 = 0
    var items: Int64 = 0
    var couldFree: Int64 = 0
}

// MARK: - Preview helpers

extension AppModel {
    @MainActor
    static var previewOverview: AppModel {
        let m = AppModel()
        m.screen = .overview
        if m.currentVolume == nil { m.currentVolume = MockData.drives.first }
        m.overviewTopFolders = MockData.topFolders
        m.overviewTypes = MockData.fileTypes
        m.suggestions = MockData.suggestions
        m.overviewStats = OverviewStats(
            used: 612_000_000_000,
            free: 388_000_000_000,
            items: 1_582_320,
            couldFree: 57_000_000_000
        )
        return m
    }

    @MainActor
    static var previewStart: AppModel {
        let m = AppModel()
        m.screen = .start
        return m
    }

    @MainActor
    static var previewScanning: AppModel {
        let m = AppModel()
        m.currentVolume = MockData.drives.first
        m.screen = .scanning
        m.isScanning = true
        m.scanProgress = 0.42
        m.filesScanned = 270_000
        m.currentScanPath = "~/Library/Application Support/Slack/Cache"
        m.biggestSoFar = MockData.topFolders
        return m
    }
}
