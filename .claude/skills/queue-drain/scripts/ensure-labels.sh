#!/usr/bin/env bash
# Ensure a repo carries the Nightshift label taxonomy (CLAUDE.md: Status, Labels).
#
# gh refuses an --add-label for a label that does not exist, so filing or
# triaging into a repo that never got the taxonomy fails mid-run. Run this
# once per repo before the first `gh issue create` / `gh issue edit` against it.
#
#   bash ensure-labels.sh blaine-hiers/Onramp            # create what's missing
#   bash ensure-labels.sh --check blaine-hiers/Onramp    # report only, exit 1 if incomplete
#
# Idempotent: existing labels are left exactly as they are, including any
# colour or description a repo has deliberately diverged on.

set -uo pipefail

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
  CHECK_ONLY=1
  shift
fi

REPO="${1:-}"
if [ -z "$REPO" ]; then
  echo "usage: ensure-labels.sh [--check] <owner/repo>" >&2
  exit 2
fi

# name|colour|description — the taxonomy CLAUDE.md defines.
# Status is exclusive; tier maps to an Agent model: string by stripping "tier/".
LABELS='status/backlog|ededed|Filed, not yet ready to work
status/needs-input|fbca04|Ask isnt yet a workable prompt
status/todo|0e8a16|An agent can start right now with zero questions
status/in-progress|1d76db|Work has actually started
status/blocked|b60205|Started, stalled on something outside the agent loop
status/in-review|5319e7|A PR is open against it
bug|d73a4a|Something isnt working
feature|a2eeef|New capability
improvement|c5def5|Better version of something that exists
security|d93f0b|Credential handling, data exposure, isolation
tier/haiku|bfd4f2|Mechanical, well-specified
tier/sonnet|7fb3e8|Ordinary bugfix / feature work
tier/opus|2b5fb8|Unclear root cause, cross-cutting, concurrency/security
tier/fable|0b2a6b|Hardest long-horizon work
tier/codex|444444|Routed to OpenAI Codex CLI'

existing=$(gh label list -R "$REPO" --limit 200 --json name --jq '.[].name' 2>/dev/null)
if [ $? -ne 0 ]; then
  echo "FAIL $REPO — cannot read labels (repo missing, or no access)" >&2
  exit 2
fi

missing=0
created=0
while IFS='|' read -r name colour desc; do
  [ -z "$name" ] && continue
  if printf '%s\n' "$existing" | grep -qxF "$name"; then
    continue
  fi
  missing=$((missing + 1))
  if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "MISSING $REPO $name"
    continue
  fi
  if gh label create "$name" -R "$REPO" -c "$colour" -d "$desc" >/dev/null 2>&1; then
    echo "CREATED $REPO $name"
    created=$((created + 1))
  else
    echo "FAIL    $REPO $name — could not create" >&2
  fi
done <<EOF
$LABELS
EOF

if [ "$CHECK_ONLY" -eq 1 ]; then
  if [ "$missing" -eq 0 ]; then
    echo "OK $REPO — taxonomy complete"
    exit 0
  fi
  echo "INCOMPLETE $REPO — $missing label(s) missing"
  exit 1
fi

if [ "$missing" -eq 0 ]; then
  echo "OK $REPO — taxonomy already complete"
elif [ "$created" -eq "$missing" ]; then
  echo "OK $REPO — created $created label(s)"
else
  echo "PARTIAL $REPO — created $created of $missing" >&2
  exit 1
fi
