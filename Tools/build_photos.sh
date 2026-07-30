#!/usr/bin/env bash
# build_photos.sh — optimize + thumbnail + strip location/camera metadata.
#
# Usage: tools/build_photos.sh <originals-dir> <out-dir>
#   <originals-dir>  folder of full-res originals named <photo-id>.<ext>
#   <out-dir>        writes <out-dir>/full/<id>.jpg and <out-dir>/thumbs/<id>.jpg
#
# Requires: sips (macOS built-in), exiftool (brew install exiftool).
# Full-size: longest edge 2560px (never upscale), JPEG sRGB q80.
# Thumbnail: longest edge 500px  (never upscale), JPEG q72.
# All metadata stripped except image Orientation. Exits 1 if any output
# still contains GPS metadata.
set -euo pipefail

FULL_MAX=2560; THUMB_MAX=500; FULL_Q=80; THUMB_Q=72

die() { echo "✗ $*" >&2; exit 1; }
command -v sips     >/dev/null 2>&1 || die "sips not found (macOS required)"
command -v exiftool >/dev/null 2>&1 || die "exiftool not found — run: brew install exiftool"
[ "$#" -eq 2 ] || die "usage: build_photos.sh <originals-dir> <out-dir>"

SRC="$1"; OUT="$2"
[ -d "$SRC" ] || die "originals dir not found: $SRC"
mkdir -p "$OUT/full" "$OUT/thumbs"

longest() { sips -g pixelWidth -g pixelHeight "$1" \
  | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print (w>h?w:h)}'; }

# Re-encode to JPEG at a given quality, resampling the longest edge down to a
# cap ONLY when the source exceeds it (never upscales).
encode() { # <in> <out> <max> <q>
  local in="$1" out="$2" max="$3" q="$4"
  if [ "$(longest "$in")" -gt "$max" ]; then
    sips -s format jpeg -s formatOptions "$q" -Z "$max" "$in" --out "$out" >/dev/null
  else
    sips -s format jpeg -s formatOptions "$q" "$in" --out "$out" >/dev/null
  fi
}

shopt -s nullglob nocaseglob
originals=("$SRC"/*.jpg "$SRC"/*.jpeg "$SRC"/*.png "$SRC"/*.heic "$SRC"/*.tif "$SRC"/*.tiff)
shopt -u nocaseglob
[ "${#originals[@]}" -gt 0 ] || die "no image files in $SRC"

count=0
for f in "${originals[@]}"; do
  id="$(basename "$f")"; id="${id%.*}"
  full="$OUT/full/$id.jpg"; thumb="$OUT/thumbs/$id.jpg"
  tmp="$OUT/full/$id.src.tmp"

  cp "$f" "$tmp"
  # Strip ALL metadata, then re-apply only Orientation (non-sensitive; keeps the
  # image upright without retaining GPS/camera/timestamp data). Read orientation
  # first and re-apply only when present, so metadata-less images stay quiet.
  orient="$(exiftool -s3 -n -Orientation "$tmp" 2>/dev/null || true)"
  exiftool -overwrite_original -all= "$tmp" >/dev/null
  [ -n "$orient" ] && exiftool -overwrite_original -n -Orientation="$orient" "$tmp" >/dev/null

  encode "$tmp"  "$full"  "$FULL_MAX"  "$FULL_Q"
  encode "$full" "$thumb" "$THUMB_MAX" "$THUMB_Q"
  rm -f "$tmp"

  for out in "$full" "$thumb"; do
    if exiftool -s -s -s -GPSLatitude -GPSLongitude "$out" | grep -q .; then
      die "GPS metadata survived in $out"
    fi
  done

  read -r w h < <(sips -g pixelWidth -g pixelHeight "$full" \
    | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w, h}')
  printf "✓ %-28s full %sx%s %sKB\n" "$id" "$w" "$h" "$(( $(stat -f%z "$full") / 1024 ))"
  count=$((count+1))
done

echo "✓ processed $count photo(s) → $OUT/full, $OUT/thumbs"
