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
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
derived="${DERIVED:-$root/build/DerivedData}"

build=(-project "$root/Pullwatch/Pullwatch.xcodeproj" -scheme Pullwatch -configuration Debug
  -destination 'platform=macOS' -derivedDataPath "$derived"
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
if [ -n "${SPM:-}" ]; then build+=(-clonedSourcePackagesDirPath "$SPM"); fi
xcodebuild build -quiet "${build[@]}"

intermediates="$derived/Build/Intermediates.noindex"
sync() {
  local catalog="$1" built="$2"
  local data=()
  while IFS= read -r f; do data+=("$f"); done < <(find "$intermediates/$built" -name '*.stringsdata')
  if ((${#data[@]})); then
    xcrun xcstringstool sync "$catalog" --stringsdata "${data[@]}"
    # xcstringstool writes `"key" : value`; the catalogs here are `"key": value`
    # with sorted keys, so only real changes show in a diff.
    python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p,encoding="utf-8")); d["strings"]=dict(sorted(d["strings"].items())); open(p,"w",encoding="utf-8").write(json.dumps(d,indent=2,ensure_ascii=False)+"\n")' "$catalog"
    echo "$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["strings"]))' "$catalog") strings in ${catalog#"$root"/}"
  fi
}
sync "$root/Pullwatch/Pullwatch/Localizable.xcstrings" "Pullwatch.build/Debug/Pullwatch.build"
sync "$root/PullwatchKit/Sources/PullwatchCore/Localizable.xcstrings" "PullwatchCore.build/Debug/PullwatchCore-t.build"
