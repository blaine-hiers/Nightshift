# Industry Scan: Agentic Issue-to-PR Pipelines (2025–2026)

**Date:** 2026-08-20
**Purpose:** Compare the approved [queue-drain pipeline design](../specs/2026-08-20-queue-drain-pipeline-design.md)
against current industry practice. Six parallel research agents; primary
sources (vendor docs, changelogs, engineering blogs) preferred.

> **Superseded in part (2026-09-04).** Nightshift has since moved its system of
> record from Linear to **GitHub Issues** (status as an exclusive `status/…`
> label, one issue per target repo, all calls via `gh`). Vendor names, dates,
> and citations below are left exactly as scanned — they are third-party facts
> about the 2025–2026 market, not statements about how Nightshift works today.
> Read the tracker-specific findings as market context, not as current design.

## Verdict

The spec's shape is not idiosyncratic — it is the 2025–2026 industry
consensus, independently converged on by every major vendor. Two elements are
ahead of what platforms ship natively (model tiering at triage, mandatory
retro-to-skills). Seven amendments are recommended from failure literature
and published best practice.

---

## 1. What the spec gets right (validated by industry)

### A dedicated issue tracker as the agent work queue — now the de facto standard
- **Linear for Agents** (May 2025) made agents first-class assignable
  workspace members; the **Agent Interaction SDK** (Aug 2025) formalized it.
  Delegation model: agent becomes *delegate*, **human stays assignee/owner** —
  exactly the spec's accountability model.
  (linear.app/changelog/2025-05-20-linear-for-agents)
- Nearly every coding agent converged on "assign the Linear issue":
  Cursor, Devin, Codegen, Charlie, Factory, Claude Code (via Cyrus), and
  GitHub Copilot cloud agent for Linear (**GA July 23, 2026** — with
  per-task model selection, draft PRs, mid-session steering).
- Linear best practices: move issue to first "started" status on pickup;
  read context from agent activities, not comments (comments are editable).

### Coordinator + subagent fan-out — Anthropic's recommended pattern
- Anthropic's *Multi-agent coordination patterns* (Apr 2026) names
  **orchestrator-subagent** the right starting pattern ("widest range of
  problems, least coordination overhead") and **generator-verifier** as the
  pattern behind quality gates. (claude.com/blog/multi-agent-coordination-patterns)
- Agent Teams docs confirm: subagents (report-back) are the cost-correct
  choice for batch work; chatty teams cost significantly more and don't run
  in headless mode anyway.
- **Devin "managed Devins"** (Mar 2026): coordinator scopes work, then
  **proposes the batch of child sessions for human approval before launch** —
  the spec's batched plan gate as a shipped commercial feature.

### Worktree-per-ticket — the settled community pattern
- Git-worktree-per-agent is the standard for parallel Claude Code;
  practical concurrency is **4–8 worktrees per developer**.
- **Cyrus** (github.com/cyrusagents/cyrus, open source) is the closest
  existing implementation of this exact pipeline: watches Linear
  assignments, one worktree per issue, Claude Code session per ticket,
  streams activities back to its tracker. Worth studying; our in-session skill is
  the lighter-weight equivalent.

### Two human gates — the consensus, and increasingly structural
- Plan gates: Google **Jules** requires plan approval before execution;
  **Devin** frames plan review as "the cheapest steering point" (approving
  up front avoids wasted compute); Claude Code **plan mode** hard-disables
  write tools until approval, with official guidance to **gate by
  uncertainty, not uniformly** — exactly the ready/needs-plan triage split.
- Merge gates: GitHub Copilot's are *structural* — agent PRs open as
  drafts, agent cannot mark ready/approve/merge, **the task assigner cannot
  approve the resulting PR** (four-eyes), CI on agent code needs a human
  "Approve and run workflows" click.
- Anthropic's documented "plan locally, execute remotely" pattern (approve
  plans in one sitting, persist as files, hand to autonomous sessions) is
  the spec's plan gate almost verbatim.

