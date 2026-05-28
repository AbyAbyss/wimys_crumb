# App Icon

`project.yml` references `AppIcon` via `ASSETCATALOG_COMPILER_APPICON_NAME`.
Add the standard macOS icon set here:

- `icon_16x16.png`     16×16  @1x
- `icon_16x16@2x.png`  32×32  @2x
- `icon_32x32.png`     32×32  @1x
- `icon_32x32@2x.png`  64×64  @2x
- `icon_128x128.png`     128
- `icon_128x128@2x.png`  256
- `icon_256x256.png`     256
- `icon_256x256@2x.png`  512
- `icon_512x512.png`     512
- `icon_512x512@2x.png` 1024

Generate from a single 1024×1024 master with Sketch / Figma / Acorn, or use
`iconutil` (Xcode bundled).

Design direction (from the Honey prototype's `proto-shell.jsx` `IAppBar`):

- 1024×1024 canvas, rounded-rectangle background fill `#E55934` (coral).
- Three offset circles in a "crumb dot trio":
  - 256×256 honey `#F3B95F` near the top-left
  - 192×192 paper `#FFFFFF` near the bottom-right
  - 128×128 honey-soft `#FBE9C6` middle-right

After dropping PNGs in, `xcodegen generate` will pick the asset catalog up.
The placeholder `Contents.json` below is the minimum xcassets accepts.
