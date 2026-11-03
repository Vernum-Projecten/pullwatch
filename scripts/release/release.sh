#!/usr/bin/env bash
# scripts/release/release.sh [--unsigned]
#
# Bouwt Pullwatch (Release, universal) en maakt met package.sh
# dist/Pullwatch-<versie>.dmg (met installatievenster) en dist/Pullwatch-<versie>.zip
# (de update voor Sparkle; release.yml schrijft er de appcast bij).
# Dezelfde stappen lokaal en in .github/workflows/release.yml.
#
# Standaard: de app gesigned met Developer ID (hardened runtime),
# genotariseerd en gestapled, daarna verpakt, en de dmg zelf ook gesigned,
# genotariseerd en gestapled. Zo opent de dmg zonder Gatekeeper-waarschuwing
# en draagt de app in de zip (voor de updater) zijn eigen ticket. Met
# --unsigned: ad-hoc gesigned, voor lokaal testen en voor CI.
#
# Nodig voor een gesignde release: een Developer ID Application-certificaat
# in een Keychain in de zoeklijst, en voor notarytool een van beide:
#   - lokaal een Keychain-profiel
#     (xcrun notarytool store-credentials pullwatch --apple-id <id> --team-id <team>),
#     ander profiel met NOTARY_PROFILE=…;
#   - in CI een App Store Connect API-sleutel: NOTARY_KEY_FILE (pad naar de
#     .p8), NOTARY_KEY_ID en NOTARY_ISSUER_ID.
# Een andere identiteit met SIGN_ID=…. De versie en het buildnummer komen uit
# Pullwatch/App.xcconfig (MARKETING_VERSION, CURRENT_PROJECT_VERSION).

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

# De inloggegevens voor notarytool: de API-sleutel als die er is (CI), anders
# het Keychain-profiel.
if [ -n "${NOTARY_KEY_FILE:-}" ]; then
  : "${NOTARY_KEY_ID:?NOTARY_KEY_FILE is set, so NOTARY_KEY_ID is needed too}"
  : "${NOTARY_ISSUER_ID:?NOTARY_KEY_FILE is set, so NOTARY_ISSUER_ID is needed too}"
  notary_auth=(--key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  notary_auth=(--keychain-profile "$NOTARY_PROFILE")
fi

# Stuurt een bestand naar Apple en wacht op het oordeel; bij een afwijzing
# komt het logboek van Apple in de uitvoer.
notarise() {
  local out id
  out="$(xcrun notarytool submit "$1" "${notary_auth[@]}" --wait --timeout 30m --output-format plist)" || true
  id="$(plutil -extract id raw -o - - <<<"$out" 2>/dev/null || true)"
  if [ "$(plutil -extract status raw -o - - <<<"$out" 2>/dev/null || true)" != "Accepted" ]; then
    echo "notarisation of $1 failed:" >&2
    printf '%s\n' "$out" >&2
    if [ -n "$id" ]; then xcrun notarytool log "$id" "${notary_auth[@]}" >&2 || true; fi
    exit 1
  fi
  echo "notarised $1 ($id)"
}

if ((sign)); then
  security find-identity -v -p codesigning | grep -qF "$SIGN_ID" || {
    echo "no code signing identity matching '$SIGN_ID' in the keychain search list; see docs/releasing.md" >&2
    exit 1
  }
fi

rm -rf "$derived/Build/Products/Release"
xcodebuild -project Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" build

# Sparkle (#9), zoals Sparkles documentatie het voor een app zonder App Sandbox zegt
# (sparkle-project.org/documentation/sandboxing): de XPC-services zijn alleen voor een
# gesandboxte app en mogen eruit. Daarna elk onderdeel van Sparkle apart signen, van binnen
# naar buiten en zonder --deep, met hardened runtime: Autoupdate, Updater.app, het framework.
# Zonder Developer ID ad-hoc, omdat het weghalen de handtekening van het framework breekt.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
[ -d "$sparkle" ] || {
  echo "no Sparkle.framework in $app" >&2
  exit 1
}
rm -rf "$sparkle/Versions/B/XPCServices"
if ((sign)); then
  sparkle_sign=(--force --options runtime --timestamp --sign "$SIGN_ID")
else
  sparkle_sign=(--force --options runtime --sign -)
fi
for part in "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle"; do
  codesign "${sparkle_sign[@]}" "$part"
done
if ((sign)); then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$app"
else
  codesign --force --options runtime --sign - "$app"
fi
codesign --verify --deep --strict --verbose=2 "$app"

if ((sign)); then
  # De app eerst, zodat ook de app in de zip een gestapled ticket heeft.
  zip="$derived/notarise.zip"
  ditto -c -k --keepParent "$app" "$zip"
  notarise "$zip"
  rm -f "$zip"
  xcrun stapler staple "$app"
  spctl --assess --type execute --verbose=2 "$app"
fi

# Het installatievenster (achtergrond, pijl, vaste posities) en de zip voor
# de updater; zie package.sh.
"$root/scripts/release/package.sh" "$app" "$version" "$root/dist"

if ((sign)); then
  codesign --force --timestamp --sign "$SIGN_ID" "$dmg"
  notarise "$dmg"
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose "$dmg"
fi
echo "$dmg"
