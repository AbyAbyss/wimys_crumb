# wimys_crumb - Implementation Plan (macOS / SwiftUI)

A friendly disk-space scanner for macOS. **Where Is My Space - crumb.** This is
the single, complete build spec for a coding agent (Claude Code). It supersedes
all earlier drafts. Use it together with the **design bundle zip**
(`where-is-my-disk-space-d`), which contains the HTML/CSS/JS prototype that
defines the exact visuals.

This document is self-contained. There are no references to other plan files.
Where the design zip is the source of truth (exact pixel values, colors), this
document says so explicitly.

---

## 0. How to use this document

1. You have two inputs: this plan, and the design bundle zip.
2. Extract the zip. Read `where-is-my-disk-space-d/README.md`, then the chat
   transcript in `chats/`, then `project/prototype.html` and every JSX file it
   imports. The chat carries the intent; the JSX carries exact pixel values.
3. The prototype is HTML/CSS/JS. Your job is to recreate the **visual output**
   in SwiftUI, not to copy the prototype's React structure. Match the look;
   structure it the SwiftUI way.
4. Do not render the prototype in a browser or screenshot it. Read the source.
   Colors, sizes, and layout are all in the JSX.
5. The visual target is the **"Honey"** direction. `project/prototype.html` is
   the target. `project/crumb.html` is an earlier two-direction exploration;
   ignore it.
6. Build in the phases in section 16. Each phase has acceptance criteria. Do
   not skip ahead. The memory budget in section 14 is a hard requirement, not a
   nice-to-have.

---

## 1. Product summary

wimys_crumb scans a Mac and shows where disk space goes at every level (disk,
folder, file type), groups folders by name across the whole system (for example
all `node_modules` totalled), and lets the user safely delete reclaimable space.
It serves everyday users first, developers second. Nine screens:

1. **Start** - drive list, scan entry point
2. **Scanning** - live scan progress
3. **Overview** - treemap dashboard, stats, quick wins
4. **Drill-down** - folder contents with a detail panel
5. **Groups** - folders grouped by name across the disk
6. **Delete** - confirmation sheet with protected-path skipping
7. **File types** - breakdown by file category
8. **History** - usage over time, snapshots, what changed
9. **Settings** - safety rules, scheduled scans, protected paths

---

## 2. Key decisions

### 2.1 Identity

