---
name: task5-schema-test-allblocks-slug
description: Ordinal-to-enumeration harness repair pattern and Z1-floor re-derivation procedure, learned repairing codex-reviewer-schema.test.sh (ADR-0193 §D7)
metadata:
  type: project
---

Durable, reusable facts from converting `codex-reviewer-schema.test.sh` from ordinal
`extract_schema <N>` selection to all-blocks enumeration (ADR-0193 §D7, plan Task 5).

**Two guard shapes in this repo's harnesses are not interchangeable, and mixing them up
defeats rule 10 (ADR-0124).** A `Z*`-style guard ("did enough assertions run", `>= N`) is
correctly a floor — new coverage should only ever raise the total, so `>=` is the right
comparison and it is meant to be bumped forward as tests are added. An `SC*`-style guard that
pins a *structural count that must equal a fixed real-world quantity* (here: SCHEMA_EOF block
count == mode count) must be `-eq`, never `-ge`. A floor on a count like that would keep
passing after a block silently disappeared as long as the total stayed above the floor —
exactly the "floor absorbs its own plant" failure ADR-0124 names. When adding a new invariant
of this second kind, state at the assertion site, explicitly, that the equality is deliberate
and that raising the pinned number is a conscious edit, not something the check should
tolerate unattended. This distinction is likely to recur any time a harness in this repo
counts a population that maps 1:1 onto something enumerable elsewhere (modes, dispatch sites,
guard strings) — see rule 7 (denominator guards) and rule 10 in the repo's root CLAUDE.md.

**Re-deriving a `Z*` floor means literally running the file before and after the edit, not
arithmetic from reading the code.** The plan text for this task stated "PASS=3 ... floor >= 2"
pre-change and predicted "floor becomes >= 5" post-change; both were confirmed by actually
running the harness (`bash codex-reviewer-schema.test.sh`) rather than trusted, and the
predicted count only matched because the plan's author had done the same measurement — it is
not safe to assume a plan's stated counts are still current by the time a task executes,
per the instruction to "re-derive rather than trust." Always run once before touching the
file and once after, and report the exact command output, not a computed guess.

**Converting a hardcoded ordinal call site to an enumeration, in bash 3.2 with `set -u` only
(no arrays/mapfile available): count the population with a plain `grep -c 'pattern' "$file"`
assigned directly via command substitution.** No `|| true` or `|| echo 0` needed *only* because
these harnesses use `set -u` alone, never `set -e`/`pipefail` — grep's nonzero exit on zero
matches does not abort the script. If a harness in this repo ever adds `set -e`, this pattern
would need revisiting (grep -c exiting 1 on a genuine zero-match count would kill the script,
and `|| echo 0` is explicitly the wrong fix per this repo's rule 5 — it double-prints on the
zero case). Then loop `_n=1; while [ "$_n" -le "$COUNT" ]; do ...; _n=$((_n+1)); done`, reusing
an existing per-ordinal extractor function unmodified — the ordinal *mechanism* inside the
extractor is not the defect; the defect was a caller hardcoding which ordinal means which mode.

**Rule 19 (leave a comment where a deleted assertion stood) applies even when nothing was
actually deleted, only re-expressed.** No coverage was lost converting ordinal to enumeration
here (S1/S2 became a generic S1/S2/S3 loop, still checking every block), but the plan still
required a comment at the old call site naming the ADR, because the *labelling knowledge*
("ordinal 1 = review, ordinal 2 = diagnose") was deleted and a future reader hitting the old
line numbers in history needs the pointer. Treat rule 19 as covering deleted *assumptions*,
not only deleted *assertions*.

See [[task1-codex-audit-mode-slug]] for the sibling memory from the same feature (stub-CLI
pattern, ADR-0154 back-reference requirement) — both were written spec/plan-first for the same
ADR-0193 feature.
