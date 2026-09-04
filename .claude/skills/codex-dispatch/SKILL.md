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

Take only the `codex` skill's model/effort tables, its stdin rule, and
its timeout table. Its interactive rules do **not** apply here — no
`AskUserQuestion` for model choice or follow-ups, no per-flag permission
prompts, no stop-and-ask before retrying, no synchronous-run preference,
and never `resume --last`. The `Tier/Codex` label plus this skill are the
standing authorization for `--full-auto` and `--skip-git-repo-check`.

**Scope guard:** `Tier/Codex` never combines with `Repo/Managed-Platform`
(no worktree/PR flow exists there). If you find that combination,
fix the labels via triage judgment before dispatching.

**Never `env-sync` into a Codex worktree.** Codex has no network, so a
ticket whose acceptance needs live calls or a Doppler `.env` cannot be
finished by Codex at all — that is a mis-tiered ticket (triage
judgment), not a Codex run. A `.env` in the worktree would also be
readable by Codex.

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
   timeout <secs> codex exec -m <model> \
     --config model_reasoning_effort="<effort>" \
     --config sandbox_workspace_write.network_access=false \
     --sandbox workspace-write --full-auto --skip-git-repo-check \
     -C <worktree-path> -o <scratchpad>/codex-<issue-id>.out \
     "<prompt>" </dev/null 2><scratchpad>/codex-<issue-id>.log
   ```

   `<secs>` is `min(effort-table value from the codex skill, remaining
   ticket budget)` — `high` → 600. Run it in the background so parallel
   tickets don't serialize. Exit status 124 means `timeout` killed it:
   that is the timeout lane below, regardless of what the log says.
   `sandbox_workspace_write.network_access=false` pins the no-network
   guarantee on the command line instead of trusting
   `~/.codex/config.toml`; `workspace-write` restricts writes, not
   reads, so Codex can read anything in the worktree.
   When it exits, capture the **session UUID** from the log:

   ```bash
   grep -m1 '^session id:' <scratchpad>/codex-<issue-id>.log \
     | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
   ```

   Anchor on the `session id:` line — the log's `workdir:` line can
   also contain a UUID-shaped path segment, and an unanchored grep
   will pick that one.

   Keep the UUID — the fix round and the Linear trail both need it.
3. **Verify.** `git -C <worktree> log origin/main..HEAD --oneline` must
   show at least one commit, and the repo's own test suite must pass
   when you run it yourself. An empty `-o` output file means Codex was
   killed before finishing — treat as a timeout (failure lane below).
   Before pushing, scan what Codex committed:
   `git -C <worktree> diff origin/main..HEAD --stat` for unexpected
   dotfiles or config, and grep the diff for credential-shaped strings
   (`-iE 'api[_-]?key|secret|token|password|BEGIN (RSA|OPENSSH)'`; use
   the repo's own secret scanner if it has one). Anything suspicious →
   do not push; Blocked with the finding. Claude's push is the only
   path out of the sandbox, so this check is the guard.
4. **Open the PR yourself.** Push from the worktree, then
   `gh pr create --head <gitBranchName>` (the `--head` flag is
   mandatory from inside a worktree), **ready for review**, body
   opening with: "Implementation by OpenAI Codex (`<model>`/`<effort>`,
   session `<uuid>`); coordinated and reviewed by Claude." plus the
   issue id and root-cause/fix summary.
5. **Codex review first.** Before any Claude review, run a **fresh**
   Codex session over the same worktree — never `resume` the
   implementer's UUID; a session re-reading its own work rubber-stamps
   it. Same command shape as step 2, but `--sandbox read-only` in
   place of `workspace-write` (a reviewer that cannot edit) and a
   `.review.out` output file. Prompt: the issue description verbatim,
   then: "Review `git diff origin/main..HEAD` in this worktree for
   correctness against the issue above. Report only correctness
   findings (bugs, missed acceptance criteria, regressions) as
   `file:line — what breaks`, or the single line `no findings`. Do
   not change any file." Post its output on the PR as a comment
   opening "Codex review (session `<uuid>`):" — you post it; Codex
   has no network. If it reports findings, run this stage's fix round
   (step 7), re-verify (step 3), push, and re-run this review once;
   findings still standing after that go to the unresolved lane in
   step 7.
6. **Claude review second — the gate.** Dispatch a fresh reviewer
   subagent using the PR-review template in
   `.claude/skills/queue-drain/references/prompts.md`; it posts its
   verdict with `gh pr review`. Reviewer tier follows queue-drain's
   rule — sonnet by default, opus if the issue carries `Security`;
   `Tier/Codex` itself implies nothing about reviewer tier. The Codex
   review is advisory input that always runs first; Claude's verdict
   is the one that gates the merge.
7. **One fix round per review stage.** If a review reports findings,
   resume Codex **by UUID — never `--last`** (parallel runs would
   cross-resume):

   ```bash
   timeout <secs> codex exec -m <model> --config model_reasoning_effort="<effort>" \
     --config sandbox_workspace_write.network_access=false \
     --sandbox workspace-write --full-auto --skip-git-repo-check \
     -C <worktree-path> -o <scratchpad>/codex-<issue-id>.fix.out resume <uuid> \
     "<review findings, file:line>" </dev/null 2>><scratchpad>/codex-<issue-id>.log
   ```

   Re-pass the same model, effort, sandbox, and worktree — without
   them, Codex may silently resume on a different default model, and
   sandbox/cwd inheritance across resume is not something we rely on.
   An empty `.fix.out` or exit 124 is a timeout, same as the first run.

   Re-verify (step 3), push, and re-run that stage's review once
   more. Each review stage — Codex's (step 5) and Claude's (step 6) —
   gets at most one fix round. If a stage still holds findings after
   its round: comment the unresolved list on the PR, move the Linear
   issue to **Blocked** with the trail — say it is waiting on a human
   to re-tier or re-scope — keep the worktree, stop. There is no
   second fix round for a stage.
8. **Close out.** `save_comment` on the issue: root cause, PR link,
   both review verdicts (Codex review + Claude reviewer), the Codex
   session UUIDs (implementer and reviewer), model/effort actually
   used. Move to In Review; Done only when merged and verified,
   tearing the worktree down in that same step.

## Failure lanes

- **Non-zero exit, no commits, or timeout:** one retry at the same
  settings (fresh session). A second failure → Blocked, waiting on a
  human to re-tier or re-scope, with the last ~20 lines of the log in
  the Linear comment. Honest failure is a valid output — never fake a
  green gate.
- **Budget (PROVISIONAL, never measured):** 30 min wall-clock per
  ticket, max 2 Codex tickets concurrent. The first real run is
  attended: record wall-clock, replace 30 with the measured number,
  and drop the PROVISIONAL mark here and in queue-drain's table.

## Attribution

The PR body line in step 4 and the Linear close-out comment are the
record that Codex authored the change. Keep both accurate — if you
(Claude) end up writing code to rescue a ticket, say so in both places
and consider whether the tier label should change.
