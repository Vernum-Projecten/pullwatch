#!/usr/bin/env bash
# .claude/hooks/block_dangerous.sh
#
# Claude Code PreToolUse hook (matcher: Bash). Refuses:
#   - rm -rf outside the temp directory
#   - force-pushes touching main, and bare force-pushes
#   - any push to the upstream repository (alessandro823/pullwatch): work
#     goes to the fork; upstream gets one combined pull request at the end
#   - gh pr create without --repo Vernum-Projecten/pullwatch (a fork's
#     default target is upstream)
#   - security commands that would export or delete signing identities

set -euo pipefail

payload="$(cat)"
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
else
  cmd="$payload"
fi
[ -n "${cmd:-}" ] || exit 0

if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])rm[[:space:]]+-[a-zA-Z]*([rR][a-zA-Z]*f|f[a-zA-Z]*[rR])'; then
  # shellcheck disable=SC2016 # the literal `$TMPDIR` is a grep pattern, not an expansion
  if ! printf '%s' "$cmd" | grep -qE 'rm[[:space:]]+-[a-zA-Z]+[[:space:]]+"?(/private)?/tmp/|\$TMPDIR'; then
    echo "BLOCKED: 'rm -rf' is not allowed outside the temp directory." >&2
    exit 2
  fi
fi

if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+push[^;|&]*(--force([^-]|$)|--force-with-lease|[[:space:]]-f([[:space:]]|$)|[[:space:]]\+[[:alnum:]])'; then
  if printf '%s' "$cmd" | grep -qE '(^|[[:space:]:/+])(main|master)([[:space:]]|$|["'"'"';&|])'; then
    echo "BLOCKED: force-push touching main is forbidden." >&2
    exit 2
  fi
  if ! printf '%s' "$cmd" | grep -qE '(feat|fix|chore|docs|refactor|perf|test|ci|build|release)/'; then
    echo "BLOCKED: bare force-push refused; name a conventional-type branch." >&2
    exit 2
  fi
fi

if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+push[[:space:]]+([^;|&]*[[:space:]])?(upstream|[^[:space:]]*alessandro823/pullwatch)'; then
  echo "BLOCKED: never push to upstream (alessandro823/pullwatch). Push to origin (Vernum-Projecten/pullwatch) and open a pull request (CLAUDE.md, Workflow)." >&2
  exit 2
fi

# In a fork, a bare `gh pr create` targets the parent repository.
if printf '%s' "$cmd" | grep -qE 'gh[[:space:]]+pr[[:space:]]+create'; then
  if ! printf '%s' "$cmd" | grep -qE '(--repo|-R)[[:space:]=]+Vernum-Projecten/pullwatch([[:space:]]|$)'; then
    echo "BLOCKED: open pull requests in the fork only: gh pr create --repo Vernum-Projecten/pullwatch --base main. Upstream gets one combined pull request when the owner says so (CLAUDE.md, Where the work happens)." >&2
    exit 2
  fi
fi

if printf '%s' "$cmd" | grep -qE 'security[[:space:]]+(export|delete-identity|delete-certificate|delete-keychain)'; then
  echo "BLOCKED: exporting or deleting signing identities is the owner's job, never a session's." >&2
  exit 2
fi

exit 0
