# Codex Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route `Tier/Codex` Linear issues to OpenAI Codex as implementer, with Claude as coordinator (Linear writes, worktrees, push, PR) and reviewer (PR review plus one Codex fix round).

**Architecture:** A new first-party skill `.claude/skills/codex-dispatch/SKILL.md` encodes the per-issue loop; small routing edits in queue-drain, its triage reference, CLAUDE.md, and docs/skills.md point `Tier/Codex` at it; a `Codex` child label is created in Linear's `Tier/` group. The vetted third-party `codex` skill is not modified — codex-dispatch cites it for CLI mechanics.

**Tech Stack:** Codex CLI (`codex exec`, v0.152.0), Linear MCP tools, `gh`, git worktrees, Git Bash.

**Spec:** `docs/superpowers/specs/2026-09-01-codex-dispatch-design.md` — read it before starting.

## Global Constraints

- Codex always runs `--sandbox workspace-write` (never `danger-full-access`) with `</dev/null` on stdin and stderr redirected to a log file.
- Resume always by session UUID, never `--last`.
- Default model/effort: `gpt-5.6-terra` / `high`; per-issue override via a `codex: <model>/<effort>` line in the Linear issue description.
- Exactly one review→fix round; after it, unresolved findings → PR comment + Linear **Blocked**.
- Budget row (PROVISIONAL): 30 min wall-clock, 2 attempts, max 2 concurrent.
- `Tier/Codex` is invalid on `Repo/Managed-Platform` issues.
- All commits in this plan are to the Foreman repo, from its root. Commit messages end with the standard Co-Authored-By / Claude-Session trailer used by this session.
- This machine's Bash tool is Git Bash; `$SCRATCH` below means the session scratchpad directory printed in the system prompt.

---

### Task 1: Smoke-test the session-UUID capture and auth pre-flight mechanics

The whole fix-round design rests on two assumptions: (a) `codex exec`'s stderr log contains the session UUID, and (b) there is a cheap auth check. Verify both against the installed CLI before writing the skill, and record what you observe — Task 2's SKILL.md must match observed reality, not the spec's guess.

**Files:**
- Create: `$SCRATCH/codex-smoke.log`, `$SCRATCH/codex-smoke.out` (scratchpad only, never committed)

**Interfaces:**
- Produces: the observed UUID-capture method (stderr grep vs `--json` fallback) and the observed auth-check command, both consumed verbatim by Task 2.

- [ ] **Step 1: Check the auth-status command**

Run: `codex login --help 2>&1 | head -20`
Expected: a `status` subcommand (or similar). Then run the real check:

```bash
codex login status
```

Expected: exit 0 with a "logged in" style message (the user authed this folder). Record the exact working command. If `codex login status` doesn't exist, find the nearest equivalent from `codex --help` and record that instead.

- [ ] **Step 2: Run a minimal Codex exec and capture stderr**

```bash
cd "$SCRATCH" && codex exec -m gpt-5.6-luna \
  --config model_reasoning_effort="low" \
  --sandbox read-only --skip-git-repo-check \
  -o codex-smoke.out \
  "Reply with exactly: OK" </dev/null 2>codex-smoke.log
```

Expected: exit 0; `codex-smoke.out` contains `OK`.

- [ ] **Step 3: Verify the session UUID is extractable**

```bash
grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$SCRATCH/codex-smoke.log" | head -1
```

Expected: one UUID. **If empty:** re-run Step 2 with `--json` added and no `2>` redirect, and extract the session id from the JSONL on stdout (look for a `session_id` or `thread_id` field in the first events). Record which method worked.

- [ ] **Step 4: Verify resume-by-UUID works**

```bash
cd "$SCRATCH" && codex exec --skip-git-repo-check resume <UUID-from-step-3> \
  "Reply with exactly: RESUMED" </dev/null 2>>codex-smoke.log
```

Expected: stdout ends with `RESUMED`. No commit for this task — it produces knowledge, not files.

---

### Task 2: Write `.claude/skills/codex-dispatch/SKILL.md`

**Files:**
- Create: `.claude/skills/codex-dispatch/SKILL.md`

