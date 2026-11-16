#!/bin/zsh
# TermiWatch auto-installer. launchd runs this every 10 seconds.
#
# Two triggers (free Apple IDs: the signature expires after 7 days):
#   USB  – an iPhone is newly plugged in and the last install is 3+ days old.
#   WiFi – once an hour, if the last install is 4+ days old and the paired
#          iPhone is reachable on the local network, install without a cable.
# It builds TermiWatch, signs it with your Apple ID, installs it on the iPhone
# and pushes the Watch app straight to the paired Apple Watch.
#
#   autoinstall.sh           normal (launchd)
#   autoinstall.sh --force   install now, over USB or Wi-Fi

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
BASE="$HOME/Library/Application Support/TermiWatchAuto"
SRC="$BASE/src"
BUILD="$BASE/build"
LOG="$BASE/autoinstall.log"
STATE="$BASE/.connected"          # USB connection already handled
LAST_OK="$BASE/.last_success"      # mtime = last successful install
LAST_WIFI="$BASE/.last_wifi_check" # mtime = last Wi-Fi attempt
WATCH_PENDING="$BASE/.watch_pending" # iPhone renewed but the watch was unreachable
LOCK="$BASE/.lock"
USB_DAYS=3
WIFI_DAYS=4
WIFI_EVERY=3600   # seconds between Wi-Fi checks

notify() { osascript -e "display notification \"$1\" with title \"TermiWatch\"" >/dev/null 2>&1; }
log() { print -r -- "$(date '+%F %T') $*" >> "$LOG"; }
age_seconds() { [[ -f "$1" ]] && echo $(( $(date +%s) - $(stat -f %m "$1") )) || echo 999999999; }

FORCE=0; [[ "$1" == "--force" ]] && FORCE=1
MODE=""

# --- Decide whether to run -------------------------------------------------
if ioreg -p IOUSB -l -w0 | grep -q '"USB Product Name" = "iPhone"'; then
  if [[ -f "$STATE" && $FORCE == 0 ]]; then
    : # this USB connection was already handled; fall through to the Wi-Fi check
  else
    touch "$STATE"
    if (( FORCE || $(age_seconds "$LAST_OK") >= USB_DAYS * 86400 )); then
      MODE="usb"
    else
      log "iPhone connected by USB; installed $(( $(age_seconds "$LAST_OK") / 86400 ))d ago, skipping"
    fi
  fi
else
  rm -f "$STATE"
fi

if [[ -z "$MODE" ]]; then
  if (( FORCE )); then
    MODE="wifi"
  elif (( $(age_seconds "$LAST_OK") >= WIFI_DAYS * 86400 && $(age_seconds "$LAST_WIFI") >= WIFI_EVERY )); then
    touch "$LAST_WIFI"
    MODE="wifi"
  elif [[ -f "$WATCH_PENDING" ]] && (( $(age_seconds "$LAST_WIFI") >= WIFI_EVERY )); then
    touch "$LAST_WIFI"
    MODE="watch"
  else
    exit 0
  fi
fi

mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK"' EXIT

log "Starting install ($MODE)"
[[ "$MODE" == "usb" ]] && notify "iPhone detectado, instalando TermiWatch…"

# --- Find the iPhone (USB preferred, otherwise local network) --------------
find_devices() {
  xcrun devicectl list devices --json-output "$BASE/.devices.json" >/dev/null 2>&1
  /usr/bin/python3 -I -c '
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit()
phone_usb=phone_any=watch=""
for x in d.get("result",{}).get("devices",[]):
    h=x.get("hardwareProperties",{}); c=x.get("connectionProperties",{})
    if c.get("pairingState")!="paired": continue
    if h.get("deviceType")=="iPhone":
        if c.get("transportType")=="wired": phone_usb=h.get("udid","")
        elif not phone_any: phone_any=h.get("udid","")
    elif h.get("deviceType")=="appleWatch" and not watch:
        watch=h.get("udid","")
print((phone_usb or phone_any) + "|" + watch)' "$BASE/.devices.json" 2>/dev/null
}

UDID=""; WATCH=""
for i in {1..10}; do
  IFS="|" read UDID WATCH <<< "$(find_devices)"
  [[ -n "$UDID" ]] && break
  sleep 3
done
if [[ -z "$UDID" ]]; then
  log "iPhone not reachable ($MODE)"
  if [[ "$MODE" == "usb" ]]; then
    notify "No pude acceder al iPhone. Desbloquéalo, confía en este Mac y vuelve a conectarlo."
    rm -f "$STATE"
  fi
  exit 1   # Wi-Fi: silently retry in an hour
fi
log "Device $UDID watch=${WATCH:-none}"

APP="$BUILD/Build/Products/Release-iphoneos/TermiWatch.app"

install_watch() {  # returns 0 on success; retries a few times (watch may be asleep)
  [[ -n "$WATCH" ]] || return 1
  for attempt in 1 2 3; do
    xcrun devicectl device install app --device "$WATCH" "$APP/Watch/TermiWatch WatchKit App.app" >> "$LOG" 2>&1 && return 0
    sleep 20
  done
  return 1
}

if [[ "$MODE" == "watch" ]]; then
  if [[ -d "$APP" ]] && install_watch; then
    rm -f "$WATCH_PENDING"; log "Watch install OK (retry)"
    notify "TermiWatch renovado también en el Apple Watch."
  else
    log "Watch still unreachable, retrying in an hour"
  fi
  exit 0
fi

# --- Build and install -----------------------------------------------------
TEAM=$(cat "$BASE/team_id" 2>/dev/null)
if ! xcodebuild -project "$SRC/TermiWatch.xcodeproj" -scheme TermiWatch -configuration Release \
     -destination "id=$UDID" -derivedDataPath "$BUILD" \
     -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
     DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic build >> "$LOG" 2>&1; then
  log "Build failed ($MODE)"
  notify "Falló la compilación de TermiWatch. Mira autoinstall.log"
  [[ "$MODE" == "usb" ]] && rm -f "$STATE"
  exit 1
fi

if xcrun devicectl device install app --device "$UDID" "$APP" >> "$LOG" 2>&1; then
  touch "$LAST_OK"; log "Installed OK ($MODE)"
  if install_watch; then
    rm -f "$WATCH_PENDING"
    log "Watch install OK"; notify "TermiWatch renovado en el iPhone y en el Apple Watch ($MODE)."
  else
    touch "$WATCH_PENDING"
    log "Watch unreachable; will retry hourly"
    notify "TermiWatch renovado en el iPhone ($MODE). El reloj se renovará cuando esté disponible."
  fi
else
  log "Install failed ($MODE)"
  [[ "$MODE" == "usb" ]] && { notify "Falló la instalación de TermiWatch. Mira autoinstall.log"; rm -f "$STATE"; }
  exit 1
fi
