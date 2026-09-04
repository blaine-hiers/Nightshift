# Queue-Drain Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One command (`/queue-drain`) that takes the Linear Todo column to draft PRs plus an honest run report, with exactly two human gates (batched plan approval, PR merge).

**Architecture:** A Claude Code skill in `.claude/skills/queue-drain/` orchestrates stages 0–7 from the spec (`docs/superpowers/specs/2026-08-20-queue-drain-pipeline-design.md`), with reference files loaded per stage (progressive disclosure) and one deterministic bash script for the worktree sweep. The main session is the coordinator; implementer and reviewer subagents are dispatched via the Agent tool; Linear is read/written via the `mcp__claude_ai_Linear__*` MCP tools.

**Tech Stack:** Claude Code skills (SKILL.md + references/), bash (sweep script + plain-bash test harness), git worktrees, `gh` CLI, Linear MCP.

## Global Constraints

Copied from the spec — every task implicitly includes these:

- Everything lands in the **Nightshift repo**; nothing is written to the knowledge vault.
- Linear team is **Engineering** (issue keys `ENG-N`); queue = status **Todo**, unblocked.
- Model tiers verbatim from Nightshift CLAUDE.md: haiku = mechanical, sonnet = ordinary default, opus = justified only; **default down, not up**.
- **WIP cap: at most 5 tickets in flight** per drain; a drain does not start when >~5 agent PRs from prior runs sit unreviewed.
- **Per-ticket budget: 60 minutes wall-clock / 2 attempts**, then the honest-failure lane.
- Every agent PR opens as a **draft**; only the coordinator marks it ready, after the verify gate.
- Reviewer subagents get **fresh context** (diff + issue + plan only) and are **scoped to correctness findings**.
- Diffs touching CI/workflow files, hooks, permissions, or credential handling are a **high-risk class** flagged for explicit human attention.
- Subagents **never** run with permission-skip flags, and **never** use `isolation: "worktree"` (it would worktree Nightshift itself).
- Doppler: default **no `.env`**; opt-in via `npm run env-sync` inside the worktree; **`dev` config only, never `prd`**.
- Compounding is **skills-only**, inside Nightshift; retro is mandatory; retro records metrics (cycle time, escalation rate).
- Commit messages: short imperative subject, plain description (Nightshift git convention).

## File Structure

```
Nightshift/
├── .claude/skills/queue-drain/
│   ├── SKILL.md                    # Task 2 — orchestrator: stages 0–7, gates, WIP cap
│   ├── references/
│   │   ├── triage.md               # Task 3 — classification rules, tier table, templates
│   │   ├── plan-gate.md            # Task 4 — plan template, batched approval, decompose path
│   │   ├── prompts.md              # Task 5 — implementer + reviewer subagent prompt templates
│   │   └── retro.md                # Task 6 — retro checklist, skill hygiene, metrics, run report
│   └── scripts/
│       └── sweep.sh                # Task 1 — deterministic worktree sweep
├── tests/
│   └── sweep_test.sh               # Task 1 — plain-bash test harness for sweep.sh
├── docs/runs/                      # created at first run by the skill (run reports; .gitkeep in Task 6)
└── CLAUDE.md                       # Task 7 — add queue-drain pointer section
```

Each reference file is one stage's worth of instructions so the coordinator loads only what the current stage needs. `sweep.sh` is the only executable code: the three-condition sweep check is exactly the kind of judgment that must be deterministic, not vibes.

---

### Task 1: Worktree sweep script

**Files:**
- Create: `scripts/../.claude/skills/queue-drain/scripts/sweep.sh` (path from repo root: `.claude/skills/queue-drain/scripts/sweep.sh`)
- Test: `tests/sweep_test.sh`