**Interfaces:**
- Consumes: Task 1's observed UUID-capture method and auth command — substitute them where the content below says `codex login status` or describes the stderr grep, if what you observed differs.
- Produces: the skill that Tasks 3–4 reference by path `.claude/skills/codex-dispatch/SKILL.md` and by name `codex-dispatch`.

- [ ] **Step 1: Write the file with this exact content** (adjusting only for Task 1 observations):

````markdown
---
name: codex-dispatch
description: Use when a Linear issue carries the Tier/Codex label, or the user asks for OpenAI Codex to implement a Linear issue — runs the issue lifecycle with Codex as implementer and Claude as coordinator and reviewer.
---

# Codex Dispatch

Codex writes the code and commits; you (the coordinator) do everything
else — every Linear write, worktree operation, push, PR creation, and
review dispatch. Codex never gets network access and never touches
Linear or GitHub. CLI mechanics (models, efforts, timeouts, stdin
rules) live in the vetted `codex` skill — this skill only encodes the
Linear workflow around them.

**Scope guard:** `Tier/Codex` never combines with `Repo/Managed-Platform`
(no worktree/PR flow exists there). If you find that combination,
fix the labels via triage judgment before dispatching.

## Pre-flight (once per run, not per ticket)

```bash
codex --version && codex login status
```

Both must succeed. If either fails, STOP the whole dispatch and report —
do not fail ticket-by-ticket against a dead CLI.

## Model and effort

