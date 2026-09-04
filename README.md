# Foreman

Foreman is not a software project. It is the working environment for doing
tracked engineering work **in other repositories**: one command turns a queue
of ready tickets into reviewed pull requests, with the tracker as the system
of record throughout.

The repo tracks the workflow, never the code being worked on. Target repos are
cloned into a gitignored `workspace/`, and each issue gets its own worktree.

## The pipeline

`queue-drain` runs the batch end to end:

```
sweep -> fetch queue -> triage -> batched plan approval -> capped fan-out (5)
      -> fresh-context verify -> ready PRs + auto-review -> close -> retro
```

Two properties make it safe to leave running:

- **The plan gate is batched.** Every ticket's plan is approved in one pass
  before any of them start, so a bad batch is stopped once rather than five
  times.
- **Verification uses fresh context.** The agent that checks the work is not
  the agent that did it. A model that has just argued itself into a fix is the
  worst possible reviewer of that fix.

## Queue invariants

The status model exists to keep the queue drainable, and one rule carries it:

> **`Todo` means an agent can start right now with zero questions.**

Anything that would make an agent stop and ask belongs in `Needs Input`
instead. Anything stalled on something outside the agent loop, a vendor, a
credential, a human decision, belongs in `Blocked`.

Never leave a stalled ticket in `Todo` or `In Progress`. `In Progress` with
nobody working it makes "what is active" meaningless, and `Todo` re-queues it
into the next drain, which burns a fresh agent rediscovering the same blocker.
Both off-ramps require a comment naming what is being waited on and who owns
it, or the status is just a shrug.

## Model tiers

Every ticket carries a tier label, set once at triage so the drain reads a
decision instead of re-deriving one. The rule is to **default down, not up**:

| Tier | Use for |
|---|---|
| `haiku` | Mechanical, well-specified tickets: doc drift, renames, a missing guard, a one-line fix. |
| `sonnet` | Ordinary bugfixes: reproduce, trace, patch, run tests. The normal default. |
| `opus` | Unclear root cause, cross-cutting refactor, concurrency or security reasoning, or after a lower tier has visibly failed. |
| `codex` | Routed through `codex-dispatch` (below). |

Escalate only when the cheaper tier visibly fails. Per-tier ticket budgets cap
what a single drain can spend.

## Cross-model review

`codex-dispatch` works a `Tier/Codex` ticket with Codex as the implementer in a
sandboxed worktree and Claude as coordinator and reviewer. Codex reviews the
diff first, read-only and fresh, then the Claude reviewer runs as the gating
verdict, with one fix round per review stage.

Two different models disagreeing about a diff surfaces things neither catches
alone, and the gate stays with one of them so review never deadlocks.

## Skills

`.claude/skills/` holds the workflow. Two are first-party:

- **queue-drain**: the batch pipeline above.
- **codex-dispatch**: the cross-model implement-and-review path.

The remaining 14 are vetted third-party imports from Trail of Bits, mattpocock,
Anthropic, vercel-labs, spillwavesolutions and skills-directory, with
provenance and licences recorded in `docs/skills.md` and `skills-lock.json`.
Every third-party skill is read file by file before installation, rejecting
anything with external network calls, credential access, obfuscated code, or
instructions that override user intent.

## Layout

```
.claude/skills/   the workflow, as skills
docs/workspace.md worktree lifecycle and teardown rules
docs/skills.md    skill inventory with provenance
docs/pipeline.html flowchart map of the whole workflow
docs/templates/   "how this app works" doc template, one per target repo
docs/superpowers/ plans, specs and research behind the pipeline
docs/runs/        run reports
workspace/        cloned target repos (gitignored, never tracked)
.env.example      env schema, names only, values live in Doppler
tests/            sweep tests
```

## Tests

```bash
bash tests/sweep_test.sh
```
