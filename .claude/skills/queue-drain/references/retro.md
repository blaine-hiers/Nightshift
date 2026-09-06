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

Bloated instructions cause agents to ignore instructions.

Systemic root cause? → file a variant-analysis follow-up issue in the repo
it applies to (`gh issue create`); do not expand scope.

## 2. Pipeline friction?
Anything queue-drain itself got wrong → edit this skill's files, commit.

## 3. Nothing to capture?
Allowed — but write "none — reviewed" in the report. Never skip silently.

## Run report — write to docs/runs/YYYY-MM-DD-drain.md and commit

    # Drain YYYY-MM-DD
    ## Tickets
    | Issue | Class | Tier | Outcome | Cycle time | Attempts |
    |---|---|---|---|---|---|
    (Issue as <repo>#<n>. Outcome: PR #N / needs-info / blocked / failed-honestly / parked / decomposed / out-of-scope / deferred-to-wave-N)
    ## Off-ramped this run   <- what a human has to unstick
    | Issue | Status | Waiting on | Owner |
    |---|---|---|---|
    (every ticket this run moved to status/needs-input or status/blocked; "none" if none)
    ## PRs awaiting merge   <- the human's worklist
    - [HIGH-RISK first, marked] ...
    ## Metrics
    - Escalation rate: {tickets whose `tier/` label was overridden up, at
      triage or mid-run} / {total} (>20% = retune tiering, and the
      rewritten labels are the evidence for how)
    - Label hygiene: {tickets whose tier this run had to derive — the `*`
      marks in the triage table} / {tickets fetched} (a rising number means
      tickets are reaching todo untriaged)
    - Misfiled rate: {issues this run transferred to another repo — the `→`
      marks in the triage table} / {tickets fetched} (a rising number means
      issues are being opened from the wrong repo's context)
    - Todo hygiene: {tickets off-ramped at triage} / {tickets fetched}
      (>30% = tickets are being filed into todo before they're workable)
    - Wall-clock by tier: {tier: actual minutes, per ticket} (the budgets in
      SKILL.md are tuned from this, not argued — fable's is uncalibrated until
      an attended run fills it in)
    - WIP-cap hits: {waves needed}
    - Prior-run PRs merged/reverted since last drain: {check gh}
    ## Skills
    - Captured: ... / "none — reviewed"
    - Retired/updated: ...
    ## Worktrees left standing
    - {path}: {reason} — mark HOLDS CREDENTIALS where `npm run env-sync` was run in that worktree
    - a tree kept for a `status/blocked` issue is expected, not a leak — label it so, and flag it if it holds credentials and the block is open-ended
    ## Gate-erosion check
    - Plan batch size this run: N (>5 = split next time)

Commit message: "Drain YYYY-MM-DD: {X} PRs, {Y} needs-info, {Z} failed".