Read the issue description for a `codex: <model>/<effort>` line
(triage's convention). Absent that, use `gpt-5.6-terra` / `high`.
Valid values and compatibility rules (e.g. `ultra` only on sol/terra)
come from the `codex` skill — on an invalid combination, fall back to
the model's highest supported effort and say so in the Linear comment.

## Per-issue flow

1. **Pick up.** `get_issue`, move to In Progress, create the worktree
   from the base clone with `gitBranchName` — standard flow, see
   `docs/workspace.md`.
2. **Run Codex.** Compose the prompt: the Linear issue description
   **verbatim**, then a conventions pointer ("Read this repo's
   CLAUDE.md / CONTRIBUTING / README first and follow its build, test,
   and style conventions"), then the contract: "Implement the fix, run
   the repo's own test suite until it passes, and commit your work to
   the current branch with a message referencing <issue-id>. Do not
   push." Then:

   ```bash
   codex exec -m <model> \
     --config model_reasoning_effort="<effort>" \
     --sandbox workspace-write --full-auto --skip-git-repo-check \
     -C <worktree-path> -o <scratchpad>/codex-<issue-id>.out \
     "<prompt>" </dev/null 2><scratchpad>/codex-<issue-id>.log
   ```

   Run it in the background with the timeout from the `codex` skill's
   effort table (`high` → 600 s) so parallel tickets don't serialize.
   When it exits, capture the **session UUID** from the log:

   ```bash
   grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
     <scratchpad>/codex-<issue-id>.log | head -1
   ```

   Keep the UUID — the fix round and the Linear trail both need it.
3. **Verify.** `git -C <worktree> log origin/main..HEAD --oneline` must
   show at least one commit, and the repo's own test suite must pass
   when you run it yourself. An empty `-o` output file means Codex was
   killed before finishing — treat as a timeout (failure lane below).
4. **Open the PR yourself.** Push from the worktree, then
   `gh pr create --head <gitBranchName>` (the `--head` flag is
   mandatory from inside a worktree), **ready for review**, body
   opening with: "Implementation by OpenAI Codex (`<model>`/`<effort>`,
   session `<uuid>`); coordinated and reviewed by Claude." plus the
   issue id and root-cause/fix summary.
5. **Review.** Dispatch a fresh reviewer subagent using the PR-review
   template in `.claude/skills/queue-drain/references/prompts.md`; it
   posts its verdict with `gh pr review`.
6. **One fix round.** If the review requests changes, resume Codex
   **by UUID — never `--last`** (parallel runs would cross-resume):

   ```bash
   codex exec --skip-git-repo-check resume <uuid> \
     "<review findings, file:line>" </dev/null 2>><scratchpad>/codex-<issue-id>.log
   ```

   Re-verify (step 3), push, and dispatch the reviewer once more. If
   findings remain: comment the unresolved list on the PR, move the
   Linear issue to **Blocked** with the trail, keep the worktree, stop.
   There is no second fix round.
7. **Close out.** `save_comment` on the issue: root cause, PR link,
   review verdict, Codex session UUID, model/effort actually used.
   Move to In Review; Done only when merged and verified, tearing the
   worktree down in that same step.

## Failure lanes

- **Non-zero exit, no commits, or timeout:** one retry at the same
  settings (fresh session). A second failure → Blocked, with the last
  ~20 lines of the log in the Linear comment. Honest failure is a
  valid output — never fake a green gate.
- **Budget (PROVISIONAL, never measured):** 30 min wall-clock per
  ticket, max 2 Codex tickets concurrent. The first real run is
  attended: record wall-clock, replace 30 with the measured number,
  and drop the PROVISIONAL mark here and in queue-drain's table.

## Attribution

The PR body line in step 4 and the Linear close-out comment are the
record that Codex authored the change. Keep both accurate — if you
(Claude) end up writing code to rescue a ticket, say so in both places
and consider whether the tier label should change.
````

- [ ] **Step 2: Verify the skill parses** — frontmatter is the first thing in the file, `name: codex-dispatch` matches the folder name:

Run: `head -5 .claude/skills/codex-dispatch/SKILL.md`
Expected: `---`, `name: codex-dispatch`, a `description:` line.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/codex-dispatch/SKILL.md
git commit -m "Add codex-dispatch skill: Codex implements, Claude coordinates and reviews"
```

---

### Task 3: Wire queue-drain to route `Tier/Codex`

**Files:**
- Modify: `.claude/skills/queue-drain/SKILL.md` (budget table ~line 23; FAN-OUT stage ~line 87)
- Modify: `.claude/skills/queue-drain/references/triage.md` (closed-set sentence ~line 30; tier table ~line 95; labels example ~line 115)

**Interfaces:**
- Consumes: skill name `codex-dispatch` and path `.claude/skills/codex-dispatch/SKILL.md` from Task 2.

- [ ] **Step 1: Add the budget row.** In `.claude/skills/queue-drain/SKILL.md`, after the fable row of the budget table, add:

```
  | codex | **30 min — PROVISIONAL, never measured** | 2 | **max 2** |
```

And after the existing fable calibration paragraph (ending "…drop the PROVISIONAL mark."), append this paragraph:

```
  Codex-tier tickets are implemented by the OpenAI Codex CLI, not a
  Claude subagent: the coordinator runs `.claude/skills/codex-dispatch/SKILL.md`
  for each (pre-flight, sandboxed `codex exec` in the worktree, Claude
  pushes and opens the PR, reviewer subagent, one Codex fix round).
  Attempt 2 of a codex ticket is a fresh Codex session; the fix round
  is separate and comes out of the review, not this attempt count.
```

- [ ] **Step 2: Add the fan-out routing note.** In the same file, at the end of the `### 4. FAN-OUT` stage text (after "…Move each issue to In Progress as its agent starts — not batched."), append:

```

**Tier/Codex tickets** are not dispatched as implementer subagents.
The coordinator works each one through the codex-dispatch skill
(worktree creation stays identical; max 2 concurrent Codex runs,
backgrounded). Their stage-5/6 review and PR flow happens inside
codex-dispatch — do not double-dispatch a stage-5 reviewer for them;
the PR auto-review in codex-dispatch is the one the human sees.
```

- [ ] **Step 3: Update triage.md.** Three edits in `.claude/skills/queue-drain/references/triage.md`:

(a) Replace the sentence `` `Repo/` is the only dimension that grows. `Tier/` is closed at four values and the type labels at three; `` with `` `Repo/` is the only dimension that grows. `Tier/` is closed at five values and the type labels at three; ``

(b) After the Fable row of the tier table, add:

```
| Codex | Route to the OpenAI Codex CLI as implementer (codex-dispatch skill). Assign only when the user asked for Codex on this work or the issue description requests it — never derive it as a cost/difficulty judgment, and never on `Repo/Managed-Platform`. Optionally record `codex: <model>/<effort>` in the description; default is gpt-5.6-terra/high. |
```

(c) In the **Writing labels back** section, after the line `labels: ["Bug", "api-server", "Sonnet"]   # complete set, not a delta`, add a sentence to the following paragraph noting: `` `Codex` is a valid `Tier/` child; it maps to the codex-dispatch skill, not to an `Agent` `model:` string. ``

- [ ] **Step 4: Verify the edits**

Run: `grep -n "codex" .claude/skills/queue-drain/SKILL.md .claude/skills/queue-drain/references/triage.md`
Expected: hits in the budget table, fan-out stage, closed-set sentence area, tier table, and labels section — and `grep -c "PROVISIONAL" .claude/skills/queue-drain/SKILL.md` returns at least 3.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/queue-drain/SKILL.md .claude/skills/queue-drain/references/triage.md
git commit -m "queue-drain: route Tier/Codex tickets through codex-dispatch"
```

---

### Task 4: Update CLAUDE.md and docs/skills.md

**Files:**
- Modify: `CLAUDE.md` (Labels table `Tier/…` row; Prompt and Model Selection tier table)
- Modify: `docs/skills.md` (First-party section)

**Interfaces:**
- Consumes: skill name `codex-dispatch` from Task 2.

- [ ] **Step 1: Labels table.** In CLAUDE.md's Labels table, change the `Tier/…` row's values from `` `Haiku`, `Sonnet`, `Opus`, `Fable` `` to `` `Haiku`, `Sonnet`, `Opus`, `Fable`, `Codex` ``.

- [ ] **Step 2: Tier table.** In the *Prompt and Model Selection* section, after the `fable` row, add:

```
| `codex` | Not a Claude tier: routes the issue to the OpenAI Codex CLI as implementer via the `codex-dispatch` skill (Claude coordinates and reviews). Opt-in only — assign when the user asks for Codex on the work; never as a cost/difficulty derivation. |
```

And after the paragraph beginning "Record the choice as the issue's `Tier/…` label…", append the sentence: `` `Tier/Codex` maps to no `Agent` `model:` string at all — it routes to the codex-dispatch skill instead. ``

- [ ] **Step 3: docs/skills.md.** Find the `## First-party` section (`grep -n "First-party" docs/skills.md`), read its entry format, and add a matching entry:

```
- **codex-dispatch** — works a `Tier/Codex` Linear issue with OpenAI Codex as implementer (sandboxed `codex exec` in the issue worktree) and Claude as coordinator/reviewer: Claude pushes, opens the PR, dispatches the reviewer, and runs one Codex fix round by session UUID. Depends on the third-party `codex` skill for CLI mechanics and the `codex` CLI being authenticated. Spec: `docs/superpowers/specs/2026-09-01-codex-dispatch-design.md`.
```

- [ ] **Step 4: Verify**

Run: `grep -n "Codex" CLAUDE.md docs/skills.md | head -20`
Expected: the Labels row, the tier table row, the model-string sentence, and the skills.md entry all present.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/skills.md
git commit -m "Document Tier/Codex and codex-dispatch in CLAUDE.md and skills inventory"
```

---

### Task 5: Create the `Tier/Codex` label in Linear

External write — no repo files. Creating a label inside work the user asked for is within the standing rules of engagement.

**Interfaces:**
- Consumes: nothing from prior tasks (independent, but do it last so docs describing the label land first).

- [ ] **Step 1: Find the `Tier` group's parent label id**

Call `mcp__claude_ai_Linear__list_issue_labels` for team `Engineering`. Locate the parent label named `Tier` (the group containing `Haiku`, `Sonnet`, `Opus`, `Fable`) and note its id.

- [ ] **Step 2: Create the child label**

Call `mcp__claude_ai_Linear__create_issue_label` with name `Codex`, the `Tier` parent id from Step 1, and the same team. (Linear capitalizes display names; `Codex` is already capitalized.)

- [ ] **Step 3: Verify**

Call `list_issue_labels` again and confirm `Tier/Codex` appears alongside the four existing tier children. Report the label id in the task output.

---

## Final verification (after all tasks)

- [ ] `git log --oneline -5` shows the three commits from Tasks 2–4.
- [ ] `grep -rn "resume --last" .claude/skills/codex-dispatch/` returns only the line warning **against** `--last`.
- [ ] Push: `git push` (the user has already authorized commit+push for this feature's file changes in this session's flow — if in doubt, ask).
