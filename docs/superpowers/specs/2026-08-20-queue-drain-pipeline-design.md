# Queue-Drain Pipeline — Design

**Date:** 2026-08-20
**Status:** Approved (brainstormed with the maintainer, sections approved individually;
amendments A1–A7 folded in from the
[industry scan](../research/2026-08-20-industry-scan-queue-drain.md), same day)
**Home:** Nightshift repo only. Nothing lands in the knowledge vault.

## Problem

Nightshift's CLAUDE.md is an excellent *manual* — worktree mechanics, Linear
rules, model tiering, teardown discipline — plus a toolbox of 12 vetted
third-party skills. But nothing executes the manual:

1. **Too much manual driving.** The human is the pipeline: noticing issues,
   dispatching subagents, moving statuses, remembering the sweep. Every batch
   is re-orchestrated from prose.
2. **Knowledge doesn't compound.** The "capture techniques as skills" rule
   exists but has never fired — 2 commits, 0 home-grown skills. All installed
   skills are imports.

Also, the documented workflow is bug-shaped (reproduce → fix). Feature work
has no path.

## Solution

One command — a **`queue-drain` skill** in `.claude/skills/queue-drain/` —
that runs the whole batch with the main session as coordinator. The human
gates exactly twice: **plan approval** (features/complex only, batched into
one sitting) and **PR merge** (outside the pipeline, as today).

Linear stays the system of record. The pipeline's queue *is* the Todo column;
statuses map 1:1 onto pipeline stages (Todo → triaged, In Progress → agent
working, In Review → PR open, Done → merged). No new statuses.

### Rejected alternatives

- **Workflow-script orchestrator** — deterministic fan-out primitives, but
  requires multi-agent opt-in per run and can't do interactive plan gates
  cleanly. Overkill for 3–15 tickets.
- **Headless CLI loop (`claude -p` per ticket)** — cron-able, but loses
  interactive gates and reimplements coordination the Agent tool provides.
  Noted as a *future wrapper* around the proven skill, not a starting point.
- **Cross-repo retro into the knowledge vault wiki** — rejected; compounding is
  skills-only, inside Nightshift.

## Stages

```
0. SWEEP     — worktree hygiene per CLAUDE.md (clean + pushed + merged →
               remove; anything else → report, don't touch)
1. FETCH     — list_issues: team ENG, status Todo, unblocked
2. TRIAGE    — classify: ready / needs-plan / needs-info; assign model tier
3. PLAN GATE — needs-plan issues get compact plans; ★ human approves, batched
4. FAN-OUT   — one subagent per ready ticket (coordinator-owned worktrees,
               per-ticket model tier, single concurrent dispatch)
5. VERIFY    — repo test suite + differential-review + karpathy-guidelines
               before any PR opens
6. CLOSE     — PR opened, Linear comment (root cause + PR link), → In Review
7. RETRO     — mandatory; skills captured or "nothing to capture" reported
```

Fan-out of `ready` tickets starts **while** the human reviews plans — plain
bugfixes never wait on feature approvals.

## Triage rules

Three questions, in order, per Todo issue:

1. **Can we locate the work?** The issue must resolve to a target repo (via
   its Linear project or description). If not → `needs-info`.
2. **Actionable without the original conversation?** (CLAUDE.md's standard.)
   Missing repro, undefined acceptance, ambiguous ask → `needs-info`: post a
   sharpening comment listing exactly what's missing; issue stays in Todo;
   skip this run. If the ask is clear but the *premise* is doubtful (reported
   bug that may not be real), it stays `ready` and the working agent runs
   `fp-check` before touching code.
3. **Needs design first?** → `needs-plan` if ANY of: `Feature` label; touches
   more than one repo; unclear root cause with cross-cutting blast radius;
   concurrency/data-loss/security reasoning; goal clear but approach isn't.
   Otherwise → `ready`.

**Tiers:** CLAUDE.md's table verbatim (haiku = mechanical, sonnet = ordinary
default, opus = justified only), default down. Triage output is a table shown
to the human before fan-out — *issue → class → tier → repo* — a sanity scan,
not a gate.

## Plan gate

Per `needs-plan` issue, a planning subagent reads the target repo and drafts
a **compact plan**: goal, approach, files touched, test plan, explicit
out-of-scope. Then:

- All plans presented **together, one sitting** — one approval moment per
  run, not N interruptions.
