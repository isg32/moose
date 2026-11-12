#!/bin/bash
# Renders every board of the design canvas to a PNG at its $preview size,
# using Playwright's headless Chromium and dc-mini.js (a small stand-in for
# the Claude Design runtime). Fonts come from assets/fonts, or Veronica's.
#
#   tool/design_render/render.sh            # design/canvas -> design/screens
set -e
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd)
SRC=${1:-$ROOT/design/canvas}; OUT=${2:-$ROOT/design/screens}
FONTS=${FONTS:-$ROOT/assets/fonts}; [ -f "$FONTS/Doto.ttf" ] || FONTS=$ROOT/../veronica/assets/fonts
BIN=$(find ~/.cache/ms-playwright -name chrome-headless-shell -type f 2>/dev/null | head -1)
[ -x "$BIN" ] || { echo "Needs Playwright's headless shell: npx playwright install chromium-headless-shell"; exit 1; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/pages" "$OUT"; cp "$HERE/dc-mini.js" "$FONTS/Doto.ttf" "$FONTS/Inter.ttf" "$WORK/"
for f in "$SRC"/*.dc.html; do
  name=$(basename "$f" .dc.html)
  read W H < <(python3 -I - "$f" <<'PY'
import re, sys
m = re.search(r'"\$preview":\{"width":(\d+),"height":(\d+)\}', open(sys.argv[1], encoding='utf-8').read())
print(m.group(1), m.group(2))
PY
)
  python3 -I - "$f" "$WORK/pages/$name.html" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
s = s.replace('<script src="./support.js"></script>',
  '<script src="../dc-mini.js"></script><style>@font-face{font-family:Doto;src:url(../Doto.ttf)}@font-face{font-family:Inter;src:url(../Inter.ttf)}</style>')
s = re.sub(r'<link rel="stylesheet" href="https://fonts.googleapis.com[^>]*>', '', s)
open(sys.argv[2], 'w', encoding='utf-8').write(s)
PY
  "$BIN" --headless --no-sandbox --hide-scrollbars --force-device-scale-factor=1 --window-size=$W,$H \
    --virtual-time-budget=6000 --allow-file-access-from-files --screenshot="$OUT/$name.png" \
    "file://$WORK/pages/$name.html" >/dev/null 2>&1
  echo "$name ${W}x${H}"
done
