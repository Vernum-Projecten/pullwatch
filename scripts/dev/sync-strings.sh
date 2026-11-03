#!/usr/bin/env bash
# scripts/dev/sync-strings.sh
#
# Builds the app and writes every string the compiler extracted into the
# String Catalogs: the app's and each kit module's Localizable.xcstrings.
# Xcode does this on every build in the IDE; xcodebuild only extracts, so
# run this after changing user-facing text outside Xcode, then add the
# English, German and French for each new entry (the keys are Dutch) and
# build again. LocalizationTests fails while any entry misses a language.

set -euo pipefail
root="$(git rev-parse --show-toplevel)"
here="$(cd "$(dirname "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
derived="${DERIVED:-$root/build/DerivedData}"

build=(-project "$root/Pullwatch/Pullwatch.xcodeproj" -scheme Pullwatch -configuration Debug
  -destination 'platform=macOS' -derivedDataPath "$derived"
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
if [ -n "${SPM:-}" ]; then build+=(-clonedSourcePackagesDirPath "$SPM"); fi
xcodebuild build -quiet "${build[@]}"

intermediates="$derived/Build/Intermediates.noindex"
# Only this Mac's architecture, the one built above: files from an earlier
# build for another architecture would keep text alive that left the code.
arch="$(uname -m)"
sync() {
  local catalog="$1" built="$2"
  local data=()
  while IFS= read -r f; do data+=("$f"); done < <(find "$intermediates/$built" -path "*/Objects-normal/$arch/*" -name '*.stringsdata')
  if ((${#data[@]})); then
    xcrun xcstringstool sync "$catalog" --stringsdata "${data[@]}"
    # Then: drop every entry the compiler no longer extracts (stale or never
    # marked), and write `"key": value` with sorted keys as the catalogs here
    # are (xcstringstool writes `"key" : value`), so a diff shows only real
    # changes. An entry with "shouldTranslate": false stays.
    python3 -I "$here/catalog-tidy.py" "$catalog" "${data[@]}"
    echo "$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["strings"]))' "$catalog") strings in ${catalog#"$root"/}"
  fi
}
sync "$root/Pullwatch/Pullwatch/Localizable.xcstrings" "Pullwatch.build/Debug/Pullwatch.build"
# Elke PullwatchKit-module met een eigen catalog; Xcode bouwt de module in
# PullwatchKit.build/Debug/<Module>-t.build.
for catalog in "$root"/PullwatchKit/Sources/*/Localizable.xcstrings; do
  module="$(basename "$(dirname "$catalog")")"
  if [ ! -d "$intermediates/PullwatchKit.build/Debug/$module-t.build" ]; then
    echo "sync-strings: no build output for $module; is it linked by the app?" >&2
    exit 1
  fi
  sync "$catalog" "PullwatchKit.build/Debug/$module-t.build"
done
