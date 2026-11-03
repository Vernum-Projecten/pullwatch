#!/usr/bin/env bash
# scripts/release/package.sh <Pullwatch.app> <versie> <uitvoermap>
#
# De bestanden van een release: Pullwatch-<versie>.dmg voor mensen en
# Pullwatch-<versie>.zip voor de updater (Sparkle, later). Overgenomen van
# FerroLICENCE. De app moet al gesigned zijn (Developer ID of ad-hoc);
# release.sh signeert, notariseert en staplet daarna de dmg. De formaten
# zijn die uit Sparkles publicatiegids: een zip van ditto die symlinks
# bewaart, en een APFS-image gecomprimeerd met lzfse. De dmg opent als een
# installatievenster dat Finder indeelt, dus dit vraagt een sessie die
# Finder mag besturen (Automatisering in Privacy en beveiliging).

set -euo pipefail

usage="usage: package.sh <app> <version> <out-dir>"
app="${1:?$usage}"
version="${2:?$usage}"
out="${3:?$usage}"
mkdir -p "$out"

ditto -c -k --sequesterRsrc --keepParent "$app" "$out/Pullwatch-$version.zip"

# Het installatievenster: de app links, een link naar Applications rechts,
# op de achtergrond die dmg-background.swift tekent. Finder legt de indeling
# vast in de .DS_Store van het volume zolang de image schrijfbaar is; daarna
# wordt de image gecomprimeerd tot de alleen-lezen .dmg die mensen openen.
here="$(cd "$(dirname "$0")" && pwd)"
volume="Pullwatch $version"
mounted="/Volumes/$volume"
work="$(mktemp -d)"
# Bij een fout geen volume of tijdelijke map achterlaten.
cleanup() {
  if [ -d "$mounted" ]; then diskutil eject "$mounted" >/dev/null 2>&1 || true; fi
  rm -rf "$work"
}
trap cleanup EXIT

swift "$here/dmg-background.swift" "$work/" >/dev/null
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff" >/dev/null

writable="$work/writable.dmg"
megabytes=$(($(du -sm "$app" | cut -f1) + 20))
diskutil image create blank --fs APFS --size "${megabytes}m" --volumeName "$volume" "$writable" >/dev/null
if [ -d "$mounted" ]; then diskutil eject "$mounted" >/dev/null; fi
diskutil image attach "$writable" >/dev/null
[ -d "$mounted" ] || {
  echo "the writable image did not mount at $mounted" >&2
  exit 1
}
ditto "$app" "$mounted/Pullwatch.app"
ln -s /Applications "$mounted/Applications"
mkdir "$mounted/.background"
cp "$work/background.tiff" "$mounted/.background/background.tiff"

# De posities zijn die van dmg-background.swift: iconen op (170, 200) en
# (490, 200) in een venster van 660 bij 400.
osascript - "$volume" <<'APPLESCRIPT' >/dev/null
on run argv
  tell application "Finder"
    tell disk (item 1 of argv)
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      -- 660 bij 400 inhoud, plus de titelbalk van 28 punten.
      set the bounds of container window to {200, 120, 860, 548}
      set options to the icon view options of container window
      set arrangement of options to not arranged
      set icon size of options to 112
      set text size of options to 13
      set background picture of options to file ".background:background.tiff"
      set position of item "Pullwatch.app" of container window to {170, 200}
      set position of item "Applications" of container window to {490, 200}
      update without registering applications
      delay 1
      close
    end tell
  end tell
end run
APPLESCRIPT
for _ in $(seq 1 20); do
  [ -f "$mounted/.DS_Store" ] && break
  sleep 0.5
done
[ -f "$mounted/.DS_Store" ] || {
  echo "Finder did not record the window layout" >&2
  exit 1
}
sync
diskutil eject "$mounted" >/dev/null
rm -f "$out/Pullwatch-$version.dmg"
diskutil image create from --format ULFO "$writable" "$out/Pullwatch-$version.dmg" >/dev/null
echo "packaged Pullwatch-$version.dmg and Pullwatch-$version.zip in $out"
