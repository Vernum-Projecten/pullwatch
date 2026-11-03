#!/usr/bin/env bash
# scripts/release/check-version.sh vX.Y.Z
#
# Het releaseplan, overgenomen van FerroLICENCE: de tag noemt de versie van
# de app (MARKETING_VERSION in Pullwatch/App.xcconfig), het buildnummer
# (CURRENT_PROJECT_VERSION) is een geheel getal, en CHANGELOG.md heeft een
# uitgebrachte sectie voor de versie met tekst erin. Alles moet kloppen
# voordat er iets gebouwd wordt.

set -euo pipefail

tag="${1:?usage: check-version.sh vX.Y.Z}"
if ! [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  echo "tag '$tag' is not vX.Y.Z" >&2
  exit 1
fi
version="${BASH_REMATCH[1]}"

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/../.."

setting() { sed -n "s/^$1 *= *\(.*\)$/\1/p" "$2" | head -n 1; }

app="$(setting MARKETING_VERSION Pullwatch/App.xcconfig)"
if [ "$app" != "$version" ]; then
  echo "tag $tag but Pullwatch/App.xcconfig says MARKETING_VERSION = $app" >&2
  exit 1
fi

build="$(setting CURRENT_PROJECT_VERSION Pullwatch/App.xcconfig)"
if ! [[ "$build" =~ ^[0-9]+$ ]]; then
  echo "Pullwatch/App.xcconfig has CURRENT_PROJECT_VERSION = '$build'; it must be a whole number" >&2
  exit 1
fi

if ! grep -qE "^## \[${version//./\\.}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md; then
  echo "CHANGELOG.md has no '## [$version] - YYYY-MM-DD' section" >&2
  exit 1
fi
if [ -z "$(bash "$here/notes.sh" "$tag")" ]; then
  echo "the CHANGELOG.md section for $version is empty; it becomes the release notes" >&2
  exit 1
fi

# Zonder GitHub App biedt de release alleen een token aan (Release.xcconfig).
# Dat mag, maar is zelden de bedoeling: een waarschuwing, geen fout.
if [ -z "$(setting PW_GITHUB_CLIENT_ID Pullwatch/Release.xcconfig)" ]; then
  echo "warning: Pullwatch/Release.xcconfig has no PW_GITHUB_CLIENT_ID; this release cannot offer Sign in with GitHub (docs/github-app.md)" >&2
fi

echo "ok: $tag matches App.xcconfig $app (build $build) and CHANGELOG.md has its section"
