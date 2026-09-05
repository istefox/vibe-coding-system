---
name: task1-codex-audit-mode-slug
description: Reusable stub-CLI test pattern and an ADR-0154 back-reference gotcha, learned writing codex-audit-mode.test.sh (spec-first, before Tasks 2-8 landed the code)
metadata:
  type: project
---

Two durable, reusable facts from writing `staging/plugin/scripts/tests/codex-audit-mode.test.sh`
spec-first (ADR-0049 §D1 — tester dispatched before the coder, briefed from plan Task 1 + SPEC.md
+ ADR-0193, not from an implementation that did not yet exist).

**Stub-CLI-on-isolated-PATH pattern, for any harness that must exercise a wrapper script which
shells out to an external CLI without ever making a live call.** Build a fake executable named
after the real CLI inside a fresh `mktemp -d`, prepend that dir to a PATH value passed only to the
subprocess under test (never exported into the harness's own ambient PATH), and for the "CLI is
absent" cases construct a PATH with the real CLI stripped out — never assume the host lacks it.
Concretely: loop `IFS=':'; for d in $PATH; do [ -x "$d/codex" ] && continue; ...` to build a
codex-free PATH deterministically regardless of what's actually installed on the runner. The stub
itself can tee its received prompt/args to a file (env var naming the file, e.g. `STUB_PROMPT_LOG`)
so assertions can inspect what the wrapper actually constructed, not just its exit code — this is
what let CX17 (dimension-correct guard embedding) be a real behavioural check instead of a
structural grep on the wrapper's own source. This pattern isn't specific to `codex`; any wrapper
around `git`, `gh`, a package manager, etc. that a harness needs to run without hitting the network
can use the same two pieces (isolated stub dir + PATH-with-tool-stripped).

**ADR-0154's back-reference requirement is easy to silently fail and produces no visible signal
from inside the test file itself.** `spec-coverage.sh`'s scope filter drops a discovered test file
from an SPEC's R-NN coverage unless the file's own text names the plan's basename (with `.md`) or
one of the `ADR-NNNN` ids the plan cites. A harness can be perfectly correct and still report every
one of its ids `UNSCOPED` if this is missing — there is no error in the test file's own output, only
a downstream `spec-coverage.sh` verdict. When writing a new `*.test.sh` for a plan-driven feature,
put the plan's basename or its ADR id literally in the header comment, and say so explicitly (so a
later editor doesn't strip it as "just a comment"). See [[spec-coverage-and-plan-tools]] if that
memory exists — this is the same mechanism from the test-writing side rather than the
architect/spec-coverage-tooling side.

Also worth remembering procedurally: when a plan's own bullet gives a near-literal code/prose
template for a task that hasn't landed yet (e.g. "case \"$MODE\" in review|diagnose|audit) ;;" or a
verbatim heading like "### HITL Gate 0-CDX — Audit engine (Codex or Claude)"), a `# plant:`
declaration built from that literal template is high-confidence. Where the plan only describes
*behaviour* for not-yet-written internals (e.g. Python post-processing whose exact variable names
are unknowable), the plant is necessarily a best-effort guess — this repo's plant-check.sh
convention explicitly tolerates that: a later task with an explicit "run every plant" step
(budgeted, small edits to the same test file) is expected to repair a `BADPLANT` needle once the
real code exists, per its own stated rule "fix the needle, never the assertion".
