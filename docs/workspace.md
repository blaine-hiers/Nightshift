# Workspace, Worktrees, and Secrets

How worktrees are created, torn down, and credentialed. Read this
before creating your first worktree of a session, before a batch sweep,
and before running `env-sync`.

CLAUDE.md carries the non-negotiables; this file carries the mechanics
and the reasons behind them.

## Workspace Layout

One **base clone** per target repo, one **worktree** per issue underneath it:

```
workspace/
└── api-server/              # base clone — never work here directly
    └── .worktrees/
        ├── issue-42/        # one per GitHub issue
        └── issue-43/
```

Worktrees live *inside* the base clone deliberately: Doppler's CLI scope is path-keyed and inherits down the directory tree, so a worktree under the scoped clone picks up the right project/config for free (see Secrets below). Add `.worktrees/` to the base clone's `.git/info/exclude` — local and untracked, so it never becomes a PR against the target repo.

Set up a ticket:

```bash
cd workspace/<repo-name>
git fetch origin
git worktree add .worktrees/issue-42 -b dev/42-<kebab-slug> origin/main
cd .worktrees/issue-42 && npm ci      # or the repo's own bootstrap
```

Worktrees share one object store, so this costs ~nothing in git terms — the base clone's `.git` is a few MB. Dependencies (`node_modules`) are per-worktree and are the real disk cost; that's unavoidable and is another reason teardown matters.

**Never read a fact about a repo from the base clone's working tree without fetching first.** The base clone sits at whatever `main` was when it was last pulled, which can be many merged PRs ago. It is there to be branched from, not to be measured. Anything that ends up in an issue body — a line count, a file inventory, "the README has no diagram" — must come from `origin/main`:

```bash
git -C workspace/<repo> fetch origin
git -C workspace/<repo> show origin/main:README.md | wc -l
```

The 2026-09-09 drain filed seven README tickets whose bodies were written from unfetched base clones. Two carried wrong numbers into the prompt — Redline described as 359 lines with 4 screenshots when `origin/main` had 161 and 8, and Gauntlet as 143 lines when it had 311. The implementers worked from the real files and flagged the discrepancy, so nothing shipped wrong, but every such error spends a subagent's attention reconciling the ticket against reality.

Set `gc.auto=0` on the base clone and fetch **once from the main thread** before dispatching a batch. Several agents fetching into one shared object store concurrently is the one way this layout bites.

## Teardown

**A worktree is deleted when its issue is closed.** The coordinator does it, not the subagent — subagents get interrupted, die, or finish with the PR still open, which is exactly how 400+ MB of dead clones accumulated once already.

```bash
git -C workspace/<repo-name> worktree remove .worktrees/issue-42   # refuses if dirty
git -C workspace/<repo-name> worktree prune
```

Prefer `worktree remove` over `rm -rf`: it refuses when the tree has uncommitted changes, which is the safety check that matters. `git worktree list` makes leftovers discoverable — a stray clone is invisible until someone runs `du`.

**Sweep before starting any new batch.** For each worktree, delete only when all three hold:

1. `git status --porcelain` is empty,
2. `HEAD` matches the branch's ref on `origin` (nothing unpushed),
3. the PR for that branch is **MERGED** (`gh pr list --state all`).

Any one failing means stop and report it rather than delete — that combination is the only evidence that a tree holds nothing unique.

**A `status/blocked` issue keeps its worktree**, by design: the work is real and half-done, and rebuilding it costs more than the disk does. It will fail the sweep's three tests and be reported as a BLOCKED tree — that report is the intended outcome, not a leak to clean up. (The sweep's `BLOCKED` label describes a *worktree*; the `status/blocked` label describes an *issue*. A blocked issue's tree is usually a BLOCKED tree, but the two are independent — don't infer one from the other.) A blocked issue holding a Doppler-synced `.env` is the one exception worth acting on: if the block is measured in weeks, drop the `.env` and re-sync on resume.

## Secrets (Doppler)

**Doppler is the source of truth; `.env` is a generated artifact.** Never hand-write or copy one between worktrees — a copied `.env` goes stale silently, which is the exact failure Doppler exists to prevent.

**Default to no `.env` at all.** Most tickets don't need one: api-server's suite runs credential-free through `scripts/setup-test-env.mjs`, and an entire 16-ticket batch merged without a `.env` ever existing under `workspace/`. Treat syncing as an opt-in for tickets that genuinely drive live support inbox/Graph calls.

When a ticket does need it, run this **inside the worktree**:

```bash
npm run env-sync        # writes .env into THIS worktree
```

`env-sync` resolves its root from `import.meta.url`, not `cwd`, so it writes to the worktree it lives in rather than the base clone.

- **`dev` only. Never `prd`.** Ticket work never touches the production config. If a synced `.env` header reads `config: prd`, stop and fix the scope.
- Scope is set **once per base clone** (`doppler setup --no-interactive -p <project> -c dev`) and inherits into every worktree beneath it. Don't run `doppler setup` per worktree — it leaves a stale `~/.doppler/.doppler.yaml` entry for every ticket you ever ran, and nothing prunes those.
- **Don't put `DOPPLER_TOKEN` in a subagent's environment.** It sidesteps scoping, but injects a long-lived token into the agent and every subprocess it spawns. Directory scope keeps the credential in the CLI's own store.
- A synced worktree holds live `dev` credentials on disk. Teardown is therefore secret hygiene, not just disk hygiene — `worktree remove` takes the `.env` with it.

