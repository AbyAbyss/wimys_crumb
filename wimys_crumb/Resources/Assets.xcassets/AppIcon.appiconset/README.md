# App Icon

`project.yml` references `AppIcon` via `ASSETCATALOG_COMPILER_APPICON_NAME`.

The PNGs in this folder are **generated** from a single source SVG:
`docs/icon.svg` (1024×1024 master, Honey palette, follows Apple's macOS
Big Sur icon template). Don't hand-edit the PNGs — edit the SVG and re-run
the generator.

## Regenerating

```sh
brew install librsvg     # one-time
./scripts/generate_icons.sh
```

That renders the SVG into these 10 PNGs:

| File                | Pixels |
| ------------------- | ------ |
| `icon_16.png`       | 16     |
| `icon_16@2x.png`    | 32     |
| `icon_32.png`       | 32     |
| `icon_32@2x.png`    | 64     |
| `icon_128.png`      | 128    |
| `icon_128@2x.png`   | 256    |
| `icon_256.png`      | 256    |
| `icon_256@2x.png`   | 512    |
| `icon_512.png`      | 512    |
| `icon_512@2x.png`   | 1024   |

`Contents.json` maps each appiconset slot to its filename, so once the PNGs
land here Xcode picks them up on the next build (no `xcodegen generate`
needed for icon-only changes).

## Design

From `proto-shell.jsx` `IAppBar` — coral squircle with the three-dot
crumb mark:

- Background: coral gradient `#E55934 → #C84621`, 832×832 inset on 1024
  canvas, corner radius 185 (the macOS squircle ratio)
- Top highlight: white at 6% opacity over the upper half for depth
- Dot trio (scaled from the 88-px brand mark):
  - honey `#F3B95F`, r=103 at (320, 320)
  - paper `#FFFFFF`, r=75 at (705, 685)
  - honey-soft `#FBE9C6`, r=47 at (615, 415)
