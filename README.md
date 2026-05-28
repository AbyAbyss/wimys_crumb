# wimys_crumb

A friendly disk-space scanner for macOS — finds where your space went, groups
similar things (every `node_modules`, every `DerivedData`), and lets you delete
the reclaimable bits safely. Built for everyday users first, developers second.

The full build spec is in
[`wimys_crumb-implementation-plan.md`](wimys_crumb-implementation-plan.md).

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Build and run

The Xcode project is generated from `project.yml`, so it isn't committed:

```
xcodegen generate
open wimys_crumb.xcodeproj
```

Then ⌘R to run. The app launches to the Start screen and lists your mounted
volumes. Click **Scan Macintosh HD** (or any volume's per-row Scan button).

Regenerate the project any time you add, remove, or rename files:

```
xcodegen generate
```

## Project layout

```
wimys_crumb/
  WimysCrumbApp.swift     App entry + WindowGroup + screen router
  Theme.swift             Honey palette, font loader, spacing
  AppModel.swift          @Observable @MainActor — state + navigation + scan wiring
  Models/
    UIModels.swift        Plain Sendable value types — DirRow, GroupRow, etc.
    MockData.swift        Sample data for previews / empty states
  Engine/
    ScanDatabase.swift    GRDB stack + migrations (per-scan SQLite file)
    ScanDatabaseQueries.swift  All query helpers + patchAfterDelete
    ScanStore.swift       Filesystem layout for scan DBs + retention + vacuum
    ScanEngine.swift      Streaming filesystem walk → SQLite writer
    Aggregator.swift      Post-scan rollups
    Suggestions.swift     "Quick wins" rule pass
    GroupCatalog.swift    Known names + taglines for the Groups screen
    HistoryLoader.swift   Cross-scan summary + diff loader
    DeleteService.swift   The only place that calls FileManager.trashItem
    FileTypeClassifier.swift  Extension → 8-bucket category map
    PathResolver.swift    Reconstruct full path from dir id (LRU-cached)
    BoundedMinHeap.swift  Top-N helper used by the walk
    Settings.swift        @AppStorage keys + protected paths catalogue
  Components/
    BrandBar / Card / Pill / DonutView / ProgressBarView / ToastView /
    ToggleSwitch / TreemapView / IconView
  Screens/
    StartView · ScanningView · OverviewView · DrillView · GroupsView ·
    TypesView · HistoryView · SettingsView · DeleteSheet · PlaceholderScreens
  Resources/
    Fonts/                Drop Bricolage Grotesque + Geist .ttf files here
    Assets.xcassets/      App icon set
```

## Releasing

Releases are tag-driven via
[`.github/workflows/release.yml`](.github/workflows/release.yml). Push a
version tag and CI builds, packages a `.dmg`, and publishes a GitHub Release:

```
git tag v0.1.0
git push origin v0.1.0
```

What the workflow does for that tag:

1. `xcodegen generate` from the committed `project.yml`.
2. `xcodebuild -configuration Release` — produces `wimys_crumb.app`. Unsigned
   (ad-hoc) for now, so first launch on another Mac needs a one-time approval
   under **System Settings → Privacy & Security → Open Anyway**.
3. `hdiutil create` — bundles the app + an `Applications` symlink into
   `wimys_crumb-<version>.dmg`.
4. `gh release create` — drafts a release titled `wimys_crumb <version>` with
   auto-generated notes from the commits since the previous tag.

The version comes from the tag (`v0.1.0` → `0.1.0`), and `CURRENT_PROJECT_VERSION`
is the GitHub Actions run number so two builds for the same tag don't collide.

### Re-running a failed release

If the workflow fails partway through, delete the tag locally + remotely and
re-tag:

```
git tag -d v0.1.0
git push origin :refs/tags/v0.1.0
# fix the issue, commit
git tag v0.1.0 && git push origin v0.1.0
```

### Code signing (future)

The workflow currently builds unsigned. To produce a notarized DMG, you'll
need a Developer ID certificate + an Apple ID app-specific password stored as
GitHub Secrets, plus extra `codesign` and `xcrun notarytool submit` steps
between **Build Release** and **Package DMG**. Not wired yet — keep an eye on
this section as it grows.

## Status

All screens from `wimys_crumb-implementation-plan.md` are implemented; the
plan's §20 Definition of Done is met. Roadmap items (background scheduled
scans via launchd, real snapshot quarantine, duplicate detection by content
hash, per-app cleanup recipes) live in the plan's §19 / §16.

## Fonts

Bricolage Grotesque + Geist + Geist Mono aren't bundled yet — drop their
`.ttf` files into `wimys_crumb/Resources/Fonts/` (see the README in that
folder for sources). Until you do, calls to `Theme.body(...)` /
`Theme.display(...)` quietly fall back to the system font.

## License

TBD.
