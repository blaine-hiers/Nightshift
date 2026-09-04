# Triage rules (queue-drain stage 2)

For every Todo issue, `get_issue` (full description + comments + labels +
project), then answer four questions IN ORDER:

## 1. Can we locate the work?
Read the issue's `Repo/…` label first — it is the answer, and it is
mutually exclusive. Only when it is absent do you derive the target repo
from the Linear project, an explicit repo name in the description, or an
unambiguous match to a clone in `workspace/` — and when you do, write the
label back (see *Writing labels back*). Cannot resolve either way →
**needs-info**.

Do not infer the repo from the project: the Nimbus project spans
`api-server` (worker and triage code) and `knowledge-base` (article
content), and several issues have no project at all.

**A repo with no label yet is not a needs-info.** When the work resolves
to a real repo that has no `Repo/` child — a new target repo, or one
getting its first issue — create the child and apply it:
`create_issue_label` with `parent: "Repo"` and no `teamId`, so it lands
workspace-level like its siblings. Then label the issue as usual.

Confirm the repo is real before minting the label: it exists in the
GitHub org, or there is a clone in `workspace/`. Never create one from a
guessed or misspelled name — the group is exclusive, so a typo'd child
silently splits one repo's issues into two buckets that no filter
reconciles, and there is no update call to rename it afterward.

`Repo/` is the only dimension that grows. `Tier/` is closed at five
values and the type labels at three; a ticket that seems to need a new
one of those needs a triage judgment, not a new label.

`Repo/Managed-Platform` is the `.builder` managed-platform install, **not** a git
repo — there is no clone to worktree, and stage 4 would fail on it.
Classify those **out-of-scope**: no status change, no comment, but list
them in the triage table so the human sees they were seen and skipped.

## 2. Actionable without the original conversation?
The Foreman standard: the description is the prompt. Missing repro
steps, undefined acceptance criteria, or an ambiguous ask → **needs-info**.
Post this comment via `save_comment` (fill the blanks, keep it short):

> Triage (queue-drain): this ticket needs more detail before an agent can
> work it. Missing: [exact list — e.g. repro steps / expected vs actual /
> target repo / acceptance criteria]. Once the description covers that,
> move it back to **Todo** and the next drain picks it up.

Then `save_issue` the status to **Needs Input** and skip it this run.
Leaving it in Todo re-triages the same ticket and re-posts the same
comment on every future drain — the move is what makes the comment a
question asked once.

## 3. Stalled on something outside the loop?
The ask is clear and workable, but no agent can finish it right now — a
missing credential or environment, a vendor-side bug, a decision only a
human can make, or a dependency on another issue that isn't Done yet
→ **blocked**. `save_comment` what is being waited on and who owns it,
`save_issue` the status to **Blocked**, and skip it.

Blocked is for *external* dependencies. If the ticket is merely
underspecified, that's needs-info (question 2) — the difference is
whether editing the description would unstick it.

**fp-check case:** ask is clear but the premise is doubtful (a reported
bug that may not be real) → classify **ready**, and add
`RUN_FP_CHECK: yes` to its dispatch note so the implementer runs the
fp-check skill before touching code.

## 4. Needs design first?
→ **needs-plan** if ANY of: `Feature` label; `Security` label; the work
touches more than one repo; unclear root cause with cross-cutting blast
radius; concurrency or data-loss reasoning; goal clear but approach
genuinely open.
→ **decompose** if it is too big for a half-page plan — the planner will
propose child issues instead of a plan.
Otherwise → **ready**.

The `Repo/` label is exclusive, so it names where the *fix* lands, not
the full blast radius — read the description for the multi-repo case
(ENG-10 is the shape: a pipeline fix in `api-server` plus a content
backfill in `knowledge-base`). One label does not mean one repo of work.

## Tier assignment (ready and needs-plan tickets)
**Read the issue's `Tier/…` label first. If it is set, that is the tier —
do not re-derive it.** The label exists so this judgment is made once and
stays reviewable across runs instead of being re-litigated by every drain.

Derive a tier only when the label is absent, using the table below
(Foreman CLAUDE.md, verbatim — default DOWN, not up), then write it
back. needs-plan tickets get a tier too — plan-gate.md's planning-subagent
dispatch rule reads it to pick sonnet vs opus. needs-info, blocked,
decompose, and out-of-scope tickets get "—" (no tier, no label write):

| Tier | Use for |
|---|---|
| Haiku | Mechanical, well-specified tickets: doc/comment drift, rename, add a missing guard, one-line regex or flag fix, status/label bookkeeping. |
| Sonnet | Ordinary bugfixes: reproduce, trace a few files, patch, run tests. This is the normal default for a well-written ticket. |
| Opus | Only when needed: unclear root cause, cross-cutting refactor, concurrency/data-loss/security reasoning, or after a lower tier has failed. |
| Fable | The hardest long-horizon agentic work, or opus already failed. 2x opus cost, and its turns run long — never assign it at triage without saying why in the table. |
| Codex | Route to the OpenAI Codex CLI as implementer (codex-dispatch skill). Assign only when the user asked for Codex on this work or the issue description requests it — never derive it as a cost/difficulty judgment, and never on `Repo/Managed-Platform`. Optionally record `codex: <model>/<effort>` in the description; default is gpt-5.6-terra/high. |

**Overriding a label.** Only when it is plainly wrong for the ticket as
written. Say so in the triage table (`Opus (was Sonnet)`) and update the
label — an override you don't write back is an opinion the next drain
never sees. Same rule if a tier proves too low *during* stage 4:
escalating the model without rewriting the label leaves the next run to
rediscover the same failure.

## Writing labels back
`save_issue`'s `labels` field **replaces the entire set** — anything you
omit is removed. Always pass the complete array: the type label, the
`Repo/` child, the `Tier/` child, and `Security` if the issue carries it.

    labels: ["Bug", "api-server", "Sonnet"]   # complete set, not a delta

Pass the child label's own name (`api-server`, `Sonnet`), not the
`Repo/api-server` display path. Linear capitalizes label names on
creation, so they read `Sonnet` / `docs-site` / `Managed-Platform` even
where the underlying repo is lowercase. Matching is case-insensitive, so a
lowercase write still lands — but write them as they display, and never
reuse a label name as an `Agent` `model:` string (that takes the lowercase
model id: `Tier/Sonnet` → `model: "sonnet"`). `Codex` is a
valid `Tier/` child; it maps to the codex-dispatch skill, not to an
`Agent` `model:` string. The current set comes from this stage's
own `get_issue` — never build the array from memory, and never write
labels for a ticket you did not just read.

## Output
Show the human this table, then proceed (sanity scan, not a gate):

| Issue | Title | Class | Tier | Repo | Moved to |
|---|---|---|---|---|---|
| ENG-N | … | ready / needs-plan / needs-info / blocked / decompose / out-of-scope | haiku/sonnet/opus/fable/codex/— | … | Needs Input / Blocked / — |

The **Moved to** column is the audit trail for every status write this
stage made. `—` for tickets left in Todo.

Mark any Tier or Repo value this stage **derived and wrote** with a
trailing `*` (`sonnet*`). Those two columns are then the audit trail for
the label writes, the way **Moved to** is for the status writes — and a
table full of `*` is the signal that tickets are reaching Todo untriaged,
which is worth a line in the retro.

## Re-entry from the off-ramps
Fetch (stage 1) reads Todo only, so `Needs Input` and `Blocked` tickets
are invisible to the next drain until a human moves them back. That is
the point — do not sweep them back into Todo yourself, and do not widen
the stage-1 fetch to include them.
