# Plan: RTF's gitignore glob and this repo's own entry differ by a dash (issue #287)

ADR: `docs/architecture/ADR-0118-287-rtf-gitignore-glob-resolution.md`

Anchor: `staging/plugin/scripts/tests/triage-state-gitignore.test.sh` (extend, never replace; T0
through T14 and the existing `Z1` floor concept must keep passing byte-for-byte as written today).

Measured baseline (re-run this at the start of Task 1 — the substrate moves underneath, per this
repo's own recurring lesson):

```
grep -n 'triage-fix-last' .gitignore
# 7:.claude/.triage-fix-last*.json
# 36:.claude/.triage-fix-last-*.json
git check-ignore -v -- ".claude/.triage-fix-last-feat_222-vendor-deployed-only-skills.json"
# .gitignore:36:.claude/.triage-fix-last-*.json	<path>
git check-ignore -v -- ".claude/.triage-fix-lastFOO.json"
# .gitignore:7:.claude/.triage-fix-last*.json	<path>
bash staging/plugin/scripts/tests/triage-state-gitignore.test.sh   # PASS=18 FAIL=0 today
```

Two entries, not one. Line 7 (`ac207d5`, initial commit) is a strict coverage superset of line 36
(`a482dbb`, PR #251 dogfood chore). T5, already in the harness, already proves line 7 alone
suppresses the append for a real per-branch filename. See ADR-0118 for the full reasoning.

---

### Task 1 — RED: pin today's redundant duplicate as a failing assertion (R-01)

Extend `triage-state-gitignore.test.sh` with a new assertion, placed after `T14` and before the
`Z1` block:

```sh
# ==================================================================================================
# T15. This repository's own .gitignore holds exactly ONE .triage-fix-last covering rule, not two.
# Commit a482dbb (PR #251, the #222 dogfood chain) hand-added the script's own glob without
# checking that the broader rule at line 7 (present since the initial commit) already covered it —
# ADR-0118. COUNT ONLY NON-COMMENT LINES, deliberately: a plausible explanatory comment near the
# surviving rule could easily mention "triage-fix-last" by name (the wording chosen for Task 2's fix
# happens not to, but a future edit might), and a naive `grep -c` over the whole file would then
# read 2 again after the fix (1 rule + 1 comment) — falsely reporting the bug as still open. That is
# the exact rule-12 shape ("a scan whose needle also matches an explanatory comment about itself")
# this repository's own history keeps finding (SA10, N9, GR1/GR5, SP1). Excluding comment lines
# closes it regardless of what any future comment says.
# ==================================================================================================
T15_N=$(grep -v '^#' "$REPO/.gitignore" | grep -c 'triage-fix-last')
if [ "${T15_N:-0}" -eq 1 ]; then
  ok "T15: this repository's .gitignore holds exactly one triage-fix-last covering rule"
else
  bad "T15: $T15_N triage-fix-last covering rule(s) in $REPO/.gitignore — expected 1 (see ADR-0118)"
fi
```

Run the harness. Confirm: **T15 fails today** (`T15_N=2`), and T0-T14 plus the existing `Z1`
(unmodified floor, still `>= 15`) all still pass. No plant on T15 — it reads the real, committed
`.gitignore` directly; see ADR-0118 Alternative 4 for why this mirrors `T12`'s own precedent in the
same file rather than needing `plant-check.sh` extended.

Budget: staging/plugin/scripts/tests/triage-state-gitignore.test.sh (~20 lines)

### Task 2 — GREEN: resolve to one rule (R-01)

Edit `/Users/stefer/Developer/vibe-coding-system/.gitignore`:

1. Delete line 36 (`.claude/.triage-fix-last-*.json`, the last line of the file) entirely.
2. Immediately above line 7, insert exactly this comment (the wording deliberately avoids the
   literal substring `triage-fix-last` and the literal glob string, so it cannot itself be
   mistaken by `T15`/`T12`'s patterns for a second rule — though both already guard against that
   regardless of wording, per Task 1's note):

   ```
   # Covers RTF's per-branch state files too (triage-state.sh's own glob is a strict subset of
   # this pattern) — do not add a second, narrower entry for it (ADR-0118).
   .claude/.triage-fix-last*.json
   ```

Result: the file's only `.triage-fix-last` rule is `.claude/.triage-fix-last*.json`, with the
explanatory comment directly above it.

Run the harness. Confirm: **T15 now passes** (count is 1, comment line excluded by `grep -v '^#'`),
and T0-T14 / `Z1` are unaffected (none of them read line 36, and `T12`'s `[a-z]`-anchored pattern
does not match the new comment's wording).

Budget: .gitignore (~3 lines changed: 1 removed, 2 added)

### Task 3 — Forward guard: the real file still covers a realistic per-branch name (R-01)

Extend the harness with a second real-file assertion, immediately after T15:

```sh
# ==================================================================================================
# T16. Forward guard: the surviving rule still covers a REALISTIC per-branch filename, on the real,
# committed .gitignore — not a fixture. Protects against a future edit that narrows or removes the
# rule entirely while "cleaning up" the file. No plant: this checks byte content of one specific
# real file, not a re-creatable mechanism (same precedent as T12/T15 — see ADR-0118 Alternative 4).
# ==================================================================================================
if git -C "$REPO" check-ignore -q -- ".claude/.triage-fix-last-zzz-regression-probe.json"; then
  ok "T16: the real .gitignore still ignores a realistic per-branch state filename"
else
  bad "T16: a realistic per-branch state filename is NOT ignored by $REPO/.gitignore"
fi
```

This should pass both before and after Task 2 (both line 7 and line 36 already cover this shape
today; only line 7 does after the fix) — it is a forward guard, not evidence the fix landed. Run
the harness and confirm it passes now.

Budget: staging/plugin/scripts/tests/triage-state-gitignore.test.sh (~10 lines)

### Task 4 — R-02 fixture: multiple pre-existing covering rules, correctly chosen seed (R-02)

Add a new fixture-based assertion generalizing `T5`-`T8` (one pre-existing rule suppresses the
append) to the shape this repository's own history actually produced: **two** differently-shaped
pre-existing rules coexisting. State explicitly, in the test file, what the seed must NOT be:

- It must **not** replay this repository's exact historical pair (`.claude/.triage-fix-last*.json`
  together with the literal `.claude/.triage-fix-last-*.json`), because `triage-state.sh`'s `elif`
  branch does a **literal** grep for the exact glob string as a fallback when `check-ignore` reports
  "not ignored" — if that exact string is one of the two seeded lines, the literal-grep fallback
  ALSO recognizes it and suppresses the append, so a plant reverting the `check-ignore` branch to
  `if false; then` would be masked and the assertion would pin nothing. This is ADR-0094's own
  named "seeding the script's own glob" dead draft, reproduced one level up in a two-rule shape.
- It must instead seed **two rules, neither of which is the literal `.claude/.triage-fix-last-*.json`
  string** — reusing `T5`'s and `T6`'s own forms together (`.claude/.triage-fix-last*.json` plus
  `.claude/`) satisfies this and needs no new seed shape to be invented.

`mk_repo()` today takes a single seed argument (`printf '%s\n' "$1" >"$_r/.gitignore"`). It does
**not** need widening: bash preserves a literal embedded newline inside a single-quoted string as
part of one `$1` argument, so passing both seed lines as one multi-line single-quoted string
produces exactly two `.gitignore` lines through the existing implementation unchanged. Verify this
by inspecting the fixture's `.gitignore` once (`cat`) before trusting the line count — a quoting
mistake here would look like a passing assertion for the wrong reason.

```sh
# ==================================================================================================
# T17. TWO pre-existing, differently-shaped covering rules together — the shape this repository's
# own history actually produced (ADR-0118) — still suppress the append; no third line is added.
# SEED CHOICE, explicitly: neither line is the script's own literal glob
# (.claude/.triage-fix-last-*.json). Seeding that exact string would let the elif's literal-grep
# fallback mask a disabled check-ignore branch — ADR-0094's named dead draft, one level up. See the
# `# plant:` declaration below: it reverts check-ignore to `if false` and MUST still be caught,
# because neither seed line equals the literal fallback string either.
# ==================================================================================================
R17=$(mk_repo '.claude/.triage-fix-last*.json
.claude/')
cycle "$R17" feat_probe
T17_N=$(gi_lines "$R17")
if [ "${T17_N:-0}" -eq 2 ]; then
  ok "T17: two differently-shaped pre-existing rules together suppress the append (no third line)"
else
  bad "T17: appended beside two pre-existing rules: $(tr '\n' '|' <"$R17/.gitignore")"
fi
# plant: T17 | plugin/skills/review-triage-fix/scripts/triage-state.sh | if git -C "$d" check-ignore -q -- "$(basename "$SF")" 2>/dev/null; then | if false; then
```

Run the harness: **T17 passes** against the current, correct `triage-state.sh` (a forward guard,
not RED-then-GREEN — the mechanism was never broken; only the test coverage was missing).

Then run `plant-check.sh` (or manually apply the same substitution to a throwaway copy) and confirm
the T17 plant **fires** — i.e. that reverting the `if git -C "$d" check-ignore ...` line to `if
false; then` makes the resulting `.gitignore` grow to 3 lines, and T17 goes from PASS to FAIL under
that mutation. This is the "inspect what the plant actually produced" step (ADR-0108) — do not mark
this task done on the strength of T17 passing alone; the plant firing is the actual proof the
assertion pins something.

Budget: staging/plugin/scripts/tests/triage-state-gitignore.test.sh (~35 lines)

### Task 5 — Raise the assertion-count floor (R-01, R-02)

`Z1`'s floor moves from `>= 15` to `>= 18` (buffer of 2, matching the original file's own buffer —
17 pre-existing assertions had a floor of 15; 20 assertions after Tasks 1/3/4 add T15, T16, T17 get
a floor of 18). Update the message text accordingly ("expected >= 18"). Confirm `Z1` reports the
new total (20) and still passes.

Budget: staging/plugin/scripts/tests/triage-state-gitignore.test.sh (~3 lines)

### Task 6 — Plant registry sanity (R-02)

Confirm `plant-check.sh`'s `PC0` collector count increases by exactly one (the new `# plant: T17 |
...` declaration) and stays `>= 10`. Run `bash staging/plugin/scripts/tests/plant-check.sh` in full
and confirm every existing plant (all ~110 of them, unrelated to this feature) still fires as
before — this task changes zero other test files, so a regression here would indicate a mistake in
how the new declaration was written (malformed field, wrong path, needle not found), not a real
collision.

Budget: none (verification only, no file changes beyond what Task 4 already made)

### Task 7 — Full-suite and CI-registration sanity pass (R-01, R-02)

1. Run the project's test command in full: `for t in staging/plugin/scripts/tests/*.test.sh; do
   bash "$t" || exit 1; done`. Confirm every `*.test.sh` file passes, not just
   `triage-state-gitignore.test.sh` — no other harness reads `.gitignore` or `triage-state.sh`
   today, so this is a pure regression check.
2. Re-confirm `T13`/`T14` (already in the file, unmodified) still hold: `triage-state-gitignore` is
   named in `docs-ci.yml`'s explicit `shell-tests` list, and `ci.yml` globs `*.test.sh` — no new CI
   registration is needed since this task adds zero new files.
3. `git status --porcelain` should show exactly two changed paths: `.gitignore` and
   `staging/plugin/scripts/tests/triage-state-gitignore.test.sh`. Anything else is out of scope for
   this feature and should not be part of this change.

Budget: none (verification only)

---

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: sonnet

PROPOSED AUDIT PROFILE:
- risk: low — a bash test-harness extension plus a one-line `.gitignore` config edit; fully
  reversible via git, no production runtime path, no user-facing behaviour change beyond git-ignore
  hygiene.
- task_type: boilerplate — mechanical extension of an existing, well-established fixture pattern
  (`mk_repo`/`cycle`/`t_covered`/`gi_lines`, already used by T5-T9) plus a declared plant following
  ADR-0108's fixed grammar; no novel algorithm, no regulated surface, no legacy-integration beyond
  the harness already in place.