**Interfaces:**
- Produces: `sweep.sh <base-clone-path> [--remove] [--skip-pr-check]` — prints one line per worktree under `<base>/.worktrees/`: `REMOVABLE <path>` or `BLOCKED <path> <reason>`; with `--remove`, removes REMOVABLE trees via `git worktree remove` + `prune`. Exit 0 always unless usage error (exit 2). Reasons: `dirty`, `unpushed`, `pr-not-merged`, `no-upstream`.
- Consumes: `gh pr list` (stubbed in tests via PATH).

- [ ] **Step 1: Write the failing test harness**

Create `tests/sweep_test.sh`:

```bash
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

echo; if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAILURES"; exit 1; fi
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/sweep_test.sh`
Expected: failures/errors — `sweep.sh` does not exist yet.

- [ ] **Step 3: Write sweep.sh**

Create `.claude/skills/queue-drain/scripts/sweep.sh`:

```bash
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
      *) state_raw="$(cd "$wt" && gh pr view "$branch" 2>/dev/null || (cd "$wt" && gh 2>/dev/null) || true)"
         case "$state_raw" in
           *MERGED*) : ;;
           *) echo "BLOCKED $wt pr-not-merged"; continue ;;
         esac ;;
    esac
  fi

  echo "REMOVABLE $wt"
  if [ "$REMOVE" -eq 1 ]; then
    git -C "$BASE" worktree remove "$wt" && git -C "$BASE" worktree prune
  fi
done
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/sweep_test.sh`
Expected: `ALL PASS` (6 ok lines). If the gh-stub tests are brittle on this machine, fix `sweep.sh`'s gh handling — not the tests' expectations.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/queue-drain/scripts/sweep.sh tests/sweep_test.sh
git commit -m "Add deterministic worktree sweep for queue-drain

Three-condition removability check (clean, pushed, PR merged) with
report-don't-touch default; plain-bash test harness with stubbed gh."
```

---

### Task 2: Orchestrator SKILL.md

**Files:**
- Create: `.claude/skills/queue-drain/SKILL.md`

**Interfaces:**
- Consumes: `scripts/sweep.sh` (Task 1), reference files (Tasks 3–6 — named here, written next; do not reorder loads).
- Produces: the `/queue-drain` command; stage sequence and gate rules every reference file plugs into.

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: queue-drain
description: Use when asked to "drain the queue", "work the Linear queue", "/queue-drain", or to batch-process Linear Todo issues into PRs. Orchestrates sweep → triage → plan gate → fan-out → verify → close → retro with the main session as coordinator.
---

# Queue Drain

One command takes the Linear Todo column to draft PRs plus an honest run
report. You (the main session) are the **coordinator**: you own all Linear
writes, all worktree creation/teardown, and the final report. Subagents
implement and review; they never write to Linear.

**The two human gates:** batched plan approval (stage 3) and PR merge
(outside this skill). Everything else runs without the human.

## Hard rules (no exceptions)

- WIP cap: max **5 tickets in flight**. If >~5 agent PRs from prior runs
  are still unreviewed, STOP and report instead of starting — never DDoS
  the merge gate. Remaining ready tickets queue for a second wave.
- Per ticket: **60 min / 2 attempts**, then the honest-failure lane.
- All PRs open as **drafts**; only you mark ready, only after the verify
  gate passes.
- Never dispatch a subagent with permission-skip flags; never use
  `isolation: "worktree"` (it worktrees Nightshift, not the target repo).
- Honest failure is a valid output. Never fake a green gate.

## Stages

### 0. SWEEP
Run `bash .claude/skills/queue-drain/scripts/sweep.sh workspace/<repo>`
for each base clone in `workspace/`. Remove only REMOVABLE trees
(re-run with `--remove`); report every BLOCKED tree and its reason in the
run report. A BLOCKED tree is never deleted by hand.

### 1. FETCH
`list_issues`: team Engineering, status Todo, not blocked. Also count open
agent PRs from prior runs (`gh pr list --author @me --state open` per
target repo, or the PRs-awaiting-merge list from the last run report in
docs/runs/). Apply the WIP-cap stop rule before proceeding.

### 2. TRIAGE
Read `references/triage.md`. Classify every issue (ready / needs-plan /
needs-info), assign tiers, post needs-info comments, show the human the
triage table. The table is a sanity scan, not a gate — proceed after
showing it.

### 3. PLAN GATE
Read `references/plan-gate.md`. Dispatch one planning subagent per
needs-plan issue (they may run while stage 4 starts for ready tickets).
Present ALL plans in ONE sitting via AskUserQuestion (approve / revise /
park per plan). Post approved plans to their Linear issues.

### 4. FAN-OUT
Per target repo: `git fetch origin` once, confirm `git config gc.auto` is
0 (set it if not). Create every worktree yourself:
`git -C workspace/<repo> worktree add .worktrees/<issue-id> -b <gitBranchName> origin/main`
then run the repo's bootstrap in each. Dispatch implementer subagents (max
5 concurrent) in a single message, using the implementer template in
`references/prompts.md`. Move each issue to In Progress as its agent
starts — not batched. Doppler only where the ticket needs live calls:
`npm run env-sync` inside that worktree, dev config only; track which
worktrees hold credentials.

### 5. VERIFY
For each returned implementation, dispatch a **fresh reviewer subagent**
(reviewer template in `references/prompts.md`) that sees only the diff,
the issue, and the plan. Correctness findings → back to the implementer
(attempt 2) or fixed trivially by you. High-risk diffs (CI/workflow
files, hooks, permissions, credential handling) are flagged in the run
report regardless of review outcome. Gate = repo tests pass AND review
clean/addressed.

### 6. CLOSE
Per passing ticket: push from the worktree, `gh pr create --draft` with
root cause + fix summary + review findings noted, mark ready only after
the gate, `save_comment` on the Linear issue (root cause + PR link), move
issue to In Review. Failed/budget-exhausted tickets: comment the finding
honestly, return the issue to Todo.

### 7. RETRO
Read `references/retro.md`. Mandatory — the run is not done until the
retro has run and the run report is written to
`docs/runs/YYYY-MM-DD-drain.md` and committed.
```

