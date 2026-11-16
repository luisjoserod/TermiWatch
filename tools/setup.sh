#!/bin/zsh
# Sets up TermiWatch auto-install on a Mac from this repository.
#
#   ./tools/setup.sh <TEAM_ID>
#
# TEAM_ID: your Apple developer team ID (Xcode → Settings → Accounts → your
# Apple ID → Personal Team). Current one: 7RBUM96B5C.
#
# What it does:
#   1. Links this repo to ~/Library/Application Support/TermiWatchAuto/src
#   2. Installs tools/autoinstall.sh and saves the team ID next to it
#   3. Installs and starts the launchd agent that builds + installs the app
#      whenever the iPhone is plugged in by USB (every 3+ days)
set -e

TEAM_ID="$1"
if [[ -z "$TEAM_ID" ]]; then
  echo "Usage: $0 <TEAM_ID>"; exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$HOME/Library/Application Support/TermiWatchAuto"
LABEL="com.luisjoserod.termiwatch-autoinstall"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

[[ -d /Applications/Xcode.app ]] || { echo "Install Xcode from the App Store first."; exit 1; }

mkdir -p "$BASE"
if [[ "$REPO" != "$BASE/src" ]]; then
  if [[ -e "$BASE/src" ]]; then
    echo "$BASE/src already exists and is not this repo. Move it away first."; exit 1
  fi
  ln -s "$REPO" "$BASE/src"
  echo "Linked $BASE/src -> $REPO"
fi

cp "$REPO/tools/autoinstall.sh" "$BASE/autoinstall.sh"
chmod +x "$BASE/autoinstall.sh"
print -r -- "$TEAM_ID" > "$BASE/team_id"

# Point the project at this team.
sed -i '' -E "s/DEVELOPMENT_TEAM = [A-Z0-9\"]+;/DEVELOPMENT_TEAM = $TEAM_ID;/" \
  "$REPO/TermiWatch.xcodeproj/project.pbxproj"

# Minimum Xcode components: iOS + watchOS platforms, Apple Silicon variant only
# (~11 GB). Both are required to build for real devices (the app embeds the
# watch app). The simulator devices Xcode auto-creates are not needed.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ARCH=$([[ "$(uname -m)" == "arm64" ]] && echo arm64 || echo universal)
xcodebuild -downloadPlatform iOS -architectureVariant "$ARCH" || true
xcodebuild -downloadPlatform watchOS -architectureVariant "$ARCH" || true
xcrun simctl delete all 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents"
sed "s#__HOME__#$HOME#g" "$REPO/tools/$LABEL.plist" > "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo
echo "Done. Plug in the iPhone (unlocked) to build and install TermiWatch."
echo "Force an install now:  zsh \"$BASE/autoinstall.sh\" --force"
echo "Log:                   $BASE/autoinstall.log"
