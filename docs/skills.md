# Skills in This Repo

Skills live in `.claude/skills/<skill-name>/SKILL.md` and are the part of
this repo that accumulates value over time. Skill changes are the commits
this repo's history should consist of.

**Third-party skills must be safety-reviewed before installation:** read
every file (SKILL.md and all bundled scripts) and reject anything with
external network calls, credential access, obfuscated code, or
instructions that override user intent.

When a debugging technique, triage pattern, or repo-onboarding step
proves useful more than once, capture it as a skill (the
`superpowers:writing-skills` skill covers how).

## Installed

Vetted third-party imports — keep provenance notes when adding more.

- **karpathy-guidelines** — behavioral rules against silent assumptions, over-engineering, and orthogonal changes; apply when writing or reviewing fixes in target repos. From [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) (MIT).
- **webapp-testing** — Playwright-based toolkit for reproducing and verifying UI bugs in local web apps, including a server-lifecycle helper (`scripts/with_server.py`). From [anthropics/skills](https://github.com/anthropics/skills) (see its LICENSE.txt). Note: example scripts reference `/mnt/user-data/outputs/` paths from Anthropic's sandbox — substitute a local path when adapting them.

From [trailofbits/skills](https://github.com/trailofbits/skills) (CC BY-SA 4.0, see `TRAILOFBITS-LICENSE.txt`):

- **github-triage** — triage a repo's open issues and PRs via `gh`: prioritize, cross-link issues to fix PRs, close resolved ones. **Write-capable** (can merge PRs and close issues) — use with care on repos you don't own. Use it to *survey* a target repo; since GitHub Issues are the tracker, its findings get filed in place.
- **variant-analysis** — after fixing one bug, hunt its siblings: generalize the root cause into Semgrep/CodeQL patterns and sweep the codebase. Ideal follow-up to any issue fix; file each confirmed variant as its own GitHub issue in the repo it affects.
- **differential-review** — security-focused review of a diff/PR/commit: blast radius, regression detection, git-history context. Use to check a fix before opening a PR.
- **fp-check** — rigorous true-positive/false-positive verification of a suspected bug, with full data-flow tracing. Use when triaging whether a reported issue is real.
- **semgrep** / **sarif-parsing** — run Semgrep scans and process SARIF results (requires `semgrep` installed; `sarif-parsing` works on any SARIF file).

From [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, LICENSE.txt in each folder):

- **resolving-merge-conflicts** — resolve merge/rebase conflicts hunk-by-hunk by tracing the intent of both sides; use when rebasing fix branches onto moved upstream.
- **triage** — state-machine issue/PR triage (needs-triage → needs-info / ready-for-agent / ready-for-human / wontfix) with agent-ready briefs. Written for GitHub, which is the tracker here — map its states onto the `status/…` labels in CLAUDE.md rather than introducing a second vocabulary alongside them. Posts an AI disclaimer on every comment. Note: it optionally calls "grilling"/"domain-modeling" skills from its home collection that aren't installed here — skip those steps or improvise.
- **git-guardrails-claude-code** — a setup skill that installs a PreToolUse hook blocking destructive git commands. **Available but not installed:** its default list blocks `git push`, which queue-drain needs for pushing fix branches (stage 6). Customize the pattern list and register as a `PreToolUse` hook on `Bash` in `.claude/settings.json` only if you intend to restrict push operations.

From [skills-directory/skill-codex](https://github.com/skills-directory/skill-codex) (MIT):

- **codex** — delegate prompts to the OpenAI Codex CLI (`codex exec` / resume) for code analysis, refactoring, and automated editing. Requires the `codex` CLI installed and authenticated separately. Single SKILL.md, no bundled scripts; reviewed 2026-09-01 — no network or credential access of its own, and high-impact flags (`--full-auto`, `--sandbox danger-full-access`) are gated behind an explicit AskUserQuestion. Extracted from the repo's plugin layout (`plugins/skill-codex/skills/codex`).

From [vercel-labs/skills](https://github.com/vercel-labs/skills) (MIT):

- **find-skills** — discover and install skills from the skills.sh ecosystem via `npx skills`. Any skill it installs into this repo still gets the file-by-file safety review above before use.

From [spillwavesolutions/design-doc-mermaid](https://github.com/spillwavesolutions/design-doc-mermaid) (MIT):

- **design-doc-mermaid** — Mermaid flowchart/sequence/architecture/deployment diagrams in Markdown, with per-type syntax guides, a troubleshooting list of common render errors, and Python scripts to extract/validate/render diagrams (the scripts need the `mmdc` CLI — `npm i -g @mermaid-js/mermaid-cli` — and only shell out to it; reviewed 2026-08-21, no network or credential access). Its SKILL.md mentions `perplexity`/`brave`/`gemini` fallbacks that aren't installed here — skip those steps. Installed via `find-skills`; pinned in `skills-lock.json`.

All 13 third-party skills from before 2026-09-01 have provenance entries in `skills-lock.json` (`codex`, installed 2026-09-01 by direct clone, is not in the lock file) for `find-skills` (`npx skills` CLI); only `design-doc-mermaid` carries a CLI-computed hash. Note: `skills-lock.json` is consumed by `find-skills`, not checked by `file-drift-sentinel` — hash pinning for drift detection is a follow-up decision.

## First-party

- **codex-dispatch** — works a `tier/codex` GitHub issue with OpenAI Codex as implementer (sandboxed `codex exec` in the issue worktree) and Claude as coordinator/reviewer: Claude pushes, opens the PR, runs a fresh read-only Codex review first, then dispatches the Claude reviewer as the gating verdict, with one fix round per review stage resumed by session UUID. Depends on the third-party `codex` skill for CLI mechanics and the `codex` CLI being authenticated. Spec: `docs/superpowers/specs/2026-09-01-codex-dispatch-design.md`.
- **queue-drain** — the batch pipeline: sweep → fetch the `status/todo` queue per repo → triage → batched plan approval → capped fan-out (5) → fresh-context verify → ready PRs + auto-review posted on GitHub → issue close → mandatory retro. Trigger with "drain the queue" or `/queue-drain`. Design and rationale: `docs/superpowers/specs/2026-08-20-queue-drain-pipeline-design.md`; run reports land in `docs/runs/`.
