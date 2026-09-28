# lmstudio-automation: Master Report email + tabbed dashboard

**Date:** 2026-09-28 · **Target repo:** `blaine-hiers/lmstudio-automation` · **Status:** filed as lmstudio-automation#100–#105

Two asks:

1. **Master Report.** One email a day that bundles several of the existing reports, with a **report configurator** for choosing which reports go in, in what order, and how much of each.
2. **Tabbed dashboard.** The dashboard (`python -m tasks.dashboard`) is one long page of sections with too many fields. Split it into tabs.

---

## What exists today (grounding)

| Fact | Where |
|---|---|
| ~45 tasks, one module each, each writes a standalone HTML report to `output/` via `lmsa.report.Report` | `tasks/*.py`, `lmsa/report.py` |
| Every run is recorded in the store's `runs` table with `status`, `report_path`, and a small `summary_json` of headline numbers | `lmsa/store.py` (`record_run`) |
| **`evening_recap` already rolls up every task that ran today** into one report: `summary_json` → tiles, a link, a failure callout, and an LLM wrap-up. This is the closest precedent. It only renders to a file; nothing emails it. | `tasks/evening_recap.py` |
| **Nothing sends email.** Gmail is read-only over IMAP with an app password (secret `imap`, user `LMSA_IMAP_USER`). Alerts go out only as a Windows toast and a Slack webhook. | `lmsa/sources/gmail.py`, `lmsa/notify.py` |
| Reports are **not email-safe**: `<style>` with the Afterhours theme, Google Fonts, a CSS-animated ticker, inline JS for handled-checkboxes, SVG maps. Gmail strips or breaks most of that. | `Report.render()` |
| The dispatcher runs every 30 min and only starts work when the PC is quiet; the `01:00–07:00` overnight window drops the input-idle requirement. | `config/schedule.toml` `[dispatch]` |
| The dashboard is one page: `00 Status`, `01…` one section per task group (Gmail / Other / Diagnostics & manual / Scheduler) full of launcher cards with every flag as a field, `02 Console`, `02b Inbox`, then `Setup`. Sections collapse, with state in `localStorage`. | `tasks/dashboard.py` `render_page`, `tasks/dashboard_setup.py` |
| Config edits from the dashboard go through an allowlisted, validated, backed-up, atomic save. Per-machine on/off lives in untracked `config/local/` (#99). | `dashboard_setup.py` `_config_save_locked` |

---

## Part A — Master Report

### A1. The model

A **master report** is a named bundle: a recipient, a send time, and an ordered list of **sections**, each pointing at one existing report (task or briefing). It does **not re-run tasks** — the dispatcher already runs them overnight. It reads the latest successful run of each task from the `runs` table and composes from that.

Multiple masters are allowed (e.g. a 6:45 "Morning" and a 19:00 "Evening"), which also means `evening_recap` can eventually become just a preset.

### A2. Config — `config/master_report.toml` (tracked defaults) + `config/local/master_report.toml` (untracked overrides: recipient, enabled)

```toml
[[master]]
name     = "morning"
title    = "Morning Report"
send_at  = "06:45"            # inside the overnight window, so an active PC can't delay it
to       = []                 # empty = LMSA_IMAP_USER (send to yourself)
enabled  = true
send     = false              # repo rule: dry-run by default; true actually sends
llm_intro = true              # optional 3-sentence "top of the morning" written by the chat model
max_age_hours = 24            # a section whose latest good run is older is shown as STALE
skip_empty = true             # omit a section whose digest has nothing in it

  [[master.section]]
  task = "inbox_brief"
  mode = "digest"             # "digest" = headline + top items | "headline" = tiles only | "link" = one line
  max_items = 5

  [[master.section]]
  task = "briefing"
  briefing = "defense"        # briefings are one task with several configs
  mode = "digest"
  max_items = 6

  [[master.section]]
  task = "markets"
  mode = "headline"

  [[master.section]]
  task = "github_digest"
  mode = "link"
```

The recipient address is personal, so it belongs in the local file, not the tracked one — same pattern as `config/local/briefings.toml`.

### A3. The digest contract (how a task shows up inside the email)

Tasks get an **optional** `digest()` hook. No task is required to have one.

```python
# in tasks/inbox_brief.py
def digest(run: RunRow, max_items: int) -> Digest: ...

@dataclass
class Digest:
    tiles: list[Tile]          # 1–4 headline numbers
    items: list[DigestItem]    # title, url (http only), one-line blurb, optional tone
    callouts: list[str]        # "3 replies overdue", etc.
```

- **Fallback for every task without a hook:** tiles from `summary_json` (reuse `evening_recap.parse_summary`) plus a link. So on day one every task can be added to a master; rich digests get added one task at a time.
- The digest reads from the store or the task's own saved data — **never calls the model** at send time (the email must go out even if LM Studio is down). The one exception is the optional `llm_intro`, which fails soft to no intro.
- Untrusted text (email subjects, scraped titles) is escaped, as everywhere else.

### A4. Rendering — a separate email-safe renderer

`Report.render()` can't be reused for the body. Add `lmsa/email_render.py`:

- Table layout, **inline styles only**, no CSS variables, no JS, no web fonts (system stack), no animation, no SVG.
- Afterhours palette approximated with `bgcolor`/inline colors; must remain readable when a client forces light mode.
- **Stay under ~100 KB** — Gmail clips messages at 102 KB. Enforce by trimming `max_items` and noting "+N more in the full report".
- A section header per report with a status chip: `OK` · `STALE (last good run 31h ago)` · `FAILED` · `NOT RUN`.

Plus one attachment: the **full master report as a normal Afterhours HTML file** (built with the existing `Report` class, all sections expanded), for opening in a browser. Links in the email body point at http URLs from the reports themselves; local `file://` report paths don't work on a phone, so they go only in the attachment.

### A5. Sending — `lmsa/mailer.py`

- SMTP over SSL to `smtp.gmail.com:465`, authenticated with the **same Gmail app password** already stored as the `imap` secret (app passwords work for both). From = `LMSA_IMAP_USER`.
- New env names in `.env.example`: `LMSA_SMTP_HOST`, `LMSA_SMTP_PORT` (defaults as above). No new secret.
- **Dry-run by default** (repo rule for anything that sends): writes `output/master-report-<name>-<ts>.html` and a `.eml` preview, sends nothing. `send = true` in config or `--send` on the CLI sends.
- The password never appears in a log, exception text, or report — follow the redaction pattern `notify.slack` and `dashboard_setup.redact` already use.
- Send failure fails soft: record the error on the run, fire `notify(..., level="urgent")` (toast + Slack).
- **Idempotent per day:** a `sends` table (master name, local date, message-id, status). A second dispatcher tick the same day does nothing; the dashboard's "Resend" button bypasses it explicitly.

### A6. Task + schedule

`tasks/master_report.py` with `--name morning`, `--send`, `--preview`. One schedule entry per master:

```toml
[tasks.master_report]
cadence = "daily 06:45"
deadline_hours = 3
model = "none"          # "chat" only if any enabled master has llm_intro = true
```

06:45 is inside the overnight window deliberately: outside it the dispatcher waits for 15 min of input-idle, so a 7:15 email could slip until you walk away from the PC. It should also run after the overnight batch, so ordering in the dispatch batch matters — master_report goes last.

### A7. Report configurator — new **Reports** tab on the dashboard

- Left: list of masters (add / rename / delete / enable).
- Right, for the selected master: send time, recipients, send vs dry-run toggle, LLM intro toggle.
- **Section builder:** every available report (from `discover_tasks` plus each briefing config) as a checklist; checked ones form an ordered list with up/down buttons (drag is a nice-to-have), and per-section mode and max items. Each row shows the task's last run status so you don't add a report that never runs — with a one-click "add to schedule" when it isn't scheduled.
- **Preview** renders the email body in a sandboxed iframe from the latest data, with the byte size shown against the 100 KB budget.
- **Send test now** sends to the recipient immediately (token-checked POST, confirm dialog).
- Saves through the existing locked / validated / backed-up / atomic config path: add `master_report.toml` to the allowlist with a validator that runs the task's own loader, as the other config files do.

---

## Part B — Tabbed dashboard

### B1. Tabs

| Tab | Contains (today's section) |
|---|---|
| **Overview** | `00 Status` tiles + anything needing attention (failed runs, missing setup, unscheduled new tools), each linking to its tab |
| **Tasks** | the four group sections, with group **filter chips** (Gmail · Other · Diagnostics · Scheduler) and a search box instead of four stacked sections |
| **Inbox** | `02b Inbox` |
| **Reports** | new — the master-report configurator (A7) and a list of the latest report files |
| **Setup** | the Setup checklist and the config-file editor |

**Console** doesn't become a tab — you launch a task in Tasks and want to watch it there. It becomes a **dock** at the bottom of every tab: collapsed to a one-line "2 running · last: inbox_brief OK" bar, expandable to today's console.

Each tab label carries an **attention badge** (reusing the counts `collapse_toggle_html` already computes), so something failing on Setup is visible from Overview.

### B2. Fewer fields — the real fix

Tabs cut the page length, but the Tasks tab would still be a wall of inputs. **Launcher cards render compact by default**: name, one-line description, last-run chip, **Run** button. Flags live behind an "Options ▸" expander, open by default only when the task has a required field or its last run failed. Write-flags (the ones that send/delete/label) stay visually separated, as they are now.

### B3. Implementation notes

- Still server-rendered in one response: every panel is in the page, JS toggles `hidden`. No framework, same CSP nonce.
- `role="tablist"` / `tab` / `tabpanel`, arrow-key navigation.
- Active tab in the URL hash (`#tasks`) so links and reloads land correctly; last tab remembered in `localStorage` with try/catch, as `COLLAPSE_JS` does.
- **Deep links must keep working:** `prefill_values` (e.g. the briefing "go deep" link) opens the Tasks tab with that card expanded and scrolled into view.
- No-JS fallback = all panels visible, which is today's page.
- Existing per-section collapse keeps working inside tabs; the stored keys stay the same.

---

## Proposed issues

Filed in `blaine-hiers/lmstudio-automation`, in dependency order.

| # | Title | Type | Tier | Depends on |
|---|---|---|---|---|
| #100 | Dashboard: split sections into tabs with a console dock | improvement | sonnet | — |
| #102 | Dashboard: compact launcher cards, options behind an expander | improvement | sonnet | #100 |
| #101 | `lmsa.mailer`: SMTP send via Gmail app password, dry-run default, redacted errors, `sends` table | feature, `security` | sonnet | — |
| #103 | `tasks.master_report`: config, digest contract with `summary_json` fallback, email-safe renderer, full-report attachment | feature | opus | #101 |
| #104 | `digest()` hooks for inbox_brief, disasters, and job_tracker | improvement | sonnet | #103 |
| #105 | Dashboard Reports tab: master-report configurator with preview and test send | feature | sonnet | #100, #103 |

#100 and #101 are `status/todo` and can run in parallel; the rest are `status/backlog` until their blockers merge. #103 is opus because it sets the contract every other task plugs into.

## Decisions (2026-09-28)

1. **Recipient:** the Gmail account the tool already reads (`LMSA_IMAP_USER`). `to = []` is the only v1 case; no other address is needed.
2. **Send time:** 06:45.
3. **Default bundle:** `inbox_brief`, `disasters`, then `job_tracker` (recruiting and job tracking), all `mode = "digest"`. #104 covers those three digest hooks.
4. **LLM intro:** yes (`llm_intro = true`), so the master's schedule entry uses `model = "chat"`. The intro still fails soft.
5. **Evening recap:** stays a separate task for now.

**Timing risk found while deciding:** `inbox_brief` is scheduled `daily 06:00` with the chat model and a 4 h deadline, so on a busy morning it may not have run by 06:45. Issue 4 must make the master handle "today's run not there yet" explicitly. The simplest fix is to move `inbox_brief` earlier, into the overnight window (e.g. 05:30). `disasters` runs at 01:15, so it's fine.
