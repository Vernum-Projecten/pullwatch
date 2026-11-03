#!/usr/bin/env bash
# scripts/release/notes.sh vX.Y.Z | vX.Y.Z-beta.N
#
# Drukt de sectie van CHANGELOG.md voor de versie af, zonder lege regels aan
# het begin en eind: de tekst van de GitHub-release. Overgenomen van
# FerroLICENCE.

set -euo pipefail

tag="${1:?usage: notes.sh vX.Y.Z | vX.Y.Z-beta.N}"
version="${tag#v}"
here="$(cd "$(dirname "$0")" && pwd)"

# Een testversie (vX.Y.Z-beta.N) komt vóór de release-cut: haar notes zijn de
# sectie die de fragmenten zouden worden, zonder de kop.
if [[ "$version" == *-beta.* ]]; then
  bash "$here/changelog.sh" --preview "${version%%-beta.*}" | tail -n +2 | sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba' -e '}'
  exit 0
fi

# De sectie loopt tot de volgende versiekop of tot de linkverwijzingen onderaan.
awk -v v="$version" '
  index($0, "## [" v "]") == 1 { on = 1; next }
  on && (/^## \[/ || /^\[[^]]+\]: /) { exit }
  on && !started && /^[[:space:]]*$/ { next }
  on { started = 1; print }
' "$here/../../CHANGELOG.md" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
