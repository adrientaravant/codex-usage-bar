#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${APP_VERSION:-}" ]]; then
  LATEST="$(gh release list -R adrientaravant/coco-usage-bar --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null | sed 's/^v//')"
  APP_VERSION="$(echo "${LATEST:-0.1.0}" | awk -F. -v OFS=. '{$NF+=1; print}')"
fi

REL="$ROOT_DIR/../releases/v$APP_VERSION"
NOTES="$REL/notes.md"

echo "Releasing Coco Usage Bar $APP_VERSION"
RELEASE_DIR="$REL" APP_VERSION="$APP_VERSION" ./script/package_tester.sh

mkdir -p "$REL"
if [[ ! -f "$NOTES" ]]; then
  cat >"$NOTES" <<EOF
## $APP_VERSION

- Adds Sparkle auto-updates and a DMG installer.
EOF
fi

./script/generate_appcast.sh "$REL" "$NOTES"

gh release view "v$APP_VERSION" -R adrientaravant/coco-usage-bar >/dev/null 2>&1 || \
  gh release create "v$APP_VERSION" \
    --repo adrientaravant/coco-usage-bar \
    --title "v$APP_VERSION" \
    --notes-file "$NOTES" \
    --latest

gh release upload "v$APP_VERSION" \
  "$REL/CocoUsageBar.dmg" \
  "$REL/CocoUsageBar.dmg.sha256" \
  "$REL/coco-usage-bar-$APP_VERSION.zip" \
  "$REL/coco-usage-bar-$APP_VERSION.zip.sha256" \
  "$REL/appcast.xml" \
  --repo adrientaravant/coco-usage-bar \
  --clobber

echo "Published https://github.com/adrientaravant/coco-usage-bar/releases/tag/v$APP_VERSION"