- [ ] **Step 2: Verify against the spec checklist**

Open `docs/superpowers/specs/2026-08-20-queue-drain-pipeline-design.md` and confirm each row maps to SKILL.md text: stages 0–7 all present; two human gates only; WIP cap 5 + backlog stop rule; 60min/2-attempt budget; draft PRs; fresh-context reviewer; high-risk diff class; no permission-skip / no isolation:worktree; Doppler dev-only; honest failure lane; retro mandatory with committed run report. Fix any miss inline.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/queue-drain/SKILL.md
git commit -m "Add queue-drain orchestrator skill

Stages 0-7 per the 2026-08-20 spec: sweep, fetch, triage, batched plan
gate, capped fan-out, fresh-context verify, Linear close, mandatory retro."
```

---

### Task 3: Triage reference

**Files:**
- Create: `.claude/skills/queue-drain/references/triage.md`

**Interfaces:**
- Consumes: stage 2 of SKILL.md (Task 2) invokes this file by path.
- Produces: classification labels `ready` / `needs-plan` / `needs-info` / `decompose` and tier labels `haiku` / `sonnet` / `opus` used verbatim by Tasks 4–6.

- [ ] **Step 1: Write triage.md**

```markdown
# Triage rules (queue-drain stage 2)

For every Todo issue, `get_issue` (full description + comments + labels +
project), then answer three questions IN ORDER:

## 1. Can we locate the work?
The issue must resolve to a target repo — via its Linear project, an
explicit repo name in the description, or an unambiguous match to a clone
in `workspace/`. Cannot resolve → **needs-info**.

## 2. Actionable without the original conversation?
The Nightshift standard: the description is the prompt. Missing repro
steps, undefined acceptance criteria, or an ambiguous ask → **needs-info**.
Post this comment (fill the blanks, keep it short):

> Triage (queue-drain): this ticket needs more detail before an agent can
> work it. Missing: [exact list — e.g. repro steps / expected vs actual /
> target repo / acceptance criteria]. Please edit the description; the
> next drain will pick it up automatically.

