// SettingsView.swift
// 210pt sidebar + content panel. Plan §8.9.
//
// Safety, Scans, Detection, Snapshots, Export, and About are all real.
// Detection is read-only in v1 (group catalog + large-file threshold).

import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var app: AppModel

    @State private var section: Section = .safety

    enum Section: String, CaseIterable, Identifiable {
        case scans, detection, safety, snapshots, export, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .scans:     return "Scans"
            case .detection: return "Detection"
            case .safety:    return "Safety"
            case .snapshots: return "Snapshots"
            case .export:    return "Export"
            case .about:     return "About"
            }
        }
        var icon: AppIcon {
            switch self {
            case .scans:     return .clock
            case .detection: return .sparkle
            case .safety:    return .shield
            case .snapshots: return .chart
            case .export:    return .download
            case .about:     return .other
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.cardGap) {
            sidebar
                .frame(width: 210)
            contentCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Spacing.screenH)
        .padding(.bottom, Spacing.screenV)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        Card(pad: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SETTINGS")
                    .font(Theme.body(11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.cInk3)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                ForEach(Section.allCases) { s in
                    sidebarButton(s)
                }
            }
        }
    }

    private func sidebarButton(_ s: Section) -> some View {
        let isSel = section == s
        return Button { section = s } label: {
            HStack(spacing: 9) {
                IconView(icon: s.icon, size: 13)
                Text(s.label)
                    .font(Theme.body(13, weight: isSel ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(isSel ? Color.cCoral : Color.cInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSel ? Color.cCoralSoft : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content panel

    private var contentCard: some View {
        Card(pad: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    switch section {
                    case .safety:    SafetyPanel(app: app)
                    case .scans:     ScansPanel()
                    case .detection: DetectionPanel()
                    case .snapshots: SnapshotsPanel(app: app)
                    case .export:    ExportPanel(app: app)
                    case .about:     AboutPanel()
                    }
                }
                .padding(24)
            }
        }
    }
}

// MARK: - Safety

private struct SafetyPanel: View {
    @Bindable var app: AppModel

    @AppStorage(SettingsKey.protectSystemPaths)  private var protectSystem: Bool = true
    @AppStorage(SettingsKey.protectActiveProjs)  private var protectActive: Bool = true
    @AppStorage(SettingsKey.confirmLargeDeletes) private var confirmLarge: Bool = true
    @AppStorage(SettingsKey.alwaysSnapshotFirst) private var snapshotFirst: Bool = true
    @AppStorage(SettingsKey.allowDeletingHidden) private var allowHidden: Bool = false

    @State private var paths: [ProtectedPath] = ProtectedPaths.all()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelHeader(
                icon: .shield,
                title: "Safety",
                subtitle: "What Crumb refuses to delete — even if you tell it to."
            )

            toggleRow(
                title: "Protect system paths",
                description: "Always skip /System, /usr, /private, and similar.",
                isOn: $protectSystem
            )
            divider
            toggleRow(
                title: "Protect active projects",
                description: "Skip folders modified in the last 7 days unless explicitly chosen.",
                isOn: $protectActive
            )
            divider
            toggleRow(
                title: "Confirm large deletes",
                description: "Show the confirmation sheet for any cleanup over 1 GB.",
                isOn: $confirmLarge
            )
            divider
            toggleRow(
                title: "Always snapshot first",
                description: "Keep a 30-day rollback. Uses ~1 % of freed space.",
                isOn: $snapshotFirst
            )
            divider
            toggleRow(
                title: "Allow deleting hidden",
                description: "Show and allow removal of dot-folders like .Trash, .config.",
                isOn: $allowHidden
            )

            Divider().overlay(Color.cLine).padding(.vertical, 6)

            protectedPathsSection
        }
    }

    private var divider: some View {
        Divider().overlay(Color.cLine).padding(.vertical, 2)
    }

    private func toggleRow(title: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Color.cInk)
                Text(description)
                    .font(Theme.body(12))
                    .foregroundStyle(Color.cInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var protectedPathsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Protected paths")
                    .font(Theme.body(14, weight: .bold))
                    .foregroundStyle(Color.cInk)
                Spacer()
                Button {
                    addPath()
                } label: {
                    HStack(spacing: 5) {
                        IconView(icon: .plus, size: 11)
                        Text("Add path")
                            .font(Theme.body(11, weight: .semibold))
                    }
                    .foregroundStyle(Color.cInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.cPanel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.cLine, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ForEach(paths) { p in
                    pathRow(p)
                    if p.id != paths.last?.id {
                        Divider().overlay(Color.cLine)
                    }
                }
            }
            .background(Color.cPanel)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.cLine, lineWidth: 1)
            )
        }
    }

    private func pathRow(_ p: ProtectedPath) -> some View {
        HStack(spacing: 10) {
            IconView(icon: .shield, size: 12)
                .foregroundStyle(p.isSystem ? Color.cRed : Color.cInk2)
            Text(p.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.cInk)
                .lineLimit(1)
                .truncationMode(.middle)
            if p.isSystem {
                Pill(text: "system", color: .cRed, soft: .cRedSoft)
            }
            Spacer()
            if !p.isSystem {
                Button { removePath(p.path) } label: {
                    IconView(icon: .x, size: 11)
                        .foregroundStyle(Color.cInk2)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func addPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Protect"
        panel.message = "Choose a folder that Crumb should never delete."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var current = ProtectedPaths.loadUserPaths()
        let p = url.path
        if !current.contains(p) {
            current.append(p)
            ProtectedPaths.saveUserPaths(current)
            paths = ProtectedPaths.all()
            app.refreshUserProtectedPaths()
        }
    }

    private func removePath(_ path: String) {
        var current = ProtectedPaths.loadUserPaths()
        current.removeAll { $0 == path }
        ProtectedPaths.saveUserPaths(current)
        paths = ProtectedPaths.all()
        app.refreshUserProtectedPaths()
    }
}

// MARK: - Scans

private struct ScansPanel: View {
    @AppStorage(SettingsKey.scheduledScanEnabled)  private var enabled: Bool = false
    @AppStorage(SettingsKey.scheduledScanFreqDays) private var freqDays: Int = 7
    @AppStorage(SettingsKey.scheduledOnlyOnPower)  private var onlyOnPower: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelHeader(
                icon: .clock,
                title: "Scans",
                subtitle: "When and how Crumb sweeps your drives."
            )

            Card(pad: 14, tintedBg: .cHoneySoft, borderColor: .cLine2) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        IconView(icon: .clock, size: 18)
                            .foregroundStyle(Color.cCoral)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Scheduled scan")
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(Color.cInk)
                            Text(enabled
                                 ? "Runs every \(freqDays) day\(freqDays == 1 ? "" : "s") the next time you open Crumb after the window has passed."
                                 : "Off. Toggle on to have Crumb queue a scan when you next open it.")
                                .font(Theme.body(12))
                                .foregroundStyle(Color.cInk2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: $enabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    if enabled {
                        HStack {
                            Text("Run every")
                                .font(Theme.body(12))
                                .foregroundStyle(Color.cInk)
                            Stepper(value: $freqDays, in: 1...30, step: 1) {
                                Text("\(freqDays) day\(freqDays == 1 ? "" : "s")")
                                    .font(Theme.body(12, weight: .semibold))
                                    .frame(minWidth: 60)
                            }
                            .controlSize(.small)
                        }
                        Toggle(isOn: $onlyOnPower) {
                            Text("Only when plugged in")
                                .font(Theme.body(12))
                                .foregroundStyle(Color.cInk)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }

            Text("Note: scheduled scans run when the app is opened, not in the background. True background scanning needs a helper agent and is on the roadmap.")
                .font(Theme.body(11))
                .foregroundStyle(Color.cInk3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Export

private struct ExportPanel: View {
    @Bindable var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelHeader(
                icon: .download,
                title: "Export",
                subtitle: "Save the current scan as JSON for analysis or backup."
            )
            Card(pad: 14) {
                HStack(alignment: .top, spacing: 12) {
                    IconView(icon: .download, size: 18)
                        .foregroundStyle(Color.cInk2)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Export scan summary")
                            .font(Theme.body(14, weight: .semibold))
                        Text(exportBlurb)
                            .font(Theme.body(12))
                            .foregroundStyle(Color.cInk2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Export…") { exportSummary() }
                        .controlSize(.small)
                        .disabled(app.overviewTopFolders.isEmpty)
                }
            }
        }
    }

    private var exportBlurb: String {
        if app.overviewTopFolders.isEmpty {
            return "Run a scan first — Export needs scan data to write."
        }
        return "Writes top-level folders + by-file-type totals + suggestions to a single .json file."
    }

    private func exportSummary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "wimys_crumb-scan.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        struct Export: Encodable {
            struct Folder: Encodable { let name: String; let totalBytes: Int64; let items: Int64 }
            struct TypeRow: Encodable { let category: String; let totalBytes: Int64; let files: Int64 }
            struct Suggestion: Encodable { let title: String; let detail: String; let saveBytes: Int64 }
            let exportedAt: Date
            let volume: String?
            let used: Int64
            let free: Int64
            let topFolders: [Folder]
            let byFileType: [TypeRow]
            let suggestions: [Suggestion]
        }

        let payload = Export(
            exportedAt: Date(),
            volume: app.currentVolume?.name,
            used: app.overviewStats.used,
            free: app.overviewStats.free,
            topFolders: app.overviewTopFolders.map {
                Export.Folder(name: $0.name, totalBytes: $0.totalSize,
                              items: $0.descendantFileCount)
            },
            byFileType: app.overviewTypes.map {
                Export.TypeRow(category: $0.type.displayName,
                               totalBytes: $0.totalSize, files: $0.fileCount)
            },
            suggestions: app.suggestions.map {
                Export.Suggestion(title: $0.title, detail: $0.detail,
                                  saveBytes: $0.saveBytes)
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(payload)
            try data.write(to: url, options: [Data.WritingOptions.atomic])
            app.showToast("Exported to \(url.lastPathComponent)")
        } catch {
            app.showToast("Export failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - About

private struct AboutPanel: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelHeader(
                icon: .other,
                title: "About",
                subtitle: "Built on the Honey design direction. SwiftUI + GRDB."
            )
            Card(pad: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    aboutRow("Version", version)
                    Divider().overlay(Color.cLine)
                    aboutRow("Build", build)
                    Divider().overlay(Color.cLine)
                    aboutRow("Engine", "Native FileManager walk → SQLite (GRDB)")
                }
            }
        }
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.body(12))
                .foregroundStyle(Color.cInk2)
            Spacer()
            Text(value)
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Color.cInk)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shared bits

private struct PanelHeader: View {
    let icon: AppIcon
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.cCoralSoft)
                IconView(icon: icon, size: 20)
                    .foregroundStyle(Color.cCoral)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.display(24, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Color.cInk)
                Text(subtitle)
                    .font(Theme.body(13))
                    .foregroundStyle(Color.cInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

// MARK: - Detection (read-only in v1)

private struct DetectionPanel: View {
    /// Mirrors the constant in ScanEngine.swift. Kept inline here because the
    /// engine declaration is `private`; this is a read-only display in v1.
    private let largeFileThresholdBytes: Int64 = 10_000_000

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelHeader(
                icon: .sparkle,
                title: "Detection",
                subtitle: "Folder names Crumb groups across the disk, plus the large-file threshold."
            )

            // Group catalog
            VStack(alignment: .leading, spacing: 10) {
                Text("Tracked group names")
                    .font(Theme.body(14, weight: .bold))
                    .foregroundStyle(Color.cInk)

                VStack(spacing: 0) {
                    ForEach(Array(GroupCatalog.entries.enumerated()), id: \.offset) { idx, entry in
                        groupRow(entry)
                        if idx != GroupCatalog.entries.count - 1 {
                            Divider().overlay(Color.cLine)
                        }
                    }
                }
                .background(Color.cPanel)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.cLine, lineWidth: 1)
                )
            }

            // Large-file threshold
            VStack(alignment: .leading, spacing: 10) {
                Text("Large-file threshold")
                    .font(Theme.body(14, weight: .bold))
                    .foregroundStyle(Color.cInk)

                Card(pad: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        IconView(icon: .sparkle, size: 18)
                            .foregroundStyle(Color.cInk2)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("≥ \(Fmt.bytes(largeFileThresholdBytes))")
                                .font(Theme.display(20, weight: .heavy))
                                .tracking(-0.3)
                                .foregroundStyle(Color.cInk)
                            Text("Files this big or larger are kept in the per-type heaviest-files list shown on the File types screen.")
                                .font(Theme.body(12))
                                .foregroundStyle(Color.cInk2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }
            }

            HStack(spacing: 8) {
                Pill(text: "read-only", color: .cInk2, soft: .cPanel)
                Text("Editing the group list and threshold is on the v2 roadmap.")
                    .font(Theme.body(12))
                    .foregroundStyle(Color.cInk3)
            }
        }
    }

    private func groupRow(_ entry: GroupCatalog.Entry) -> some View {
        HStack(spacing: 10) {
            Text(entry.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.cInk)
            if entry.devOnly {
                Pill(text: "dev", color: .cLilac, soft: .cLilacSoft)
            }
            Spacer()
            Text(entry.tagline)
                .font(Theme.body(12))
                .foregroundStyle(Color.cInk2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Snapshots (per-scan list + delete + clear all)

private struct SnapshotsPanel: View {
    @Bindable var app: AppModel

    @State private var snapshots: [ScanStore.SnapshotInfo] = []
    @State private var loading: Bool = true
    @State private var pendingDelete: ScanStore.SnapshotInfo? = nil
    @State private var confirmClearAll: Bool = false

    private var totalBytes: Int64 {
        snapshots.reduce(0) { $0 + $1.sizeOnDisk }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelHeader(
                icon: .chart,
                title: "Snapshots",
                subtitle: "Every completed scan lives in its own SQLite file. Delete the ones you no longer need."
            )

            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading scan files…")
                        .font(Theme.body(12))
                        .foregroundStyle(Color.cInk2)
                }
            } else if snapshots.isEmpty {
                Card(pad: 14) {
                    HStack(spacing: 10) {
                        IconView(icon: .chart, size: 16)
                            .foregroundStyle(Color.cInk3)
                        Text("No scans yet — run one from the Start screen.")
                            .font(Theme.body(13))
                            .foregroundStyle(Color.cInk2)
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(snapshots) { snap in
                        snapshotRow(snap)
                        if snap.id != snapshots.last?.id {
                            Divider().overlay(Color.cLine)
                        }
                    }
                }
                .background(Color.cPanel)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.cLine, lineWidth: 1)
                )

                HStack {
                    Text("\(snapshots.count) scan\(snapshots.count == 1 ? "" : "s") · \(Fmt.bytes(totalBytes)) on disk")
                        .font(Theme.body(12))
                        .foregroundStyle(Color.cInk2)
                    Spacer()
                    Button(role: .destructive) {
                        confirmClearAll = true
                    } label: {
                        Text("Clear all scan data")
                            .font(Theme.body(12, weight: .semibold))
                    }
                    .controlSize(.small)
                }
            }
        }
        .onAppear(perform: reload)
        .alert("Delete this scan?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let snap = pendingDelete { performDelete(snap) }
                pendingDelete = nil
            }
        } message: {
            if let snap = pendingDelete {
                Text("Removes \(snap.volumeName) — \(Fmt.bytes(snap.sizeOnDisk)). The scan data is gone for good (the files themselves aren't touched).")
            }
        }
        .alert("Clear all scan data?", isPresented: $confirmClearAll) {
            Button("Cancel", role: .cancel) { }
            Button("Clear all", role: .destructive) { performClearAll() }
        } message: {
            Text("Deletes every scan database (\(Fmt.bytes(totalBytes))). Your files are untouched; only Crumb's history of them is removed.")
        }
    }

    private func snapshotRow(_ snap: ScanStore.SnapshotInfo) -> some View {
        HStack(spacing: 10) {
            IconView(icon: .chart, size: 12)
                .foregroundStyle(Color.cInk2)
            VStack(alignment: .leading, spacing: 2) {
                Text(snap.volumeName)
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Color.cInk)
                Text("\(Fmt.relative(snap.startedAt)) · \(Fmt.bytes(snap.sizeOnDisk))")
                    .font(Theme.body(11))
                    .foregroundStyle(Color.cInk2)
            }
            Spacer()
            if let used = snap.totalUsed {
                Text(Fmt.bytes(used))
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Color.cInk)
                    .monospacedDigit()
            }
            Button { pendingDelete = snap } label: {
                IconView(icon: .x, size: 11)
                    .foregroundStyle(Color.cInk2)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Delete this scan")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func reload() {
        loading = true
        Task.detached {
            let store = ScanStore()
            let snaps = store.loadSnapshots()
            await MainActor.run {
                snapshots = snaps
                loading = false
            }
        }
    }

    private func performDelete(_ snap: ScanStore.SnapshotInfo) {
        let wasCurrent = app.isCurrentScanDatabase(snap.url)
        // Drop AppModel's open DatabasePool BEFORE deleting the file. If we
        // unlink while GRDB still holds a writer handle, SQLite's lock /
        // WAL state can leak into the next scan and surface as a confusing
        // disk I/O error on the very first INSERT.
        if wasCurrent { app.handleDeletedCurrentScan() }
        let store = ScanStore()
        store.deleteSnapshot(snap.url)
        snapshots.removeAll { $0.id == snap.id }
        app.refreshRecentScans()
    }

    private func performClearAll() {
        let hadCurrent = app.currentScanDatabaseURL != nil
        // Same ordering rule as performDelete above.
        if hadCurrent { app.handleDeletedCurrentScan() }
        let store = ScanStore()
        store.clearAllSnapshots()
        snapshots = []
        app.refreshRecentScans()
    }
}
