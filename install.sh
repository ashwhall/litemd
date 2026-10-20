#!/bin/sh
# Installs LiteMD, or updates it to the latest release. Safe to run again at any time.
#   curl -fsSL https://raw.githubusercontent.com/ashwhall/litemd/main/install.sh | sh
set -eu

REPO="ashwhall/litemd"
APP="/Applications/LiteMD.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
  echo "LiteMD needs macOS on Apple Silicon." >&2
  exit 1
fi

# The releases/latest page redirects to .../releases/tag/vX.Y.Z.
latest_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")
latest=${latest_url##*/v}
case "$latest" in
  ""|*/*) echo "Couldn't find a LiteMD release on GitHub." >&2; exit 1 ;;
esac

installed=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
if [ "$installed" = "$latest" ]; then
  echo "LiteMD $installed is already up to date."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading LiteMD $latest..."
curl -fsSL "https://github.com/$REPO/releases/download/v$latest/LiteMD.zip" -o "$tmp/LiteMD.zip"
ditto -x -k "$tmp/LiteMD.zip" "$tmp"
codesign --verify --deep "$tmp/LiteMD.app"

# Quit politely, so any unsaved documents get a save prompt rather than being killed.
was_running=false
if pgrep -xq LiteMD; then
  was_running=true
  echo "Quitting LiteMD..."
  osascript -e 'quit app "LiteMD"' >/dev/null 2>&1 || true
  for _ in $(seq 60); do
    pgrep -xq LiteMD || break
    sleep 1
  done
  if pgrep -xq LiteMD; then
    echo "LiteMD is still open. Save or close your documents, quit it, then run this again." >&2
    exit 1
  fi
fi

rm -rf "$APP"
ditto "$tmp/LiteMD.app" "$APP"

# Register the app and its Quick Look extension without launching it.
"$LSREGISTER" -f "$APP"
pluginkit -a "$APP/Contents/PlugIns/LiteMDQuickLook.appex"
qlmanage -r >/dev/null 2>&1 || true

if [ -n "$installed" ]; then
  echo "Updated LiteMD from $installed to $latest."
else
  echo "Installed LiteMD $latest. Select a .md file in Finder and press space to preview it."
fi

if [ "$was_running" = true ]; then
  open "$APP"
fi