Issue stays in Todo. Skip it this run.

**fp-check case:** ask is clear but the premise is doubtful (a reported
bug that may not be real) → classify **ready**, and add
`RUN_FP_CHECK: yes` to its dispatch note so the implementer runs the
fp-check skill before touching code.

## 3. Needs design first?
→ **needs-plan** if ANY of: `Feature` label; touches more than one repo;
unclear root cause with cross-cutting blast radius; concurrency,
data-loss, or security reasoning; goal clear but approach genuinely open.
→ **decompose** if it is too big for a half-page plan — the planner will
propose child issues instead of a plan.
Otherwise → **ready**.

## Tier assignment (ready tickets)
Nightshift CLAUDE.md table, verbatim. Default DOWN, not up:

| Tier | Use for |
|---|---|
| haiku | Mechanical, well-specified: doc/comment drift, rename, missing guard, one-line regex/flag fix, bookkeeping |
| sonnet | Ordinary bugfix: reproduce, trace a few files, patch, run tests. Normal default |
| opus | Only when justified: unclear root cause, cross-cutting refactor, concurrency/data-loss/security, or after a lower tier failed |

## Output
Show the human this table, then proceed (sanity scan, not a gate):

| Issue | Title | Class | Tier | Repo |
|---|---|---|---|---|
| ENG-N | … | ready / needs-plan / needs-info / decompose | haiku/sonnet/opus/— | … |
```

- [ ] **Step 2: Verify** — check the three questions match the spec's Triage section order and wording intent; check the tier table matches Nightshift CLAUDE.md's "Prompt and Model Selection" table meaning; check `needs-info` never advances and `fp-check` rides on `ready`. Fix inline.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/queue-drain/references/triage.md
git commit -m "Add queue-drain triage reference

Three-question classification, needs-info comment template, fp-check
flag, and the model-tier table from CLAUDE.md."
```

---

### Task 4: Plan-gate reference

**Files:**
- Create: `.claude/skills/queue-drain/references/plan-gate.md`

**Interfaces:**
- Consumes: `needs-plan` / `decompose` labels from Task 3.
- Produces: the compact plan format the implementer prompt (Task 5) treats as part of its ticket prompt; the batched-approval procedure stage 3 runs.

- [ ] **Step 1: Write plan-gate.md**

```markdown
# Plan gate (queue-drain stage 3)

## Drafting
Dispatch ONE planning subagent per needs-plan issue (sonnet unless the
issue's own tier is opus). Its prompt: the issue verbatim + "Read the
target repo at <path-to-base-clone>. Produce ONLY the compact plan below —
half a page. Do not write code."

Compact plan format (all five sections required):

    ## Plan: <issue-id> <title>
    **Goal:** one sentence.
    **Approach:** 2-5 sentences — the chosen path and why, over what
    alternative.
    **Files:** exact paths to create/modify.
    **Test plan:** which existing suites run; what new test proves the fix.
    **Out of scope:** what this deliberately does NOT touch.

For **decompose** tickets the planner instead returns 2-5 proposed child
issues (title + 2-3 sentence description + suggested class/tier each).

## The one sitting
When all plans are back, present them TOGETHER with AskUserQuestion —
one question per plan, options: Approve / Revise / Park. Never trickle
plans one at a time across the run. Keep the batch readable: if more than
~5 plans, say so and split into two sittings — a rubber-stamped approval
is a failed gate.

- **Approve** → `save_comment` the plan onto the Linear issue, prefix
  "Approved plan (queue-drain):". Ticket joins fan-out; the plan comment
  is part of the implementer's prompt.
- **Revise** → redraft with the human's feedback, re-present in the same
  sitting if quick, else next sitting.
- **Park** → `save_comment` the draft plan, prefix "Draft plan (parked):".
  Issue stays Todo; next run resumes with the feedback already on the
  ticket.
- **Decompose approved** → create the child issues (`save_issue`), link
  them to the parent, comment the split on the parent, move the parent to
  Backlog.
```

