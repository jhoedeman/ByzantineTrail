#!/usr/bin/env bash
# import_photos.sh — idempotent photo import driver for Byzantine Trail.
#
# For each row in Tools/photo_manifest.tsv (<folder-name><TAB><site-id>) whose
# folder exists under <incoming-root>, this:
#   1. stages + renames the folder's images to <site-id>-<n>.<ext> in shot order
#      (ordered by the trailing number in each filename, then name),
#   2. runs build_photos.sh (strips ALL GPS/camera metadata, resizes to a
#      2560px "full" and a 500px "thumb", fails if any GPS tag survives),
#   3. copies the thumbnails into ByzantineTrail/Resources/thumbs/ (bundled),
#   4. merges a photos[] array into catalog.json via jq (format-preserving,
#      --indent 1), stamping every photo with credit "Photo: John Hoedeman".
# Full-size images accumulate in Tools/photo-build/full/ (git-ignored) for later
# upload to the content repo (see docs/CATALOG_HOSTING.md) — never bundled.
#
# IDEMPOTENT: a site that already has photos in catalog.json AND whose first
# thumbnail is present is skipped, so re-running after adding new folders only
# processes the new ones. Use --force to reprocess, --only to target folders.
#
# Usage:
#   Tools/import_photos.sh <incoming-root> [--force] [--only "Folder Name"]...
#
# Requires: jq, exiftool, sips (see build_photos.sh).
set -euo pipefail

CREDIT="Photo: John Hoedeman"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CATALOG="$REPO/ByzantineTrail/Resources/catalog.json"
THUMBS_DEST="$REPO/ByzantineTrail/Resources/thumbs"
MANIFEST="$SCRIPT_DIR/photo_manifest.tsv"
BUILD_OUT="$SCRIPT_DIR/photo-build"          # git-ignored; holds full/ + thumbs/
STAGE="$BUILD_OUT/.stage"                     # per-site rename scratch

die() { echo "✗ $*" >&2; exit 1; }
command -v jq       >/dev/null 2>&1 || die "jq not found"
command -v exiftool >/dev/null 2>&1 || die "exiftool not found — brew install exiftool"
[ -f "$CATALOG" ]  || die "catalog not found: $CATALOG"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"

[ "$#" -ge 1 ] || die "usage: import_photos.sh <incoming-root> [--force] [--only \"Folder\"]..."
ROOT="$1"; shift
[ -d "$ROOT" ] || die "incoming root not found: $ROOT"

FORCE=0
ONLY=""            # newline-separated allowlist of folder names; empty = all
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --only)  shift; [ "$#" -ge 1 ] || die "--only needs a folder name"; ONLY="$ONLY$1"$'\n' ;;
    *) die "unknown arg: $1" ;;
  esac
  shift
done

mkdir -p "$THUMBS_DEST" "$BUILD_OUT/full" "$BUILD_OUT/thumbs"

site_exists()  { jq -e --arg id "$1" '.sites | any(.id == $id)'                 "$CATALOG" >/dev/null; }
site_has_pics(){ jq -e --arg id "$1" '(.sites[] | select(.id==$id) | .photos // []) | length > 0' "$CATALOG" >/dev/null; }

processed=0; skipped=0; missing=0

