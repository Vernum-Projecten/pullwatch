#!/usr/bin/env bash
# scripts/release/release.sh [--unsigned]
#
# Bouwt Pullwatch (Release, universal) en maakt dist/Pullwatch-<versie>.dmg.
# Standaard: gesigned met Developer ID (hardened runtime), genotariseerd en
# gestapled, zodat de DMG zonder Gatekeeper-waarschuwing opent. Met
# --unsigned: ad-hoc gesigned, voor lokaal testen.
#
# Nodig voor een gesignde release: een Developer ID Application-certificaat
# in de Keychain en een notarytool-profiel
# (xcrun notarytool store-credentials pullwatch --apple-id <id> --team-id <team>).
# Andere waarden met SIGN_ID=… en NOTARY_PROFILE=….
# De versie komt uit Pullwatch/App.xcconfig (MARKETING_VERSION).

set -euo pipefail

sign=1
case "${1:-}" in
  "") ;;
  --unsigned) sign=0 ;;
  *)
    echo "usage: release.sh [--unsigned]" >&2
    exit 2
    ;;
esac

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIGN_ID="${SIGN_ID:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-pullwatch}"

version="$(sed -n 's/^MARKETING_VERSION *= *//p' Pullwatch/App.xcconfig)"
[ -n "$version" ] || {
  echo "no MARKETING_VERSION in Pullwatch/App.xcconfig" >&2
  exit 1
}
derived="$root/build"
app="$derived/Build/Products/Release/Pullwatch.app"
dmg="$root/dist/Pullwatch-$version.dmg"

xcodebuild -project Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" build

if ((sign)); then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$app"
  codesign --verify --strict --verbose=2 "$app"
fi

stage="$root/dist/dmg"
rm -rf "$stage"
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname Pullwatch -srcfolder "$stage" -ov -format UDZO "$dmg"
rm -r "$stage"

if ((sign)); then
  codesign --force --timestamp --sign "$SIGN_ID" "$dmg"
  xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose "$dmg"
fi
echo "$dmg"
