# Triage rules (queue-drain stage 2)

For every `status/todo` issue, `gh issue view <n> -R blaine-hiers/<repo>
--json number,title,body,labels,comments,url,projectItems` (full body +
comments + labels + project), then answer four questions IN ORDER:

## 1. Can we locate the work?
**The repo the issue lives in is the repo the fix lands in.** That is the
whole benefit of tracking in GitHub Issues — there is no separate repo field to
read, derive, or write back, and no way for it to drift out of sync with
reality. Stage 1 fetched the issue from a specific repo; that repo is the
answer.

Two cases still need a judgment:

**The issue is filed in the wrong repo.** The body plainly describes work
in another repo. Don't relabel — **transfer** it, which preserves the
number's redirect and the comment history:

```bash
gh issue transfer <n> -R blaine-hiers/<from-repo> blaine-hiers/<to-repo>
```

Then treat it as belonging to the new repo for the rest of this run, and
note the transfer in the triage table. Transfer only within `blaine-hiers`
and only when the correct repo is unambiguous; if you are guessing, that is
**needs-info** instead.

**The work spans two repos.** Being filed in one repo names where the
*primary* fix lands, not the full blast radius — read the body for the
multi-repo case (a pipeline fix in one repo plus a content backfill in
another is the shape). One issue location does not mean one repo of work.
When the second repo's part is substantial, file it as its own issue there
and link the two; when it's a one-line follow-on, note it in the plan.

**`managed-platform` issues** (filed in `blaine-hiers/Nightshift`) are the
`.builder` managed-platform install, **not** a git repo — there is no clone
to worktree, and stage 4 would fail on one. Classify those
**out-of-scope**: no status change, no comment, but list them in the triage
table so the human sees they were seen and skipped.

## 2. Actionable without the original conversation?
The Nightshift standard: the body is the prompt. Missing repro steps,
undefined acceptance criteria, or an ambiguous ask → **needs-info**.
Post this comment via `gh issue comment` (fill the blanks, keep it short):

> Triage (queue-drain): this ticket needs more detail before an agent can
> work it. Missing: [exact list — e.g. repro steps / expected vs actual /
> acceptance criteria]. Once the body covers that, move it back to
> **status/todo** and the next drain picks it up.

Then swap the status label to **`status/needs-input`** and skip it this run:

```bash
gh issue edit <n> -R blaine-hiers/<repo> \
  --remove-label status/todo --add-label status/needs-input
```

Leaving it in todo re-triages the same ticket and re-posts the same
comment on every future drain — the move is what makes the comment a
question asked once.

## 3. Stalled on something outside the loop?
The ask is clear and workable, but no agent can finish it right now — a
missing credential or environment, a vendor-side bug, a decision only a
human can make, or a dependency on another issue that isn't closed yet
→ **blocked**. Comment what is being waited on and who owns it, swap the
status label to **`status/blocked`**, and skip it.

Blocked is for *external* dependencies. If the ticket is merely
underspecified, that's needs-info (question 2) — the difference is
whether editing the body would unstick it.

**fp-check case:** ask is clear but the premise is doubtful (a reported
bug that may not be real) → classify **ready**, and add
`RUN_FP_CHECK: yes` to its dispatch note so the implementer runs the
fp-check skill before touching code.

## 4. Needs design first?
→ **needs-plan** if ANY of: `feature` label; `security` label; the work
touches more than one repo; unclear root cause with cross-cutting blast
radius; concurrency or data-loss reasoning; goal clear but approach
genuinely open.
→ **decompose** if it is too big for a half-page plan — the planner will
propose child issues instead of a plan.
Otherwise → **ready**.

## Tier assignment (ready and needs-plan tickets)
**Read the issue's `tier/…` label first. If it is set, that is the tier —
do not re-derive it.** The label exists so this judgment is made once and
stays reviewable across runs instead of being re-litigated by every drain.

