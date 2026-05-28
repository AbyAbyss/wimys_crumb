#!/usr/bin/env bash
# generate_icons.sh
# Renders docs/icon.svg into the 10 PNG sizes the macOS AppIcon asset catalog
# expects, writing them straight into the AppIcon.appiconset folder so Xcode
# picks them up on the next build.
#
# Renderer: tries `rsvg-convert` first (brew install librsvg), then falls back
# to Python's `cairosvg` (pip install cairosvg). Either works.
#
# Re-run any time docs/icon.svg changes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC="$REPO_ROOT/docs/icon.svg"
DEST="$REPO_ROOT/wimys_crumb/Resources/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$SRC" ]]; then
  echo "error: source SVG not found at $SRC" >&2
  exit 1
fi

mkdir -p "$DEST"

# size:name pairs (one per macOS icon slot).
SIZES=(
  "16:icon_16.png"
  "32:icon_16@2x.png"
  "32:icon_32.png"
  "64:icon_32@2x.png"
  "128:icon_128.png"
  "256:icon_128@2x.png"
  "256:icon_256.png"
  "512:icon_256@2x.png"
  "512:icon_512.png"
  "1024:icon_512@2x.png"
)

if command -v rsvg-convert >/dev/null 2>&1; then
  echo "Rendering with rsvg-convert"
  for pair in "${SIZES[@]}"; do
    size="${pair%%:*}"
    name="${pair##*:}"
    echo "  ${size}px -> $name"
    rsvg-convert -w "$size" -h "$size" "$SRC" -o "$DEST/$name"
  done
elif python3 -c "import cairosvg" >/dev/null 2>&1; then
  echo "Rendering with python3 + cairosvg"
  python3 - "$SRC" "$DEST" <<'PY'
import sys, cairosvg
src, dest = sys.argv[1], sys.argv[2]
sizes = [
    (16,   "icon_16.png"),
    (32,   "icon_16@2x.png"),
    (32,   "icon_32.png"),
    (64,   "icon_32@2x.png"),
    (128,  "icon_128.png"),
    (256,  "icon_128@2x.png"),
    (256,  "icon_256.png"),
    (512,  "icon_256@2x.png"),
    (512,  "icon_512.png"),
    (1024, "icon_512@2x.png"),
]
for px, name in sizes:
    print(f"  {px}px -> {name}")
    cairosvg.svg2png(url=src, output_width=px, output_height=px,
                     write_to=f"{dest}/{name}")
PY
else
  echo "error: no SVG renderer found." >&2
  echo "  Install one of:" >&2
  echo "    brew install librsvg              # provides rsvg-convert" >&2
  echo "    pip3 install cairosvg             # Python fallback" >&2
  exit 1
fi

echo "Done. 10 PNGs written to $DEST"
