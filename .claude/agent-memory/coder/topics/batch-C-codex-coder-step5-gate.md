---
name: batch-c-codex-coder-step5-gate
description: Non-obvious facts from wiring the codex-coder backend gate into step5-implementation.md (ADR-0196, plan tasks 4-6, CK19-CK33) — a dispatch-site-marker quoting trap, and where slice_heading actually draws section boundaries versus where the plan's prose implies they are.
metadata:
  type: project
---

**Fact 1 — quoting an existing `<!-- dispatch-site: NAME class=... -->` marker verbatim inside new
prose breaks `dispatch-completion.test.sh`'s DC21/DC25 population scan.** Those checks derive the
declared dispatch-site population with `grep -hoE 'dispatch-site: [a-z0-9-]+'` across every
`SKILL.md`/`references/*.md` — a plain substring match, blind to markdown backticks or code-fence
context. Writing a sentence like `` The `<!-- dispatch-site: step5-batch-coder class=isolated -->`
marker below stays exactly where it is `` to describe an existing marker makes that name appear
TWICE in the scan, and DC21's frozen baseline (`EXPECTED=...` list, one entry per real site) then
reads as drift even though nothing about the actual marker changed. Fix: refer to the site by its
bare id without the `dispatch-site:` colon token, e.g. `` The `step5-batch-coder` isolated-dispatch
marker below stays... ``. Related to [[batch-B-codex-coder-scope-check]]'s Fact 1 (plant comments
must not be copied into production files) — same root cause, a scanner whose needle is a plain
substring match against prose that happens to quote the mechanism's own declaration syntax.

**Fact 2 — `slice_heading` (used by every CK/CX-style dispatch-gate test) cuts a section at the
NEXT literal `^#### ` line, full stop — it does not know or care what the plan's prose calls "the
Stage 2 text".** ADR-0196's plan brief says, almost verbatim, "add before the existing `**Stage 2 —
coder.**` text" for the Workflow-path pipeline-degeneration content. But the test that actually
gates R-09 (`CK32`) scopes its three regexes to `CK_WORKFLOW = slice_heading('#### Workflow
dispatch path...')`, which ends at the very next `#### ` heading — `#### Codex tester exit-code
handling (ADR-0194)` — dozens of lines BEFORE `**Stage 2 — coder.**` ever appears (Stage 1, the
whole tester dispatch, and the entire Merge-back section sit in between). Content placed literally
adjacent to `**Stage 2 — coder.**` is invisible to a check scoped to an earlier `#### ` heading.
Resolution used here: split the coder's codex-branch content in two — a SHORT statement of "no
coder stage in pipeline(), runs in the orchestrator's own live turn sequentially, degenerates to
zero stages if tester is also codex and review isn't checkpoint" placed right at the end of the
`#### Workflow dispatch path` section's own prose (satisfies the heading-scoped check), and the FULL
operational recipe (worktree add, hook invocation with all required flags, `branch per` pointer,
merge-back) placed at the literal site the plan's prose names (right before `**Stage 2 — coder.**`,
which by then falls under a LATER, different `#### ` heading's slice — `#### Merge-back and
base-fork audit` — so the "above" in "branch per `#### Codex coder exit-code handling` above" reads
correctly, since that heading was introduced earlier in the file). When a plan names a bolded
sub-heading (not a real `#### ` heading) as an anchor, check which `#### ` slice a checkpoint test
actually scopes to before trusting the plan's own wording about "where".

**Fact 3 — an option's `(Recommended)` label is not read as "the default" by these tests; the
literal word must appear.** `CK20`/`CK22`/`CK27` all require the flattened text to contain "default"
within a fixed distance of the option name (`claude-sonnet.{0,50}default`,
`astra.{0,50}default.{0,80}sol`, `medium.{0,30}default...`). ADR-0196's own Decision section already
phrases this as `claude-sonnet (default, today's behaviour)` — copy that shape (`(default, ...)`
or `(default) (Recommended)`) into every option label the gate offers, not just `(Recommended)`
alone, which reads as user-preference framing but not as the machine-checkable default marker.

**Fact 4 — an exact-count assertion on a common word (`AskUserQuestion`) can be stricter on a new
sibling test than on the precedent it was modeled after.** The tester's own gate
(`codex-tester-dispatch-gate.test.sh`, CX25) uses `-ge 2` for its `AskUserQuestion` count inside the
exit-code slice, tolerating a third incidental mention (e.g. a closing sentence about why a Workflow
stage has no such hook). The coder's analogous test (`CK29`) uses `-eq 2` for the SAME kind of slice
— an incidental third mention of the literal string "AskUserQuestion" (even in a sentence not
proposing a real ask) flips a passing check to failing. Don't assume a sibling test's tolerance
(`-ge`) carries over; grep the actual comparison operator in the new test before writing prose that
repeats a tool name.
