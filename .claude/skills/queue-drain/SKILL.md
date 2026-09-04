---
name: queue-drain
description: Use when asked to "drain the queue", "work the Linear queue", "/queue-drain", or to batch-process Linear Todo issues into PRs. Orchestrates sweep → triage → plan gate → fan-out → verify → close → retro with the main session as coordinator.
---

# Queue Drain

One command takes the Linear Todo column to reviewed, ready-for-review PRs
plus an honest run report. You (the main session) are the **coordinator**: you own all Linear
writes, all worktree creation/teardown, and the final report. Subagents
implement and review; they never write to Linear.

**The two human gates:** batched plan approval (stage 3) and PR merge
(outside this skill). Everything else runs without the human.

## Hard rules (no exceptions)

- WIP cap: max **5 tickets in flight**. If >~5 agent PRs from prior runs
  are still unreviewed, STOP and report instead of starting — never DDoS
  the merge gate. Remaining ready tickets queue for a second wave.
- Per ticket, budget by tier — then the honest-failure lane:

  | Tier | Wall-clock | Attempts | Concurrent |
  |---|---|---|---|
  | haiku | 20 min | 2 | — |
  | sonnet | 60 min | 2 | — |
  | opus | 90 min | 2 | — |
  | fable | **120 min — PROVISIONAL, never measured** | **1** | **max 1** |
  | codex | **30 min — PROVISIONAL, never measured** | 2 | **max 2** |

  Fable's single attempt is deliberate: a second unattended run on an
  unchanged prompt rarely converges, and a first fable failure usually means
  the ticket is mis-scoped — a human problem, not a retry problem. It should
  fail toward a human rather than toward more spend. **The first fable ticket
  runs attended** (see ENG-70): watch it, record wall-clock and token spend,
  replace the 120 with the measured number, and drop the PROVISIONAL mark.

  Codex-tier tickets are implemented by the OpenAI Codex CLI, not a
  Claude subagent: the coordinator runs `.claude/skills/codex-dispatch/SKILL.md`
  for each (pre-flight, sandboxed `codex exec` in the worktree, Claude
  pushes and opens the PR, reviewer subagent, one Codex fix round).
  Attempt 2 of a codex ticket is a fresh Codex session; the fix round
  is separate and comes out of the review, not this attempt count.
- PRs open **ready for review** (not draft) — the verify gate (stage 5)
  has already passed by the time a PR exists, and every PR gets an
  automatic review posted on GitHub at open (stage 6). Open as a draft
  only when the ticket still owes human-only work (an attended probe, a
  proof that needs infra the agent lacks) — and say exactly what is owed
  in the PR body and the Linear comment.
- Never dispatch a subagent with permission-skip flags; never use
  `isolation: "worktree"` (it worktrees Foreman, not the target repo).
- Honest failure is a valid output. Never fake a green gate.

## Stages

### 0. SWEEP
Run `bash .claude/skills/queue-drain/scripts/sweep.sh workspace/<repo>`
for each base clone in `workspace/`. Remove only REMOVABLE trees
(re-run with `--remove`); report every BLOCKED tree and its reason in the
run report. A BLOCKED tree is never deleted by hand.

### 1. FETCH
`list_issues`: team Engineering, **status Todo only**. `Needs Input` and
`Blocked` are deliberately out of scope — they are waiting on a human,
and pulling them in re-burns a subagent on a known blocker. Never widen
this fetch to "catch up" on them. Also count open
agent PRs from prior runs (`gh pr list --author @me --state open` per
target repo, or the PRs-awaiting-merge list from the last run report in
docs/runs/). Apply the WIP-cap stop rule before proceeding.

**Check push access per target repo here, not at stage 6:**
`gh api repos/<org>/<repo> --jq .permissions.push` for every `Repo/` label
in the fetch. A `false` means every ticket for that repo will finish
implemented-but-unpushable; classify them **blocked** at triage (waiting on
write access, owner: the org admin) instead of spending implementer and
reviewer budget on branches that can only sit in worktrees. The 2026-08-23
drain learned this after seven chat-service tickets were already in flight.

### 2. TRIAGE
Read `references/triage.md`. Classify every issue (ready / needs-plan /
needs-info / blocked / decompose / out-of-scope), take the repo and tier
from the issue's `Repo/…` and `Tier/…` labels — deriving and writing one
back only when it's missing — post needs-info and
blocked comments (`save_comment`) and move those issues to `Needs Input`
/ `Blocked` (`save_issue`), show the human the
triage table. The table is a sanity scan, not a gate — proceed after
showing it.

