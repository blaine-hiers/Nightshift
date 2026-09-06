# Gauntlet Feature Upgrades — Implementation Plan

**Goal:** Take Gauntlet from a working single-sample A/B harness to one whose
numbers survive scrutiny, that delivers the per-section attribution its README
already promises, and that can put a locally-served fine-tune under test on the
same corpus as Claude.

**Architecture:** Five phases against `blaine-hiers/Gauntlet`. Phases 1–3 harden
what exists (statistics, isolation, checks, reporting, concurrency). Phase 4
introduces a **provider axis** — the `claude -p` subprocess call is extracted
behind an interface so an OpenAI-compatible local endpoint becomes a peer of the
Claude CLI rather than a fork of the project. Phase 5 builds section ablation on
top of all of it.

**Tech Stack:** Python 3.12, pytest, pyyaml, `claude -p --output-format json`,
an OpenAI-compatible `/v1/chat/completions` endpoint for local models.

**Repo:** `workspace/Gauntlet`, one worktree per issue under `.worktrees/`.
Baseline at plan time: 1,535 lines, 38 tests passing in 0.55s.

**Issues** (`blaine-hiers/Gauntlet`): Phase 1 → #1, Phase 2 → #2,
Phase 3 → #3, Phase 4 → #4 (`status/needs-input` until the endpoint details
land), Phase 5 → #5.

---

## Global Constraints

- **Every phase keeps `python -m pytest` green.** The suite is fast; there is no
  excuse for a red commit.
- **Result rows are append-only JSONL and must stay backward-readable.** New
  fields get defaults on read (`cmd_compare` already does this for `model`);
  never rewrite or reorder existing rows.
- **Run directories stay under the system temp root**, never inside the repo.
  That is the contamination guarantee and it is easy to break by accident.
- **No behavior change without a test that would have caught the old behavior.**
- Work happens in the worktree, not the base clone.

---

## Why this order

Ablation (Phase 5) is the headline feature and it comes last on purpose. It
multiplies the number of runs by the number of sections in the CLAUDE.md, so
running it before repeats (Phase 1) would produce a large table of single-sample
noise, and running it before concurrency (Phase 3) would take hours per sweep.

The local provider lands before ablation rather than after because it is the
thing that makes ablation affordable: a full section sweep at N=5 repeats is
expensive on Claude and free on a local endpoint.

---

## Phase 1 — Make the numbers trustworthy

Three defects, all of which currently let the harness state a conclusion it has
not earned.

### Task 1.1: Model-aware resume key

`cmd_run` keys `recorded_pairs` on `(task_id, variant)` (`gauntlet/cli.py:87`),
but `--model` overrides the model per run and `build_compare` treats model as a
real dimension. Re-running a label under a second model skips every cell as
"already recorded" and silently emits a single-model comparison.

**Files:** `gauntlet/cli.py`, `tests/test_cli.py`

- [ ] Widen the key to `(task_id, variant, model, repeat_idx)`; read `model` from
      each existing row with `row.setdefault("model", cfg.model)` so pre-model
      rows still dedupe correctly.
- [ ] Test: a label with rows recorded under model A does not skip when re-run
      under model B, and *does* skip when re-run under model A.

### Task 1.2: Repeats and dispersion

Every reported number is one sample. `build_report` flags a variant on
`s["empty"] >= s["current"]` — a 0.001 gap trips the verdict.

**Files:** `gauntlet/cli.py`, `gauntlet/report.py`, `tests/test_report.py`

- [ ] Add `--repeats N` (default 1). Stamp each row with `repeat_idx`.
- [ ] Aggregate per (task, variant, model) cell: mean and standard deviation of
      the composite score, and the sample count.
- [ ] Report mean ± sd in the per-task matrix; show `n` in the variant summary.
- [ ] **Gate the verdict on a margin.** Flag a task only when the `empty` mean
      exceeds the `current` mean by more than the pooled dispersion — not on a
      bare `>=`. State the rule in the report text so a reader knows what
      "flagged" means.
- [ ] Test: with two repeats scoring 0.4 and 0.6 against a `current` mean of
      0.5, the task is *not* flagged; with `empty` at 0.9/0.9 it is.

### Task 1.3: Close the user-scope contamination channel

The README's isolation argument covers the project direction only. `claude -p`
still inherits `~/.claude/settings.json`, installed plugins, skills, and MCP
servers from the invoking user. There is no `~/.claude/CLAUDE.md` on the current
machine, but nothing prevents one appearing, and the rest already leaks — so the
`empty` variant is not empty.

**Files:** `gauntlet/runner.py`, `tests/test_runner.py`, `README.md`

- [ ] Invoke the CLI with an isolated settings directory and
      `--strict-mcp-config` so no user-level MCP servers load.
