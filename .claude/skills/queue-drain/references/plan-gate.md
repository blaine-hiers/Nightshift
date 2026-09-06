# Plan gate (queue-drain stage 3)

## Drafting
Dispatch ONE planning subagent per needs-plan or decompose issue (sonnet
unless the issue's tier — its `tier/…` label, as resolved in stage 2 — is
`tier/opus` or `tier/fable`, which both plan at opus). Its prompt: the issue
verbatim + "Read the target repo at <path-to-base-clone>. Produce ONLY the
compact plan below — half a page. Do not write code."

Compact plan format (all five sections required):

    ## Plan: <repo>#<n> <title>
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

- **Approve** → `gh issue comment` the plan onto the issue, prefix
  "Approved plan (queue-drain):". Ticket joins fan-out; the plan comment
  is part of the implementer's prompt.
- **Revise** → redraft with the human's feedback, re-present in the same
  sitting if quick, else next sitting.
- **Park** → comment the draft plan, prefix "Draft plan (parked):", then
  swap the status label to **`status/needs-input`**. A park is a deferred
  human decision, which is exactly what that label is for — left in
  `status/todo`, the next drain re-plans it and re-presents the same
  question. Moving it back to `status/todo` is the human's signal that the
  decision is made.
- **Decompose approved** → create the child issues in the **same repo** as
  the parent:

      gh issue create -R blaine-hiers/<repo> -t "<title>" -F <body-file> \
        -l status/todo,bug,tier/sonnet

  Link each child to the parent by referencing the parent's number in its
  body (`Parent: #<n>`), comment the split on the parent, and move the
  parent to `status/backlog`. Label every child on creation: a status, a
  type, and the tier the planner suggested for it — a child that lands in
  `status/todo` unlabeled is a ticket the next drain has to re-triage from
  scratch.
