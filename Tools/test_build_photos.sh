#!/usr/bin/env bash
# Smoke test for build_photos.sh — self-contained: it synthesizes its own
# oversized, GPS-tagged JPEG original (from an embedded 1x1 PNG upscaled by sips),
# runs the tool, and asserts the size caps + GPS stripping. No external fixtures.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

command -v exiftool >/dev/null 2>&1 || { echo "SKIP: exiftool not installed (brew install exiftool)"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
src="$tmp/src"; out="$tmp/out"; mkdir -p "$src"

# Embedded 1x1 PNG (decoded, then upscaled to an oversized original so the
# downscale path is exercised deterministically without any committed binary).
base64 -D >"$tmp/seed.png" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
PNG
sips -s format jpeg -z 3000 4000 "$tmp/seed.png" --out "$src/test-1.jpg" >/dev/null

# Inject fake GPS so we can prove the tool strips it.
exiftool -overwrite_original -GPSLatitude=41.0086 -GPSLatitudeRef=N \
  -GPSLongitude=28.9802 -GPSLongitudeRef=E "$src/test-1.jpg" >/dev/null

bash "$here/build_photos.sh" "$src" "$out"

[ -f "$out/full/test-1.jpg" ]   || { echo "FAIL: full output missing"; exit 1; }
[ -f "$out/thumbs/test-1.jpg" ] || { echo "FAIL: thumb output missing"; exit 1; }

dim() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w, h}'; }
read -r fw fh < <(dim "$out/full/test-1.jpg")
read -r tw th < <(dim "$out/thumbs/test-1.jpg")
[ "$fw" -le 2560 ] && [ "$fh" -le 2560 ] || { echo "FAIL: full $fw x $fh exceeds 2560"; exit 1; }
[ "$tw" -le 500 ]  && [ "$th" -le 500 ]  || { echo "FAIL: thumb $tw x $th exceeds 500"; exit 1; }

for o in "$out/full/test-1.jpg" "$out/thumbs/test-1.jpg"; do
  if exiftool -s -s -s -GPSLatitude -GPSLongitude "$o" | grep -q .; then
    echo "FAIL: GPS survived in $o"; exit 1
  fi
done

echo "PASS: build_photos smoke test (full ${fw}x${fh}, thumb ${tw}x${th}, GPS stripped)"
