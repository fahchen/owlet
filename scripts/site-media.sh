#!/usr/bin/env bash
# Regenerates the panel screenshots on the website from the real panel views and the preview fixtures.
# Glass is composited by the window server, so this needs an unlocked screen and Screen Recording
# permission for the terminal. Only the preview's own window is captured, never the desktop.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/site/media"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

# A plain backdrop: the glass has nothing to pick up, and the panel is easy to find and cut out.
ffmpeg -hide_banner -loglevel error -f lavfi -i "color=c=0xf2f2f5:s=2060x1100" -frames:v 1 "$work/backdrop.png"
python3 "$root/scripts/panel-preview.py" --screenshots "$work/shots" --background "$work/backdrop.png"

# Crops each capture to the panel and makes everything outside its rounded corners transparent.
python3 -I - "$work/shots" "$out" <<'EOF'
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw

shots, out = Path(sys.argv[1]), Path(sys.argv[2])
for name, target in [("success", "translate"), ("learning", "learn"), ("learning-selected", "collect")]:
    image = Image.open(shots / f"{name}.png").convert("RGBA")
    # The preview records where the glass sits, in points, so the crop never guesses at shadows.
    frame = json.loads((shots / f"{name}.json").read_text())
    scale = image.width / frame["window"]
    box = [round(frame[k] * scale) for k in ("x", "y")]
    box += [box[0] + round(frame["width"] * scale), box[1] + round(frame["height"] * scale)]
    panel = image.crop(box)
    # PanelMetrics.cornerRadius
    radius = round(34 * scale)
    mask = Image.new("L", panel.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, panel.width - 1, panel.height - 1], radius, fill=255)
    panel.putalpha(mask)
    panel.save(out / f"{target}.webp", quality=90, method=6)
    print(target, panel.size)
    if target == "translate":
        # Link previews want a PNG at 1200x630; the translated panel on white is the page in one look.
        card = Image.new("RGBA", (1200, 630), "white")
        shrunk = panel.resize((1040, round(panel.height * 1040 / panel.width)), Image.LANCZOS)
        card.alpha_composite(shrunk, ((1200 - shrunk.width) // 2, (630 - shrunk.height) // 2))
        card.convert("RGB").save(out / "og.png", optimize=True)
EOF

# The main window's pages and the Language settings pane. The window is captured with a solid window
# right behind it, so its translucent sidebar never shows the desktop.
python3 "$root/scripts/panel-preview.py" --app-shots "$work/app"
python3 -I - "$work/app" "$out" <<'EOF'
import sys
from pathlib import Path
from PIL import Image, ImageChops

app, out = Path(sys.argv[1]), Path(sys.argv[2])
for name in ["notebook", "history"]:
    Image.open(app / f"{name}.png").save(out / f"{name}.webp", quality=90, method=6)
pane = Image.open(app / "settings-language.png").convert("RGB")
# The pane is drawn on a tall canvas; cut it just below the last row.
blank = Image.new("RGB", pane.size, pane.getpixel((2, pane.height - 2)))
bottom = ImageChops.difference(pane, blank).getbbox()[3]
pane.crop((0, 0, pane.width, min(pane.height, bottom + 48))).save(out / "languages.webp", quality=90, method=6)
print("app shots", pane.width, bottom)
EOF
