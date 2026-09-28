# Dawnpatrol, Legwork & Bindery — Feature Roadmap

**Goal:** Take three working apps from "does what it says" to "does what it
promises." Each is already strong; each has exactly one place where it breaks
its own stated principle, and each drops the human judgment it collected before
that judgment reaches the artifact a client is left holding. Those two patterns
organise this roadmap.

**Scope:** `blaine-hiers/Dawnpatrol`, `blaine-hiers/Legwork`,
`blaine-hiers/Bindery`. Worktrees under `workspace/<repo>/.worktrees/`.

**Baselines at plan time:** Dawnpatrol 67 tests, Legwork 102, Bindery 247 —
all green. Six PRs open, all reporting MERGEABLE.

---

## Global Constraints

These are not preferences. A proposal that breaks one is not a smaller version
of a good idea, it is a different product.

- **Python standard library only.** No pip, no dependencies, ever. Dawnpatrol's
  optional `claude` CLI call is the single exception and must always be
  permitted to fail without taking the run down.
- **Local-first.** No hosted service, no account, no telemetry; no network in
  Legwork or Bindery at all.
- **Nothing is filtered away.** Everything collected is kept and ordered.
- **Every figure shows its arithmetic.** No single-point number without visible
  working.
- **Bindery is read-only on client documents**, enforced by dedicated tests.
- **Legwork never invents a rate**, never collapses a range to a point, and
  never guesses a handling tick the owner did not make.

---

## Theme A — Honour "nothing is hidden"

All three apps state this principle and all three break it in exactly one
place. This is the cheapest, highest-credibility work available.

| App | Where it breaks | Status |
|---|---|---|
| Dawnpatrol | `digest.build()` returned `merged[:40]`; the UI could not reach the rest | **Fixed**, PR #7 |
| Bindery | `_headlines()` uses a fixed category order then `return out[:5]` (`analyze.py:724`) | Phase 1 |
| Legwork | chase demo drops comma-less lines client-side despite its own hint | Filed, #5 |

**Bindery's is the worst of the three** and is also its highest-value single
change. The headline block is the part an advisor reads aloud in the room. A
catastrophic concentration finding can be pushed off the list by nothing more
than its position in an if/elif chain. Replace the fixed order and the cap with
a severity sort that shows its own arithmetic. It is hours of work, touches no
I/O, needs no schema change, and it is a prerequisite for anything that adds new
finding types — otherwise each addition needs its own bespoke priority rule.

---

## Theme B — The artifact is weaker than the session

Each app collects human judgment and then loses it at the boundary where
something leaves the machine. This is the same bug wearing three costumes.

- **Dawnpatrol.** `POST /api/kept` captures the advisor's own curation with a
  note framed as "what does this mean for a 20-person company". `render_markdown`
  never references the KEPT collection, so the `reports/*.md` a 6am task writes
  drops the only human judgment in the product. *(Verified: no KEPT reference in
  `digest.py`.)*
- **Legwork.** The live demo is the persuasive core — the owner watching their
  own email get parsed, misses shown honestly. `to_markdown` / `to_text` never
  reference it. The packet the owner keeps could have come from a slide deck,
  which is the exact accusation the app exists to disprove.
- **Bindery.** No memory across visits. There is no way to tell a returning
  client "you had 40 duplicates in March, you have 6 now" — which is the natural
  shape of a second invoice for a practice built on repeat engagements.

---

## Phase 0 — Land the foundation (do this first)

Nothing below should start before this clears.

1. **Merge the six open PRs.** All MERGEABLE; #5 and #7 were verified to
   auto-merge cleanly despite touching the same two files.
2. **Legwork #3 is a hard prerequisite for all Legwork work.** Only the first
   field edit per sheet is saved; every later edit is silently discarded because
   `save()` swaps the object graph out from under handlers bound at the last
   paint. Every Legwork feature below assumes a sheet that saves. `tier/opus`.
3. Clear the cheap correctness backlog: Dawnpatrol #9–#12, Legwork #4–#6,
   Bindery #4.