- [ ] Record the isolation posture in each result row (which flags were passed),
      so an old run is self-describing.
- [ ] Test asserts the isolation flags are present in the constructed argv.
- [ ] Update the README's *Contamination isolation* section — it currently
      describes only half the problem, which is worse than describing none of it.

---

## Phase 2 — Sharpen the signal

Cheap, additive, and each one closes a way the harness can currently be fooled.

### Task 2.1: Blast-radius and negative checks

`VALID_CHECKS` is four file-based types, all single-path. A "read-only" task
proves itself with one `file_unchanged` while being free to trash fifty other
files undetected.

**Files:** `gauntlet/tasks.py`, `gauntlet/scoring.py`, `tests/test_scoring.py`,
`tasks/README.md`

- [ ] `snapshot_unchanged` — diff the whole run dir against the manifest, which
      is already computed and loaded. Report the count and identity of drifted
      paths, not just pass/fail. This is the real read-only assertion.
- [ ] `file_not_contains` — lets a trap be asserted deterministically instead of
      leaning on the judge (the Jacksonville trap in `01-fa-dc-count.yaml` is the
      motivating case).
- [ ] `file_matches` — regex, for structure the substring check cannot express.
- [ ] Extend the `path`-required validation in `load_tasks` to cover the new
      types, and allow `snapshot_unchanged` to carry an `allow` glob list rather
      than a `path`.

### Task 2.2: Record what the run actually cost

The premise is "which sections earn their tokens," and no ratio is ever
computed. Two concrete gaps: `num_turns` from the CLI's JSON payload is
discarded, and the judge's own cost is never attributed, so the report's
"Total cost" understates every row that carries a rubric.

**Files:** `gauntlet/runner.py`, `gauntlet/judge.py`, `gauntlet/cli.py`,
`gauntlet/report.py`

- [ ] Capture `num_turns` (and token counts, when the payload carries them) into
      the result row.
- [ ] Return the judge's cost from `judge_output` and record it separately as
      `judge_cost_usd` — separate, because judge spend is harness overhead and
      should not inflate the variant's measured cost.
- [ ] Add a score-per-dollar and a score-per-turn column to the variant summary.
      A variant that gains 0.02 for 3,000 extra tokens should read as the loss it
      is.

### Task 2.3: Judge robustness

One call, no retry, raw reply discarded. An unparseable reply yields
`score: None`, which `_task_score` then silently drops from the composite — the
task scores on its checks alone and nothing says so.

**Files:** `gauntlet/judge.py`, `gauntlet/report.py`, `tests/test_judge.py`

- [ ] Retry once on unparseable output before giving up.
- [ ] Optional `--judge-samples K` taking the median score, for tasks where the
      rubric is genuinely borderline.
- [ ] Persist the raw judge reply on the row for audit.
- [ ] Surface degraded rows in the report rather than folding them silently into
      the mean.

### Task 2.4: Report gaps

**Files:** `gauntlet/report.py`, `tests/test_report.py`

- [ ] Errors column in `build_report` — `build_compare` has one, and without it a
      variant that errored on every task reads as `n/a` rather than as a failure.
- [ ] Per-category breakdown. Categories are a first-class concept in `tasks.py`
      and appear nowhere in the summary.
- [ ] Stamp snapshot provenance (source root, timestamp, file count, manifest
      hash) into `make_snapshot`'s output and onto every result row, so runs from
      different weeks are known to be comparable or known not to be.

---

## Phase 3 — Concurrency

Four tasks × three variants is twelve serial `claude -p` invocations at up to
900s each. Repeats and ablation both multiply that.

**Files:** `gauntlet/cli.py`, `tests/test_cli.py`

- [ ] Add `--concurrency N` (default 1, so existing behavior is the default).
- [ ] Thread the (task × variant × repeat) grid. Run directories are already
      uniquely named by a hash of task and variant — extend that hash with
      `repeat_idx` so parallel repeats cannot collide.
- [ ] Guard the `results.jsonl` append with a lock; keep the flush-per-row
      behavior so an interrupted sweep stays resumable.
- [ ] Keep console output coherent under concurrency — buffer per cell and emit
      on completion rather than interleaving.
- [ ] Test with a stubbed executor that concurrent rows all land exactly once.

---

## Phase 4 — Provider axis and local models

**Decision: build this into Gauntlet, not as a separate project.** The entire
value is comparative — same corpus, same tasks, same checks, same judge. A
second project duplicates snapshot, task loading, scoring, and reporting on day
one and diverges by week two. What belongs at the seam is an interface, not a
repo boundary.

### Task 4.1: Extract the provider interface

**Files:** new `gauntlet/providers/`, `gauntlet/runner.py`, `gauntlet/config.py`