### Verify gate before PR — universal
- **Charlie** ships "CI green before the PR opens" as product behavior.
- Anthropic (Jul 2026, *Building verification loops with skills*): encode
  checks as skills; **run the reviewer in a fresh-context subagent separate
  from the implementer** ("a reviewer not influenced by the main agent's
  reasoning is less biased").
- Review vendors' core product problem is false-positive suppression:
  CodeRabbit re-grounds every comment before posting; Greptile ships
  per-comment confidence (addressed-rate 30%→43% after adding it); GitHub
  fuses Copilot review with deterministic CodeQL/ESLint.

### Model tiering — measurably right, and a differentiator
- Community routing data: Haiku ~60% of tasks / Sonnet ~30% / Opus ~10%
  cuts cost **~51%** vs uniform top-tier. Tuning metric: if cheap-model
  output needs expensive-model correction **>~20%** of the time, tiering is
  losing money. No native platform ships tiered routing at triage — the
  spec is ahead here.

### Retro-to-skills — named practice: "compounding engineering"
- Every's plan→work→assess→**compound** loop (mandatory, not ad hoc):
  every fix/review comment gets its principle codified into agent
  instructions. Devin converts successful sessions into **Playbooks**
  (Procedure / Specifications / Forbidden Actions schema — a good template
  for captured skills). Linear's own native agent (Mar 2026) saves
  successful conversations as reusable "Skills."
- Universal trust model: **agent proposes, human approves** — matches
  keeping capture inside the coordinator-run retro.

---

## 2. What the industry does that the spec lacks — recommended amendments

**A1. Fresh-context reviewer, correctness-scoped.** Run
`differential-review` in a **separate subagent** that sees only the diff +
criteria — never self-review by the implementing agent. Scope it to
correctness: Anthropic warns gap-hunting reviewers *always* find gaps,
driving over-engineering. (Spec currently lets the implementer run its own
review.)

**A2. Draft PRs + structural conventions.** Open every agent PR as a
**draft**; only the coordinator (after verify gate) marks it ready.
Industry-wide convention (Copilot, Codex, Cursor).

**A3. Per-ticket budget.** Copilot caps sessions at 59 minutes. Add a
wall-clock/attempt cap per ticket feeding the honest-failure lane, so a
stuck agent becomes a report, not a hang.

**A4. WIP cap on the drain.** Practical worktree concurrency is 4–8; GitHub
now ships per-user open-PR caps because agent PR floods are real. **curl
shut down its bug bounty (Feb 2026) at ~95% false-positive rate** — the
canonical lesson: *agent output volume DDoSes the human gate*. Cap
concurrent tickets per run (suggest 5) and don't start a new drain while
review backlog exceeds a threshold.

**A5. CI/workflow diffs are a high-risk class.** The **Amazon Q compromise**
(data-wiper shipped to ~1M devs via rubber-stamped PR + over-permissioned
CI token) and the **Nx attack** (malicious releases weaponizing local agents
via `--dangerously-skip-permissions`-style flags) both route through agent
pipelines. Verify gate must flag any diff touching CI/workflow files,
hooks, or permissions for explicit human attention — and subagents never
run with blanket permission-skip flags.

**A6. Retro measures, not vibes.** METR's RCT: experienced devs were **19%
slower** with AI while *believing* they were 20% faster. Track per run:
cycle time per ticket, tier-escalation rate (>20% = retune tiering), and
revert rate + change failure rate on merged agent PRs (DX's paired
metrics). Add one metrics line to the run report.

**A7. Skill hygiene rules.** From Claude Code best practices + community
retro tooling (claude-improve, self-improving-skills): before writing a
lesson, **dedupe against existing instructions**; route it — CLAUDE.md only
if universally applicable, a skill if situational, a hook if it must be
deterministic ("bloated CLAUDE.md files cause Claude to ignore your actual
instructions"); periodically retire stale skills.

**Watch-item (not an amendment): gate erosion.** Willison + the failure
literature agree the gates only work while the human genuinely reviews.
Batched plan approval is efficient exactly until it becomes rubber-stamping
— keep plan batches small enough to actually read.

---

## 3. Calibrating expectations (field data)

- **Devin's 18-month retrospective**: PR merge rate 34%→67% YoY; "senior at
  codebase understanding, junior at execution." Even mature fleets see ~1/3
  of PRs rejected — the merge gate is load-bearing.
- **OpenHands** (massive parallel refactors): ~5 concurrent agents in
  practice; work is "80–90% automatable" — the needs-info lane is permanent,
  not a v1 limitation.
- **DORA 2025**: AI raises throughput *and* instability simultaneously;
  review capacity is the bottleneck. **GitClear**: 8× growth in duplicated
  code blocks; duplication + short-term churn are the specific defect
  signatures the diff-review skill should hunt.
- **DX (Q2 2026)**: AI now authors ~52% of code; median PR size doubled —
  keep agent PRs small.

## 4. Future options noted, out of scope now

- **Linear Agent Sessions API** (pending/active/awaitingInput/complete/
  stale; elicitation activities) — the native mechanism if the pipeline ever
  becomes a headless/webhook service. `awaitingInput` maps to
  needs-plan/needs-info.
- **Claude Code Auto-fix** (webhook-driven CI-failure self-healing on open
  PRs) — a post-PR extension so routine CI red doesn't bounce to the
  coordinator.
- **Cursor-style auto-triage rules** (category→agent routing) — partial
  automation of the triage step once patterns stabilize.
- **Ralph-Wiggum-style loop-until-empty** (Anthropic plugin; Stop-hook exit
  conditions) — turning one pass into drain-until-empty.

## Source note

Findings drawn from vendor primary sources: GitHub docs/changelogs, Linear
changelog + developer docs, Anthropic engineering blog + Claude Code docs,
Cognition (Devin) docs + 2025 performance review, OpenAI, Google Jules,
Cursor, Factory, CodeRabbit, Greptile, Graphite, OpenHands, METR
(arXiv 2507.09089), DORA 2025, GitClear 2025, DX, curl/Bleeping Computer,
ReversingLabs (Amazon Q), Snyk (Nx), The Register (Matplotlib incident),
Simon Willison.
