#!/usr/bin/env bash
# scripts/release/check-version.sh vX.Y.Z | vX.Y.Z-beta.N
#
# Het releaseplan, overgenomen van FerroLICENCE: de tag noemt de versie van
# de app (MARKETING_VERSION in Pullwatch/App.xcconfig), het buildnummer
# (CURRENT_PROJECT_VERSION) is een geheel getal, en CHANGELOG.md heeft een
# uitgebrachte sectie voor de versie met tekst erin, en changelog.d/ heeft
# geen fragmenten meer (changelog.sh --assemble). Een testversie
# (vX.Y.Z-beta.N, Sparkle's beta-kanaal) komt vóór die cut: haar notes zijn
# de fragmenten die er nog staan. Release.xcconfig heeft Sparkle's openbare
# sleutel, anders kan geen app de update controleren. Alles moet kloppen
# voordat er iets gebouwd wordt.

set -euo pipefail

tag="${1:?usage: check-version.sh vX.Y.Z | vX.Y.Z-beta.N}"
if ! [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)(-beta\.[0-9]+)?$ ]]; then
  echo "tag '$tag' is not vX.Y.Z or vX.Y.Z-beta.N" >&2
  exit 1
fi
version="${BASH_REMATCH[1]}"
beta="${BASH_REMATCH[2]}"

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

if [ -n "$beta" ]; then
  # Een testversie: de versie is nog niet uitgebracht en haar notes zijn de fragmenten.
  if grep -qF "## [$version]" CHANGELOG.md; then
    echo "CHANGELOG.md already has a [$version] section; a test version comes before the release cut" >&2
    exit 1
  fi
  if [ -z "$(bash "$here/notes.sh" "$tag")" ]; then
    echo "no fragment in changelog.d/ for $tag; its notes would be empty" >&2
    exit 1
  fi
else
  if ! grep -qE "^## \[${version//./\\.}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md; then
    echo "CHANGELOG.md has no '## [$version] - YYYY-MM-DD' section" >&2
    exit 1
  fi
  if [ -z "$(bash "$here/notes.sh" "$tag")" ]; then
    echo "the CHANGELOG.md section for $version is empty; it becomes the release notes" >&2
    exit 1
  fi

  # De release-cut (changelog.sh --assemble) zet de fragmenten in CHANGELOG.md
  # en verwijdert ze; een fragment dat er nog staat, ontbreekt in de notes.
  left="$(find changelog.d -maxdepth 1 -type f -name '*.md' ! -name README.md | sort)"
  if [ -n "$left" ]; then
    echo "changelog.d/ still holds fragments; run scripts/release/changelog.sh --assemble $version YYYY-MM-DD on the release branch first:" >&2
    echo "$left" >&2
    exit 1
  fi
fi

# Sparkle (#9): zonder openbare sleutel in de release-build kan geen app de
# update controleren, en het secret SPARKLE_PRIVATE_KEY ondertekent hem.
if [ -z "$(setting SPARKLE_PUBLIC_ED_KEY Pullwatch/Release.xcconfig)" ]; then
  echo "Pullwatch/Release.xcconfig has no SPARKLE_PUBLIC_ED_KEY; make Sparkle's key pair first (docs/releasing.md, Sparkle's key)" >&2
  exit 1
fi

# Zonder GitHub App biedt de release alleen een token aan (Release.xcconfig).
# Dat mag, maar is zelden de bedoeling: een waarschuwing, geen fout.
if [ -z "$(setting PW_GITHUB_CLIENT_ID Pullwatch/Release.xcconfig)" ]; then
  echo "warning: Pullwatch/Release.xcconfig has no PW_GITHUB_CLIENT_ID; this release cannot offer Sign in with GitHub (docs/github-app.md)" >&2
fi

echo "ok: $tag matches App.xcconfig $app (build $build) and CHANGELOG.md has its section"