- [ ] Define an `AgentProvider` protocol: given a prompt and a run directory,
      execute and return a normalized result (output text, turns, cost, tokens,
      error state).
- [ ] `ClaudeCliProvider` reproduces today's behavior exactly, including the
      Phase 1.3 isolation flags. This is a pure refactor — the existing runner
      tests must pass untouched.
- [ ] Move provider selection into config as a `providers` map, subsuming the
      current top-level `model` and the `--model` override. Keep both working:
      an absent `providers` key means one implicit Claude provider using `model`.

### Task 4.2: OpenAI-compatible provider with a tool loop

A local model is not an agent. Making it one means supplying the loop and the
tools, confined to the run directory.

**Files:** `gauntlet/providers/openai_compat.py`, tests

- [ ] HTTP client against `{base_url}/v1/chat/completions` with tool-calling.
      Configurable base URL, model name, API key via env var name (never a
      literal key in config), and timeout.
- [ ] Minimal tool set covering what the four task categories need:
      `list_dir`, `read_file`, `write_file`, `move_file`, `grep`.
- [ ] **Path jail.** Every tool resolves its argument and asserts it stays under
      the run directory. A model that escapes the run dir invalidates the run and
      can damage the machine; this is the single most important test in the
      phase, and it must cover `..`, absolute paths, and symlinks.
- [ ] Turn cap mirroring `max_turns`, and a wall-clock timeout mirroring
      `timeout_s`.
- [ ] Record tokens rather than `cost_usd` — local inference has no dollar cost,
      and reporting `0.00` next to Claude's real spend would flatter it
      dishonestly. Leave `cost_usd` null and let the report render it as `local`.

### Task 4.3: Provider as a reporting axis

**Files:** `gauntlet/report.py`, `tests/test_report.py`

- [ ] Generalize `build_compare`'s `(model, variant)` cell key to
      `(provider, model, variant)`. The existing pattern carries over directly.
- [ ] **Label cross-provider rows as scaffold-confounded.** A local model driven
      by our five-tool loop and Claude driven by Claude Code are not running the
      same agent, so an absolute score gap between them measures the scaffolds as
      much as the models. The defensible comparison is *within* a provider:
      local-model × CLAUDE.md-variant, which is exactly the question Gauntlet
      exists to answer. The report must say this where the numbers appear, not
      only in the README, or someone will quote the wrong column.

### Prerequisite

The endpoint is not on this machine — nothing on PATH, no Ollama or LM Studio
install directories, nothing serving on 11434/1234/8000. Confirm the base URL,
model name, and auth before Task 4.2, and add a preflight that fails fast with a
clear message when the endpoint is unreachable rather than after the first task
times out.

---

## Phase 5 — Section ablation

The README claims Gauntlet "reports which sections earn their tokens." Today
nothing connects a section to an outcome: `lint.py` scores sections statically,
and the A/B is whole-file only. This phase closes that gap and is the reason the
other four phases are worth doing.

**Files:** new `gauntlet/ablate.py`, `gauntlet/cli.py`, `gauntlet/report.py`,
`README.md`

- [ ] Reuse `lint._split_sections` to decompose the snapshot's CLAUDE.md, then
      generate one synthetic variant per section-removed (`minus-<slug>`).
- [ ] Handle heading nesting: removing an `##` must take its `###` children with
      it. The current splitter is flat and will need hierarchy — this is the one
      genuinely fiddly piece of the phase.
- [ ] `gauntlet ablate --label <l>` generates the variants and runs the grid,
      honoring `--repeats` and `--concurrency`.
- [ ] Per-section delta table: score change versus the full file, tokens
      reclaimed, and a verdict per section. A section whose removal costs
      nothing measurable is a section to delete.
- [ ] Cross-reference the static lint columns (est. tokens, imperatives, dead
      paths) against the measured delta in one table — static suspicion beside
      empirical evidence is the artifact this whole project is for.
- [ ] Guard the cost: `sections × variants × tasks × repeats` grows fast. Print
      the planned cell count and require confirmation past a threshold.

---

## Deferred

Not in scope, recorded so they are not rediscovered:

- **Packaging and CI** — no `pyproject.toml`, no console script, no ruff, no
  Actions workflow running the 38 tests. Worth doing, unrelated to these five
  phases; pick it up when the branch settles.
- **Lint depth** — `len(body) // 4` as a token estimate, flat `#` splitting,
  dead-path detection only for backticked strings containing a slash. Phase 5
  needs the nesting fix; the tokenizer and contradiction detection can wait.
- **Task corpus size** — `tasks/README.md` targets 12–16 tasks, 3–4 per
  category; there are 4. Statistical power in Phase 1 and section resolution in
  Phase 5 both improve with more tasks, so this becomes the binding constraint
  once the machinery is built.
