#!/usr/bin/env bash
# SPDX-FileCopyrightText: Pullwatch contributors
# SPDX-License-Identifier: Apache-2.0
# scripts/checks/acknowledgements.sh: keeps the acknowledgements in the app
# (#166) complete. The app ships the licence of everything it contains in
# Contents/Resources/Acknowledgements/, listed in acknowledgements.json. This
# check fails when a dependency is added or bumped without updating that list.
#
# Usage:
#   acknowledgements.sh [<repo-root>]
#       Checks, against the project's Package.resolved:
#       - every pin is in the manifest (with the resolved version) or in
#         acknowledgements-not-linked.txt (with a reason), never in both;
#       - every package in the manifest is still pinned;
#       - every file the manifest names exists and is not empty;
#       - the LICENSE and NOTICE in the app are the repository's;
#       - NOTICE names every manifest entry and its version.
#   acknowledgements.sh --self-test
#       Runs the check over a stub repository: complete, then with one
#       entry removed, one version bumped and one file missing.
#
# Needs jq. Exit 0 when complete, 1 when not, 2 on a usage error.

set -euo pipefail

readonly RESOLVED=Pullwatch/Pullwatch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
readonly FOLDER=Pullwatch/Pullwatch/Acknowledgements/Resources/Acknowledgements
readonly NOT_LINKED=scripts/checks/acknowledgements-not-linked.txt

