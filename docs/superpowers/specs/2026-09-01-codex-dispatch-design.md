# Codex Dispatch — Design

**Date:** 2026-09-01
**Status:** Approved
**Depends on:** the vetted third-party `codex` skill (`.claude/skills/codex/`, from skills-directory/skill-codex) for CLI mechanics; the existing queue-drain pipeline (`docs/superpowers/specs/2026-08-20-queue-drain-pipeline-design.md`).

## Goal

Let OpenAI Codex take the **implementer** seat for selected GitHub issues while
Claude keeps the **coordinator** and **reviewer** seats. Codex writes the code
and commits; Claude owns every issue write, worktree operation, push, PR
creation, and PR review. One review-feedback round goes back to Codex, then the
lane ends honestly.

Decisions locked with the user:

- **Routing:** a `tier/codex` label, not Codex-by-default and not
  conversation-only.
- **Sandboxing:** Codex runs `--sandbox workspace-write`; it never gets
  network. Claude performs the push and `gh pr create` (the PR body credits
  Codex as author).
- **Model/effort:** triage picks per issue; default `gpt-5.6-terra` at `high`.
- **Review loop:** exactly one Codex fix round after Claude's review, then stop.

## 1. Routing

- Add **`tier/codex`** to the exclusive `tier/` label set. An issue
  carrying it is implemented by Codex instead of a Claude subagent, in both
  hand-dispatch and `/queue-drain`. All other tiers behave exactly as today.
- Triage may record a model/effort override as a one-line
  `codex: <model>/<effort>` note in the issue description. Absent that, the
  default is `gpt-5.6-terra` / `high`.
- Valid models/efforts and their compatibility rules come from the `codex`
  skill (e.g. `max`/`ultra` only on GPT-5.6 models); codex-dispatch defers to
  it rather than duplicating the table.

## 2. Per-issue flow (`.claude/skills/codex-dispatch/SKILL.md`)

Claude is coordinator throughout. Codex only ever writes code inside the
worktree.

1. **Pick up.** `gh issue view`, set status/in-progress, create the worktree from the base
   clone using the derived `dev/<n>-<slug>` branch name — unchanged from the standard flow
   (`docs/workspace.md`).
2. **Run Codex.** Compose the prompt from the issue body verbatim plus
   a pointer to the target repo's conventions (its CLAUDE.md / CONTRIBUTING /
   README) and the instruction to implement, run the repo's own test suite, and
   **commit** the work. Then, with the worktree as the working directory:

   ```
   codex exec -m <model> \
     --config model_reasoning_effort="<effort>" \
     --sandbox workspace-write --full-auto --skip-git-repo-check \
     -C <worktree> -o <final-msg-file> \
     "<prompt>" </dev/null 2><log-file>
   ```

   - `</dev/null` is mandatory (codex blocks forever on open stdin).
   - Timeout per the codex skill's effort table (`high` → 600 s); run in
     background so parallel tickets don't serialize.
   - Capture the **session UUID** from the stderr log file; it is required for
     the fix round and recorded on the issue.
3. **Verify and open the PR.** Claude checks the worktree has new commits and
   the repo's test suite passes. Then Claude pushes the branch and runs
   `gh pr create` — ready for review, body opening with: "Implementation by
   OpenAI Codex (`<model>`/`<effort>`, session `<uuid>`); coordinated and
   reviewed by Claude", plus `Fixes #<n>`.
4. **Review.** Claude dispatches the same fresh reviewer subagent as today
   (PR-review template in `.claude/skills/queue-drain/references/prompts.md`),
   which posts its verdict via `gh pr review`.
5. **One fix round.** If the review requests changes:

   ```
   codex exec --skip-git-repo-check resume <uuid> "<review findings>" \
     </dev/null 2>><log-file>
   ```

   Resume **by session UUID, never `--last`** — `--last` is parallel-unsafe
   when multiple Codex tickets run concurrently. Re-verify tests, push, and
   have the reviewer re-review once. If issues remain, comment the unresolved
   findings on the PR, move the GitHub issue to **`status/blocked`** with the trail, and
   stop. No further rounds.
6. **Close out.** Unchanged from the standard flow: issue comment with root
   cause, PR link, Codex session ID, and model/effort; `status/in-review`, closed when
   merged and verified; worktree teardown at close, by the coordinator.

## 3. Queue-drain and docs wiring

Small edits only:

- **queue-drain SKILL.md** fan-out stage gains a `codex` tier row:
  dispatch via codex-dispatch; budget **30 min wall-clock, 1 fix round, max 2
  concurrent** — provisional like fable's, revisit after a real run.
- **queue-drain triage reference** notes `tier/codex` as a valid triage
  outcome and the `codex: <model>/<effort>` description convention.
- **CLAUDE.md** tier table gains the Codex row (and the note that
  `tier/codex` routes to codex-dispatch, not to an `Agent` model string).
- **docs/skills.md** gets a first-party entry for codex-dispatch.
- **Labels:** `gh label create tier/codex` in each target repo that needs it.

## 4. Failure handling

- **Codex exits non-zero, produces no commits, or times out:** one retry at
  the same settings, then `status/blocked` with a log excerpt in the issue comment —
  mirrors the existing honest-failure lane.
- **Empty `-o` output file:** codex was killed before finishing (known
  behavior — it writes output only at completion); treat as a timeout.
- **`codex` CLI missing or unauthenticated:** a pre-flight check
  (`codex --version` plus `codex login status`, or the nearest equivalent this
  CLI version supports) at dispatch start fails the whole run loudly, rather
  than failing per-ticket.
- **`managed-platform` issues** are out of scope for `tier/codex` (no
  worktree/PR flow exists for them); triage must not combine the two.

## Out of scope

- Codex running with network access (`danger-full-access`) — rejected for
  credential-exposure reasons.
- More than one review→fix round.
- Any change to non-Codex tiers, the WIP cap, or the plan gate.
