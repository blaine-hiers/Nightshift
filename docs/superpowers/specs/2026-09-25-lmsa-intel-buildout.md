# lmstudio-automation — "Intel" build-out (design, draft for approval)

Target: `blaine-hiers/lmstudio-automation`. One epic, one issue per feature,
one branch (`dev/<epic#>-intel-buildout`), one PR — same shape as the #32
build-out. Decisions below come from the 2026-09-25 conversation.

## Decisions taken

| Question | Answer |
|---|---|
| Email check-off | Stored locally (hidden from later reports), with an optional Gmail archive/mark-read behind a WRITES confirm, undoable |
| Mil/geo scope | Conflict tracker, geopolitical risk map, defense industry news, OSINT movements |
| Regions | Global, ranked by activity; regions are a config filter, not a fixed list |
| Crawling | Feeds + site watch, follow links to full articles, open web search, user-defined topic reports |
| Search backend | Self-hosted SearXNG (Docker), with a Setup checklist item |
| Map | Inline SVG world map, works offline, countries shaded and clickable |
| "What else" | Capabilities page in the dashboard, plus an ideas list filed as backlog issues |
| Branch | Epic + one PR |

## Architecture: one briefing engine, many reports

The military and geo reports and the "report of my liking" are all the **same
engine** with different config. Each report is one file:
`config/briefings/<name>.toml`. Adding a new report means writing a TOML file,
with no code change. The dashboard's onboarding flow then offers
"Add to schedule" as it does today.

```
config/briefings/<name>.toml
  sources: feeds, watched pages, search queries, APIs (gdelt, dod_contracts, adsb_mil, ...)
        │
lmsa.web      fetch → robots.txt / per-host rate limit / ETag cache → article text
lmsa.search   SearXNG queries → candidate URLs
        │
tasks.briefing   dedupe → embed → cluster into stories → rank (interest × recency × volume)
                 → memo'd extract() per story (summary, countries, actors, severity)
                 → "what changed since last run" diff
        │
lmsa.report   story cards · SVG world map · trend sparklines · "new since yesterday"
```

## Issues (proposed)

### A. Foundations
1. **Prompts as files** (item 2): `lmsa.prompts.load("<task>/<name>")` reads
   `prompts/<task>/<name>.md`. Move the 11 inline prompts out of the task code.
   The prompt's hash goes into `memo_version` so changing a prompt invalidates
   cached results. `tier/sonnet`.
2. **`lmsa.web` fetch layer**: a shared polite fetcher (robots.txt, per-host
   delay, ETag/If-Modified-Since cache in `data/web/`, size caps), plus RSS/Atom
   parsing moved out of `front_page.py`. Adds main-text extraction from
   articles (new dependency: `trafilatura`). `tier/opus`.
3. **`lmsa.search` + SearXNG Setup item**: a JSON-API client, a Setup checklist
   item (reachable? `format=json` enabled?), and a sample `docker run` command.
   `tier/sonnet`.
4. **Briefing engine**: `tasks/briefing.py --name <briefing>` and the config
   schema above. It clusters articles into stories, summarizes each story once
   (memo), and compares against the last run. `tier/opus`.
5. **Site watch**: watched pages are fetched daily, and each report shows a
   text diff of what changed plus an LLM "does this change matter?" note.
   Usable from any briefing. `tier/sonnet`.

### B. Military / geo
6. **Geo tagging + SVG world map component**: country extraction through
   `extract()`, normalized to ISO-3166 codes. `report.Section.world_map()`
   draws an inline Natural Earth 1:110m map (public domain, about 200 KB,
   shipped as package data) with a choropleth plus click-to-section. It also
   goes in `style_preview`. `tier/opus`.
7. **Conflict tracker briefing**: global, ranked by activity. Sources: ISW,
   Crisis Group CrisisWatch, ReliefWeb API, Reuters/AP/BBC world feeds, and
   GDELT DOC 2.0 queries. Output: per-conflict "what changed in 24 h" plus
   escalation or de-escalation flags. `tier/opus`.
8. **Geopolitical risk map**: GDELT event and tone volume per country, compared
   with a 30-day baseline kept in SQLite. Output: a shaded world map, the top
   movers, and a sparkline for each region. `tier/opus`.
9. **Defense industry briefing**: parses the daily DoD contract announcements
   (defense.gov) with `extract()` into contractor, amount, program and service,
   plus Defense News and Breaking Defense feeds. Includes a running contract
   ledger. `tier/sonnet`.
10. **OSINT movements**: samples adsb.lol's public `/v2/mil` endpoint on every
    dispatcher tick, and the USNI Fleet Tracker weekly for naval activity.
    Output: daily aggregates by aircraft type, region and notable patterns,
    with public data only and aggregate reporting. `tier/sonnet`.

### C. Email check-off
11. **Check-off from reports and the dashboard** (`security`): adds a
    `handled` table keyed by Message-ID. Email cards get checkboxes. They work
    when a report is opened through the dashboard (`/reports/...`, same origin
    and token). When the report file is opened directly they're disabled, with
    a hint. The dashboard gets an **Inbox** panel of open items from
    brief/follow-up/deadlines. An optional "also archive / mark read in Gmail"
    uses a new `Gmail.archive` / `Gmail.mark_read`. It needs the WRITES
    confirm, is logged per run, and `--undo` works. `tier/opus`.

