# Subagent prompt templates (queue-drain stages 4-5)

Fill every {placeholder}. Dispatch via the Agent tool with `model: "{tier}"`
— **the lowercase model id, not the Linear label**. Linear capitalizes label
names, so `Tier/Sonnet` dispatches as `model: "sonnet"`; passing `"Sonnet"`
fails the enum. Never add permission-skip flags.

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
    - Commit in the worktree (short imperative subject). Do NOT push, do
      NOT open a PR, do NOT touch Linear — the coordinator owns those.
    - Doppler: only if instructed in this prompt; then `npm run env-sync`
      in the worktree, dev config only; if .env says prd, stop and report.

    Your report is read by the coordinator and copied into Linear and PR
    bodies. NEVER put a real credential value, a real person's full name,
    or a real phone number in it — refer to file:line and mask values
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

Fresh subagent, sonnet by default (opus if the ticket's tier is `Tier/Opus`
or `Tier/Fable`, or if it carries `Security`). It gets ONLY what is in this prompt — never
the implementer's transcript.

    You are reviewing a diff for correctness. You did not write it.

    Issue {issue-id}: {title}
    --- description (verbatim) ---
    {full Linear description}
    --- {if plan} approved plan ---
    {plan comment}
    --- diff ---
    {output of: git -C {worktree} diff origin/main...HEAD}
    ---
    Verify by RUNNING, not reading: execute the tests, reproduce each
    claimed behaviour, and probe the edge cases with throwaway scripts in
    the worktree (never push, never call a live API). Your report is
    copied into Linear and PR bodies — never echo a real credential value,
    full name, or phone number; refer to file:line and mask values.
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
- **Fable tickets get no attempt 2, and only one runs at a time.** Findings
  on a fable diff go to a human, not back to the implementer; a second run at
  2x opus rates on an unchanged prompt is the pipeline's most expensive way to
  learn nothing. The max-1-concurrent rule sits inside the WIP cap of 5, so a
  wave may hold one fable ticket plus four others.

## PR-REVIEW PROMPT (stage 6 — post-open, verdict is posted on GitHub)

Fresh subagent, same tier rule as the stage-5 reviewer. Runs once per PR,
immediately after `gh pr create`. It never sees the implementer's or the
stage-5 reviewer's transcript.

    You are reviewing pull request #{pr-number} in {org/repo} for
    correctness. You did not write it. Post your verdict on the PR.

    Issue {issue-id}: {title}
    --- description (verbatim) ---
    {full Linear description}
    --- {if plan} approved plan ---
    {plan comment}
    ---
    Worktree (the PR's branch is checked out here; run tests here, never
    switch branches, never push): {absolute worktree path}

    Steps:
    1. `gh pr diff {pr-number} -R {org/repo}` — read the whole diff.
    2. Run the repo's test suite in the worktree and record the counts.
    3. Verify by RUNNING, not reading: reproduce each claimed behaviour
       and probe edge cases with throwaway scripts (never call a live API,
       never create a .env).
    4. Use the differential-review skill. Report ONLY correctness
       findings: bugs, missed acceptance criteria, regressions,
       blast-radius risks, unhandled failure modes. Style/architecture
       preferences are OUT OF SCOPE. Do not invent findings.
    5. Post ONE review on the PR:
       - no findings → `gh pr review {pr-number} -R {org/repo} --comment -b "<body>"`
       - findings    → `gh pr review {pr-number} -R {org/repo} --request-changes -b "<body>"`
       GitHub refuses `--request-changes` (and `--approve`) on a PR the
       same account authored, which is every PR this pipeline opens. When
       it does, post `--comment` instead with the first line
       `Verdict: changes requested` — never drop the review.
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
