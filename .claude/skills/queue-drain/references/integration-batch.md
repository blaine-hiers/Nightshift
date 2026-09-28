# Integration-batch mode (one PR for many tickets)

Use when the human asks for a whole batch as **one feature branch and one PR**
instead of a PR per ticket. That also resolves the WIP-cap stop rule: the
batch adds one PR to the merge queue, not N. First used on the 2026-09-24
headroom drain (14 feature tickets → one PR).

## Shape

- One integration worktree: `.worktrees/batch` on `dev/<first>-<last>-feature-batch`
  cut from `origin/main`. Only the coordinator commits there, and only merges.
- One worktree and sub-branch per ticket, cut from the **current integration
  branch head**, not from `origin/main`. Later waves then build on what has
  already landed.
- Order waves by file overlap. Tickets that change a shared type or the core
  maths go first; UI-only ones and ones that consume other features (compare,
  export) go last. A ticket that depends on another waits until that one merges.
- Stage 5 runs per ticket as normal. A ticket merges into the integration
  branch with `git merge --no-ff` (one merge commit per issue, so the history
  still reads per feature) only after its review is clean. Run the full suite,
  lint and build after **every** merge, then commit.
- Stage 6: one PR, with a `Fixes #N` line per issue, a table of the pre-merge
  review findings, and the integration decisions. Every issue gets a comment
  and moves to `status/in-review`.

## Rules learned the hard way

- **New state fields are optional, with defaults.** A required field added to
  a shared type (`HardwareSpec.tflopsBf16`, `CalcState.runtime`) breaks every
  sibling branch's test fixtures at merge time. If a required field is
  unavoidable, fix the fixtures in the merge commit.
- **Give siblings a shared contract up front** when two tickets will touch the
  same derived figure. Name the fields and their meaning in both prompts (e.g.
  `fixedBytes` / `bytesPerUser` for "the chart and capacity maths read these").
  Otherwise each ticket invents its own and the merge has to reconcile them.
- **Features that duplicate the whole state must be generic over it.** Compare
  columns and URL encoders nest `encodeState` wholesale, never field lists, so
  fields added later round-trip automatically.
- **Put foundation tickets first, and have them publish contracts.** A ticket that others
  build on (a tab shell, a data catalog) goes in wave 1. Its prompt makes it define the
  file slots, a state sub-slice per downstream ticket, and any handoff callback, and report
  them back. Pass those contracts verbatim into the wave-2 prompts. Parallel tickets then
  touch disjoint files, and they get distinct URL-key prefixes (`pt_*` and `ph*`).
- **A load-a-row action must satisfy `row == calculate(state after load)`.** Anything that
  computes a result for a derived state and then offers to load it ("Use", "Apply")
  diverges as soon as the load path clamps, merges or keeps a stale field. Clamp in one
  shared helper, replace slices whole in the loader, and test through the real reducer,
  not the isolated patch.
- **Hidden-but-mounted panels** (tabs) duplicate accessible labels, which breaks
  `getByLabelText` in tests and confuses screen readers. Tell implementers to use labels
  that are unique across panels. Full-App jsdom suites also need a raised `testTimeout`.
- **Per-ticket reviews cannot see integration bugs.** The stage-6 review of the
  combined PR must probe cross-feature combinations explicitly. On
  2026-09-24 it found 6 bugs no per-ticket review could have (offload × cost,
  × launch command, × capacity, × compare). Budget one fix round on the
  integration branch plus a re-review.
- **Teardown.** Per-issue sub-branches are merged locally and never pushed, so
  `sweep.sh` reports their worktrees as BLOCKED `no-upstream`. Once the batch PR
  merges, confirm each sub-branch is an ancestor of the merged head
  (`git merge-base --is-ancestor dev/<n>-… origin/main`), then run
  `git worktree remove` on each one and delete the branch.
- **Main moves under a long batch.** Before the final review, fetch and merge
  `origin/main` into the integration branch, then rerun the suite and push, so
  the PR stays mergeable.
