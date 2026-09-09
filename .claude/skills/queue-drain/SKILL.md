---
name: queue-drain
description: Use when asked to "drain the queue", "work the issue queue", "/queue-drain", or to batch-process GitHub issues labeled status/todo into PRs. Orchestrates sweep → triage → plan gate → fan-out → verify → close → retro with the main session as coordinator.
---

# Queue Drain

One command takes the `status/todo` issues across every target repo to
reviewed, ready-for-review PRs plus an honest run report. You (the main
session) are the **coordinator**: you own all GitHub issue writes, all
worktree creation/teardown, and the final report. Subagents implement and
review; they never write to an issue.

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
  runs attended:** watch it, record wall-clock and token spend, replace the
  120 with the measured number, drop the PROVISIONAL mark, and comment the
  measurement on the fable-calibration issue in `blaine-hiers/Nightshift`.

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
  in the PR body and the issue comment.
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
The queue is per-repo, so fetch per-repo. For each base clone in
`workspace/`, plus `blaine-hiers/Nightshift` itself (which holds the
`managed-platform` and `nightshift` work that has no repo of its own):

```bash
gh issue list -R blaine-hiers/<repo> --state open --label status/todo \
  --json number,title,body,labels,assignees,url --limit 100
```

**`status/todo` only.** `status/needs-input` and `status/blocked` are
deliberately out of scope — they are waiting on a human, and pulling them
in re-burns a subagent on a known blocker. Never widen this fetch to
"catch up" on them. Also count open agent PRs from prior runs
(`gh pr list -R blaine-hiers/<repo> --author @me --state open` per target
repo, or the PRs-awaiting-merge list from the last run report in
`docs/runs/`). Apply the WIP-cap stop rule before proceeding.

**Check push access per target repo here, not at stage 6:**
`gh api repos/blaine-hiers/<repo> --jq .permissions.push` for every repo
that returned issues. A `false` means every ticket in that repo will finish
implemented-but-unpushable; classify them **blocked** at triage (waiting on
write access, owner: the repo admin) instead of spending implementer and
reviewer budget on branches that can only sit in worktrees. The 2026-08-23
drain learned this after seven chat-service tickets were already in flight.

A repo with open `status/todo` issues but **no clone in `workspace/`** is
not skippable — clone it (`gh repo clone blaine-hiers/<repo>
workspace/<repo>`) and include it. The clone list is a cache, not the
queue's definition.

**Confirm the label taxonomy exists per repo, here, before triage writes
any label:**

```bash
bash .claude/skills/queue-drain/scripts/ensure-labels.sh blaine-hiers/<repo>
```

`gh` refuses `--add-label` for a label that does not exist, so a repo that
never got the taxonomy fails the *first status move of stage 4*, mid-run,
after its worktree is already built. The script is idempotent and leaves
existing labels untouched, including deliberate colour divergence; `--check`
reports without creating. The 2026-09-09 drain found three of seven repos
(Onramp, Redline, Nightshift) had no `status/…` or `tier/…` labels at all.

### 2. TRIAGE
Read `references/triage.md`. Classify every issue (ready / needs-plan /
needs-info / blocked / decompose / out-of-scope), take the tier from the
issue's `tier/…` label — deriving and writing one back only when it's
missing — post needs-info and blocked comments (`gh issue comment`) and
swap those issues' status labels to `status/needs-input` /
`status/blocked` (`gh issue edit`), then show the human the triage table.
The table is a sanity scan, not a gate — proceed after showing it.

### 3. PLAN GATE
Read `references/plan-gate.md`. Dispatch one planning subagent per
needs-plan or decompose issue (they may run while stage 4 starts for ready
tickets). Present ALL plans in ONE sitting via AskUserQuestion (approve /
revise / park / decompose per plan). For decompose tickets the planner
returns proposed child issues instead of a plan; on approval, create the
child issues with `gh issue create` in the same repo and move the parent to
`status/backlog` (details in `references/plan-gate.md`). Post approved plans
as comments on their issues.

### 4. FAN-OUT
The ready tickets are already grouped by repo — that is what stage 1's
per-repo fetch produced, and it is what the once-per-repo fetch below is
keyed on. Per target repo: `git fetch origin` once, confirm
`git config gc.auto` is 0 (set it if not). Create every worktree yourself:

```bash
git -C workspace/<repo> worktree add .worktrees/issue-<n> \
  -b dev/<n>-<kebab-slug> origin/main
```

then run the repo's bootstrap in each. Dispatch implementer subagents (max
5 concurrent) in a single message, using the implementer template in
`references/prompts.md`. Swap each issue to `status/in-progress` as its
agent starts — not batched.

**tier/codex tickets** are not dispatched as implementer subagents.
The coordinator works each one through the codex-dispatch skill
(worktree creation stays identical; max 2 concurrent Codex runs,
backgrounded). Their stage-5/6 review and PR flow happens inside
codex-dispatch — do not double-dispatch a stage-5 reviewer for them;
the PR auto-review in codex-dispatch is the one the human sees.

**Calibration gate.** While fable's or codex's budget is marked
PROVISIONAL, a ticket of that tier is not fanned out with the others: say
so, dispatch it **alone and attended**, and record actual wall-clock plus
token spend on the fable-calibration issue in `blaine-hiers/Nightshift`
(fable) or in the run report (codex). That measurement is what replaces
the guessed budget. Fan out the rest of the wave normally — the gate holds
up one ticket, not the batch.

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
clean/addressed AND the implementer's report confirms its
karpathy-guidelines self-check (part of the implementer prompt in
`references/prompts.md`).

### 6. CLOSE
Per passing ticket: push from the worktree, then
`gh pr create -R blaine-hiers/<repo> --head dev/<n>-<kebab-slug>`
(inside a `git worktree`, `gh` does not detect the tracking branch and aborts
with "you must first push the current branch" even after a successful push —
`--head` is mandatory). The body carries `Fixes #<n>` — that is what links
the PR to the issue and closes it on merge — plus root cause, fix summary,
and the stage-5 review findings. Open **ready for review**; add `--draft`
only when the ticket still owes human-only work, and name it in the body.

**Auto-review the PR.** Once the PR exists, dispatch a fresh reviewer
subagent (PR-review template in `references/prompts.md`, same tier rule as
stage 5) that checks out nothing — it reads the PR diff via `gh pr diff`,
runs the suite in the ticket's worktree, and posts its verdict on GitHub
with `gh pr review <n> --comment` (clean) or `--request-changes` (findings),
file:line per finding. This is the reviewer the human sees; stage 5's is the
one the implementer sees. Then `gh issue comment` on the issue (root cause
+ PR link + review verdict) and swap it to `status/in-review`.

Hand-dispatched batches (CLAUDE.md *Multiple Tickets at Once*) follow the same
open-ready + auto-review rule; the coordinator runs the review step itself.

**Deliverables that live outside git** (a document-library project folder, a Slack
canvas): the repo copy is canonical and goes through the PR like anything
else; the coordinator then mirrors it by dispatching a haiku subagent that
calls the M365 MCP upload tool directly (subagents can), headed with the PR
and commit it mirrors. Never retype a document through the main session, and
never let a subagent edit a canvas — that write is the coordinator's.

Every ticket that did **not** pass gets an honest `gh issue comment` and then
exactly one status label, by what the comment says is needed next:

| What the ticket turned out to need | Status |
|---|---|
| An external dependency — credential, environment, vendor fix, human decision | `status/blocked` |
| A better description — the ask was wrong, unclear, or the premise failed fp-check | `status/needs-input` |
| Nothing — it just ran out of budget or attempts and is genuinely retryable as written | `status/todo` |
| Nothing, and it is genuinely mid-flight with a live worktree you're keeping | leave `status/in-progress` |

`status/todo` is only for tickets a fresh subagent could retry unchanged and
plausibly finish. If the next run would hit the same wall, it belongs in
one of the off-ramps — returning it to todo just schedules the same
failure again.

If ready tickets remain beyond the WIP cap, return to stage 4 for the
next wave before stage 7.

### 7. RETRO
Read `references/retro.md`. Mandatory — the run is not done until the
retro has run and the run report is written to
`docs/runs/YYYY-MM-DD-drain.md` and committed.
