# Plan gate (queue-drain stage 3)

## Drafting
Dispatch ONE planning subagent per needs-plan or decompose issue (sonnet
unless the issue's tier — its `Tier/…` label, as resolved in stage 2 — is
`Tier/Opus` or `Tier/Fable`, which both plan at opus). Its prompt: the issue verbatim + "Read the
target repo at <path-to-base-clone>. Produce ONLY the compact plan below —
half a page. Do not write code."

Compact plan format (all five sections required):

    ## Plan: <issue-id> <title>
    **Goal:** one sentence.
    **Approach:** 2-5 sentences — the chosen path and why, over what
    alternative.
    **Files:** exact paths to create/modify.
    **Test plan:** which existing suites run; what new test proves the fix.
    **Out of scope:** what this deliberately does NOT touch.

For **decompose** tickets the planner instead returns 2-5 proposed child
issues (title + 2-3 sentence description + suggested class/tier each).

## The one sitting
When all plans are back, present them TOGETHER with AskUserQuestion —
one question per plan, options: Approve / Revise / Park. Never trickle
plans one at a time across the run. Keep the batch readable: if more than
~5 plans, say so and split into sittings — a rubber-stamped approval
is a failed gate. `AskUserQuestion` takes at most **4** questions per call,
so a sitting is 4 plans; a 20-plan run is five consecutive sittings, and the
human should be told the count up front. Put the decision the plan hinges
on (fail-open vs fail-closed, revert vs keep, drop vs relocate) in the
question text and make it the option labels — an "Approve" that hides a
baked-in decision is the rubber stamp this rule exists to prevent.

- **Approve** → `save_comment` the plan onto the Linear issue, prefix
  "Approved plan (queue-drain):". Ticket joins fan-out; the plan comment
  is part of the implementer's prompt.
- **Revise** → redraft with the human's feedback, re-present in the same
  sitting if quick, else next sitting.
- **Park** → `save_comment` the draft plan, prefix "Draft plan (parked):",
  then `save_issue` the status to **Needs Input**. A park is a deferred
  human decision, which is exactly what that status is for — left in
  Todo, the next drain re-plans it and re-presents the same question.
  Moving it back to Todo is the human's signal that the decision is made.
- **Decompose approved** → create the child issues (`save_issue`), link
  them to the parent, comment the split on the parent (`save_comment`),
  move the parent to Backlog. Label every child on creation: the parent's
  `Repo/` child, a type, and the `Tier/` the planner suggested for it — a
  child that lands in Todo unlabeled is a ticket the next drain has to
  re-triage from scratch.
