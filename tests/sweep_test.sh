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
git worktree add -q .worktrees/ENG-1 -b test/ENG-1
( cd .worktrees/ENG-1 && git config user.email t@t && git config user.name t \
  && echo fix > f.txt && git commit -qam fix && git push -q origin test/ENG-1 )

# --- stub gh: reports MERGED for test/ENG-1 ---
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
echo dirty >> "$TMP/base/.worktrees/ENG-1/f.txt"
OUT="$(bash "$SWEEP" "$TMP/base")"
assert_contains "$OUT" "BLOCKED" "dirty worktree is BLOCKED"
assert_contains "$OUT" "dirty" "dirty reason reported"
( cd "$TMP/base/.worktrees/ENG-1" && git checkout -q -- f.txt )

# T3: unpushed commit => BLOCKED unpushed
( cd "$TMP/base/.worktrees/ENG-1" && echo more > g.txt && git add g.txt && git commit -qm more )
OUT="$(bash "$SWEEP" "$TMP/base")"
assert_contains "$OUT" "unpushed" "unpushed commit is BLOCKED unpushed"
( cd "$TMP/base/.worktrees/ENG-1" && git push -q origin test/ENG-1 )

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
if [ -d "$TMP/base/.worktrees/ENG-1" ]; then
  echo "FAIL - --remove removes the worktree"; FAILS=$((FAILS+1))
else echo "ok   - --remove removes the worktree"; fi

# T10: a dirty (BLOCKED) worktree must never be removed, even with --remove
cd "$TMP/base"
git worktree add -q .worktrees/ENG-3 -b test/ENG-3
( cd .worktrees/ENG-3 && git config user.email t@t && git config user.name t \
  && echo base > i.txt && git add i.txt && git commit -qm base && git push -q origin test/ENG-3 )
echo dirty >> "$TMP/base/.worktrees/ENG-3/i.txt"
OUT="$(bash "$SWEEP" "$TMP/base" --skip-pr-check --remove)"
if [ -d "$TMP/base/.worktrees/ENG-3" ]; then
  echo "ok   - BLOCKED (dirty) worktree survives --remove"
else
  echo "FAIL - BLOCKED (dirty) worktree survives --remove"; FAILS=$((FAILS+1))
fi
assert_contains "$OUT" "BLOCKED" "dirty worktree with --remove still reports BLOCKED"

# T7: no-upstream => BLOCKED no-upstream
# Create a worktree on a new branch that is never pushed to origin
cd "$TMP/base"
git worktree add -q .worktrees/ENG-2 -b test/ENG-2
( cd .worktrees/ENG-2 && git config user.email t@t && git config user.name t \
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

echo; if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAILURES"; exit 1; fi
