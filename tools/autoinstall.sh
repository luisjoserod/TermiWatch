#!/bin/zsh
# TermiWatch auto-installer: launchd runs this every few seconds.
# When an iPhone is newly plugged in by USB (and the last install is older than
# REINSTALL_DAYS), it builds TermiWatch, signs it with your Apple ID and installs it.
# The Watch app is embedded, so the iPhone pushes it to the paired Apple Watch.

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
BASE="$HOME/Library/Application Support/TermiWatchAuto"
SRC="$BASE/src"
BUILD="$BASE/build"
LOG="$BASE/autoinstall.log"
STATE="$BASE/.connected"
LAST_OK="$BASE/.last_success"
LOCK="$BASE/.lock"
REINSTALL_DAYS=3   # free Apple IDs: signature expires after 7 days

notify() { osascript -e "display notification \"$1\" with title \"TermiWatch\"" >/dev/null 2>&1; }
log() { print -r -- "$(date '+%F %T') $*" >> "$LOG"; }

# Cheap check: is an iPhone on USB?
if ! ioreg -p IOUSB -l -w0 | grep -q '"USB Product Name" = "iPhone"'; then
  rm -f "$STATE"; exit 0
fi
[[ -f "$STATE" && "$1" != "--force" ]] && exit 0   # already handled this connection
touch "$STATE"

if [[ "$1" != "--force" && -f "$LAST_OK" ]]; then
  age=$(( ($(date +%s) - $(stat -f %m "$LAST_OK")) / 86400 ))
  if (( age < REINSTALL_DAYS )); then log "iPhone connected; installed ${age}d ago, skipping"; exit 0; fi
fi

mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK"' EXIT

log "iPhone connected, starting install"
notify "iPhone detectado, instalando TermiWatch…"

# Wait for the device to be ready (unlocked/trusted)
UDID=""
for i in {1..20}; do
  xcrun devicectl list devices --json-output "$BASE/.devices.json" >/dev/null 2>&1
  UDID=$(/usr/bin/python3 -I -c '
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit()
for x in d.get("result",{}).get("devices",[]):
    h=x.get("hardwareProperties",{}); c=x.get("connectionProperties",{})
    if h.get("platform")=="iOS" and h.get("deviceType")=="iPhone" and c.get("transportType")=="wired":
        print(h.get("udid","")); break' "$BASE/.devices.json" 2>/dev/null)
  [[ -n "$UDID" ]] && break
  sleep 3
done
if [[ -z "$UDID" ]]; then
  log "Could not see the iPhone via devicectl (locked or not trusted?)"
  notify "No pude acceder al iPhone. Desbloquéalo, confía en este Mac y vuelve a conectarlo."
  rm -f "$STATE"; exit 1
fi
log "Device $UDID"

TEAM=$(cat "$BASE/team_id" 2>/dev/null)
if ! xcodebuild -project "$SRC/TermiWatch.xcodeproj" -scheme TermiWatch -configuration Release \
     -destination "id=$UDID" -derivedDataPath "$BUILD" \
     -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
     DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic build >> "$LOG" 2>&1; then
  log "Build failed"; notify "Falló la compilación. Mira autoinstall.log"; rm -f "$STATE"; exit 1
fi

APP="$BUILD/Build/Products/Release-iphoneos/TermiWatch.app"
if xcrun devicectl device install app --device "$UDID" "$APP" >> "$LOG" 2>&1; then
  touch "$LAST_OK"; log "Installed OK"
  # Also push straight to the paired Apple Watch (best effort; it must be nearby and unlocked)
  WATCH=$(/usr/bin/python3 -I -c '
import json,sys
for x in json.load(open(sys.argv[1])).get("result",{}).get("devices",[]):
    h=x.get("hardwareProperties",{})
    if h.get("deviceType")=="appleWatch": print(h.get("udid","")); break' "$BASE/.devices.json" 2>/dev/null)
  if [[ -n "$WATCH" ]] && xcrun devicectl device install app --device "$WATCH" "$APP/Watch/TermiWatch WatchKit App.app" >> "$LOG" 2>&1; then
    log "Watch install OK"; notify "TermiWatch instalado en el iPhone y en el Apple Watch."
  else
    log "Watch install skipped/failed"; notify "TermiWatch instalado en el iPhone. El reloj lo recibirá desde la app Watch."
  fi
else
  log "Install failed"; notify "Falló la instalación. Mira autoinstall.log"; rm -f "$STATE"; exit 1
fi