- Resolve conflicts with a small node script (region → resolution function)
  written to the scratchpad, not with inline shell. Apostrophes in inline
  `node -e '…'` break bash quoting.

## Lessons from the 2026-09-24 lmstudio-automation run (31 tickets, one PR)

- **Keep one living contracts file per batch** in the scratchpad (foundation APIs + "lessons from reviews so far") and have every implementer and reviewer prompt read it first. Append each lesson the moment a review finds a new bug class (per-item isolation, bounded model input, disclosed truncation, safe URLs, cursor rules). Repeats of a bug class dropped sharply after a lesson landed in the file.
- **Put shared prompt boilerplate in files** (`implementer-rules.md`, `reviewer-rules.md` in the scratchpad) and keep each dispatch prompt to the ticket-specific notes. That keeps 60+ dispatches consistent and short.
- **A bug class found in one ticket's review is swept across its siblings straight away.** The day-granularity Gmail cursor bug surfaced in #20's review, but #7, #12 and #13 had the same pattern already merged. Fix it once, centrally (a shared module), on its own integration branch with a review, not ticket by ticket.
- **Budget two integration fix rounds for data-loss-critical shared code.** The whole-branch integration review found 11 cross-feature bugs, and its re-review found more edge cases in the same cursor design. The fix that converged replaced the design with a simpler one (the coordinator's call); patching the old design a third time would not have.
- **Retries count toward the WIP cap.** Sending attempt-2s back while new tickets were in flight pushed concurrency to 7. Hold new dispatches until retries drain.
- **Security, write-path and data-loss tickets need an opus reviewer, and an opus re-review after attempt 2.** Three sonnet tickets (#15, #16, #25) had to be escalated to opus mid-run. Tier such tickets `opus` at filing.
- **The merge script must fail loudly.** A `pytest | tail -1` pipeline masks pytest's exit code; twice a commit or merge went through on red. Use `set -o pipefail`, or check `$?` before `git commit`. Union-resolve append-only files (dependency lists, `.env.example` names) automatically, and resolve everything else by hand.
- **Commit-trailer rules go in the implementer prompt from dispatch one.** Subagents add the harness's default `Co-Authored-By` trailer unless told not to. Stripping it afterwards rewrites history, which then needs a force-push (the permission check blocks that) or a new branch name.
- **Coordinator edits go through the Edit tool, not string replacement in heredoc Python.** Backslash escapes (`\n`, `\D`, `ö`) got mangled three times in this run.

## Lessons from the 2026-09-25 lmstudio-automation run (23 tickets, one PR)

- **Fakes hide missing constructor arguments.** Every test injected a SearXNG fake, so two production call sites that built `SearXNG()` without its required `base_url` passed the suite, and both features were dead in production. The integration review caught it only by running each shipped config with no factory. For every client a sibling constructs, add one test on the real (no-fake) construction path.
- **Check contracts-file claims against the merged code.** `contracts.md` said `SearXNG` defaulted its URL; the merged #51 code didn't. Two later tickets were written against the file, not the code. When a foundation ticket merges, the coordinator copies its signatures from the code into the contracts file, not from the implementer's report.
- **Parallel store tables go in named migrations** (`dict name -> idempotent SQL`), never numbered ones, so siblings don't race for a number. Their merge conflicts are mechanical: a small resolver that closes the first entry's string and drops the markers. Never run the text-union resolver on code: it silently dropped a closing `"""` once.
- **Reviewers never launch real task runs.** A reviewer probing a dashboard `POST /api/run` really ran a task, which may send alerts or start local servers. Say so in every reviewer prompt: test fakes and throwaway scripts only.
- **Keep drain state in files, so a pause or `/compact` costs nothing.** The owner paused the run overnight. The contracts file, rules files, and coordinator log let a compacted session restart the three stopped agents with the same prompts and no rediscovery. Log `PAUSED` and `RESUMED` lines. On pause, check each stopped worktree for uncommitted work before restarting.