- [ ] **Step 2: Verify** — plan format has exactly the spec's five elements (goal, approach, files, test plan, out-of-scope); approval is one batched sitting with the gate-erosion guard; parked plans persist on the ticket; decompose creates child issues rather than expanding scope. Fix inline.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/queue-drain/references/plan-gate.md
git commit -m "Add queue-drain plan-gate reference

Compact five-section plan format, single-sitting batched approval with
approve/revise/park, and the decompose path to child issues."
```

---

### Task 5: Subagent prompt templates

**Files:**
- Create: `.claude/skills/queue-drain/references/prompts.md`

**Interfaces:**
- Consumes: tier + class labels (Task 3), approved plan text (Task 4), worktree paths created in stage 4.
- Produces: `IMPLEMENTER PROMPT` and `REVIEWER PROMPT` templates; the implementer's required report format (`RESULT: done|failed`, files, test output) that stage 5/6 parses.

- [ ] **Step 1: Write prompts.md**

```markdown
# Subagent prompt templates (queue-drain stages 4-5)

Fill every {placeholder}. Dispatch via the Agent tool with
`model: "{tier}"`. Never add permission-skip flags.

## IMPLEMENTER PROMPT

    You are fixing ONE Linear issue. Work ONLY in your worktree.

    Issue {issue-id}: {title}
    --- description (verbatim) ---
    {full Linear description}
    --- {if plan} approved plan (verbatim) ---
    {plan comment}
    ---
    Worktree: {absolute worktree path} (branch already created — never
    switch branches, never touch any other directory)
    Budget: 60 minutes. If you cannot finish, STOP and report honestly.
    {if RUN_FP_CHECK} Before any code change, use the fp-check skill to
    verify the reported bug is real. If it is not, report that as your
    result — do not "fix" a non-bug.

    Rules:
    - Read the target repo's CLAUDE.md/CONTRIBUTING first; use its own
      build/test tooling and match its style.
    - Reproduce before fixing. Apply the karpathy-guidelines skill: no
      silent assumptions, no orthogonal changes, no over-engineering.
    - Run the repo's test suite before claiming done.
    - Commit in the worktree (short imperative subject). Do NOT push, do
      NOT open a PR, do NOT touch Linear — the coordinator owns those.
    - Doppler: only if instructed in this prompt; then `npm run env-sync`
      in the worktree, dev config only; if .env says prd, stop and report.

    Report back EXACTLY:
    RESULT: done | failed
    ROOT CAUSE: {1-3 sentences}
    FIX: {1-3 sentences, or why it failed}
    FILES: {changed paths}
    TESTS: {suite command run + pass/fail counts, verbatim tail}
    HIGH-RISK: {yes + which CI/workflow/hook/permission/credential files
    were touched, or no}
    NOTES: {anything the reviewer or retro should know}

## REVIEWER PROMPT

Fresh subagent, sonnet by default (opus if the ticket was opus). It gets
ONLY what is in this prompt — never the implementer's transcript.

    You are reviewing a diff for correctness. You did not write it.

    Issue {issue-id}: {title}
    --- description (verbatim) ---
    {full Linear description}
    --- {if plan} approved plan ---
    {plan comment}
    --- diff ---
    {output of: git -C {worktree} diff origin/main...HEAD}
    ---
    Use the differential-review skill. Report ONLY correctness findings:
    bugs, missed acceptance criteria, regressions, blast-radius risks,
    unhandled failure modes. Style and architecture preferences are OUT
    OF SCOPE — do not report them. If the diff is correct, say so plainly;
    do not invent findings to seem thorough.
    Separately flag HIGH-RISK: any changes to CI/workflow files, hooks,
    permissions, or credential handling.

    Report back EXACTLY:
    VERDICT: pass | findings
    FINDINGS: {numbered list with file:line, or "none"}
    HIGH-RISK: {yes + files, or no}