### 3. PLAN GATE
Read `references/plan-gate.md`. Dispatch one planning subagent per
needs-plan or decompose issue (they may run while stage 4 starts for ready tickets).
Present ALL plans in ONE sitting via AskUserQuestion (approve / revise /
park / decompose per plan). For decompose tickets the planner returns proposed child issues instead of a plan; on approval, create the child issues in Linear and move the parent to Backlog (details in references/plan-gate.md). Post approved plans to their Linear issues (save_comment).

### 4. FAN-OUT
Group the ready tickets by their `Repo/` label — that grouping is what
the once-per-repo fetch below is keyed on. Per target repo:
`git fetch origin` once, confirm `git config gc.auto` is
0 (set it if not). Create every worktree yourself:
`git -C workspace/<repo> worktree add .worktrees/<issue-id> -b <gitBranchName> origin/main`
then run the repo's bootstrap in each. Dispatch implementer subagents (max
5 concurrent) in a single message, using the implementer template in
`references/prompts.md`. Move each issue to In Progress as its agent
starts — not batched.

**Tier/Codex tickets** are not dispatched as implementer subagents.
The coordinator works each one through the codex-dispatch skill
(worktree creation stays identical; max 2 concurrent Codex runs,
backgrounded). Their stage-5/6 review and PR flow happens inside
codex-dispatch — do not double-dispatch a stage-5 reviewer for them;
the PR auto-review in codex-dispatch is the one the human sees.

**Calibration gate.** While fable's or codex's budget is marked
PROVISIONAL, a ticket of that tier is not fanned out with the others: say
so, dispatch it **alone and attended**, and record actual wall-clock plus
token spend as a comment on ENG-70 (fable) or in the run report (codex).
That measurement is what replaces the guessed budget. Fan out the rest
of the wave normally — the gate holds up one ticket, not the batch.

Doppler only where the ticket needs live calls:
`npm run env-sync` inside that worktree, dev config only; track which
worktrees hold credentials.

### 5. VERIFY
For each returned implementation, dispatch a **fresh reviewer subagent**
(reviewer template in `references/prompts.md`) that sees only the diff,
the issue, and the plan. Correctness findings → back to the implementer
(attempt 2) or fixed trivially by you. High-risk diffs (CI/workflow
files, hooks, permissions, credential handling) are flagged in the run
report regardless of review outcome. Gate = repo tests pass AND review
clean/addressed AND the implementer's report confirms its karpathy-guidelines self-check (part of the implementer prompt in references/prompts.md).

### 6. CLOSE
Per passing ticket: push from the worktree, `gh pr create --head <gitBranchName>`
(inside a `git worktree`, `gh` does not detect the tracking branch and aborts
with "you must first push the current branch" even after a successful push —
`--head` is mandatory) with root cause + fix summary + stage-5 review
findings noted. Open **ready for review**; add `--draft` only when the
ticket still owes human-only work, and name it in the body.

**Auto-review the PR.** Once the PR exists, dispatch a fresh reviewer
subagent (PR-review template in `references/prompts.md`, same tier rule as
stage 5) that checks out nothing — it reads the PR diff via `gh pr diff`,
runs the suite in the ticket's worktree, and posts its verdict on GitHub
with `gh pr review <n> --comment` (clean) or `--request-changes` (findings),
file:line per finding. This is the reviewer the human sees; stage 5's is the
one the implementer sees. Then `save_comment` on the Linear issue (root cause
+ PR link + review verdict), move the issue to In Review.

Hand-dispatched batches (CLAUDE.md *Multiple Tickets at Once*) follow the same
open-ready + auto-review rule; the coordinator runs the review step itself.

**Deliverables that live outside git** (a document-library project folder, a Slack
canvas): the repo copy is canonical and goes through the PR like anything
else; the coordinator then mirrors it by dispatching a haiku subagent that
calls the M365 MCP upload tool directly (subagents can), headed with the PR
and commit it mirrors. Never retype a document through the main session, and
never let a subagent edit a canvas — that write is the coordinator's.

Every ticket that did **not** pass gets an honest `save_comment` and then
exactly one status, by what the comment says is needed next:

| What the ticket turned out to need | Status |
|---|---|
| An external dependency — credential, environment, vendor fix, human decision | `Blocked` |
| A better description — the ask was wrong, unclear, or the premise failed fp-check | `Needs Input` |
| Nothing — it just ran out of budget or attempts and is genuinely retryable as written | `Todo` |
| Nothing, and it is genuinely mid-flight with a live worktree you're keeping | leave `In Progress` |

`Todo` is only for tickets a fresh subagent could retry unchanged and
plausibly finish. If the next run would hit the same wall, it belongs in
one of the off-ramps — returning it to Todo just schedules the same
failure again.

If ready tickets remain beyond the WIP cap, return to stage 4 for the
next wave before stage 7.

### 7. RETRO
Read `references/retro.md`. Mandatory — the run is not done until the
retro has run and the run report is written to
`docs/runs/YYYY-MM-DD-drain.md` and committed.
