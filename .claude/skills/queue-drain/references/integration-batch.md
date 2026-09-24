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