### D. Items 3–7 from the survey
12. **Voice memo / meeting transcription**: watches a Recordings folder and
    transcribes with `faster-whisper` (new dependency; the dispatcher gets a
    `model = "whisper"` VRAM class). The LLM then produces a summary with
    action items. `tier/opus`.
13. **Document inbox auto-filing**: a drop folder, read by the vision model or
    OCR, which proposes a title, tags and sender and then files the document.
    Dry-run by default, undoable (reuses the `file_sorter` pattern).
    `tier/sonnet`.
14. **Photo captioning + search**: captions the Pictures library with the
    vision model, embeds the captions, and makes them searchable from
    `doc_search`. Incremental, using the memo. `tier/sonnet`.
15. **Related notes report**: a weekly report of related or near-duplicate
    documents from the existing embeddings. `tier/sonnet`.
16. **Bookmark tagging**: reads Chrome/Edge bookmarks plus links emailed to
    yourself, fetches them through `lmsa.web`, tags and summarizes them, and
    makes them searchable. `tier/sonnet`.

### E. What else
17. **Capabilities page** `/capabilities`: generated from each task's
    docstring, `SETUP` block, schedule and last run. For each task it shows
    what it does, how to run it, what's missing, and a sample report link.
    `tier/sonnet`.
18. **Ideas backlog**: a brainstorm filed as separate `status/backlog` issues.
    Not built on this branch.

### F. Added after the second research pass (2026-09-25)
19. **Disaster fusion**: GDACS, USGS earthquakes and NASA EONET/FIRMS fires
    (all free, no key) in one daily report. It also feeds the risk map's hazard
    sub-score. `tier/sonnet`.
20. **Prediction markets**: Polymarket, Metaculus and Manifold odds on
    geopolitical questions, with 24 h/7 d movement. The report matches them to
    stories by embedding and shows them on the story cards. `tier/sonnet`.
21. **Ask your briefings**: extends `tasks.ask` so its corpus also covers
    everything crawled (stories, articles, contracts, markets), with cited
    answers. `tier/sonnet`.
22. **Source lean + blindspot**: `lean` and `reliability` are tagged per source
    in the briefing config. Story cards get a coverage-balance bar, and there's
    a "blindspot" section for clusters where more than 80% of the coverage
    comes from one lean. `tier/sonnet`.
23. **Go deep**: a "research this further" action on any story, launched from
    the dashboard. It runs a bounded iterative SearXNG + fetch + summarize loop
    (query and page caps) and writes a long report with citations.
    Inspired by GPT Researcher and STORM. `tier/opus`.

Folded into existing issues (no new issue):
- **#4 engine**: a richer story schema (summary, highlights, key quotes,
  timeline, why it matters). Quotes are **checked against the source text**,
  and unverifiable quotes are flagged, not shipped (Kagi News was burned by
  fabricated quotes). A cheap keyword pre-filter runs before any LLM call.
  The report shows a read-time estimate and ends with "you're caught up".
- **#5 site watch**: each page gets a natural-language alert rule ("only tell
  me if the price drops below $50"), the LLM writes the change summary
  instead of showing a raw diff, and pages can have optional typed fields.
  This is the changedetection.io pattern.
- **#7 conflict tracker**: think-tank publications (ISW, CSIS, RAND,
  Brookings, Crisis Group) as a source group.
- **#8 risk map**: the composite index shows its sub-scores (conflict, hazard,
  markets) next to the blended number, never as one opaque score.
- **#11 check-off**: after you archive the same sender repeatedly, it offers
  to create a real Gmail filter (the Inbox Zero pattern), behind the same
  WRITES confirm.

Considered, not taken now (backlog candidates for #18): sanctions/export
list diffs (OFAC SDN, BIS Entity List), CISA KEV cyber report, thumbs and
implicit-feedback re-ranking, NOTAM/airspace closures, Telegram channel
monitoring, AIS dark-vessel detection, satellite change detection, an
actor/entity graph, cross-source contradiction detection, podcast clipping,
spaced-repetition resurfacing, and alternate summary styles (ELI5 / 5Ws).

## Risks and open points
- **Overnight window**: crawling, GDELT, whisper and photos all compete for
  01:00–07:00. The briefing engine needs per-source caps, and the dispatcher's
  `max_run_minutes` may need raising or cadences staggered.
- **VRAM**: whisper and the chat model can't both be resident in 10 GB, so
  they run in separate dispatcher batches.
- **New dependencies**: `trafilatura`, `faster-whisper`, and a Natural Earth
  data file. Everything else stays stdlib + existing.
- **Check-off security**: report pages gain a write path. It must reuse the
  dashboard's Host/Origin/token checks, and archive has to be undoable.
- **Branch size**: 17 issues on one PR is bigger than #32 in code volume. The
  PR will be long; review it area by area.