check() {
  local root=$1 failed=0
  local manifest="$root/$FOLDER/acknowledgements.json"
  fail() {
    echo "acknowledgements: $*" >&2
    failed=1
  }
  for f in "$root/$RESOLVED" "$manifest" "$root/$NOT_LINKED"; do
    [[ -f "$f" ]] || {
      echo "acknowledgements: missing ${f#"$root"/}" >&2
      return 1
    }
  done

  # identity<TAB>version of every pin, and of every package in the manifest.
  local pins acknowledged not_linked
  pins="$(jq -r '.pins[] | "\(.identity)\t\(.state.version // "")"' "$root/$RESOLVED")"
  acknowledged="$(jq -r '.components[] | select(.package != null) | "\(.package)\t\(.version)"' "$manifest")"
  not_linked="$(grep -v '^#' "$root/$NOT_LINKED" | grep -v '^[[:space:]]*$' || true)"

  local identity version reason listed
  while IFS=$'\t' read -r identity version; do
    [[ -n "$identity" ]] || continue
    listed="$(awk -F'\t' -v id="$identity" '$1 == id { print $2 }' <<<"$acknowledged")"
    reason="$(awk -v id="$identity" 'index($0, id ":") == 1 { sub(/^[^:]*:[[:space:]]*/, ""); print }' <<<"$not_linked")"
    if [[ -n "$listed" && -n "$reason" ]]; then
      fail "$identity is in acknowledgements.json and in $NOT_LINKED; pick one."
    elif [[ -n "$listed" ]]; then
      [[ "$listed" == "$version" ]] ||
        fail "$identity is $version in Package.resolved but $listed in acknowledgements.json."
    elif [[ -z "$(awk -v id="$identity" 'index($0, id ":") == 1' <<<"$not_linked")" ]]; then
      fail "$identity ($version) is in Package.resolved but not in acknowledgements.json (with its licence) or in $NOT_LINKED (with a reason)."
    elif [[ -z "$reason" ]]; then
      fail "$identity has no reason in $NOT_LINKED."
    fi
  done <<<"$pins"

  while IFS=$'\t' read -r identity version; do
    [[ -n "$identity" ]] || continue
    awk -F'\t' -v id="$identity" '$1 == id { found = 1 } END { exit !found }' <<<"$pins" ||
      fail "$identity is in acknowledgements.json but no longer in Package.resolved."
  done <<<"$acknowledged"

  local file
  while IFS= read -r file; do
    [[ -s "$root/$FOLDER/$file" ]] || fail "$FOLDER/$file is missing or empty."
  done < <(jq -r '.components[] | .file, (.notice // empty)' "$manifest")

  for file in LICENSE NOTICE; do
    cmp -s "$root/$file" "$root/$FOLDER/$file" ||
      fail "$FOLDER/$file differs from $file; copy it again (cp $file $FOLDER/)."
  done

  local name
  while IFS=$'\t' read -r name version; do
    grep -qF -- "$name" "$root/NOTICE" || fail "NOTICE does not name $name."
    grep -qF -- "$version" "$root/NOTICE" || fail "NOTICE does not name version $version of $name."
  done < <(jq -r '.components[] | "\(.name)\t\(.version)"' "$manifest")

  if ((failed)); then
    echo "acknowledgements: see $FOLDER/acknowledgements.json; licence texts come verbatim from the package checkouts." >&2
    return 1
  fi
  echo "acknowledgements: $(jq '.components | length' "$manifest") components, every pin accounted for."
}

self_test() {
  # Global, so the EXIT trap still sees it after the function returns.
  work="$(mktemp -d)"
  trap 'rm -r -- "$work"' EXIT
  local stub="$work/repo"
  mkdir -p "$stub/$(dirname "$RESOLVED")" "$stub/$FOLDER" "$stub/$(dirname "$NOT_LINKED")"
  cat >"$stub/$RESOLVED" <<'JSON'
{ "pins" : [
  { "identity" : "sparkle", "state" : { "version" : "2.10.1" } },
  { "identity" : "swift-log", "state" : { "version" : "1.16.2" } },
  { "identity" : "swift-nio", "state" : { "version" : "2.105.0" } }
] }
JSON
  cat >"$stub/$FOLDER/acknowledgements.json" <<'JSON'
{ "components" : [
  { "id" : "sparkle", "name" : "Sparkle", "version" : "2.10.1", "file" : "sparkle-LICENSE.txt", "package" : "sparkle" },
  { "id" : "swift-log", "name" : "SwiftLog", "version" : "1.16.2", "file" : "swift-log-LICENSE.txt", "notice" : "swift-log-NOTICE.txt", "package" : "swift-log" },
  { "id" : "octicons", "name" : "GitHub Octicons", "version" : "19.41.0", "file" : "octicons-LICENSE.txt" }
] }
JSON
  printf '# comment\nswift-nio: only the SDK'"'"'s conformance tools use it.\n' >"$stub/$NOT_LINKED"
  printf 'Apache License\n' >"$stub/LICENSE"
  printf 'Sparkle 2.10.1, SwiftLog 1.16.2, GitHub Octicons 19.41.0\n' >"$stub/NOTICE"
  cp "$stub/LICENSE" "$stub/NOTICE" "$stub/$FOLDER/"
  for f in sparkle-LICENSE.txt swift-log-LICENSE.txt swift-log-NOTICE.txt octicons-LICENSE.txt; do
    echo text >"$stub/$FOLDER/$f"
  done

  # expect NAME WANT: the check over the stub exits WANT.
  expect() {
    local name=$1 want=$2 status=0
    bash "$SELF" "$stub" >"$work/out" 2>&1 || status=$?
    if [[ "$status" -ne "$want" ]]; then
      echo "acknowledgements: self-test failed: $name exited $status, wanted $want." >&2
      cat "$work/out" >&2
      exit 1
    fi
  }
  # edit FILE JQ: rewrite a JSON file of the stub.
  edit() {
    jq "$2" "$1" >"$work/tmp" && mv "$work/tmp" "$1"
  }
  snapshot() { cp -R "$stub" "$work/clean"; }
  restore() { rm -r "$stub" && cp -R "$work/clean" "$stub"; }

  expect "a complete stub" 0
  snapshot

  edit "$stub/$FOLDER/acknowledgements.json" 'del(.components[] | select(.id == "swift-log"))'
  expect "a linked package missing from the manifest" 1
  restore

  edit "$stub/$RESOLVED" '(.pins[] | select(.identity == "sparkle") | .state.version) = "2.11.0"'
  expect "a bumped dependency" 1
  restore

  edit "$stub/$RESOLVED" '.pins += [{ "identity" : "swift-new", "state" : { "version" : "1.0.0" } }]'
  expect "a new dependency" 1
  restore

  printf 'swift-log: also listed\n' >>"$stub/$NOT_LINKED"
  expect "a package in both lists" 1
  restore

  rm "$stub/$FOLDER/swift-log-NOTICE.txt"
  expect "a missing licence file" 1
  restore

  : >"$stub/$FOLDER/octicons-LICENSE.txt"
  expect "an empty licence file" 1
  restore

  echo changed >>"$stub/NOTICE"
  expect "a NOTICE in the app that is out of date" 1
  restore

  printf 'Sparkle 2.10.1, GitHub Octicons 19.41.0\n' | tee "$stub/NOTICE" >"$stub/$FOLDER/NOTICE"
  expect "a NOTICE without an entry" 1
  restore

  echo "acknowledgements: self-test passed."
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
readonly SELF
case "${1:-}" in
  --self-test) self_test ;;
  -*)
    echo "usage: acknowledgements.sh [<repo-root>] | --self-test" >&2
    exit 2
    ;;
  "") check "$(cd "$(dirname "$SELF")/../.." && pwd)" ;;
  *) check "$1" ;;
esac