- **Approved** → plan posted as a Linear comment (it becomes part of the
  implementing agent's prompt) → ticket joins fan-out.
- **Revise** → redrafted within the run.
- **Park** → stays Todo with the draft plan and feedback attached as
  comments; next run resumes from there.

Ticket-scale plans (half a page), not project-scale specs — deliberately NOT
the full brainstorm→spec ceremony. A ticket too big for a half-page plan gets
triaged as **decompose**: the planner proposes child issues in Linear and the
human approves the split at the same sitting.

## Fan-out mechanics

Codifies CLAUDE.md exactly; coordinator owns everything shared:

1. Per target repo: one `git fetch` from the main thread, `gc.auto=0`
   confirmed, **before** any agent launches.
2. Coordinator creates every worktree first
   (`.worktrees/<issue-id>`, branch = Linear's `gitBranchName`, from
   `origin/main`), runs the repo's bootstrap, then dispatches all subagents
   in a **single message** for concurrency.
3. Each subagent receives: issue ID, Linear description (+ approved plan
   comment) **verbatim**, worktree path, model tier, and a **per-ticket
   budget** (default 60 minutes wall-clock / 2 attempts; A3). Budget
   exhausted → the ticket takes the honest-failure lane, never a hang.
   One subagent = one issue = one worktree. Never `isolation: "worktree"`
   (documented footgun — it would worktree Nightshift itself, which
   contains no target repo). Subagents never run with permission-skip
   flags (`--dangerously-skip-permissions` and kin are a documented attack
   primitive; A5).
3a. **WIP cap** (A4): at most **5 tickets in flight** per drain, and a
   drain does not start while more than ~5 agent PRs from prior runs sit
   unreviewed — agent output volume must never DDoS the merge gate
   (lesson: curl's bug-bounty shutdown at ~95% AI false positives).
   Remaining ready tickets queue for the next wave within the same run.
4. **Doppler:** default no `.env`. Only tickets driving live calls run
   `npm run env-sync` inside their worktree, `dev` config only. Coordinator
   tracks which worktrees hold credentials — their teardown is secret
   hygiene, not just disk hygiene.
5. Coordinator moves each issue to In Progress as its agent starts (not
   batched), relays results, owns all Linear writes at close.

## Verify gate

Every PR opens as a **draft** (A2); only the coordinator marks it ready —
and only after all of:

- The target repo's **own test suite passes** in the worktree.
- **`differential-review`** runs in a **fresh-context subagent** — never
  the implementing agent reviewing itself (A1). The reviewer sees only the
  diff, the issue, and the plan, and is **scoped to correctness findings**
  (gap-hunting reviewers always find gaps; style/architecture preferences
  are out of scope). Findings fixed or explicitly noted in the PR body.
- **High-risk diff class** (A5): any diff touching CI/workflow files,
  hooks, permissions, or credential handling is flagged for explicit human
  attention in the run report — regardless of review outcome (lessons:
  Amazon Q compromise, Nx attack).
- **`karpathy-guidelines`** self-check by the implementer: no silent
  assumptions, no orthogonal changes, no over-engineering.
- PR body **and** Linear comment both carry root cause + fix summary.

A ticket that can't pass (broken upstream suite, unreproducible) doesn't
fake it: the agent reports back, the coordinator comments the finding on the
issue and returns it to Todo (or leaves In Progress if genuinely mid-flight).
**Honest failure is a valid pipeline output.**

## Retro (mandatory)

Run isn't "done" until the coordinator — not a subagent — answers:

1. **Technique worth keeping?** Used twice this run, or once with obvious
   reuse → new/updated skill in `.claude/skills/`, committed. Systemic root
   causes → file a `variant-analysis` follow-up issue in Linear rather than
   expanding scope mid-run.
2. **Pipeline friction?** The queue-drain skill's own defects → edit the
   skill, commit. The pipeline improves itself the same way it improves the
   queue.
3. **Nothing worth capturing?** Allowed — but reported explicitly, never
   silently skipped.

**Skill hygiene** (A7): before writing any lesson, dedupe against existing
skills and CLAUDE.md. Route it: CLAUDE.md only if universally applicable; a
skill if situational; a hook if it must be deterministic. Flag stale skills
for retirement. Bloated instructions cause agents to ignore instructions.

**Metrics, not vibes** (A6): the retro records per-run numbers — cycle time
per ticket, tier-escalation rate (>~20% means the tiering is mistuned), and
(looking back at prior runs) revert/rework on merged agent PRs. Perceived
speedup is unreliable (METR: devs 19% slower while feeling 20% faster).

## Run report (final output)

- Tickets worked → outcome: **PR** / **needs-info** / **failed honestly**
- PRs awaiting merge (the human's worklist), with **high-risk diffs
  flagged first** (A5)
- Run metrics (A6): cycle time per ticket, escalation rate, WIP-cap hits
- Skills captured (or "none — reviewed")
- Worktrees left standing and why

**Gate-erosion watch:** batched approvals are efficient exactly until they
become rubber-stamping. Plan batches and PR worklists stay small enough to
genuinely read — that's what the WIP cap protects.

## Linear integration summary

| Stage | Linear calls |
|---|---|
| FETCH | `list_issues` (team ENG, Todo, unblocked) |
| TRIAGE | `get_issue`; `save_comment` for needs-info |
| PLAN GATE | `save_comment` (plan + approval note) |
| FAN-OUT | branch from `gitBranchName`; issue → In Progress per agent |
| CLOSE | `save_comment` (root cause + PR link); → In Review |
| Merge (human) | → Done; signals next sweep to tear down that worktree |

Caveat: the claude.ai Linear MCP is interactively authenticated — fine for
the in-session model chosen here. A future cron/headless wrapper would need a
Linear API key instead. Out of scope now.

## Out of scope

- Scheduled/headless runs (future wrapper around the proven skill)
- Event-driven triggers (Linear webhooks)
- Any writes to the knowledge vault
- New Linear statuses or workflow changes
- Full superpowers spec ceremony for ticket-scale work

## Success criteria

- One command takes the Todo column to PRs + an honest run report with at
  most one mid-run human interruption (batched plan approval).
- Every PR that opens has passed the verify gate.
- Every run ends with a retro commit or an explicit "nothing to capture".
- Thin tickets leave the run with sharpening comments in Linear — the queue
  itself compounds.
