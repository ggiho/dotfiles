#!/bin/bash
# Build a custom terminal-notifier bundle so Claude Code notifications carry the
# Claude icon instead of Apple's Terminal icon.
#
# macOS takes a notification's icon from the *sending bundle* and offers no API to
# override it per notification — terminal-notifier removed -appIcon and -sender in
# 3.0.0 for exactly this reason. Its README documents a renamed copy of the app as
# the only workaround, which is what this script builds.
#
# Re-run after Homebrew upgrades terminal-notifier.
set -euo pipefail

DEST="$HOME/Applications/Claude Code Notifier.app"
ICON_SRC="/Applications/Claude.app/Contents/Resources/electron.icns"
BUNDLE_ID="fr.julienxx.oss.terminal-notifier.claude-code"

bin=$(command -v terminal-notifier 2>/dev/null || true)
[ -n "$bin" ] || { echo "terminal-notifier not installed — nothing to do" >&2; exit 0; }

# .../Cellar/terminal-notifier/<ver>/bin/terminal-notifier -> .../<ver>/terminal-notifier.app
src="$(dirname "$(dirname "$(readlink -f "$bin")")")/terminal-notifier.app"
[ -d "$src" ] || { echo "source bundle not found next to $bin" >&2; exit 1; }
[ -f "$ICON_SRC" ] || { echo "Claude.app icon not found ($ICON_SRC) — skipping custom bundle" >&2; exit 0; }

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -R "$src" "$DEST"

# swap the icon (README: an existing .icns is used as-is)
rm -f "$DEST/Contents/Resources/Terminal.icns"
cp "$ICON_SRC" "$DEST/Contents/Resources/ClaudeCode.icns"

P="$DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile ClaudeCode"      "$P"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID"    "$P"
/usr/libexec/PlistBuddy -c "Set :CFBundleName 'Claude Code'"       "$P"

# upstream ships ad-hoc signed; re-seal after editing the bundle
codesign --force --sign - "$DEST" >/dev/null 2>&1

# make LaunchServices aware of the new bundle id
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST" >/dev/null 2>&1 || true

echo "built: $DEST"
echo "bundle id: $BUNDLE_ID"
echo
echo "이 번들은 새 bundle id 라서 알림 권한을 따로 받아야 한다:"
echo "  System Settings → Notifications → 'Claude Code' 를 켤 것"
echo "  (첫 발송 시 권한 프롬프트가 뜨면 허용해도 된다)"
