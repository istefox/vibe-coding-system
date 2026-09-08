---
name: plan-contract-scan-blind-spot-shared-extractor
description: A plan's own grep-based "every call-site is listed here" contract analysis can still miss a call site that reads the same doomed variable through a DIFFERENT consumer/extractor function than the one the plan tracked — found removing SKILL.md-reading assertions in codex-audit-mode.test.sh (ADR-0197 Task 4)
metadata:
  type: project
---

Migrating `deep-refactor` off the vendored `SKILL.md` (ADR-0197, plan
`2026-09-07-migrate-deep-refactor-out-of-vendored-pa.md`, Task 4), the plan's own "Read this
second" section claimed to enumerate every call-site reading the doomed file, and instructed
removing the `SKILL_MD`/`SKILL_TEXT` variable *definitions* outright. Literally following that
would have been fatal: `extract_guard()` (feeding `GUARD1`/`GUARD2`, which feed CX14-CX17 — NOT
named anywhere in Task 4's R-05/06/07 bullets) also reads `"$SKILL_MD"` directly, as does one
inline `awk`/`grep -n` block inside CX22. Under this repo's universal `set -u`, removing the
variable would have aborted the ENTIRE script at the `GUARD1=$(extract_guard ...)` line — before
even S0 finishes — turning "delete 7 stale assertions" into "delete all 39 assertions' ability to
run at all." The tell was running the file: a `bash -n` syntax check does NOT catch this (unset
variable expansion is a runtime error, not a parse error).

**Lesson for future "Read this second"-style plans in this repo: a shared extractor
function/variable can have MULTIPLE call sites feeding DIFFERENT downstream consumers, and a
plan's grep for the doomed file's literal path can miss the ones that go through a helper function
whose own body — not the call site — names the file.** `grep -n SKILL_MD <file>` would have found
every one of these sites (they all exist in the current file), so the omission wasn't a tooling
gap, it was scope: the plan's author grepped for CX-id-level call sites tied to the migration's own
requirement ids, not for every downstream consumer of the shared variable transitively. Before
literally deleting a variable/function definition a plan names, grep the WHOLE file for its name
first and diff that against the plan's own enumerated call-site list — if the diff is non-empty and
the extra consumers are out of the current task's stated scope, keep the variable/function, add a
comment explaining why it's retained against the letter of the instruction, and flag the gap
explicitly in the report rather than either (a) blindly deleting and breaking the file or (b)
silently doing the out-of-scope work to "fix" it.

**Resolution pattern that worked:** keep the variable, remove only the callers/consumers that
actually ARE in scope (S0's hard-exit half, `SKILL_TEXT`, the finding-schema extraction, CX10,
CX20-CX25 and their five plants), leave the out-of-scope consumer (`extract_guard`/CX14-CX17)
completely untouched, and write the retention as its OWN rule-19 comment at the variable's
definition site — not folded into the removal comments — explicitly naming what still needs it and
that the same fate-decision CX10 got (see below) will eventually need making for it too, once the
file is actually deleted (a later task, out of this one's scope).

**A second, structurally identical decision recurs whenever a migration retires a file that fed a
cross-check assertion (not just a presence/prose assertion):** `CX10` compared
`codex-reviewer.sh`'s (still-owned) JSON schema against `SKILL.md`'s (now-externally-owned)
finding-schema fence. The plan explicitly flagged CX10 as needing an explicit fate decision rather
than "leave it reading an empty variable." The right call was REMOVAL, not freezing a hardcoded
local copy of the field list — because a hardcoded copy recreates exactly the duplicate-source-of-
truth problem the migration exists to eliminate (root CLAUDE.md rule 6), now against a schema this
repo no longer owns. Any future "retire vendored file X" migration should scan for this same shape
— an assertion that cross-checks a REMAINING-owned file's behaviour against the FILE BEING RETIRED
— and default to removal with a rule-19 comment citing rule 6, not to freezing a baseline, unless
the plan explicitly asks for a frozen baseline instead.

See [[task1-codex-audit-mode-slug]] and [[task5-schema-test-allblocks-slug]] for sibling memories
from earlier work on this same file family.
