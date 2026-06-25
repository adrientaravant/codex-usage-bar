# Releasing Coco Usage Bar

Coco Usage Bar uses the same lightweight release lane as Slite Agent Bar:

- first install: Apple Development signed DMG, not notarized
- updates: Sparkle 2 appcast on GitHub Releases
- feed URL baked into the app: `https://github.com/adrientaravant/coco-usage-bar/releases/latest/download/appcast.xml`

The first Sparkle-capable build is `v0.2.0`. Anyone on an older build must install it manually once. Later builds can update from the menu item or Sparkle's scheduled checks.

## Cut A Release

```bash
APP_VERSION=0.2.1 ./script/release.sh
```

The script:

1. Builds a universal macOS app.
2. Signs it with the local Apple Development identity when available.
3. Creates `CocoUsageBar.dmg` for first-time installs.
4. Creates `coco-usage-bar-<version>.zip` for Sparkle.
5. Signs `appcast.xml` with the Sparkle key stored in Keychain under account `coco-usage-bar`.
6. Publishes a normal GitHub Release with the DMG, zip, appcast, and checksums.

Do not publish the release as a draft or prerelease. GitHub's `latest` redirect skips those, which would strand the appcast.

## First Install Caveat

This free path is not notarized. macOS may require right-click > Open once after dragging the app to Applications. Auto-updates after that are Sparkle-signed.

For no-warning first install, use a Developer ID Application certificate and notarize the DMG/zip.