Derive a tier only when the label is absent, using the table below
(Nightshift CLAUDE.md, verbatim — default DOWN, not up), then write it
back. needs-plan tickets get a tier too — plan-gate.md's planning-subagent
dispatch rule reads it to pick sonnet vs opus. needs-info, blocked,
decompose, and out-of-scope tickets get "—" (no tier, no label write):

| Tier | Use for |
|---|---|
| `tier/haiku` | Mechanical, well-specified tickets: doc/comment drift, rename, add a missing guard, one-line regex or flag fix, status/label bookkeeping. |
| `tier/sonnet` | Ordinary bugfixes: reproduce, trace a few files, patch, run tests. This is the normal default for a well-written ticket. |
| `tier/opus` | Only when needed: unclear root cause, cross-cutting refactor, concurrency/data-loss/security reasoning, or after a lower tier has failed. |
| `tier/fable` | The hardest long-horizon agentic work, or opus already failed. 2x opus cost, and its turns run long — never assign it at triage without saying why in the table. |
| `tier/codex` | Route to the OpenAI Codex CLI as implementer (codex-dispatch skill). Assign only when the user asked for Codex on this work or the issue body requests it — never derive it as a cost/difficulty judgment, and never on a `managed-platform` issue. Optionally record `codex: <model>/<effort>` in the body; default is gpt-5.6-terra/high. |

**Overriding a label.** Only when it is plainly wrong for the ticket as
written. Say so in the triage table (`opus (was sonnet)`) and update the
label — an override you don't write back is an opinion the next drain
never sees. Same rule if a tier proves too low *during* stage 4:
escalating the model without rewriting the label leaves the next run to
rediscover the same failure.

## Writing labels back
`gh issue edit` takes deltas, not a replacement set — `--add-label` and
`--remove-label` touch only what you name, so there is no way to silently
drop a label you forgot to re-list. Both flags accept comma-separated
values, and the two exclusive groups (`status/…`, `tier/…`) are swapped
rather than added:

```bash
gh issue edit 24 -R blaine-hiers/Redline \
  --remove-label status/todo --add-label status/in-progress,tier/sonnet,bug
```

Label names are lowercase and are used verbatim — `tier/sonnet` becomes an
`Agent` `model:` string by stripping the prefix (`model: "sonnet"`), with
no case translation anywhere. `tier/codex` is a valid tier; it maps to the
codex-dispatch skill, not to an `Agent` `model:` string.

**A label that doesn't exist yet fails the edit** rather than being created
silently. Create it once per repo, then apply it:

```bash
gh label create tier/sonnet -R blaine-hiers/<repo> -c "1D76DB" \
  -d "Model tier: sonnet"
```

Read the current set from this stage's own `gh issue view` — never build a
label edit from memory, and never write labels for a ticket you did not
just read.

## Output
Show the human this table, then proceed (sanity scan, not a gate):

| Issue | Title | Class | Tier | Repo | Moved to |
|---|---|---|---|---|---|
| repo#N | … | ready / needs-plan / needs-info / blocked / decompose / out-of-scope | haiku/sonnet/opus/fable/codex/— | … | status/needs-input / status/blocked / — |

The **Moved to** column is the audit trail for every status write this
stage made. `—` for tickets left in `status/todo`.

Mark any Tier this stage **derived and wrote** with a trailing `*`
(`sonnet*`), and any issue this stage **transferred** with a trailing `→`
in the Repo column (`Redline →`). Those columns are then the audit trail
for the label and transfer writes, the way **Moved to** is for the status
writes — and a table full of `*` is the signal that tickets are reaching
todo untriaged, which is worth a line in the retro.

## Re-entry from the off-ramps
Fetch (stage 1) reads `status/todo` only, so `status/needs-input` and
`status/blocked` tickets are invisible to the next drain until a human
moves them back. That is the point — do not sweep them back into todo
yourself, and do not widen the stage-1 fetch to include them.
