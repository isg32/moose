#!/bin/bash
# Refreshes the app renders the docs show (docs/renders/*.webp).
#
# The renders come from the local peek goldens in test_peek/ (git-ignored:
# a harness that draws each screen at 390 × 844 on the night and paper
# wallpapers). This re-runs them, then shrinks each to 1.5× as WebP.
#
#   tool/docs_renders.sh          # run the peeks, then convert
#   tool/docs_renders.sh --keep   # convert what test_peek/out already has
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
[ -d test_peek ] || { echo "Needs the local test_peek/ harness"; exit 1; }
[ "$1" = "--keep" ] || flutter test test_peek --update-goldens
OUT=docs/renders; mkdir -p "$OUT"
for f in test_peek/out/*.png; do
  name=$(basename "$f" .png)
  # Portrait renders are 1170 wide, landscape 2532; keep 1.5× of 390 / 844.
  read W H < <(magick identify -format '%w %h\n' "$f")
  if [ "$W" -gt "$H" ]; then size=1266x; else size=585x; fi
  magick "$f" -resize "$size" -quality 82 -define webp:method=6 "$OUT/$name.webp"
done
du -sh "$OUT"
