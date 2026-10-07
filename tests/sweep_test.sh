#!/usr/bin/env bash
# Plain-bash tests for queue-drain sweep.sh. Run: bash tests/sweep_test.sh
set -u
SWEEP="$(cd "$(dirname "$0")/.." && pwd)/.claude/skills/queue-drain/scripts/sweep.sh"
FAILS=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

assert_contains() { # $1=haystack $2=needle $3=label
  if echo "$1" | grep -qF "$2"; then echo "ok   - $3"
  else echo "FAIL - $3"; echo "  wanted: $2"; echo "  got: $1"; FAILS=$((FAILS+1)); fi
}

# --- fixture: bare origin + base clone + one worktree on a pushed branch ---
git init -q --bare "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/base" 2>/dev/null
cd "$TMP/base"
git config user.email t@t; git config user.name t
echo hi > f.txt; git add f.txt; git commit -qm init; git push -q origin HEAD:main 2>/dev/null
git worktree add -q .worktrees/issue-1 -b test/issue-1
( cd .worktrees/issue-1 && git config user.email t@t && git config user.name t \
  && echo fix > f.txt && git commit -qam fix && git push -q origin test/issue-1 )

# --- stub gh: reports MERGED for test/issue-1 ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "MERGED"
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# T1: clean + pushed + merged PR => REMOVABLE
OUT="$(bash "$SWEEP" "$TMP/base")"
assert_contains "$OUT" "REMOVABLE" "clean pushed merged worktree is REMOVABLE"

# T2: dirty worktree => BLOCKED dirty
echo dirty >> "$TMP/base/.worktrees/issue-1/f.txt"
OUT="$(bash "$SWEEP" "$TMP/base")"
assert_contains "$OUT" "BLOCKED" "dirty worktree is BLOCKED"
assert_contains "$OUT" "dirty" "dirty reason reported"
( cd "$TMP/base/.worktrees/issue-1" && git checkout -q -- f.txt )

# T3: unpushed commit => BLOCKED unpushed
( cd "$TMP/base/.worktrees/issue-1" && echo more > g.txt && git add g.txt && git commit -qm more )
OUT="$(bash "$SWEEP" "$TMP/base")"
assert_contains "$OUT" "unpushed" "unpushed commit is BLOCKED unpushed"
( cd "$TMP/base/.worktrees/issue-1" && git push -q origin test/issue-1 )

# T4: gh says OPEN => BLOCKED pr-not-merged
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "OPEN"
EOF
chmod +x "$TMP/bin/gh"
OUT="$(bash "$SWEEP" "$TMP/base")"
assert_contains "$OUT" "pr-not-merged" "open PR is BLOCKED pr-not-merged"

# T5: --skip-pr-check ignores gh => REMOVABLE
OUT="$(bash "$SWEEP" "$TMP/base" --skip-pr-check)"
assert_contains "$OUT" "REMOVABLE" "--skip-pr-check makes it REMOVABLE"

# T6: --remove deletes the worktree
bash "$SWEEP" "$TMP/base" --skip-pr-check --remove >/dev/null
if [ -d "$TMP/base/.worktrees/issue-1" ]; then
  echo "FAIL - --remove removes the worktree"; FAILS=$((FAILS+1))
else echo "ok   - --remove removes the worktree"; fi

# T10: a dirty (BLOCKED) worktree must never be removed, even with --remove
cd "$TMP/base"
git worktree add -q .worktrees/issue-3 -b test/issue-3
( cd .worktrees/issue-3 && git config user.email t@t && git config user.name t \
  && echo base > i.txt && git add i.txt && git commit -qm base && git push -q origin test/issue-3 )
echo dirty >> "$TMP/base/.worktrees/issue-3/i.txt"
OUT="$(bash "$SWEEP" "$TMP/base" --skip-pr-check --remove)"
if [ -d "$TMP/base/.worktrees/issue-3" ]; then
  echo "ok   - BLOCKED (dirty) worktree survives --remove"
else
  echo "FAIL - BLOCKED (dirty) worktree survives --remove"; FAILS=$((FAILS+1))
fi
assert_contains "$OUT" "BLOCKED" "dirty worktree with --remove still reports BLOCKED"

# T7: no-upstream => BLOCKED no-upstream
# Create a worktree on a new branch that is never pushed to origin
cd "$TMP/base"
git worktree add -q .worktrees/issue-2 -b test/issue-2
( cd .worktrees/issue-2 && git config user.email t@t && git config user.name t \
  && echo newbranch > h.txt && git add h.txt && git commit -qm newbranch )
# Note: intentionally NOT pushed to origin
OUT="$(bash "$SWEEP" "$TMP/base")"
assert_contains "$OUT" "BLOCKED" "unpushed new branch is BLOCKED"
assert_contains "$OUT" "no-upstream" "new branch with no remote ref is BLOCKED no-upstream"

# T8: normal run exits 0
bash "$SWEEP" "$TMP/base" --skip-pr-check >/dev/null 2>&1
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then echo "ok   - normal run exits 0"
else echo "FAIL - normal run exits 0"; echo "  got exit code: $EXIT_CODE"; FAILS=$((FAILS+1)); fi

