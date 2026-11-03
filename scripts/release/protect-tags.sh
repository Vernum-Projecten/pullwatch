#!/usr/bin/env bash
# scripts/release/protect-tags.sh [owner/repo]
#
# Maakt (eenmalig) de ruleset van de repository die release-tags vastzet:
# v*-tags kunnen niet verwijderd of verplaatst worden. Overgenomen van
# FerroLICENCE. Idempotent: stopt met 0 als er al een ruleset "release-tags"
# is. Vraagt beheerrechten op de repository (docs/releasing.md).

set -euo pipefail

repo="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

if gh api "repos/$repo/rulesets" --jq '.[].name' | grep -qx 'release-tags'; then
  echo "ok: ruleset 'release-tags' already exists on $repo"
  exit 0
fi

gh api --method POST "repos/$repo/rulesets" \
  --input - <<'JSON' >/dev/null
{
  "name": "release-tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "update" },
    { "type": "non_fast_forward" }
  ]
}
JSON
echo "ok: ruleset 'release-tags' created on $repo (v* tags: no delete, no move)"
