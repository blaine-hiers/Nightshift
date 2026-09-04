#!/usr/bin/env bash
# Queue-drain stage 0: sweep worktrees under a base clone.
# A worktree is REMOVABLE only when ALL hold (Foreman CLAUDE.md):
#   1. git status --porcelain is empty
#   2. HEAD is pushed to its branch on origin
#   3. the PR for that branch is MERGED (gh; skippable with --skip-pr-check)
# Anything else is BLOCKED with a reason — report, don't touch.
#
# Usage: sweep.sh <base-clone-path> [--remove] [--skip-pr-check]
set -u

BASE="${1:-}"; shift || true
REMOVE=0; SKIP_PR=0
for arg in "$@"; do
  case "$arg" in
    --remove) REMOVE=1 ;;
    --skip-pr-check) SKIP_PR=1 ;;
    *) echo "usage: sweep.sh <base-clone-path> [--remove] [--skip-pr-check]" >&2; exit 2 ;;
  esac
done
[ -d "$BASE/.git" ] || { echo "usage: sweep.sh <base-clone-path> [--remove] [--skip-pr-check]" >&2; exit 2; }

WT_ROOT="$BASE/.worktrees"
[ -d "$WT_ROOT" ] || exit 0

for wt in "$WT_ROOT"/*/; do
  [ -d "$wt" ] || continue
  wt="${wt%/}"

  # 1. clean?
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    echo "BLOCKED $wt dirty"; continue
  fi

  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)"

  # 2. pushed? HEAD must equal the branch's ref on origin
  remote_sha="$(git -C "$wt" ls-remote origin "refs/heads/$branch" 2>/dev/null | cut -f1)"
  local_sha="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  if [ -z "$remote_sha" ]; then
    echo "BLOCKED $wt no-upstream"; continue
  fi
  if [ "$remote_sha" != "$local_sha" ]; then
    echo "BLOCKED $wt unpushed"; continue
  fi

  # 3. PR merged?
  if [ "$SKIP_PR" -eq 0 ]; then
    state="$(cd "$wt" && gh pr list --head "$branch" --state all --json state \
             --jq '.[0].state' 2>/dev/null || true)"
    # tolerate stub/plain-text gh output in tests
    case "$state" in
      *MERGED*) : ;;
      *) state_raw="$(cd "$wt" && gh pr view "$branch" 2>/dev/null || true)"
         case "$state_raw" in
           *MERGED*) : ;;
           *) echo "BLOCKED $wt pr-not-merged"; continue ;;
         esac ;;
    esac
  fi

  echo "REMOVABLE $wt"
  if [ "$REMOVE" -eq 1 ]; then
    git -C "$BASE" worktree remove "$wt" && git -C "$BASE" worktree prune || echo "WARN $wt remove-failed" >&2
  fi
done

exit 0
