#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOLDER="${1:?usage: generate_appcast.sh <release-folder> [release-notes-file]}"
NOTES="${2:-}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-coco-usage-bar}"
DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX:-https://github.com/adrientaravant/coco-usage-bar/releases/latest/download/}"

TOOL="$(find "$ROOT_DIR/.build/artifacts/sparkle" -name generate_appcast -type f 2>/dev/null | head -1)"
if [[ -z "$TOOL" ]]; then
  echo "generate_appcast not found. Run swift build first so SwiftPM fetches Sparkle." >&2
  exit 1
fi

EXTRA_ARGS=()
if [[ -n "$NOTES" ]]; then
  if [[ ! -f "$NOTES" ]]; then
    echo "release notes not found: $NOTES" >&2
    exit 1
  fi
  EXT="${NOTES##*.}"
  case "$EXT" in
    md|html|txt) ;;
    *) echo "release notes must be .md, .html, or .txt" >&2; exit 1 ;;
  esac
  shopt -s nullglob
  for archive in "$FOLDER"/*.zip; do
    cp "$NOTES" "$FOLDER/$(basename "${archive%.zip}").$EXT"
  done
  shopt -u nullglob
  EXTRA_ARGS+=(--embed-release-notes)
fi

DMG_STASH=""
restore_dmgs() {
  if [[ -n "$DMG_STASH" && -d "$DMG_STASH" ]]; then
    shopt -s nullglob
    for dmg in "$DMG_STASH"/*.dmg; do mv "$dmg" "$FOLDER"/; done
    shopt -u nullglob
    rmdir "$DMG_STASH" 2>/dev/null || true
  fi
}

shopt -s nullglob
DMGS=("$FOLDER"/*.dmg)
shopt -u nullglob
if [[ "${#DMGS[@]}" -gt 0 ]]; then
  DMG_STASH="$(mktemp -d)"
  trap restore_dmgs EXIT
  mv "${DMGS[@]}" "$DMG_STASH"/
fi

"$TOOL" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} \
  "$FOLDER"

restore_dmgs
trap - EXIT

echo "$FOLDER/appcast.xml"