- **App name (display):** wimys_crumb
- **Wordmark in the brand bar:** "crumb" (the prototype's wordmark). The full
  `wimys_crumb` is the product/bundle name; the UI shows the short "crumb".
- **Bundle identifier:** `app.wimys.crumb`
- **Product/target name in Xcode:** `wimys_crumb`

### 2.2 Distribution model: non-sandboxed, notarized (default)

A true whole-system scan requires a **non-sandboxed** app distributed as a
notarized Developer ID `.dmg`. This is the recommended path; the core value
(scanning the whole drive, finding `node_modules` everywhere, surfacing system
caches) is crippled by the App Sandbox.

If App Store distribution is required instead, switch to **sandboxed**: the app
can then only scan folders the user grants via `NSOpenPanel` plus
security-scoped bookmarks. That changes the Start screen ("choose a folder to
scan" rather than "scan Macintosh HD") and narrows the scan engine to bookmarked
URLs. The rest is unchanged. **This plan assumes non-sandboxed, notarized.**

### 2.3 Other fixed decisions

- **Language / UI:** Swift, SwiftUI. AppKit only where SwiftUI lacks a
  capability (window config, `NSWorkspace`, `NSOpenPanel`, `NSSavePanel`).
- **Minimum OS:** macOS 14 (Sonoma). Gives `@Observable`, modern `Canvas`,
  `ContentUnavailableView`.
- **Window:** native resizable `NSWindow`. The prototype's faux title bar (fake
  traffic lights, fixed 1280x820 canvas, scale-to-fit) is a prototype artifact.
  Do **not** reproduce it. Use the real macOS title bar; the crumb brand bar and
  tab strip live inside the content below it.
- **Default / minimum window size:** 1280x820 default, 1100x740 minimum.
- **Fonts:** bundle the real fonts (section 15). Do not substitute SF Pro.
- **Storage / engine:** SQLite via GRDB. Streaming aggregation, no in-memory
  file tree. This is the heart of the app and is specified in sections 9 to 14.
- **No other dependencies.** GRDB is the only third-party package. Charts (the
  History chart) uses Apple's built-in `Charts` framework or a custom `Canvas`.

---

## 3. Project setup

- Xcode app project, product name `wimys_crumb`, interface SwiftUI, language
  Swift, SwiftUI App lifecycle.
- Bundle id `app.wimys.crumb`. Deployment target macOS 14.0.
- App Sandbox **off** (per 2.2).
- `Info.plist`: add `NSDesktopFolderUsageDescription`,
  `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, and
  a clear app-purpose string. Full Disk Access is handled at runtime (12.3), not
  via Info.plist.
- Add GRDB via Swift Package Manager (`github.com/groue/GRDB.swift`). If a
  zero-dependency policy is mandated, use the system `import SQLite3` C API
  instead; expect 200 to 400 extra lines of binding boilerplate.
- Bundle the fonts and register via `ATSApplicationFontsPath` or load at launch
  with `CTFontManagerRegisterFontsForURLs`.

---

## 4. Architecture

Lean and functional. Value-typed models, one observable app model, an actor for
the engine, SQLite as the single source of truth for scan data.

```
wimys_crumb/
  WimysCrumbApp.swift         App entry, WindowGroup, window sizing, font load
  Theme.swift                 Honey palette, fonts, spacing, shadows
  AppModel.swift              @Observable @MainActor: navigation + UI state +
                              action methods. Holds NO scan tree. Reads queries.
  Models/
    UIModels.swift            DirRow, GroupRow, FileTypeTotal, LargeFileRow,
                              ScanProgress, Snapshot, DeleteTarget, Toast,
                              Suggestion. Plain Sendable value types.
    MockData.swift            Mock instances matching shared.jsx, for previews
                              and the pre-first-scan empty states only.
  Engine/
    ScanDatabase.swift        GRDB stack, schema, migrations, query helpers.
    ScanEngine.swift          actor: streaming filesystem walk -> SQLite.
    Aggregator.swift          post-scan bottom-up total_size; post-delete patch.
    GroupQueries.swift        group-by-name SQL + instance queries.
    FileTypeClassifier.swift  extension -> 8 categories (static table).
    DeleteService.swift       trash / permanent delete + protected guard +
                              SQLite patch after delete.
    Suggestions.swift         quick-wins rules pass over the scan database.
    PathResolver.swift        parent-chain path reconstruction + LRU cache.
    Settings.swift            @AppStorage-backed preferences + protected paths.
    ScanStore.swift           manages scan .sqlite files: list, prune, vacuum.
  Components/
    Card, Pill, ProgressBarView, DonutView, ToggleSwitch, ToastView,
    TreemapView, BubbleChartView, UsageChartView, StackedTypeBar, BrandBar
  Screens/
    StartView, ScanningView, OverviewView, DrillView, GroupsView,
    DeleteSheet, TypesView, HistoryView, SettingsView
```

### 4.1 Layering rules

- **Models** are plain `struct`s, `Sendable`, value types. They are query-result
  shapes, not a live object graph. There is no `ScanNode` tree held in memory.
- **Engine** is the only code that touches the filesystem or SQLite. `ScanEngine`
  is an `actor`. It reports progress via `AsyncStream<ScanProgress>`.
- **AppModel** is `@Observable`, `@MainActor`. It owns navigation state, the
  currently displayed query results, selections, the toast, and action methods.
  After any data-changing operation (scan complete, delete), it **re-runs the
  relevant query** to refresh, rather than mutating a cached tree. See 7.2.
- **Views** render `AppModel` and call its actions. No filesystem, no SQLite, no
  business logic in views.

This mirrors the prototype: `makeInitState` -> `AppModel` initial state,
`set(patch)` -> direct property mutation, the screen router -> a `switch` on
`AppModel.screen`. The difference is that lists of folders/groups/files come
from SQLite queries, not from a JS array literal.

---

## 5. Design system (Theme.swift)

All values come from `project/a-base.jsx`. Treat that file as the source of
truth and read it for anything not listed here.

### 5.1 Color palette ("Honey")

Static `Color` values. Hex from `a-base.jsx`:

| Token      | Hex       | Use                          |
|------------|-----------|------------------------------|
| bg         | #FBF6EC   | page background              |
| paper      | #FFFFFF   | card / surface               |
| panel      | #F4ECDA   | muted surface, footers       |
| ink        | #2A2118   | primary text                 |
| ink2       | #7C6F5F   | secondary text               |
| ink3       | #B5A48E   | tertiary text                |
| line       | #E8DFCC   | default border / track       |
| line2      | #D7C9AA   | stronger border              |
| coral      | #E55934   | primary accent               |
| coralSoft  | #FDE3DA   | coral tint background        |
| honey      | #F3B95F   | secondary accent             |
| honeySoft  | #FBE9C6   | honey tint background        |
| sage       | #5FA37C   | success / "free" / shrinkers |
| sageSoft   | #D8ECDD   | sage tint                    |
| lilac      | #9E8FCF   | "dev" tag                    |
| lilacSoft  | #E8E2F5   | lilac tint                   |
| navy       | #2C3E66   | viz hue                      |
| navySoft   | #D9DFEB   | navy tint                    |
| red        | #C9412A   | danger / stale / protected   |
| redSoft    | #F6D9D2   | red tint                     |

- **Visualization hue ring** (`A_HUES`), used in order for treemap tiles, file
  types, legends: `[coral, honey, sage, lilac, navy, #D86A8A, #7BAFD4]`.
- Window canvas behind content: #E8DECB with an optional faint radial dot
  pattern (1px dots, 24px grid, ~7% ink). Optional polish.

### 5.2 Typography

Three bundled families (section 15):

- **Bricolage Grotesque** - display, weights 500 to 800. Wordmark, big numbers,
  headings, card titles with personality.
- **Geist** - body / UI, weights 400 to 700. Default for body, labels, buttons.
- **Geist Mono** - monospace, weights 400 to 600. Paths, the live scan path.

Provide `Theme.display(size:weight:)`, `Theme.body(...)`, `Theme.mono(...)`.
Apply tight negative tracking on large display text (roughly -0.4 to -3 scaling
with size; read exact values per heading from the JSX).

### 5.3 Spacing, radius, shadow

- Card radius 16, button radius 8 to 12, pill radius 999 (capsule).
- Card border 1px `line`; card shadow a hairline (`0 1px 0 line`). Modal shadow
  heavier (`0 30px 80px` at ~25% ink).
- Standard screen content padding 20 horizontal, 20 bottom. Gaps between cards
  14.

### 5.4 Reusable components (Components/)

Specs from `a-base.jsx`:

- **Card** - paper bg, 1px `line` border, radius 16, default padding 18,
  hairline shadow. Tinted variant (Quick Wins uses `honeySoft`).
- **Pill** - capsule, padding ~3x9, 11px weight-600. Soft (tinted bg, colored
  text) and solid (colored bg, paper text) modes.
- **ProgressBarView (Bar)** - rounded track in `line`, colored fill, height 4 to
  10. Fill is a percentage.
- **DonutView** - ring via `Circle().trim` or `Canvas`. Configurable size,
  stroke, color, track, centered percent label. Used on Start drives.
- **ToggleSwitch** - custom 36x20 capsule, 16x16 knob, accent when on, `line2`
  off. Do not use stock SwiftUI `Toggle` styling; match the prototype.
- **ToastView** - dark (`ink`) capsule pinned bottom-center, sage check circle,
  message, optional action (Undo in `honey`). Auto-dismiss (6s default, 8s for
  delete). Slide-up + fade in.

---

## 6. App shell and navigation

### 6.1 Window and layout

`WimysCrumbApp.swift` makes one `WindowGroup` with sizes from 2.3. Layout:

```
[ native macOS title bar ]
[ BrandBar:  crumb logo | tab strip | (Rescan) | drive picker | cog ]
[ Body: active screen, subtle fade on change ]
[ overlays: DeleteSheet, ToastView ]
```

Screen changes get a 0.25s ease fade plus a tiny upward translate (the
prototype's `aScreenIn`).

### 6.2 BrandBar (Components/BrandBar.swift)

From `proto-shell.jsx` `IAppBar`:

- Left: a 32x32 rounded-10 `coral` square with the "crumb dot trio" (three small
  offset circles in honey / paper / honeySoft), then the wordmark "crumb" in
  Bricolage 800, 22px. Clicking the logo goes to Start.
- Tab strip (hidden on Start and Scanning): a `paper` pill container with four
  tabs - Overview, Groups, File types, History. Active tab has `ink` bg and
  `paper` text. The Overview tab stays active for both Overview and Drill.
- Right: a "Rescan" button (refresh icon, hidden on Start/Scanning), a drive
  picker showing the current drive with a chevron, and a 38x38 cog that opens
  Settings (tinted `coralSoft`/`coral` when Settings is open).

### 6.3 Navigation model

```swift
enum Screen { case start, scanning, overview, drill, groups, types, history, settings }
```

Methods on `AppModel`, mirroring `nav` in `proto-app.jsx`:
`goToStart()` (resets scan + selections), `startScan(volume:)` (sets `.scanning`,
resets progress, kicks the engine), `goToOverview()`, `goToGroups()`,
`goToTypes()`, `goToHistory()`, `drillInto(dirId:)` (sets `.drill`, loads the
breadcrumb and that folder's children query), `openSettings()`. Tab taps route
to the matching screen.

---

## 7. State model (AppModel)

`@Observable @MainActor`. Holds **no scan tree**. Properties:

- **Navigation:** `screen`, `currentVolume` (id, name, capacity values).
- **Scan:** `scanProgress` (0 to 1), `isScanning`, `isPaused`,
  `currentScanPath`, `filesScanned`, `etaSeconds`, `biggestSoFar`
  (`[DirRow]`, small, see 10.4).
- **Overview:** `overviewTopFolders` (`[DirRow]`), `overviewStats`
  (used/free/items/couldFree), `overviewTypes` (`[FileTypeTotal]`),
  `suggestions` (`[Suggestion]`).
- **Drill:** `drillCrumb` (`[(id, name)]`), `drillItems` (`[DirRow]`, the result
  of the latest children query), `drillSelection` (`Set<Int64>` of dir ids),
  `drillDetail` (the `DirRow` shown in the detail panel), `showHidden` (Bool).
- **Groups:** `groups` (`[GroupRow]`), `expandedGroup` (name?),
  `expandedInstances` (`[DirRow]` for the open group), `groupsSelection`
  (`Set<Int64>`), `groupsStaleOnly` (Bool).
- **Types:** `typeTotals` (`[FileTypeTotal]`), `selectedType`,
  `selectedTypeFiles` (`[LargeFileRow]`).
- **History:** `snapshots` (`[Snapshot]`), `usageSeries` (`[(Date, Int64)]`),
  `growers`/`shrinkers` (`[(path, deltaBytes)]`).
- **Delete:** `deleteSheetOpen`, `deleteTargets` (`[DeleteTarget]`), `deleteKind`
  (`.trash` / `.forever`), `takeSnapshot` (Bool).
- **Toast:** optional `Toast`.
- **Session totals:** `freedBytes`.
- **Settings:** `settingsSection`, the five safety toggles, `protectedPaths`
  (path + isSystem), scheduled-scan config.

### 7.1 Data source: everything is a query

`overviewTopFolders`, `drillItems`, `groups`, `expandedInstances`,
`typeTotals`, `selectedTypeFiles`, `snapshots`, `usageSeries`,
`growers`/`shrinkers` are **all populated by running a SQL query** against the
current scan database (queries in section 11). They are caches of a query
result, refreshed by re-querying, never hand-mutated to stay "in sync".

### 7.2 Refresh-by-requery (the seam fix)

After any operation that changes the data (scan completion, a delete), the
`AppModel` does **not** patch its arrays element by element. It re-runs the
query that produced the currently visible list. Concretely:

- Scan completes -> `loadOverview()` runs the Overview queries and assigns.
- A delete succeeds -> `DeleteService` patches the database (8.6, 11), then
  `AppModel` calls the loader for whatever screen is visible
  (`loadDrill(dirId:)`, `loadGroups()`, `loadTypes()`, `loadOverview()`), plus
  always refreshes `overviewStats.freedBytes`.

This keeps the UI and the database consistent with one code path and no
divergence bugs.

### 7.3 Undo

For `.trash` deletes, Undo restores from the macOS Trash (the OS keeps the
files; `DeleteService` returns the resulting Trash URLs). On Undo: move the items
back with `FileManager`, then re-insert their rows into SQLite (the deleter
stashed the deleted rows in memory for the toast's lifetime) and re-run the
ancestor aggregation patch, then refresh the visible screen. For `.forever`
deletes there is no Undo; the toast omits the action.

---

## 8. Screen specifications

Each screen lists purpose, layout, interactions, acceptance. For exact spacing,
font sizes, and colors, read the matching prototype file. The prototype uses
mock data; the real app renders real query results, falling back to `MockData`
only in previews and before the first scan.

### 8.1 Start (`proto-start-scan.jsx` -> StartView.swift)

- **Layout:** two columns ~1.4 : 1.
- **Left hero card:** soft diagonal gradient `honeySoft` -> `coralSoft` with a
  faint dotted texture. A "Ready to scan" pill, the headline "Where did your
  space go?" in Bricolage 800 (~56px, two lines), a one-line subhead, a primary
  "Scan Macintosh HD" button (dark `ink`, pressed-down shadow), and a "Pick a
  specific folder..." text link.
- **Right drives card:** mounted volumes. Each row: a 56px donut (percent used),
  drive name, "X used of Y - kind", a "Scan" button. A drive over 85% full shows
  an "almost full" red pill and a red donut. Below, a "Last scans" list (from
  `ScanStore`, tappable, loads that scan's Overview).
- **Real data:** enumerate volumes with
  `FileManager.mountedVolumeURLs(includingResourceValuesForKeys:)`; read
  `.volumeTotalCapacityKey` / `.volumeAvailableCapacityKey` /
  `.volumeNameKey` / `.volumeUUIDStringKey`. The boot volume is the primary
  target. "Pick a specific folder" opens an `NSOpenPanel` (directories only) and
  scans that subtree.
- **Acceptance:** real volumes with correct sizes; scan buttons start a scan of
  that volume; recent scans come from `ScanStore` (the list of `.sqlite` files).

### 8.2 Scanning (`proto-start-scan.jsx` -> ScanningView.swift)

- **Layout:** two columns ~1.2 : 1.
- **Left progress hero:** a "Scanning"/"Paused" pill with a pulsing dot, heading
  "Sweeping {drive}", a very large percent in Bricolage ~84px, a progress bar, a
  "{done} / {total} files" line and an ETA, a monospace box with the path being
  scanned, and Pause / Cancel controls. (Drop the prototype's "Skip animation";
  there is no fake animation in the real app.)
- **Right "Biggest so far":** a live list of the largest folders found, each
  with a colored folder icon, name, size, bar. A "live" pill. A hint line that
  updates as the scan progresses.
- **Real data:** the engine streams `ScanProgress` (fraction, files scanned,
  current path). `biggestSoFar` is read from SQLite during the scan (WAL allows
  reads mid-write) every ~1s: `SELECT ... FROM dirs ORDER BY total_size DESC
  LIMIT 6` over the partial data, or, if `total_size` is not yet aggregated
  mid-scan, from `own_size` of the dirs flushed so far. Pause suspends the
  engine; Cancel stops it and returns to Start. Completion routes to Overview
  and fires a "Scan complete" toast.
- **Acceptance:** progress is driven by the real engine, not a timer; Pause and
  Cancel work; the biggest list updates during the scan from SQLite; completion
  routes to Overview.

### 8.3 Overview (`proto-overview-drill.jsx` -> OverviewView.swift)

- **Layout:** a top row of four stat cards, then ~1.6 : 1.
- **Stat cards:** Used, Free, Items scanned, and a dark CTA card ("Could free
  X" before cleanup, "Freed so far" after). The Used card carries a "+X this
  week" delta pill (from the two most recent snapshots; omit if only one scan
  exists). The CTA navigates to Groups.
- **Main left treemap card:** `TreemapView` of top-level folders, legend below.
  A tile click drills in.
- **Main right two cards:** a "By file type" mini-list (top 6 with bars) and a
  "Quick wins" card (`honeySoft`) listing suggestions; each opens the Delete
  sheet preloaded with targets.
- **TreemapView:** split items into top 3 and the rest; two rows height-
  proportional to their size sums; within a row, tiles flex by size; colors from
  `A_HUES`; show name, size, and a shield if protected. See `ITreemap` for exact
  split logic.
- **Real data:** stats and treemap from Overview queries (11). Suggestions from
  `Suggestions.swift` (13). "Items scanned" is `scans.file_count`.
- **Acceptance:** treemap reflects the real top-level breakdown; tiles drill in;
  stat cards update after a delete; quick wins open the delete sheet.

### 8.4 Drill-down (`proto-overview-drill.jsx` -> DrillView.swift)

- **Layout:** a clickable breadcrumb row, then ~1fr : 280px.
- **Left content list:** header with folder name, item count, total size, a
  "Show hidden" checkbox. Rows: a checkbox, an icon (folder, or a distinct
  "hidden" icon for dot-folders; red-tinted if stale), name + subtitle (item
  count, "stale" if not modified in 180+ days), a size bar, the age, the size.
  Footer shows selected count and total with a Delete button.
- **Right detail panel:** a gradient header tile, the selected item's name and
  full path (from `PathResolver`), a metadata table (Size, Items, Last modified,
  Kind, Permissions), and "Reveal in Finder" + "Delete this folder".
- **Behavior:** a row click sets `drillDetail`; the checkbox is independent and
  feeds the footer selection; "Show hidden" filters dot-folders; Delete opens
  the sheet with selected items.
- **Real data:** `drillItems` is the children query for the current dir id (11).
  Path display via `PathResolver`. "Reveal in Finder" via
  `NSWorkspace.activateFileViewerSelecting`. Drilling into a folder runs the
  children query for its id.
- **Acceptance:** breadcrumb navigates up (re-queries each level); checkboxes
  drive the footer; the detail panel reflects the clicked row; hidden folders
  honor the toggle; delete routes to the sheet.

### 8.5 Groups (`proto-groups-settings.jsx` -> GroupsView.swift)

- **Layout:** a bubble-chart hero card, then a group-list card.
- **Bubble hero:** circles sized by each group's total (radius scales with the
  square root of total), scattered, colored from the hue ring; a bubble click
  expands that group; the selected bubble gets an `ink` stroke. See
  `computeBubbles`. Draw with `Canvas` or stacked `Circle`s; positions can be a
  fixed layout matching the prototype or a deterministic packing.
- **Group list:** rows of a checkbox, chevron, group name (monospace) + optional
  "dev" pill, a tagline, the folder count, the average age, a bar, the total.
  Expanding reveals instances (path via `PathResolver`, age, bar, size,
  checkbox). A "Stale only" filter shows groups with average age over 90 days.
  Selecting instances reveals a floating "Free X" bulk-delete button.
- **Real data:** `GroupQueries.swift` (11) produces `GroupRow`s by grouping
  `dirs` on `name` for the known group names. Expanding runs the instances query.
- **Acceptance:** groups are real cross-disk aggregates; bubbles size correctly;
  expand shows real instances; the stale filter works; bulk delete opens the
  sheet with selected instances.

### 8.6 Delete sheet (`proto-groups-settings.jsx` -> DeleteSheet.swift)

- A centered modal ~580px wide over a dimmed blurred backdrop.
- **Header:** a trash icon tile, "Delete N items?", and the space-freed line. If
  any target is protected, a red banner explains protected paths are skipped.
- **Target list:** icon, path (monospace), age, size per row. Protected rows are
  dimmed, struck through, labelled "Skipped - system protected".
- **Options:** a Trash / Forever radio pair ("Move to Trash - recoverable" vs
  "Delete forever - no undo") and a "Take snapshot first" checkbox.
- **Actions:** Cancel, and a confirm button "Move N - free X" / "Delete N -
  free X". Disabled if every target is protected.
- **Behavior:** confirming calls `DeleteService` (10). On success: fire a toast
  ("Freed X - N items moved to Trash / deleted", with Undo when kind is Trash),
  update `freedBytes`, and **refresh the visible screen by re-query** (7.2). The
  database is patched by `DeleteService` (rows removed, ancestor `total_size`
  re-aggregated) before the refresh.
- **Acceptance:** protected paths are always excluded from the actual delete;
  Trash deletes are recoverable via Undo; Forever requires the kind to be
  explicitly chosen and never touches protected paths; totals and lists update
  live via re-query.

### 8.7 File types (`proto-types-history.jsx` -> TypesView.swift)

- **Layout:** a stacked-bar hero, then ~1fr : 400px.
- **Stacked bar:** all eight categories as segments, flex-sized by total,
  clickable; the selected segment gets an `ink` outline.
- **Left type grid:** a two-column grid of type cards (icon tile, name, file
  count, percent of disk, size, a bar). A card click selects that type.
- **Right detail panel:** a tinted header for the selected type, then the
  heaviest files in that category (name, location via `PathResolver`, age,
  "stale" tag, size). A "Clean stale {type}" button opens the delete sheet with
  the stale files preloaded; a "Show all in Finder" button.
- **Categories:** Video, Photos, Code, Apps, Documents, Music, Archives, Other.
  See `FILE_TYPES` / `TYPE_SAMPLES`.
- **Real data:** `typeTotals` from `file_type_totals` (11); `selectedTypeFiles`
  from `large_files` filtered by type (11). Classification in
  `FileTypeClassifier.swift` (13).
- **Acceptance:** categories reflect the real scan; selecting a type updates the
  panel; "Clean stale" opens the delete sheet with real stale files.

### 8.8 History (`proto-types-history.jsx` -> HistoryView.swift)

- **Layout:** a chart card, then ~1fr : 1.4fr.
- **Chart:** a 30-day disk-usage area chart, coral line, soft area fill; hover a
  day to show usage; "today" marked. Two stats: today's usage and the 30-day
  change. Use Apple's `Charts` or a custom `Canvas` for `UsageChartView`.
- **Left snapshots list:** past scans, each with date, usage, delta, and
  Compare / Restore actions.
- **Right "What changed in the last week":** Growers (paths that grew, red, up
  arrows) and Shrinkers (paths that shrank, sage, down arrows), each with a
  magnitude bar.
- **Real data:** History needs persistence. Each completed scan writes a
  snapshot row and `snapshot_top_folders` rows (12). `usageSeries` is built from
  `scans` rows. Growers/shrinkers diff the two most recent scans'
  `snapshot_top_folders`. With fewer than two scans, show an honest empty state
  ("History builds up as you scan over time") rather than fabricated data.
- **Acceptance:** the chart reflects real recorded scans; with fewer than two
  scans an honest empty state shows; Compare is wired; Restore may be a clearly
  labelled stub in v1.

### 8.9 Settings (`proto-groups-settings.jsx` -> SettingsView.swift)

- **Layout:** a 210px sidebar and a content panel.
- **Sidebar:** Scans, Detection, Safety, Snapshots, Export, About.
- **Safety panel:** five toggles - Protect system paths, Protect active
  projects, Confirm large deletes, Always snapshot first, Allow deleting hidden.
  Below, a "Protected paths" list: system paths (locked, red "system" pill) and
  user paths (removable). "Add path" appends a user path via `NSOpenPanel`.
- **Scans panel:** the scheduled-scan card (frequency, next run, "only when
  plugged in") with a toggle.
- **Snapshots panel:** lists scan databases with their sizes (from `ScanStore`),
  per-scan delete, and "Clear all scan data".
- **Export panel:** exports the current scan as CSV and/or JSON via
  `NSSavePanel` (real, not a stub).
- **About panel:** version, license, font credits.
- **Detection panel:** group-name list and large-file threshold; can be a v1
  read-only or simple editable panel.
- **Persistence:** all settings via `@AppStorage` / `UserDefaults`. User
  protected paths stored as a JSON array; system protected paths are compiled in.
- **Acceptance:** toggles persist across launches; user protected paths add and
  remove; system protected paths cannot be removed; the protected list is what
  `DeleteService` actually consults; Export writes a real file; Snapshots panel
  reflects and manages real `.sqlite` files.

---

## 9. Why the engine is SQLite-streaming (read before coding)

A typical macOS volume has 3 to 5 million files. Holding any per-file Swift
object across the whole scan is fatal: even a lean struct with `URL`, name,
`Date`, and an enum is hundreds of bytes once Foundation's URL caching and heap
overhead are counted, so five million of them is multiple GB before anything
else. A naive in-memory tree is exactly why an earlier attempt climbed past
12GB.

**Hard rule:** the engine never keeps per-file Swift objects past the directory
they live in. Per-file data is folded into the parent directory's counters and
discarded inside the same loop iteration. Anything that must survive the scan
goes into SQLite, not Swift memory. The only file-level rows that ever persist
are a small bounded `large_files` set for the "heaviest files" UI.

---

## 10. Scan engine (Engine/ScanEngine.swift)

The core of the product. Real, not mocked. Single writer; no multi-thread
fan-out in v1 (I/O dominates; one writer keeps it simple).

### 10.1 Walk

`FileManager.enumerator(at:includingPropertiesForKeys:options:errorHandler:)`
with **only** these keys:
`.isDirectoryKey, .isHiddenKey, .isPackageKey, .isSymbolicLinkKey,
.totalFileAllocatedSizeKey, .contentModificationDateKey, .nameKey`.
Options: `.skipsPackageDescendants`, `.producesRelativePathURLs`. Skip symlinks
explicitly (`.isSymbolicLinkKey`) to avoid cycles and double counting. Treat
`.isPackageKey == true` as a leaf (one item; do not descend), matching Finder.

Read each entry's resource values, then **drop the URL**. The only persistent
identity is the integer `dirs.id` assigned at insert.

### 10.2 In-memory state during walk (the entire working set)

- **`pathStack`**: currently-open directories as
  `(id, name, ownSize, fileCount, childDirCount, perTypeCounts[8])`. Real depth
  is rarely above 30; a few KB.
- **`writeBuffer`**: pending `DirRow`/`LargeFileRow` inserts, flushed every
  ~2000 rows in a transaction.
- **`topFilesByType[8]`**: a bounded min-heap per type, cap ~500 each. A new file
  beating the heap minimum replaces it. ~500KB total.
- **`globalTypeTotals[8]`**: (size, count) per type. Trivial.

No file objects, no full-path strings, no URL retention. If any structure grows
with the number of files, it is a bug.

### 10.3 Per-entry logic

- Symlink: skip.
- Directory (not a skipped package descendant): assign a new id, append a
  partial `dirs` row to the buffer (name, parent_id, depth, mtime, is_hidden,
  is_package, zero aggregates), push onto `pathStack`. Maintain the stack by
  comparing depth (from relative path components): when depth jumps up, pop and
  flush popped dirs; same or deeper, push/sibling.
- File: classify the extension into one of 8 types via a static dictionary
  (no allocation in the hot path). Increment the top-of-stack `ownSize`,
  `fileCount`, `perTypeCounts[type]` and the `globalTypeTotals[type]`. If
  `size >= LARGE_FILE_THRESHOLD` (start 10MB) or it beats `topFilesByType[type]`
  minimum, push into that heap (drop the min if at cap).

### 10.4 Leaving a directory (flush)

When a dir pops off `pathStack`: update its buffered `dirs` row with `own_size`,
`file_count`, `child_dir_count`; discard the in-memory entry. The Scanning
screen's `biggestSoFar` is a separate ~1s read query (8.2), not this stack.

### 10.5 Batch writes

Every ~2000 buffered rows: one transaction, prepared-statement inserts, commit,
clear. Progress: count files in the loop; push a `ScanProgress` onto the
`AsyncStream` every ~100ms (throttle, never per file). The "currently scanning"
path is the reconstructed top of `pathStack`.

### 10.6 Post-scan aggregation (Aggregator.swift)

After the walk:

1. **Bottom-up total_size**, for `depth` from max down to 0:
   ```sql
   UPDATE dirs SET
     total_size = own_size + COALESCE(
       (SELECT SUM(total_size) FROM dirs c WHERE c.parent_id = dirs.id), 0),
     descendant_file_count = file_count + COALESCE(
       (SELECT SUM(descendant_file_count) FROM dirs c WHERE c.parent_id = dirs.id), 0)
   WHERE depth = ?;
   ```
   ~max_depth queries (about 30), each fast via `idx_dirs_parent` /
   `idx_dirs_depth`.
2. **Flush `topFilesByType`** into `large_files` in one transaction.
3. **File-type totals**: insert 8 rows from `globalTypeTotals` into
   `file_type_totals`.
4. **Snapshot top folders**: insert each top folder's total into
   `snapshot_top_folders` for History diffs.
5. Set `scans.completed_at`, counts, volume capacities. The scan is queryable.

### 10.7 Cancel / pause

Check `Task.isCancelled` and a paused flag between batch boundaries. Pause:
sleep 50ms and re-check. Cancel: drop the buffer, skip aggregation, mark the
scan aborted, delete the in-progress database.

### 10.8 Errors

The `errorHandler` returns `true` to continue. Count unreadable paths in one
`skippedCount` integer; report at the end. This drives the Full Disk Access
prompt (12.3).

---

## 11. Database (Engine/ScanDatabase.swift) and queries

SQLite via GRDB. WAL mode. One database file per scan (no `scan_id` column inside
`dirs`; the file is the scope).

### 11.1 Pragmas

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous  = NORMAL;
PRAGMA temp_store   = MEMORY;
PRAGMA mmap_size    = 268435456;   -- 256MB mmap window (OS-paged)
PRAGMA cache_size   = -50000;      -- 50MB page cache
```

### 11.2 Schema

```sql
CREATE TABLE dirs (
  id INTEGER PRIMARY KEY,
  parent_id INTEGER REFERENCES dirs(id),
  name TEXT NOT NULL,
  depth INTEGER NOT NULL,
  is_hidden INTEGER NOT NULL DEFAULT 0,
  is_package INTEGER NOT NULL DEFAULT 0,
  mtime INTEGER,
  own_size INTEGER NOT NULL DEFAULT 0,
  file_count INTEGER NOT NULL DEFAULT 0,
  child_dir_count INTEGER NOT NULL DEFAULT 0,
  total_size INTEGER NOT NULL DEFAULT 0,
  descendant_file_count INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_dirs_parent ON dirs(parent_id);
CREATE INDEX idx_dirs_name   ON dirs(name);
CREATE INDEX idx_dirs_total  ON dirs(total_size DESC);
CREATE INDEX idx_dirs_depth  ON dirs(depth);

CREATE TABLE large_files (
  id INTEGER PRIMARY KEY,
  dir_id INTEGER NOT NULL REFERENCES dirs(id),
  name TEXT NOT NULL,
  size INTEGER NOT NULL,
  mtime INTEGER,
  ext TEXT,
  file_type INTEGER NOT NULL
);
CREATE INDEX idx_large_files_size ON large_files(size DESC);
CREATE INDEX idx_large_files_type ON large_files(file_type, size DESC);
CREATE INDEX idx_large_files_dir  ON large_files(dir_id);

CREATE TABLE file_type_totals (
  file_type INTEGER PRIMARY KEY,
  total_size INTEGER NOT NULL,
  file_count INTEGER NOT NULL
);

CREATE TABLE scans (
  id INTEGER PRIMARY KEY,
  volume_uuid TEXT NOT NULL,
  volume_name TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  completed_at INTEGER,
  total_used INTEGER,
  total_free INTEGER,
  dir_count INTEGER,
  file_count INTEGER,
  skipped_count INTEGER
);

CREATE TABLE snapshot_top_folders (
  scan_id INTEGER NOT NULL REFERENCES scans(id),
  path TEXT NOT NULL,
  total_size INTEGER NOT NULL
);
CREATE INDEX idx_snap_top ON snapshot_top_folders(scan_id);
```

**No `files` table.** That absence is the central memory win. Paths are not
stored on `dirs`; reconstruct from the parent chain (11.5).

### 11.3 Why this schema

- A `files` table of 5M rows would bloat the database and force slow per-row
  aggregation. Only directories (typically 100K to 500K) plus a bounded
  `large_files` set persist.
- Storing each dir's name + `parent_id` instead of a full path avoids repeating
  the `/Users/{name}/...` prefix across hundreds of thousands of rows.
- Indexes map to screens: `idx_dirs_name` powers Groups in one query;
  `idx_dirs_total` powers treemap and drill; `idx_large_files_type` powers the
  File Types panel.

### 11.4 Queries (one per screen)

`:rootId` is the dirs row for the volume root.

Overview treemap:
```sql
SELECT id,name,total_size,descendant_file_count,mtime,is_hidden,is_package
FROM dirs WHERE parent_id = :rootId ORDER BY total_size DESC LIMIT 12;
```

Drill children:
```sql
SELECT id,name,total_size,descendant_file_count,mtime,is_hidden,is_package
FROM dirs WHERE parent_id = :dirId ORDER BY total_size DESC;
```

Groups aggregate:
```sql
SELECT name, COUNT(*) AS count, SUM(total_size) AS total,
       AVG((strftime('%s','now') - mtime)/86400.0) AS avg_age_days
FROM dirs
WHERE name IN ('node_modules','.venv','DerivedData','__pycache__','Caches',
               '.gradle','Pods','target','build','dist')
GROUP BY name ORDER BY total DESC;
```

Group instances:
```sql
SELECT id,parent_id,total_size,mtime FROM dirs
WHERE name = :groupName ORDER BY total_size DESC;
```

File-type totals:
```sql
SELECT file_type,total_size,file_count FROM file_type_totals
ORDER BY total_size DESC;
```

Heaviest files for a type:
```sql
SELECT f.name,f.size,f.mtime,f.ext,f.dir_id
FROM large_files f WHERE f.file_type = :type
ORDER BY f.size DESC LIMIT 50;
```

History usage series: read `scans` rows (completed) ordered by `started_at`.
Growers/shrinkers: diff the two latest scans' `snapshot_top_folders` on `path`.

### 11.5 Path reconstruction (Engine/PathResolver.swift)

```swift
func fullPath(of dirId: Int64) -> String {
    var parts: [String] = []; var current: Int64? = dirId
    while let id = current {
        let row = db.dirNameAndParent(id)   // SELECT name,parent_id WHERE id=?
        parts.insert(row.name, at: 0); current = row.parentId
    }
    return "/" + parts.joined(separator: "/")
}
```
Back it with a small LRU (~1000 entries) since the same folder renders
repeatedly. Called only when a row's path is actually shown.

---

## 12. Delete (Engine/DeleteService.swift) and storage lifecycle

### 12.1 Protected-path guard

Before anything, partition targets into allowed and protected. A target is
protected if its path is, or is inside, any protected path. The **system set is
fixed and non-removable**: `/System`, `/Library`, `/usr`, `/bin`, `/sbin`,
`/private`, `~/Library/Keychains`, `~/.ssh`, `~/.gnupg`, plus user-added paths
from Settings. The UI never enables a delete including a protected target; the
service is the second line of defense and refuses them regardless.

### 12.2 Delete operations and the database patch (the seam fix)

- **Move to Trash:** `FileManager.trashItem(at:resultingItemURL:)` per target.
  Recoverable; keep the returned Trash URLs and the deleted `dirs` rows in
  memory for the toast's lifetime so Undo can restore both filesystem and
  database.
- **Delete forever:** `FileManager.removeItem(at:)`. Only when "Delete forever"
  is chosen. Never on protected paths.
- **Patch SQLite after a successful delete** (this is required, not optional):
  1. Delete the affected `dirs` subtree rows: `DELETE FROM dirs WHERE id = ?`
     plus all descendants (recursive CTE on `parent_id`, or repeated by depth).
     Delete their `large_files` rows too.
  2. Re-aggregate ancestors: for each deleted target, walk its `parent_id` chain
     to root and subtract the removed `total_size` / `descendant_file_count`
     from each ancestor (a targeted decrement, cheaper than a full re-aggregate).
  3. Recompute `file_type_totals` deltas for any `large_files` removed.
- After the patch, `AppModel` refreshes the visible screen by re-query (7.2) and
  updates `freedBytes`.

### 12.3 Full Disk Access

Parts of the filesystem need Full Disk Access, granted by the user in System
Settings > Privacy & Security > Full Disk Access; it cannot be requested
programmatically. On first run, and whenever `skippedCount` is high, show a
clear explainer with a button deep-linking to the pane
(`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`).
The scan still works without it; it just skips protected areas and reports how
many.

### 12.4 Storage lifecycle (Engine/ScanStore.swift)

- **Location:** `~/Library/Application Support/wimys_crumb/scans/`.
- **Naming:** `{volume_uuid}-{started_at}.sqlite` per completed scan. Active
  scans write to `in-progress-{started_at}.sqlite` and are renamed only on
  success; orphaned in-progress files are deleted on next launch.
- **Retention:** always keep the latest scan per volume; keep up to ~10 per
  volume for History; pinned snapshots are exempt from the cap.
- **Cleanup:** Settings > Snapshots shows each scan database's size with
  per-scan delete and a "Clear all scan data" button. On launch, vacuum scan
  databases older than 30 days. A 1TB / 5M-file database is ~100 to 300MB; ten
  is the worst case worth capping.
- **Concurrency:** WAL allows the UI to read while the engine writes. One writer
  connection in the engine actor; short-lived read connections from query
  helpers.

### 12.5 Scheduled scans (v1 scope)

Store the schedule; on launch, if the scheduled time has passed and the machine
is on power, run a scan. A true background scan while the app is closed needs a
`launchd` agent or helper - future work. Keep the Settings copy honest ("runs
next time you open wimys_crumb").

---

## 13. Grouping, classification, suggestions

- **GroupQueries.swift:** the group-by-name SQL (11.4) plus the instances query.
  Known group names: `node_modules`, `.venv`, `DerivedData`, `__pycache__`,
  `Caches`, `.gradle`, `Pods`, `target`, `build`, `dist`. Flag dev-only groups
  for the "dev" pill. Taglines are a static lookup per group name.
- **FileTypeClassifier.swift:** a static extension -> category table for the 8
  categories (Video, Photos, Code, Apps, Documents, Music, Archives, Other).
  Used in the scan hot path; keep it a plain dictionary keyed by lowercased ext.
- **Suggestions.swift (Quick wins):** a rules pass over the scan database -
  empty Trash, stale `node_modules` (dev groups not modified in 6+ months), old
  Downloads (files in Downloads older than 6 months, from `large_files` + dir
  lookups), `DerivedData`, large `Caches`. Each suggestion has a title, detail,
  estimated saving, and a `kind` (`safe` or `review`). **Duplicate-photo
  detection** is hard; for v1 either omit it or use a cheap heuristic (same size
  + same name stem) labelled clearly as `review`, never `safe`. Real
  perceptual-hash dedup (where a GPU could help) is explicitly v2.

---

## 14. Memory and performance budget (hard requirement)

| Phase                  | Budget    | Composition                                   |
|------------------------|-----------|-----------------------------------------------|
| Idle (no scan)         | < 100 MB  | SwiftUI runtime, no DB open                   |
| Scan in progress       | < 250 MB  | 50MB SQLite cache, 256MB mmap (lazy/OS-paged), |
|                        |           | ~1MB stack + buffer, ~500KB heaps             |
| Browsing results       | < 200 MB  | 50MB SQLite cache, query result rows          |
| After a delete         | < 200 MB  | unchanged                                     |

If resident memory exceeds 300MB during a scan, something is wrong. Suspects, in
order: per-file Swift retention, unfreed `URL`s, an unbounded buffer, or the
SQLite mmap (OS-paged; counted as `File-Mapped` in `vmmap`, distinct from heap -
if that is the bulk, it is fine). Verify with Instruments Allocations and
`vmmap`.

Performance: for v1, `FileManager.enumerator` with the options above is fine.
Only if a large-volume scan is still slow after the architecture is correct,
consider (later, not v1): a `getattrlistbulk` C bridge (2 to 5x faster bulk
attribute reads), or parallel walkers per top-level subtree writing to the same
WAL database (1.5 to 2x at best on SSD/APFS). Never spawn millions of `Task`s;
each is a real allocation.

---

## 15. Assets to bundle

Openly licensed; include the license files:

- **Bricolage Grotesque** - weights 500, 600, 700, 800 (SIL OFL).
- **Geist** and **Geist Mono** - weights 400, 500, 600, 700 (SIL OFL, Vercel).

Register in `Info.plist` (`ATSApplicationFontsPath`) or load at launch. Produce
an app icon in the crumb style (the coral square with the dot trio is a natural
start) as an asset-catalog `.icns` set.

---

## 16. Build phases and acceptance

Build in order. Each phase compiles, runs, and meets acceptance before the next.

### Phase 1 - Foundation
Xcode project named `wimys_crumb`, `Theme`, `AppModel` with navigation, the
native window, `BrandBar`, all `Components/`, GRDB wired with the schema and
empty-database open/close, and the Start screen with **real** mounted-volume
enumeration. `MockData` for previews.
**Acceptance:** app launches to a real Start screen; real volumes with correct
sizes; navigation enum and tab strip work; all components render in previews;
an empty scan database opens and migrates cleanly.

### Phase 2 - Scan engine + Overview
Real `ScanEngine` streaming to SQLite, `Aggregator`, the Scanning screen wired
to live progress and the `biggestSoFar` read query, and Overview (treemap, stat
cards, quick wins) rendering real query results.
**Acceptance:** a real scan runs off the main thread with live progress;
Pause/Cancel work; completion routes to Overview; the treemap reflects the real
top-level breakdown; **resident memory stays under 250MB throughout a scan of a
1TB / 5M-file volume**.

### Phase 3 - Drill, Groups, Delete
Drill screen (children queries, breadcrumb, detail panel, `PathResolver`),
`GroupQueries` + Groups screen + bubbles, and the Delete sheet with
`DeleteService` (real Trash, protected guard, SQLite patch, Undo).
**Acceptance:** drilling navigates by re-query; groups are real cross-disk
aggregates; deletes move to Trash, respect protected paths, patch the database,
support Undo, and refresh the visible screen by re-query with totals updating
live.

### Phase 4 - File types, History
`FileTypeClassifier` + File types screen; snapshots + `ScanStore` + History
screen with the usage chart and growers/shrinkers diff.
**Acceptance:** file-type breakdown is real; History reflects recorded scans and
shows an honest empty state with fewer than two scans; growers/shrinkers diff
the two latest scans correctly.

### Phase 5 - Settings, polish
Full Settings (Safety, Scans, Snapshots, Export, About real; Detection at least
read-only), Full Disk Access prompts, scheduled-scan launch behavior, Export to
CSV/JSON, empty/error states, the app icon, launch-time vacuum of old scan
databases, and a final visual pass against the prototype.
**Acceptance:** settings persist; protected paths are editable and are what the
delete service consults; Export writes a real file; the Snapshots panel manages
real `.sqlite` files; resident memory under 200MB while browsing any screen on a
real 5M-file volume (verified via Activity Monitor or `vmmap`); the app matches
the prototype's look across all nine screens.

---

## 17. macOS gotchas

- **Folder size is slow** - walking every file. Keep it off the main thread;
  batch UI updates.
- **`.totalFileAllocatedSizeKey` vs `.fileSizeKey`** - use the former (on-disk,
  what actually frees up).
- **Packages** - `.app`, `.photoslibrary`, etc. are single items; do not descend.
- **Symlinks/hardlinks** - skip symlinks (cycles/double counting); accept minor
  hardlink double counting in v1.
- **APFS** - OS-reported free space differs from naive sums (local snapshots,
  purgeable space). Show the volume's reported capacity values, not your own sum.
- **Permissions** - expect unreadable paths even with Full Disk Access; skip and
  count; never crash.
- **Never delete without the sheet** - every destructive path goes through
  `DeleteSheet` and `DeleteService`; the protected guard lives in the service,
  not just the UI.
- **Notarization** - a non-sandboxed app must be Developer ID signed and
  notarized or Gatekeeper blocks it.
- **mmap counts as resident** - the 256MB SQLite mmap shows as resident memory
  but is OS-paged file mapping, not heap. Confirm via `vmmap` before chasing a
  phantom leak.

---

## 18. Sanity checks before writing engine code

- The engine actor has exactly one `Task` doing the walk. No nested
  `withTaskGroup`. No `Task { }` inside the file loop.
- No method takes a `[URL]` of all files in a directory. If you see one, that is
  the leak.
- No `[String]` of paths grows without bound. The only growing thing is SQLite,
  on disk.
- The path stack is at most ~50 deep. Test it.
- `large_files` is at most ~5000 rows after a scan (8 types x 500 plus stray
  files over 10MB). Test it.
- `dirs` is bounded by directory count (100K to 500K), not file count.

Violate any of these and stop to fix before continuing. Bounded memory is the
point.

---

## 19. Out of scope for v1 (recorded for later)

Per-app cleanup recipes (Slack/Xcode/Docker); drag-a-folder-onto-the-app to
inspect a path; a menu-bar mini-mode for at-a-glance free space; true background
scheduled scans via a `launchd` agent; robust duplicate-file detection by
content hash (the legitimate place a GPU could help); the `getattrlistbulk`
fast-path and parallel walkers (performance optimizations, only if needed).

---

## 20. Definition of done

All nine screens implemented in SwiftUI, visually matching
`project/prototype.html` (Honey direction), with the wordmark "crumb" and product
name `wimys_crumb`. A real scan of the boot volume completes off the main thread
with live progress and stays within the memory budget in section 14. Grouping,
file-type breakdown, and suggestions are computed from the SQLite scan database.
Deletes move to Trash (or delete forever when chosen), honor the protected-path
guard, patch the database, support Undo, and refresh the UI by re-query.
Settings and scan history persist across launches. Old scan databases are
pruned and vacuumed. The app is signed and notarizable.