while IFS=$'\t' read -r folder sid || [ -n "$folder" ]; do
  case "$folder" in \#*|"") continue;; esac
  [ -n "$sid" ] || { echo "✗ no site-id for folder: $folder" >&2; missing=1; continue; }

  if [ -n "$ONLY" ] && ! printf '%s' "$ONLY" | grep -qxF "$folder"; then continue; fi

  src="$ROOT/$folder"
  if [ ! -d "$src" ]; then
    [ -n "$ONLY" ] && echo "✗ folder not found: $folder" >&2 && missing=1
    continue
  fi
  site_exists "$sid" || { echo "✗ site-id not in catalog: $sid (folder: $folder)" >&2; missing=1; continue; }

  # Idempotency: skip if already wired and its first thumbnail is present.
  if [ "$FORCE" -eq 0 ] && site_has_pics "$sid" && [ -f "$THUMBS_DEST/$sid-1.jpg" ]; then
    echo "• skip  $sid  (already wired)"
    skipped=$((skipped+1)); continue
  fi

  # Optional attribution sidecar: Tools reads a plain-text "_credits.txt" in the
  # folder to credit third-party/licensed photos. One line per source file:
  #     <source-filename>: <Attribution text> <https://license-url>, <source>
  # e.g. 1.jpg: Sailko, CC BY 3.0 <https://creativecommons.org/licenses/by/3.0>, via Wikimedia Commons
  # The angle-bracketed URL is split off into the photo's licenseURL; the rest
  # (with the URL removed) becomes the displayed credit. Files with no matching
  # line — or folders with no _credits.txt at all — default to the owner credit.
  # (Bash 3.2 on macOS has no associative arrays; credit_for() greps the file.)
  credits_file="$src/_credits.txt"

  # Collect + order the folder's images: sort by trailing integer, then name.
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  n=0
  declare -a SRCNAME=()          # SRCNAME[n] = original source filename for photo n
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # Skip zero-byte source files (e.g. an incompletely-synced cloud file or a
    # corrupt original) so one bad file doesn't abort the whole batch. Remaining
    # valid images are renumbered contiguously.
    if [ ! -s "$src/$f" ]; then echo "⚠ skip empty/corrupt source: $folder/$f" >&2; continue; fi
    n=$((n+1))
    SRCNAME[$n]="$f"
    ext="${f##*.}"; ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
    cp "$src/$f" "$STAGE/$sid-$n.$ext"
  done < <(
    cd "$src" && for f in *.jpg *.jpeg *.png *.heic *.tif *.tiff \
                          *.JPG *.JPEG *.PNG *.HEIC *.TIF *.TIFF; do
      [ -e "$f" ] || continue
      stem="${f%.*}"; num="$(printf '%s' "$stem" | grep -oE '[0-9]+$' || true)"
      printf '%08d\t%s\n' "${num:-0}" "$f"
    done | sort -n | cut -f2-
  )
  [ "$n" -gt 0 ] || { echo "✗ no images in folder: $folder" >&2; missing=1; continue; }

  # Optimize + strip metadata into the shared build output.
  "$SCRIPT_DIR/build_photos.sh" "$STAGE" "$BUILD_OUT" >/dev/null

  # Publish thumbnails into the bundled resources dir.
  for i in $(seq 1 "$n"); do cp "$BUILD_OUT/thumbs/$sid-$i.jpg" "$THUMBS_DEST/$sid-$i.jpg"; done

  # Build this site's photos[] array (one TSV record per photo: index, credit,
  # licenseURL) then let jq assemble it. Third-party photos carry a licenseURL;
  # owner photos get the default credit and no licenseURL key at all.
  recfile="$STAGE/.credits.tsv"; : > "$recfile"
  for i in $(seq 1 "$n"); do
    srcname="${SRCNAME[$i]}"
    raw=""
    if [ -f "$credits_file" ]; then
      # Match the line whose key (text before the first ':') names this source
      # photo. Compare by STEM only — the filename minus its extension, lowercased
      # — because the owner's credits convention writes keys as "N.jpg" regardless
      # of the real source extension ("1.JPG", "1.png" all key off "1"). Matching
      # the full filename would miss those and silently fall back to the owner
      # credit, misattributing a third-party photo. Then strip "<key>:" + whitespace.
      raw="$(awk -F: -v k="$srcname" '
        function stem(s){ sub(/\.[^.]*$/,"",s); return tolower(s) }
        { key=$1; sub(/^[ \t]+/,"",key); sub(/[ \t]+$/,"",key);
          if (stem(key)==stem(k)) { sub(/^[^:]*:[ \t]*/,""); print; exit } }' "$credits_file")"
    fi
    if [ -n "$raw" ]; then
      lurl="$(printf '%s' "$raw" | grep -oE '<https?://[^>]+>' | head -1 | tr -d '<>' || true)"
      cred="$(printf '%s' "$raw" | sed -E 's/[[:space:]]*<https?:\/\/[^>]+>//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
    else
      lurl=""; cred="$CREDIT"
    fi
    printf '%s\t%s\t%s\n' "$i" "$cred" "$lurl" >> "$recfile"
  done
  photos_json="$(jq -R -n --arg id "$sid" '
    [inputs | split("\t") | {
      id:     "\($id)-\(.[0])",
      thumb:  "thumbs/\($id)-\(.[0]).jpg",
      full:   "full/\($id)-\(.[0]).jpg",
      credit: .[1]
    } + (if (.[2] // "") != "" then { licenseURL: .[2] } else {} end)]' "$recfile")"
  tmp="$CATALOG.tmp"
  jq --indent 1 --arg id "$sid" --argjson photos "$photos_json" \
    '(.sites[] | select(.id == $id) | .photos) |= $photos' "$CATALOG" > "$tmp"
  mv "$tmp" "$CATALOG"

  echo "✓ wired $sid  ($n photo$([ "$n" -eq 1 ] || echo s))"
  processed=$((processed+1))
done < "$MANIFEST"

rm -rf "$STAGE"
echo "————"
echo "processed=$processed  skipped=$skipped  problems=$missing"
[ "$missing" -eq 0 ] || die "finished with problems (see ✗ lines above)"

echo "Validating catalog…"
swift "$SCRIPT_DIR/validate_catalog.swift" "$CATALOG" "$REPO/ByzantineTrail/Resources"
