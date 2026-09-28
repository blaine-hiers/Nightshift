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

From [tt-a1i/archify](https://github.com/tt-a1i/archify) (MIT, `LICENSE` in the skill folder; derived from Cocoon-AI/architecture-diagram-generator):

- **archify** — renders architecture / workflow / sequence / dataflow / lifecycle diagrams from a small typed JSON spec into a self-contained interactive HTML artifact (inline SVG, dark/light, pan/zoom/search/trace, PNG/SVG/WebM export), with JSON Schema validation, a `deliver` step that emits SHA-256 receipts, and headless-Chrome `visual-check` evidence. Pure Node ≥18 with **zero runtime dependencies**; drive it via `node bin/archify.mjs <doctor|guide|validate|deliver|visual-check|preview|brands|demo>`. Complements `design-doc-mermaid`: Mermaid for diagrams-in-Markdown, archify for a standalone polished HTML artifact (it also ingests pasted Mermaid).

  Installed 2026-09-08 by direct clone at upstream `1072200`, vendoring `archify/` from the repo root. Reviewed file by file. **Two deviations from upstream:**
  - Upstream ships a phone-home version check (`scripts/check-update.mjs` → `https://tt-a1i.github.io/archify/skill-updates/archify/stable.json`) that SKILL.md told the agent to run on every diagram. It was a bounded, payload-free GET that never downloaded or installed anything, but it is still an unprompted external network call, so **the "Update awareness" section and both update scripts were removed**. Re-check for upstream releases by hand.
  - `test/` (needs devDeps and repo-root scripts that aren't vendored) and the five pre-rendered example HTMLs (~4 MB, regenerate with `node bin/archify.mjs examples`) were left out; `package.json`'s `test`/`check:release-identity` scripts consequently don't run. `doctor` passes all 15 checks without them.

  The only remaining network path is `brands capture "<url>"`, which fetches a logo **solely** from a URL the user supplies — guarded against credentials-in-URL, non-standard ports, private/link-local addresses, and DNS rebinding (it pins the validated IP at socket time). `preview` binds `127.0.0.1` only and checks the `Host` header. No credential access, no obfuscated code, nothing that overrides user intent.

All 13 third-party skills from before 2026-09-01 have provenance entries in `skills-lock.json` (`codex`, installed 2026-09-01 by direct clone, is not in the lock file) for `find-skills` (`npx skills` CLI); only `design-doc-mermaid` carries a CLI-computed hash. Note: `skills-lock.json` is consumed by `find-skills`, not checked by `file-drift-sentinel` — hash pinning for drift detection is a follow-up decision.

## First-party

- **codex-dispatch** — works a `tier/codex` GitHub issue with OpenAI Codex as implementer (sandboxed `codex exec` in the issue worktree) and Claude as coordinator/reviewer: Claude pushes, opens the PR, runs a fresh read-only Codex review first, then dispatches the Claude reviewer as the gating verdict, with one fix round per review stage resumed by session UUID. Depends on the third-party `codex` skill for CLI mechanics and the `codex` CLI being authenticated. Spec: `docs/superpowers/specs/2026-09-01-codex-dispatch-design.md`.
- **queue-drain** — the batch pipeline: sweep → fetch the `status/todo` queue per repo → triage → batched plan approval → capped fan-out (5) → fresh-context verify → ready PRs + auto-review posted on GitHub → issue close → mandatory retro. Trigger with "drain the queue" or `/queue-drain`. Design and rationale: `docs/superpowers/specs/2026-08-20-queue-drain-pipeline-design.md`; run reports land in `docs/runs/`.