4. **Decide Bindery #3** (contradiction detection). Design is in Phase 3.

---

## Phase 1 — Cheap, high-credibility (days, not weeks)

| # | App | Item | Size |
|---|---|---|---|
| 1 | Bindery | Severity-ranked, uncapped headline list (Theme A) | S |
| 2 | Dawnpatrol | Source health trend — flag a feed failing N days running | M |
| 3 | Dawnpatrol | Window-days control on the Collect button | S |
| 4 | Legwork | Per-role hand-time rollup, grouped by the `who` already collected | S |
| 5 | Bindery | Per-client near-duplicate threshold and score weights | S |
| 6 | Bindery | Unreadable files grouped by folder, not only by reason | S |

**On #2:** the source list was verified once, in August. Two feeds have since
degraded — VentureBeat AI returns a persistent HTTP 429, ZDNet AI a 404 — and
nothing would have surfaced that drift. "A broken source is on the screen, not
in a log" currently holds one morning at a time and is defeated in aggregate.

**On #3:** the backend already accepts `windowDays` 1–14; the UI posts an empty
body and can never ask for it. Pure wiring, for the "I was on-site for four
days" case.

**On #4:** the sheet already collects `who` per step but applies one blended
rate to all of them. An owner who runs payroll will notice a $22/hr office hour
priced identically to a $95/hr tech hour, in the one column the code's own
comments flag as most sensitive.

**On #6:** "all 340 unreadable files live in `\\Server\Archive\Pre-2015`" is a
remediation plan. "Here are 12 reasons files fail" is not.

---

## Phase 2 — Close Theme B

| # | App | Item | Size |
|---|---|---|---|
| 7 | Legwork | Pin a live-demo result into the exported one-pager | M |
| 8 | Dawnpatrol | Kept-list call-prep export, optional flat client tag | M |
| 9 | Bindery | Re-engagement trend: snapshot each scan, show deltas | M |

**#7 carries a real risk that must be designed in, not bolted on:** pasted
customer text contains real names and addresses. Pinning a demo result into an
exported file needs an explicit, visible "include this in the export?"
confirmation. Silently baking a customer's PII into a leave-behind would be a
serious misstep.

**#9 needs a retention cap** so a five-year engagement does not grow an
unbounded sqlite file, and must show its arithmetic rather than becoming
"the score went up" theatre.

---

## Phase 3 — Ambitious