# T9: usage error exits 2
bash "$SWEEP" "$TMP/base" --bogus >/dev/null 2>&1
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 2 ]; then echo "ok   - usage error exits 2"
else echo "FAIL - usage error exits 2"; echo "  got exit code: $EXIT_CODE"; FAILS=$((FAILS+1)); fi

# T11: behind-only (remote moved on) => REMOVABLE once PR is merged
cd "$TMP/base"
git worktree add -q .worktrees/issue-4 -b test/issue-4
( cd .worktrees/issue-4 && git config user.email t@t && git config user.name t \
  && echo commit1 > j.txt && git add j.txt && git commit -qm "local commit" && git push -qu origin test/issue-4 )
# Now simulate gh pr update-branch by adding a commit on the bare origin repo directly
cd "$TMP/origin.git"
PARENT=$(git rev-parse refs/heads/test/issue-4)
NEWTREE=$(git -C "$TMP/base" rev-parse origin/test/issue-4^{tree})
NEWCOMM=$(git commit-tree -p "$PARENT" -m "merge commit on remote" "$NEWTREE")
git update-ref refs/heads/test/issue-4 "$NEWCOMM"
# Fetch in worktree to see the new remote commit; upstream should already be tracking
( cd "$TMP/base/.worktrees/issue-4" && git fetch -q origin )
OUT="$(bash "$SWEEP" "$TMP/base" --skip-pr-check)"
assert_contains "$OUT" "REMOVABLE" "behind-only worktree (after gh pr update-branch) is REMOVABLE"

# T12: ahead-only (local has unpushed commits) => BLOCKED unpushed
cd "$TMP/base"
git worktree add -q .worktrees/issue-5 -b test/issue-5
( cd .worktrees/issue-5 && git config user.email t@t && git config user.name t \
  && echo commit1 > k.txt && git add k.txt && git commit -qm "first commit" && git push -q origin test/issue-5 \
  && echo commit2 > k.txt && git commit -qam "unpushed commit" )
OUT="$(bash "$SWEEP" "$TMP/base")"
assert_contains "$OUT" "unpushed" "ahead-only worktree (has unpushed commits) is BLOCKED unpushed"

# T13: the remote moved on but this run's fetch fails => BLOCKED fetch-failed,
# never "unpushed" (misleading) and never REMOVABLE (unverified).
cd "$TMP/base"
git worktree add -q .worktrees/issue-6 -b test/issue-6
( cd .worktrees/issue-6 && git config user.email t@t && git config user.name t   && echo commit1 > m.txt && git add m.txt && git commit -qm "local commit" && git push -qu origin test/issue-6 )
cd "$TMP/origin.git"
PARENT=$(git rev-parse refs/heads/test/issue-6)
NEWCOMM=$(git commit-tree -p "$PARENT" -m "remote-only commit" "$(git rev-parse "$PARENT^{tree}")")
git update-ref refs/heads/test/issue-6 "$NEWCOMM"
# An extra fetch refspec for a ref that doesn't exist makes every fetch fail,
# while ls-remote (which ignores refspecs) still sees the new remote commit.
OUT="$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.fetch        GIT_CONFIG_VALUE_0=+refs/heads/no-such-branch:refs/remotes/origin/no-such-branch        bash "$SWEEP" "$TMP/base" --skip-pr-check | grep issue-6)"
assert_contains "$OUT" "fetch-failed" "remote moved on but fetch failed is BLOCKED fetch-failed"

# T14: leftover dirs that aren't worktrees (Windows leaves an empty one behind
# when a shell is still cd'd into a tree during `git worktree remove`). Without
# the .git check, `git -C` resolves to the base clone and misreports them.
mkdir -p "$TMP/base/.worktrees/leftover-empty" "$TMP/base/.worktrees/leftover-full"
echo junk > "$TMP/base/.worktrees/leftover-full/x.txt"
OUT="$(bash "$SWEEP" "$TMP/base" --skip-pr-check)"
assert_contains "$OUT" "ORPHAN $TMP/base/.worktrees/leftover-empty" "empty non-worktree dir is ORPHAN"
assert_contains "$OUT" "BLOCKED $TMP/base/.worktrees/leftover-full not-a-worktree" "non-empty non-worktree dir is BLOCKED not-a-worktree"
[ -d "$TMP/base/.worktrees/leftover-empty" ] && echo "ok   - ORPHAN kept without --remove" \
  || { echo "FAIL - ORPHAN kept without --remove"; FAILS=$((FAILS+1)); }
bash "$SWEEP" "$TMP/base" --skip-pr-check --remove >/dev/null 2>&1
[ ! -d "$TMP/base/.worktrees/leftover-empty" ] && echo "ok   - --remove deletes an empty ORPHAN" \
  || { echo "FAIL - --remove deletes an empty ORPHAN"; FAILS=$((FAILS+1)); }
[ -f "$TMP/base/.worktrees/leftover-full/x.txt" ] && echo "ok   - --remove never touches a non-empty leftover" \
  || { echo "FAIL - --remove never touches a non-empty leftover"; FAILS=$((FAILS+1)); }

echo; if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAILURES"; exit 1; fi
