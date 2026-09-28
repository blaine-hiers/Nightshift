#!/usr/bin/env bash
# Queue-drain stage 0: sweep worktrees under a base clone.
# A worktree is REMOVABLE only when ALL hold (Nightshift CLAUDE.md):
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

  # 2. pushed? Classify ahead/behind/diverged.
  # GIT_TERMINAL_PROMPT=0: an unattended sweep must fail, never block on a
  # credential prompt.
  GIT_TERMINAL_PROMPT=0 git -C "$wt" fetch -q origin 2>/dev/null || true
  remote_sha="$(GIT_TERMINAL_PROMPT=0 git -C "$wt" ls-remote origin "refs/heads/$branch" 2>/dev/null | cut -f1)"
  local_sha="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  if [ -z "$remote_sha" ]; then
    echo "BLOCKED $wt no-upstream"; continue
  fi
  if [ "$remote_sha" != "$local_sha" ]; then
    # Classify against the sha ls-remote just reported, not @{u}: if the fetch
    # failed, @{u} is stale and could make a behind-only tree look unpushed.
    # A failed fetch also means that sha may be missing locally -- then we
    # can't tell, and say so.
    if ! ahead_behind="$(git -C "$wt" rev-list --left-right --count "$remote_sha...HEAD" 2>/dev/null)"; then
      echo "BLOCKED $wt fetch-failed"; continue
    fi
    behind=$(echo "$ahead_behind" | awk '{print $1}')
    ahead=$(echo "$ahead_behind" | awk '{print $2}')
    # Behind-only: local is ancestor of remote, nothing to push => treat as pushed
    if [ "$behind" -gt 0 ] && [ "$ahead" -eq 0 ]; then
      # Fast-forward to remote when removing (optional, keeps tree clean)
      if [ "$REMOVE" -eq 1 ]; then
        git -C "$wt" merge --ff-only -q "$remote_sha" 2>/dev/null || true
      fi
    else
      # Ahead or diverged => blocked
      echo "BLOCKED $wt unpushed"; continue
    fi
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
