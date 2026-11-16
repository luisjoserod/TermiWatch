#!/bin/zsh
# Regenerates the watch app icons (thin gray ring, full-bleed square so watchOS
# masks it to a perfect circle) and the complication icon (inset circle) from
# the original upstream artwork.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
ORIG="$TMP/original-1024.png"
ICON="$REPO/TermiWatch WatchKit App/Assets.xcassets/AppIcon.appiconset"
COMP="$REPO/TermiWatch WatchKit Extension/Assets.xcassets/ComplicationIcon.imageset/icon@2x.png"

# Original icon from the upstream commit this fork is based on.
git -C "$REPO" show "d7ab1fb:TermiWatch WatchKit App/Assets.xcassets/AppIcon.appiconset/black-1024@1x.png" > "$ORIG"

for f in "$ICON"/*.png; do
  px=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
  swift "$REPO/tools/make_icon.swift" "$ORIG" "$f" fullbleed "$px"
done
swift "$REPO/tools/make_icon.swift" "$ORIG" "$COMP" inset 94
echo "Icons regenerated."
