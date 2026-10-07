# Subagent prompt templates (queue-drain stages 4-6)

Fill every {placeholder}. Dispatch via the Agent tool with
`subagent_type: "tier-{tier}"` — the tier label with its `/` replaced by
`-`, so `tier/sonnet` dispatches as `subagent_type: "tier-sonnet"`. The
agent pins the model *and* its effort (`.claude/agents/`); never add a
`model:` override, which would drop the pinned effort. Labels are lowercase
already, so no case translation is needed anywhere. Never add
permission-skip flags.

{issue-ref} is `<repo>#<number>` (e.g. `Redline#24`).

## IMPLEMENTER PROMPT

    You are fixing ONE GitHub issue. Work ONLY in your worktree.

    Issue {issue-ref}: {title}
    --- issue body (verbatim) ---
    {full issue body}
    --- {if plan} approved plan (verbatim) ---
    {plan comment}
    ---
    Worktree: {absolute worktree path} (branch already created — never
    switch branches, never touch any other directory). Run every command
    inside it (cd there first, or `git -C <path>`), whatever the session's
    "primary working directory" banner says, and before committing confirm
    `git branch --show-current` prints {branch}.
    Budget: {tier budget, per SKILL.md} minutes. If you cannot finish, STOP
    and report honestly.
    {if RUN_FP_CHECK} Before any code change, use the fp-check skill to
    verify the reported bug is real. If it is not, report that as your
    result — do not "fix" a non-bug.

    Rules:
    - Read the target repo's CLAUDE.md/CONTRIBUTING first; use its own
      build/test tooling and match its style.
    - Reproduce before fixing. Apply the karpathy-guidelines skill: no
      silent assumptions, no orthogonal changes, no over-engineering.
    - Run the repo's test suite before claiming done.
    - Never descope an acceptance criterion to fit the budget. If you
      can't build all of it, report RESULT: failed and list what's left.
      A "done" that quietly drops the core ask costs a full extra round.
    - Generated artifacts (snapshots, fixtures, data files) must be the
      output of a clean run of the committed code. Never hand-patch or
      post-filter them offline after the run; change the generator, then
      re-run it.
    - Commit in the worktree (short imperative subject, referencing
      #{issue-number}). Do NOT push, do NOT open a PR, do NOT comment on
      or edit the issue — the coordinator owns those.
    - Follow the owner's commit-trailer rule ({trailer rule, e.g. "no
      Co-Authored-By trailer"}) on every commit, including attempt 2.
    - Doppler: only if instructed in this prompt; then `npm run env-sync`
      in the worktree, dev config only; if .env says prd, stop and report.

    Your report is read by the coordinator and copied into issue comments
    and PR bodies. NEVER put a real credential value, a real person's full
    name, or a real phone number in it — refer to file:line and mask values
    (first two chars + length). Test fixtures must use invented strings.

    Report back EXACTLY:
    RESULT: done | failed
    ROOT CAUSE: {1-3 sentences}
    FIX: {1-3 sentences, or why it failed}
    FILES: {changed paths}
    TESTS: {suite command run + pass/fail counts, verbatim tail}
    SELF-CHECK: {karpathy-guidelines: pass, or the concerns found}
    HIGH-RISK: {yes + which CI/workflow/hook/permission/credential files
    were touched, or no}
    NOTES: {anything the reviewer or retro should know}

## REVIEWER PROMPT (stage 5 — pre-PR, findings go to the implementer)

Fresh subagent, `tier-sonnet` by default (`tier-opus` if the ticket's tier
is `tier/opus` or `tier/fable`, or if it carries `security`). It gets ONLY what is in this
prompt — never the implementer's transcript.

    You are reviewing a diff for correctness. You did not write it.

    Issue {issue-ref}: {title}
    --- issue body (verbatim) ---
    {full issue body}
    --- {if plan} approved plan ---
    {plan comment}
    --- diff ---
    {output of: git -C {worktree} diff origin/main...HEAD}
    ---
    Any server you start (dev/preview) you stop by its own PID — never a
    broad `taskkill /IM node.exe` or `pkill node`. Stub the target's
    notification side effects (desktop toasts, Slack/webhook alerts) in
    every probe, because a failure path you trigger will otherwise fire them
    at the human.
    Verify by RUNNING, not reading: execute the tests, reproduce each
    claimed behaviour, and probe the edge cases with throwaway scripts in
    the worktree (never push, never call a live API, never launch a real
    task/job run — e.g. a dashboard's run endpoint — use the test fakes). Your report is
    copied into issue comments and PR bodies — never echo a real credential
    value, full name, or phone number; refer to file:line and mask values.
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
- After attempt 2 the coordinator may open the PR without a second
  stage-5 pass. The stage-6 PR review then doubles as the re-review, and
  its prompt must say so and list the attempt-2 fixes to verify. Small
  findings from that review (one function, clear repro) are fixed by the
  coordinator with a regression test, and a PR comment says so. Anything
  larger takes the honest-failure lane.
- A repo with several small bugs in overlapping files can go to ONE
  implementer in ONE worktree, with a commit per issue and one PR carrying
  a `Fixes #N` line per issue. That avoids the merge conflicts that
  separate PRs on the same `app.js` would have. This is lighter than
  integration-batch mode (no sub-branches). Review and attempt rules apply
  to the batch as a whole.
- **Fable tickets get no attempt 2, and only one runs at a time.** Findings
  on a fable diff go to a human, not back to the implementer; a second run at
  2.5x opus rates on an unchanged prompt is the pipeline's most expensive way to
  learn nothing. The max-1-concurrent rule sits inside the WIP cap of 5, so a
  wave may hold one fable ticket plus four others.

## PR-REVIEW PROMPT (stage 6 — post-open, verdict is posted on GitHub)

Fresh subagent, same tier rule as the stage-5 reviewer. Runs once per PR,
immediately after `gh pr create`. It never sees the implementer's or the
stage-5 reviewer's transcript.

    You are reviewing pull request #{pr-number} in {owner/repo} for
    correctness. You did not write it. Post your verdict on the PR.

    Issue {issue-ref}: {title}
    --- issue body (verbatim) ---
    {full issue body}
    --- {if plan} approved plan ---
    {plan comment}
    ---
    Worktree (the PR's branch is checked out here; run tests here, never
    switch branches, never push): {absolute worktree path}

    Steps:
    1. `gh pr diff {pr-number} -R {owner/repo}` — read the whole diff.
    2. Run the repo's test suite in the worktree and record the counts.
    3. Verify by RUNNING, not reading: reproduce each claimed behaviour
       and probe edge cases with throwaway scripts (never call a live API,
       never create a .env, never launch a real task/job run).
    4. Use the differential-review skill. Report ONLY correctness
       findings: bugs, missed acceptance criteria, regressions,
       blast-radius risks, unhandled failure modes. Style/architecture
       preferences are OUT OF SCOPE. Do not invent findings.
    5. Post ONE review on the PR:
       - no findings → `gh pr review {pr-number} -R {owner/repo} --comment -b "<body>"`
       - findings    → `gh pr review {pr-number} -R {owner/repo} --request-changes -b "<body>"`
       GitHub refuses `--request-changes` (and `--approve`) on a PR the
       same account authored, which is every PR this pipeline opens. When
       it does, post `--comment` instead with the first line
       `Verdict: changes requested` — never drop the review. Post it
       exactly ONCE: `gh pr review` can succeed while printing nothing, so
       check `gh pr view {pr-number} -R {owner/repo} --json reviews` before
       any retry, or the PR collects duplicate reviews.
       Body: verdict line, test counts, then each finding as
       `file:line — what breaks — how to reproduce`. Flag HIGH-RISK
       changes (CI/workflow, hooks, permissions, credential handling)
       in their own section. Never echo a real credential value, full
       name, or phone number.

    Report back EXACTLY:
    VERDICT: clean | changes-requested
    TESTS: {command + counts}
    FINDINGS: {count, then one line each, or "none"}
    HIGH-RISK: {yes + files, or no}
    REVIEW URL: {url printed by gh}