**10. Bindery — contradiction detection** (`feature`, decision pending on #3).

General semantic contradiction detection is not achievable at acceptable
false-positive rates without an NLP model, which the constraints forbid. The
buildable version is a **closed set of hand-authored fact extractors** — labour
rate, payment terms, warranty length, insurance limit, price-list effective date
— each an `re` pattern requiring a fixed anchor phrase adjacent to the value.
Two values for the same field key, in different documents, differing beyond a
tolerance, become a "same fact, different files, different values" finding shown
with both snippets. The advisor confirms; the tool never declares.

False-positive control is architectural, not statistical: it only ever compares
numbers adjacent to the *same* anchor phrase from a short curated list. It never
compares any two numbers near any two phrases — that is what would cry wolf on
every page count and invoice total in the folder.

The honest cost is recall. A business phrasing its warranty in a way no anchor
expects gets nothing, and the report must say so out loud rather than let "no
contradictions found" read as "verified consistent." **If it cannot reach
near-zero false positives, the correct outcome is to drop the README's
contradiction claim and ship a smaller "known business facts, side by side"
table with no contradiction language at all.** That is a good result, not a
failure.

**11. Dawnpatrol — cross-day story threading.** Match today's merged stories
against yesterday's stored report and annotate "continuing — first seen {date}"
rather than presenting a third-morning story as brand new. Reuses
`_canonical_url` and `_shingles`. **Must land after #9**, which fixes the
canonical-URL merge path it depends on, and needs its own decay term — a story
resurfacing for the third day is not automatically more important, and without
that the ranking starts rewarding staleness.

**12. Dawnpatrol — band-diversity-aware corroboration.** A lab post plus a
practitioner writeup plus a wire story is stronger evidence than three outlets
syndicating one press release. `Story.also` currently stores only
`{source, url}` — no band — so the corroboration bonus is blind to exactly the
distinction the band system exists to draw. Changes rank order, so it must be
re-validated against the pinned ranking tests.

**13. Legwork — a real "who goes where" demo.** The one handling answer with no
runnable demo. A deterministic greedy first-draft assignment with the reason
written beside each one, framed as a draft the owner edits. The picker is
already honest here — `board`'s blurb reads *"Not built yet. Named here so the
sheet doesn't imply it exists"* — so this is an opportunity, not a repair.
Needs explicit "assumed, not told" flagging mirroring the extraction demo's
`missed`, or it starts to look like judgement was quietly automated.

**14. Legwork — second-visit delta report.** Re-enter measured numbers after a
build and compare the original range against observed reality, still as ranges.
A pure diff of two `analyze()` snapshots. The only feature here that operates
*after* the sale, which is why it matters for a repeat-engagement practice.

**15. Bindery — cross-folder comparison.** Point at the official shared drive
and someone's personal export; report what exists in both with different
content. The index already partitions by `kb_id` and the near-duplicate
algorithm is already `kb_id`-agnostic. For an SMB with no IT department this is
often *the* finding that explains why the documentation is unreliable. Keep it
narrowly framed — "does the same content exist twice, and does it agree" — or it
scope-creeps into a general folder-diff product.

**16. Bindery — headless batch mode.** `py app.py --scan <folder> --kb <name>
--export report.md`, calling `ingest_folder` and `analyze` directly without the
server. Twelve active clients currently means opening the GUI twelve times.
Must share the same functions as the GUI path, not reimplement them.

---

## What we will not build

Recorded so the same tempting ideas do not get re-proposed each quarter.

- **A "top 5 only" or smart-curate mode in Dawnpatrol.** The most requestable
  feature and the one that guts the founding refusal. You cannot audit an
  absence.
- **Self-tuning ranking weights.** If `KEYWORDS` can change without a human
  editing `sources.py`, a Tuesday score is no longer traceable to a fixed
  inspectable table. A suggestion the advisor commits by hand is acceptable; an
  automatic reweight is not.
- **Industry benchmarks in Legwork** ("shops like yours save X"). The one-pager
  already prints *"These are your numbers, not an industry average."* There is
  no dataset behind a solo practice, and a stranger's numbers on this owner's
  page is precisely what the trust model exists to prevent.
- **Auto-suggested handling ticks.** `core.py` already refuses to guess handling
  on import: *"Guessing it would put ticks on a client's sheet that the client
  never made."* The ticks are worth something only because the owner said them.
- **A suggested hourly rate.** Once one dollar figure on the page is soft, none
  of the others can be trusted.
- **LLM summarisation or "chat with your documents" in Bindery.** Breaks
  stdlib-only and no-network, and undoes the actual differentiator: inspectable,
  boring determinism the advisor can point at.
- **Any write path in Bindery** — auto-dedupe, auto-archive, auto-rename. Turns
  "this app cannot write" into "this app can write, but only when a flag is
  off", which is a categorically weaker promise to make a client.
- **A bundled OCR engine.** No stdlib OCR exists. Page-count triage captures
  most of the practical value — "here is what is worth paying to OCR" — without
  crossing the line.
- **Hosted or synced anything.** Local-first is the trust model, not a
  deployment detail.

---

## Open decisions

1. **Bindery #3** — build contradiction detection to the design in Phase 3, or
   drop the README claim? Blocks Phase 3 item 10.
2. **Dawnpatrol dead feeds** — VentureBeat (429) and ZDNet (404) have degraded
   since verification. Move them to `DEAD_FEEDS` with their failure recorded,
   per the file's existing convention, or keep retrying?
3. **The README test counts** are hardcoded in all three repos and drifted three
   different ways across the open PRs. Decide whether that number belongs in a
   README at all.
4. **GitHub Project** — `gh project` needs `read:project` on the token. Until
   then this roadmap sequences against per-repo issues only.
