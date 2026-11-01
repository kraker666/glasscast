#!/bin/bash
# Usage: package-ipa.sh <path/to/App.app> <entitlements.plist> <output.ipa>
# Ad-hoc signs the app (embedding the entitlements so SideStore can see them), then zips
# it into an IPA. SideStore re-signs everything with the owner's free Apple ID on install.
set -euo pipefail

APP="$1"
ENTITLEMENTS="$2"
OUT="$3"

if [ -d "$APP/Frameworks" ]; then
  find "$APP/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -print0 |
    while IFS= read -r -d '' fw; do
      codesign --force --sign - --timestamp=none "$fw"
    done
fi
codesign --force --sign - --timestamp=none --entitlements "$ENTITLEMENTS" "$APP"

echo "Entitlements embedded in $(basename "$APP"):"
codesign -d --entitlements - "$APP" || true
echo "Bundle contents:"
ls "$APP"

WORK=$(mktemp -d)
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
(cd "$WORK" && zip -qry ipa.zip Payload)
mv "$WORK/ipa.zip" "$OUT"
ls -lh "$OUT"
