#!/usr/bin/env bash
# scripts/release/notes.sh vX.Y.Z
#
# Drukt de sectie van CHANGELOG.md voor de versie af, zonder lege regels aan
# het begin en eind: de tekst van de GitHub-release. Overgenomen van
# FerroLICENCE.

set -euo pipefail

tag="${1:?usage: notes.sh vX.Y.Z}"
version="${tag#v}"
here="$(cd "$(dirname "$0")" && pwd)"

# De sectie loopt tot de volgende versiekop of tot de linkverwijzingen onderaan.
awk -v v="$version" '
  index($0, "## [" v "]") == 1 { on = 1; next }
  on && (/^## \[/ || /^\[[^]]+\]: /) { exit }
  on && !started && /^[[:space:]]*$/ { next }
  on { started = 1; print }
' "$here/../../CHANGELOG.md" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