## Dispatch rules (coordinator)
- Max 5 implementers concurrent, single message, one worktree each.
- Reviewer runs AFTER the implementer reports done; findings go back to
  the implementer as attempt 2 (same worktree, same prompt + "Address
  these review findings: {list}"). After attempt 2 the ticket either
  passes or takes the honest-failure lane — never attempt 3.
```

- [ ] **Step 2: Verify** — implementer never pushes/PRs/writes Linear (coordinator-owned per spec); reviewer is fresh-context, correctness-scoped, and sees only diff+issue+plan; budget and attempt cap match Global Constraints; report formats are parseable and carry HIGH-RISK flags end-to-end. Fix inline.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/queue-drain/references/prompts.md
git commit -m "Add queue-drain subagent prompt templates

Implementer and fresh-context reviewer templates with fixed report
formats, budget/attempt caps, and high-risk diff flagging."
```

---

### Task 6: Retro reference + run report

**Files:**
- Create: `.claude/skills/queue-drain/references/retro.md`
- Create: `docs/runs/.gitkeep`

**Interfaces:**
- Consumes: per-ticket outcomes, timings, and HIGH-RISK flags from stages 4–6.
- Produces: the run-report file format in `docs/runs/YYYY-MM-DD-drain.md` that stage 1 of the NEXT run reads for the WIP-cap backlog check.

- [ ] **Step 1: Write retro.md**

```markdown
# Retro (queue-drain stage 7) — mandatory

Run by the coordinator, never a subagent. The drain is not done until
this file's checklist is complete and the run report is committed.

## 1. Technique worth keeping?
Scan the run: anything used twice, or once with obvious reuse (repo
quirk, debugging pattern, gotcha)? → new or updated skill in
`.claude/skills/`. **Hygiene before writing:**
- Dedupe: does an existing skill or CLAUDE.md already cover it? Update
  that instead.
- Route: CLAUDE.md only if universally applicable; a skill if
  situational; a hook if it must be deterministic.
- Retire: flag any skill this run proved stale.
Systemic root cause? → file a variant-analysis follow-up issue in Linear;
do not expand scope.

## 2. Pipeline friction?
Anything queue-drain itself got wrong → edit this skill's files, commit.

## 3. Nothing to capture?
Allowed — but write "none — reviewed" in the report. Never skip silently.

## Run report — write to docs/runs/YYYY-MM-DD-drain.md and commit

    # Drain YYYY-MM-DD
    ## Tickets
    | Issue | Class | Tier | Outcome | Cycle time | Attempts |
    |---|---|---|---|---|---|
    (Outcome: PR #N / needs-info / failed-honestly / parked)
    ## PRs awaiting merge   <- the human's worklist
    - [HIGH-RISK first, marked] ...
    ## Metrics
    - Escalation rate: {tickets needing a higher tier} / {total} (>20% =
      retune tiering)
    - WIP-cap hits: {waves needed}
    - Prior-run PRs merged/reverted since last drain: {check gh}
    ## Skills
    - Captured: ... / "none — reviewed"
    - Retired/updated: ...
    ## Worktrees left standing
    - {path}: {reason}
    ## Gate-erosion check
    - Plan batch size this run: N (>5 = split next time)

Commit message: "Drain YYYY-MM-DD: {X} PRs, {Y} needs-info, {Z} failed".
```

Also create empty `docs/runs/.gitkeep`.

- [ ] **Step 2: Verify** — retro's three questions match the spec; hygiene = dedupe/route/retire; metrics cover cycle time, escalation rate (20% threshold), WIP-cap hits; high-risk PRs sort first in the worklist; report path matches what SKILL.md stage 7 and stage 1 reference. Fix inline.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/queue-drain/references/retro.md docs/runs/.gitkeep
git commit -m "Add queue-drain retro reference and run-report format

Mandatory three-question retro with skill hygiene (dedupe/route/retire),
run metrics, and the docs/runs report the next drain's WIP check reads."
```

---

### Task 7: Wire into Nightshift CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (Nightshift root — add a section after "Working an Issue")

**Interfaces:**
- Consumes: the finished skill (Tasks 1–6).
- Produces: discoverability — any future session knows the drain exists.

- [ ] **Step 1: Add the section**

Insert into Nightshift `CLAUDE.md`, after the "Multiple Tickets at Once" section:

```markdown
### Draining the Queue

For batch work, don't hand-orchestrate: the **queue-drain** skill
(`.claude/skills/queue-drain/`) runs the whole loop — sweep → fetch Todo
queue → triage → batched plan approval → capped fan-out (5) → fresh-context
verify → draft PRs → Linear close → mandatory retro. Trigger it with
"drain the queue" or `/queue-drain`. Design and rationale:
`docs/superpowers/specs/2026-08-20-queue-drain-pipeline-design.md`.
Run reports land in `docs/runs/`.
```

Note: `CLAUDE.md` has a pre-existing uncommitted modification. Commit ONLY this hunk if possible (`git add -p CLAUDE.md`); if the pre-existing edit is entangled, stop and ask the human rather than committing someone else's pending change.

- [ ] **Step 2: Verify** — section states the trigger phrase, the stage summary matches SKILL.md, and paths are correct.

- [ ] **Step 3: Commit**

```bash
git add -p CLAUDE.md   # select only the Draining the Queue hunk
git commit -m "Point CLAUDE.md at the queue-drain skill"
```

---

### Task 8: Tabletop dry run (validation)

**Files:**
- No new files; may produce inline fixes to Tasks 2–6 files.

**Interfaces:**
- Consumes: everything.
- Produces: a validated skill; fixes committed.

- [ ] **Step 1: Read-only live fetch**

From Nightshift, with Linear MCP available: run stages 1–2 for real —
`list_issues` (team Engineering, Todo), classify per `references/triage.md`, and produce the triage table. **No Linear writes** (no comments, no status moves) — this is a dry run. Confirm: every issue got exactly one class; tier assigned to every `ready`; any unresolvable-repo issue classed `needs-info`.

- [ ] **Step 2: Tabletop stages 3–7**

Walk stages 3–7 on paper against the real triage output (or, if the queue is empty, against these three synthetic tickets: a one-line doc fix [expect ready/haiku], a `Feature`-labeled request [expect needs-plan], a vague "app is slow" report [expect needs-info]). At each stage, confirm the instructions are executable without guessing: exact tool named, exact template named, exact next step. Any point where the coordinator would have to improvise → fix the relevant file inline.

- [ ] **Step 3: Run the sweep test suite once more**

Run: `bash tests/sweep_test.sh`
Expected: `ALL PASS`.

- [ ] **Step 4: Commit any fixes**

```bash
git add .claude/skills/queue-drain/
git commit -m "Fix queue-drain gaps found in tabletop dry run"
```

(Skip the commit if the dry run found nothing — say so explicitly.)

---

## Self-review notes

- **Spec coverage:** stages 0–7 → Task 2; triage rules → Task 3; plan gate → Task 4; fan-out mechanics + budgets + Doppler → Tasks 2/5; verify gate (fresh reviewer, correctness scope, high-risk class, draft PRs) → Task 5 + Task 2 stage 5/6; retro + metrics + skill hygiene + run report → Task 6; sweep → Task 1; discoverability → Task 7; validation → Task 8. Out-of-scope items (headless, webhooks, the knowledge vault writes, new statuses) have no tasks — correct.
- **Type/name consistency:** class labels (`ready`/`needs-plan`/`needs-info`/`decompose`), tier labels, `RESULT:`/`VERDICT:` report keys, `RUN_FP_CHECK`, `docs/runs/YYYY-MM-DD-drain.md`, and `.worktrees/<issue-id>` are used identically across Tasks 2–6.
- **Placeholder scan:** all templates carry full content; `{placeholders}` appearing inside prompt templates are runtime fill-ins by design, not plan gaps.
