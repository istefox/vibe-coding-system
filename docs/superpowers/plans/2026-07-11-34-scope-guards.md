# Plan — Scope guards: autopilot-build CWD check, project-conductor manifest binding, nightly-autopilot check 6

**Date:** 2026-07-11
**ADR:** [ADR-0030](../../architecture/ADR-0030-34-scope-guards.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/34-scope-guards-autopilot-cwd-check-conduct.spec.md`,
issue #34, confirmed byte-identical)
**Style:** TDD (red → green → checkpoint). Auto mode active, no intermediate HITL inside this plan;
commit/push stay HITL per repo `CLAUDE.md` invariant (see HITL gates, end of file). Three independent
findings, one shared test file, one commit — ADR-0030 §3.4 records why this bundles at the issue's own
granularity rather than splitting into three ADRs/plans/commits.

**Task checklist (eight tasks — checked off by the coder as each completes; both `concept-to-code`
SKILL.md's Step 5 pre-dispatch check and `autopilot-build` SKILL.md's Check 5 grep this file for
`- [ ]`, so every task gets one, unlike this plan's own prose elsewhere):**

- [x] Task 1 — RED: Section A (`scope-guards.test.sh`, new file) — autopilot-build Check 1 fixtures.
- [x] Task 2 — GREEN: fix `autopilot-build/SKILL.md` Check 1 + reconcile `GUIDA-USO-IT.md`.
- [x] Task 3 — RED: Section B — project-conductor manifest-binding fixtures.
- [x] Task 4 — GREEN: fix `project-conductor/SKILL.md` at all three call sites.
- [x] Task 5 — RED: Section C — nightly-autopilot check-6 fixtures.
- [x] Task 6 — GREEN: fix `nightly-autopilot/SKILL.md` check 6.
- [x] Task 7 — Wire `docs-ci.yml`, full regression sweep, bash-safety sweep, scope verification.
- [x] Task 8 — SPEC.md checkbox update, final report.

---

## Why every RED in this plan is genuine RED (except explicitly-labeled companions)

Every genuine-RED assertion below was traced by hand against the real, unfixed files during planning
(ADR-0030 §1 reproduces all three defects directly, including a full scenario table for Finding A).
Three assertions (A3, B5, C4/C5) are **non-regression companions**: A3 (exact-match CWD) already
passes today because the original code's first `!=` check already short-circuits that one case to "no
abort"; B5 (`export-csv` binding to its own manifest) and C4/C5 (`hook_verified: false`/`true` both
passing when exactly one well-formed manifest exists) exist to pin the happy path so the fix cannot
silently make everything fail closed, not to prove a defect. Each task states explicitly which category
its own assertions fall into.

## Fixture and path conventions (read once, applies to every task below)

- **File to create:** `staging/plugin/scripts/tests/scope-guards.test.sh` (new file — this is a fresh
  file, not an extension of an existing one; SPEC.md names three findings across three different
  `SKILL.md` files with no existing shared test file to extend).
- **Header, path derivation, PASS/FAIL idiom** (copy verbatim from
  `concept-to-code-bsd-autopilot-gates.test.sh`'s own preamble, the closest structural precedent —
  multi-finding, lettered sections, static + dynamic mix):
  ```bash
  #!/bin/bash
  set -u

  SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
  STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
  AB_SKILL="$STAGING/plugin/skills/autopilot-build/SKILL.md"
  PC_SKILL="$STAGING/plugin/skills/project-conductor/SKILL.md"
  NA_SKILL="$STAGING/plugin/skills/nightly-autopilot/SKILL.md"

  PASS=0; FAIL=0
  ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
  bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  ```
  Full header comment block (file docstring, six lines summarizing the three sections with their
  finding numbers) is specified in Task 1's contract — do not skip it; every existing file in this
  directory has one and `ADR-0030` cites finding numbers 2.5/P2, 3.10, 3.11 that belong in it verbatim.
- **Placeholder substitution idiom — reuse verbatim, do not invent a new one:** this repo's own
  established technique (`concept-to-code-bsd-autopilot-gates.test.sh`'s `extract_slug_stamp`/A3) is
  bash's native `${VAR//<placeholder>/$replacement}` global substitution (bash 3.2-safe — this specific
  `${var//pattern/string}` form has existed since bash 2.x, unlike `${var,,}`/`mapfile`/`declare -A`),
  applied to the output of an `awk`-based fence extractor, written to a temp `.sh` file, then executed
  with `bash <tempfile>`. Do not use raw `sed` substitution for this (delimiter-escaping risk against
  paths containing `/`) and do not use bare `eval` (precedent uses a temp file + `bash`, not `eval`).
- **Bash 3.2 / BSD safety (every file touched this plan):** no `${var,,}`, no `mapfile`, no `<()`, no
  `declare -A`, no GNU-only regex shorthands (`\s`, `\d`) in any `grep -E`/`awk` pattern — plain
  `grep -q`/`grep -c` (BRE) and `awk` with `-v` variable passing only, matching every existing file in
  this directory.
- **Per-task checkpoint (three checks, all must pass before moving to the next task):**
  1. `bash -n <every file touched this task>` (for `.sh` files only — `SKILL.md`/`GUIDA-USO-IT.md` are
     not shell scripts, skip `bash -n` for those, use the content-diff check in each task instead).
  2. `grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' <changed .sh file>` — must be empty.
  3. `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — must stay green, unchanged (this
     plan adds zero `PAIRS` entries anywhere — ADR-0030 §2.4 records why).

## Pre-flight constraints

- Confirmed baseline before Task 1 (re-verified during planning, not assumed):
  `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` → 8/8 files green
  (this is also `.claude/test-cmd`'s literal content — confirmed by reading the file).
- Writes are confined to: `staging/plugin/scripts/tests/scope-guards.test.sh` (new),
  `staging/plugin/skills/autopilot-build/SKILL.md`, `staging/plugin/skills/project-conductor/SKILL.md`,
  `staging/plugin/skills/nightly-autopilot/SKILL.md`, `docs/GUIDA-USO-IT.md`,
  `.github/workflows/docs-ci.yml`, `SPEC.md` (checkbox updates, final task), `docs/architecture/` and
  `docs/superpowers/plans/` (already written by this ADR/plan pass).
- Do not touch: any file under `~/.claude` (the deployed copies stay defective until a separate,
  human-gated `sync-to-claude.sh --apply` — same convention as ADR-0025/26/27/28/29),
  `staging/plugin/scripts/hook-verify-workflow.sh` and its own test file (issue #33 territory,
  explicitly out of scope for issue #34 per SPEC.md's own "Out" section — this plan only *reads* the
  concept of that script's statelessness, in a comment, never edits it),
  `staging/sync-to-claude.sh` and `staging/plugin/scripts/tests/pairs-completeness.test.sh` (confirmed
  by reading both before this plan was written that no new `PAIRS` entry is needed — ADR-0030 §2.4; the
  new test file's three closest structural siblings are *also* absent from `PAIRS`),
  `staging/plugin/skills/autopilot-build/tests/run-tests.sh` and
  `staging/plugin/skills/concept-to-code/SKILL.md` (both confirmed compatible with this fix by reading
  before this plan was written — ADR-0030 §1 "Cross-check" — no edit needed to either),
  `.claude/test-cmd` (its existing wildcard glob already covers the new file by pattern, confirmed by
  reading it — no edit needed), any historical ADR (immutable records; ADR-0020 and ADR-0029 are
  **related to, not amended by**, this ADR — neither needed a correction, per ADR-0030 §1), any file
  under `docs/manifests/` (manifest state transitions are outside this plan's scope — this plan edits
  skill *instructions*, not any specific project's runtime manifest).
- `autopilot-build/SKILL.md` edits are scoped exactly to Check 1's body (current lines 53-63) — the
  heading line (51), the "Do NOT invoke" bullets, the prerequisites bullet (34, already correct), Checks
  2 through 8, the verification checklist (316-329), and everything else in the file are
  **byte-identical, untouched**. Confirm with a targeted diff in Task 7's checkpoint.
- `project-conductor/SKILL.md` edits are scoped exactly to the three `ls -t ...` one-liners (current
  lines 59, 164, 247) and, at each site, the one following sentence that says "Read `current_step` from
  the manifest" (update each to read from `$_manifest`, handling the empty case exactly as that site's
  existing prose already does for "not found"). Nothing else in the file changes — not Step 0's
  reconciliation loop structure, not Step 3's gate prose, not Step 5's branches A/B/C bodies, not the
  Invariants section.
- `nightly-autopilot/SKILL.md` edits are scoped exactly to check 6 (current lines 103-104, one bullet,
  no fence today). Checks 1-5, 7, 8, Phase P, Phase 1, Phase 2, and the Safety invariants section are
  **byte-identical, untouched**.
- `docs/GUIDA-USO-IT.md` edits are scoped exactly to the two identified sentences (current lines
  262-263 and 800-803) — reconcile the missing "or subdirectory of it" exception only; do not rewrite
  either surrounding paragraph further.

## Anchor invariants (HARD — must stay true after every task)

- `bash staging/plugin/scripts/tests/phase1.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/prep.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/hook-probe.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh` → exit 0, unchanged 39/39
  (untouched by this plan — issue #33 territory, explicitly out of scope here).
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` → exit 0, unchanged (no new `PAIRS`
  entries added at any point in this plan).
- `bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` → exit 0, unchanged
  17/17 (untouched by this plan).
- `bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` → exit 0,
  unchanged 21/21 (untouched by this plan).
- `git status` shows changes only under the Pre-flight "writes are confined to" list. Nothing under
  `~/.claude` is ever touched.

---

## Task 1 — RED: Section A (`scope-guards.test.sh`, new file) — autopilot-build Check 1 fixtures

- [x] Create `staging/plugin/scripts/tests/scope-guards.test.sh` with the file header, path
  derivation/PASS-FAIL preamble ("Fixture and path conventions" above), and Section A's six
  assertions (genuine RED for A4/A5/A6; A1/A2 genuine RED against today's text; A3 a non-regression
  companion, already passing).

**Files modified:**
- `staging/plugin/scripts/tests/scope-guards.test.sh` (new).

**Contract — file docstring (top of file, immediately after the shebang, before `set -u`):**
```bash
# scope-guards test harness (ADR-0030) -- three findings from the concept-to-code audit
# (SPEC.md / issue #34). Three lettered sections:
#   Section A (Finding 2.5, P2, ~6 tests) -- autopilot-build/SKILL.md Check 1's scope guard was
#     inverted (compared containment in the wrong direction) and not slash-anchored: a session
#     opened at a PARENT of project_root (allowed by ADR-0020) aborted; a session opened INSIDE
#     project_root, or at an unrelated sibling directory sharing a name prefix, both wrongly
#     passed. Fixed to a `case`-based, quoted, slash-anchored containment test.
#   Section B (Finding 3.10, ~6 tests) -- project-conductor/SKILL.md's three manifest-lookup call
#     sites globbed by bare substring (*<topic-slug>*.manifest.yml), so a feature slug that is a
#     hyphen-prefix of another feature's slug (e.g. "export" / "export-csv") could bind to the
#     wrong manifest and silently mark a feature complete, or auto-resume the wrong chain, without
#     it ever having run. Fixed with a naming-convention-anchored glob plus an exact-match check
#     against the candidate manifest's own topic: field.
#   Section C (Finding 3.11, ~6 tests) -- nightly-autopilot/SKILL.md pre-flight check 6 named a
#     "global smoke-test record written by hook-verify-workflow.sh" that does not exist (verified:
#     that script is deliberately read-only and stateless -- ADR-0029 Section 1 "Gap flagged for
#     issue #34"; hook-verify-workflow.sh internals are out of scope for issue #34 -- SPEC.md
#     "Out"). Fixed with a concrete, roadmap-wide hook_verified validity check over whatever
#     manifests currently exist, and an explicit, non-blocking zero-manifest branch for Phase P's
#     pre-any-feature pre-flight moment (ADR-0030 Section 2.3/3.3).
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Never point any variable at $HOME/.claude/... -- that is the deployed copy, out of scope.
# Bash 3.2 clean. Run: bash scope-guards.test.sh
```

**Contract — Section A, insert verbatim after the preamble:**
```bash
# =====================================================================================
# Section A -- Finding 2.5 (P2): autopilot-build Check 1 scope guard
# =====================================================================================

extract_check1() {
  awk '
    /^\*\*Check 1 / { grab=1; next }
    grab && /^```bash/ { infence=1; next }
    grab && infence && /^```/ { exit }
    grab && infence { print }
  ' "$AB_SKILL"
}

# run_check1 <manifest-path> -- substitutes <manifest-path>, writes the result to a temp script,
# and appends a trailing `exit 0` OUTSIDE the extracted text (harness-only normalization: the
# extracted snippet's own last-executed statement is ambiguous on the pass path -- an `if` guard
# whose condition is false has exit status 1 even though no SCOPE ERROR fires and no `exit 1`
# runs; the production contract does not need its own trailing exit 0, since the real caller reads
# printed output, not a raw $?, exactly as the ORIGINAL, buggy code already required -- see
# ADR-0030 Consequences/Negative and this plan's Risk register). The abort path's own internal
# `exit 1` still fires first and this appended line is never reached in that case.
# Caller must `cd` to the desired CWD before calling.
run_check1() {
  RAW="$(extract_check1)"
  CMD="${RAW//<manifest-path>/$1}"
  printf '%s\nexit 0\n' "$CMD" > "$TMP/check1-cmd.sh"
  bash "$TMP/check1-cmd.sh"
}

# A1 (static, genuine RED now): the old inverted, unquoted, unanchored containment test is gone.
if grep -qF '${cwd_n##$project_root_n}' "$AB_SKILL"; then
  bad "A1: old inverted, unquoted containment test is still present in Check 1"
else
  ok "A1: old inverted, unquoted containment test is gone from Check 1"
fi

# A2 (static, genuine RED now): the new, quoted, slash-anchored case pattern is present.
if grep -qF '"$cwd_n"/*)' "$AB_SKILL"; then
  ok "A2: new quoted, slash-anchored containment test is present in Check 1"
else
  bad "A2: new quoted, slash-anchored containment test should be present in Check 1"
fi

# Fixture: $TMP/a/proj (the project), $TMP/a/proj/sub (a child), $TMP/a/proj-backup (a sibling
# sharing a hyphenated name prefix). Resolved through `cd && pwd -P` so the fixture manifest and
# the script's own `pwd -P` agree (macOS mktemp -d gives /var/folders/... which pwd -P resolves to
# /private/var/folders/... -- same gotcha stop-gate.sh/triage-state.sh already document).
mkdir -p "$TMP/a/proj/sub" "$TMP/a/proj-backup"
PROJ_REAL=$(cd "$TMP/a/proj" && pwd -P)
A_MANIFEST="$TMP/a/fixture.manifest.yml"
printf 'project_root: "%s"\n' "$PROJ_REAL" > "$A_MANIFEST"

# A3 (dynamic, non-regression companion, already passing today): exact match, CWD == project_root
# => PASS (exit 0). Already true today too (the old code's first `!=` check already short-circuits
# this one case to "no abort") -- pinned here so the rewrite cannot silently break it.
( cd "$PROJ_REAL" && run_check1 "$A_MANIFEST" ) >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "A3: CWD == project_root => PASS (exit 0)" || bad "A3: CWD == project_root should PASS"

# A4 (dynamic, genuine RED): parent CWD, project_root beneath it => PASS (exit 0). ADR-0020 D3 #1
# explicitly allows this; today's bug aborts it.
( cd "$TMP/a" && run_check1 "$A_MANIFEST" ) >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "A4: parent CWD, project_root beneath it => PASS (exit 0)" || bad "A4: parent CWD should PASS"

# A5 (dynamic, genuine RED): child CWD, project_root above it => ABORT (exit 1). Today's bug passes
# this silently.
( cd "$PROJ_REAL/sub" && run_check1 "$A_MANIFEST" ) >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "A5: child CWD, project_root above it => ABORT (exit 1)" || bad "A5: child CWD should ABORT"

# A6 (dynamic, genuine RED): sibling directory sharing a hyphenated name prefix => ABORT (exit 1).
# Today's bug passes this silently (unanchored prefix strip).
( cd "$TMP/a/proj-backup" && run_check1 "$A_MANIFEST" ) >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "A6: sibling 'proj-backup' => ABORT (exit 1)" || bad "A6: sibling directory should ABORT"
```

**Expected now (RED):** A1 fails (old string still present). A2 fails (new string absent). A3
passes (already true). A4 fails (`RC=1` not `0`). A5 fails (`RC=0` not `1`). A6 fails (`RC=0` not
`1`).

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/scope-guards.test.sh
bash staging/plugin/scripts/tests/scope-guards.test.sh
# expect: PASS=1 (A3) FAIL=5 (A1, A2, A4, A5, A6)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 2 — GREEN: fix `autopilot-build/SKILL.md` Check 1 + reconcile `GUIDA-USO-IT.md`

- [x] Replace Check 1's body with the corrected, `case`-based containment test; reconcile the two
  `docs/GUIDA-USO-IT.md` prose sites that describe the same contract.

**Files modified:**
- `staging/plugin/skills/autopilot-build/SKILL.md`
- `docs/GUIDA-USO-IT.md`

**Contract — `autopilot-build/SKILL.md`, replace the fenced bash block under the "Check 1" heading
(current lines 53-63) with:**
```bash
# Extract project_root from the manifest file directly (no yq dependency)
project_root=$(grep '^project_root:' "<manifest-path>" | sed 's/project_root: *"//' | sed 's/".*//' | sed "s/project_root: *//")
cwd=$(pwd -P)
# Normalize: strip trailing slash
project_root_n="${project_root%/}"
cwd_n="${cwd%/}"
# PASS iff cwd == project_root, or project_root is strictly under cwd (slash-anchored, quoted
# pattern side). ADR-0020 D3 #1: "Session CWD equals manifest.project_root or is a parent of it."
in_scope=false
if [ "$cwd_n" = "$project_root_n" ]; then
  in_scope=true
else
  case "$project_root_n" in
    "$cwd_n"/*) in_scope=true ;;
  esac
fi
if [ "$in_scope" = false ]; then
  echo "SCOPE ERROR: manifest project_root ($project_root) is not this session's CWD ($cwd) and is not a subdirectory of it. Open a new session inside a directory at or above $project_root and run autopilot-build from there."
  exit 1
fi
```
Do **not** add a trailing `exit 0` to this production contract — that normalization lives only in the
test harness's `run_check1` helper (Task 1), for the reason recorded there and in this plan's Risk
register. The heading line itself (`**Check 1 — Scope guard (run FIRST, before reading the
manifest):**`) is unchanged.

**Contract — `docs/GUIDA-USO-IT.md`, current lines 262-263, replace:**
```
1. **Scope guard** (primo, prima di leggere il manifest): `project_root` nel manifest deve
   corrispondere alla CWD della sessione. Se non coincide: abort con SCOPE ERROR.
```
with:
```
1. **Scope guard** (primo, prima di leggere il manifest): `project_root` nel manifest deve
   coincidere con la CWD della sessione, oppure esserne una sottodirectory. In ogni altro caso:
   abort con SCOPE ERROR.
```

**Contract — `docs/GUIDA-USO-IT.md`, current line 802 only (the exact physical line — line 801
ends "...corrente. Se il" and line 803 starts "vale anche per...", both unchanged; only the single
physical line 802 in between is replaced):**
```
`project_root` nel manifest non coincide con la CWD, la chain abortisce con SCOPE ERROR. Questo
```
with:
```
`project_root` nel manifest non coincide con la CWD né ne è una sottodirectory, la chain abortisce con SCOPE ERROR. Questo
```
(Reassembled, the full sentence reads: "...Se il `project_root` nel manifest non coincide con la CWD
né ne è una sottodirectory, la chain abortisce con SCOPE ERROR. Questo vale anche per i sub-agent di
workflow.")

**Expected (GREEN):** A1, A2, A4, A5, A6 pass; A3 unchanged (was already passing).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/scope-guards.test.sh
# expect: PASS=6 FAIL=0 (Section A complete; Sections B/C not yet added)
grep -n 'oppure esserne una sottodirectory\|né ne è una sottodirectory' docs/GUIDA-USO-IT.md
# expect: two matches, at the two corrected sites
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 3 — RED: Section B — project-conductor manifest-binding fixtures

- [x] Append Section B's six assertions to `scope-guards.test.sh` (genuine RED for B1, B2, B3, B4,
  B6; B5 a non-regression companion pinning the happy path).

**Files modified:**
- `staging/plugin/scripts/tests/scope-guards.test.sh` (append).

**Contract — insert verbatim, after Section A:**
```bash
# =====================================================================================
# Section B -- Finding 3.10: project-conductor manifest binding
# =====================================================================================

extract_conductor_lookup() {
  awk '
    /^### Step 5 — Evaluate chain outcome/ { grab=1 }
    grab && /^```bash/ { infence=1; next }
    grab && infence && /^```/ { exit }
    grab && infence { print }
  ' "$PC_SKILL"
}

# run_conductor_lookup <root> <slug> -- runs the extracted lookup with `_root` preset to <root> and
# <topic-slug> substituted with <slug>, then prints the resulting $_manifest value on stdout (empty
# if nothing bound). Test fixture roots are always plain mktemp -d paths (no spaces/quote
# characters), so a simple double-quoted assignment is sufficient -- no shell-escaping helper
# needed for this harness's own controlled inputs.
run_conductor_lookup() {
  RAW="$(extract_conductor_lookup)"
  CMD="${RAW//<topic-slug>/$2}"
  {
    printf '_root="%s"\n' "$1"
    printf '%s\n' "$CMD"
    printf 'printf "%%s" "$_manifest"\n'
  } > "$TMP/conductor-cmd.sh"
  bash "$TMP/conductor-cmd.sh"
}

# B1 (static, genuine RED now): the old bare-substring glob is gone from all 3 call sites.
_old_count=$(grep -cF 'ls -t "$_root"/docs/manifests/*<topic-slug>*.manifest.yml' "$PC_SKILL")
[ "$_old_count" -eq 0 ] && ok "B1: old bare-substring glob is gone from all call sites" \
  || bad "B1: old bare-substring glob still present at $_old_count site(s)"

# B2 (static, genuine RED now): the new anchored glob is present at all 3 call sites.
_new_count=$(grep -cF '"$_root"/docs/manifests/????-??-??-"$_slug".manifest.yml' "$PC_SKILL")
[ "$_new_count" -eq 3 ] && ok "B2: anchored glob is present at all 3 call sites" \
  || bad "B2: anchored glob expected at 3 call sites, found $_new_count"

# B3 (static, genuine RED now): the topic-field verification is present at all 3 call sites.
_verify_count=$(grep -cF "grep '^topic:' \"\$_cand\"" "$PC_SKILL")
[ "$_verify_count" -eq 3 ] && ok "B3: topic-field verification is present at all 3 call sites" \
  || bad "B3: topic-field verification expected at 3 call sites, found $_verify_count"

# Fixture: two manifests in the same docs/manifests/ dir -- "export" and "export-csv" -- the exact
# collision SPEC.md finding 3.10 names.
mkdir -p "$TMP/b/root/docs/manifests"
B_ROOT="$TMP/b/root"
printf 'topic: "export"\nproject_root: "%s"\n' "$B_ROOT" > "$B_ROOT/docs/manifests/2026-07-01-export.manifest.yml"
printf 'topic: "export-csv"\nproject_root: "%s"\n' "$B_ROOT" > "$B_ROOT/docs/manifests/2026-07-02-export-csv.manifest.yml"

# B4 (dynamic, genuine RED): slug "export" must bind to its own manifest, never export-csv's.
B4_OUT=$(run_conductor_lookup "$B_ROOT" "export")
case "$B4_OUT" in
  *export-csv.manifest.yml) bad "B4: slug 'export' wrongly bound to the export-csv manifest" ;;
  *export.manifest.yml) ok "B4: slug 'export' binds to its own manifest, not export-csv" ;;
  *) bad "B4: slug 'export' resolved to unexpected value: $B4_OUT" ;;
esac

# B5 (dynamic, non-regression companion): slug "export-csv" must still bind to its own manifest
# (proves the fix does not just make everything fail closed).
B5_OUT=$(run_conductor_lookup "$B_ROOT" "export-csv")
case "$B5_OUT" in
  *export-csv.manifest.yml) ok "B5: slug 'export-csv' still binds to its own manifest" ;;
  *) bad "B5: slug 'export-csv' should bind to its own manifest (got: $B5_OUT)" ;;
esac

# B6 (dynamic, genuine RED): a manifest whose filename matches the anchored glob but whose internal
# topic: field disagrees (simulated corruption / hand-edit) must NOT bind.
mkdir -p "$TMP/b/root2/docs/manifests"
B_ROOT2="$TMP/b/root2"
printf 'topic: "something-else"\nproject_root: "%s"\n' "$B_ROOT2" > "$B_ROOT2/docs/manifests/2026-07-01-drift.manifest.yml"
B6_OUT=$(run_conductor_lookup "$B_ROOT2" "drift")
[ -z "$B6_OUT" ] && ok "B6: filename-glob match with disagreeing internal topic: field does not bind" \
  || bad "B6: should not bind when internal topic: field disagrees (got: $B6_OUT)"
```

**Expected now (RED):** B1 fails (old glob still present, 3 sites). B2 fails (new glob absent, 0
found). B3 fails (verification absent, 0 found). B4 fails (binds to `export-csv`, the exact
collision). B5 passes (already works — bare substring already matches `export-csv` correctly for its
own exact slug too). B6 fails (today's glob matches the filename and there is no field verification
at all, so it binds when it should not).

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/scope-guards.test.sh
bash staging/plugin/scripts/tests/scope-guards.test.sh
# expect: PASS=7 (6 from Section A + B5) FAIL=5 (B1, B2, B3, B4, B6)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 4 — GREEN: fix `project-conductor/SKILL.md` at all three call sites

- [x] Replace the `ls -t ...` one-liner at all three call sites (Step 0, Step 3, Step 5) with the
  anchored-glob-plus-topic-verification block; update each site's immediately following sentence to
  read `current_step` from `$_manifest`.

**Files modified:**
- `staging/plugin/skills/project-conductor/SKILL.md`

**Contract — replace, verbatim, at all three call sites (current lines 59, 164, 247 — anchor on
content, not line number, since fixing site 1 shifts the line numbers of sites 2 and 3):**
```bash
# Anchor to the manifest naming convention (YYYY-MM-DD-<topic-slug>.manifest.yml) instead of a bare
# substring glob, then verify the winning candidate's own topic: field equals the derived slug
# exactly -- anchoring alone still lets one slug bind to a different slug sharing a hyphen-joined
# prefix (e.g. "export" vs "export-csv"; SPEC.md finding 3.10).
_slug="<topic-slug>"
_cand=$(ls -t "$_root"/docs/manifests/????-??-??-"$_slug".manifest.yml 2>/dev/null | head -1)
_manifest=""
if [ -n "$_cand" ]; then
  _cand_topic=$(grep '^topic:' "$_cand" | sed 's/topic: *"//' | sed 's/".*//' | sed "s/topic: *//")
  [ "$_cand_topic" = "$_slug" ] && _manifest="$_cand"
fi
```
At **Site 1** (Step 0, inside the `for every - [ ] <feature> line` reconciliation loop), the
`<topic-slug>` placeholder is the per-iteration derived slug, exactly as the current buggy one-liner
already uses it there. At **Site 2** (Step 3) and **Site 3** (Step 5), `<topic-slug>` is the slug
already derived from `<next-feature>` per that step's own existing prose, exactly as today.

**Contract — update the sentence immediately following each of the three call sites:**
- Site 1: "Read `current_step` from the manifest." → "Read `current_step` from `$_manifest` (skip
  this feature's reconciliation if `$_manifest` is empty — no verified manifest exists for it yet)."
- Site 2: "Read `current_step`:" → "Read `current_step` from `$_manifest` (empty means no verified
  in-progress manifest — fall through to the standard gate below, exactly as the existing 'no
  manifest' path already does)."
- Site 3: "Read `current_step`." → "Read `current_step` from `$_manifest` (empty falls into branch C
  below, exactly as today's 'manifest not found' case already does)."

Nothing else in Step 0, Step 3, or Step 5 changes — the reconciliation loop structure, the gate
options, and branches A/B/C's own bodies are untouched.

**Expected (GREEN):** B1, B2, B3, B4, B6 pass; B5 unchanged (was already passing).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/scope-guards.test.sh
# expect: PASS=12 (6 Section A + 6 Section B) FAIL=0 (Section C not yet added) -- verified during
# implementation: Section B has 6 assertions (B1-B6), not 7; the "PASS=13 (... 7 Section B)"
# expectation this comment originally carried was an arithmetic error, corrected here per the
# ADR-0029-style "verify against real behavior, not assumed" discipline.
grep -c 'ls -t "\$_root"/docs/manifests/????-??-??-"\$_slug".manifest.yml' staging/plugin/skills/project-conductor/SKILL.md
# expect: 3
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 5 — RED: Section C — nightly-autopilot check-6 fixtures

- [x] Append Section C's six assertions to `scope-guards.test.sh` (genuine RED for C1, C2, C3, C6;
  C4/C5 non-regression companions once a well-formed manifest exists — genuinely RED today too,
  since today's check 6 has no bash at all to execute).

**Files modified:**
- `staging/plugin/scripts/tests/scope-guards.test.sh` (append).

**Contract — insert verbatim, after Section B:**
```bash
# =====================================================================================
# Section C -- Finding 3.11: nightly-autopilot check 6
# =====================================================================================

extract_check6() {
  awk '
    /^6\. \*\*hook_verified known/ { grab=1; next }
    grab && /^7\. / { exit }
    grab && /^[[:space:]]*```bash/ { infence=1; next }
    grab && infence && /^[[:space:]]*```/ { exit }
    grab && infence { print }
  ' "$NA_SKILL"
}
# NOTE (corrected during Task 5/6 execution): the fenced bash block Task 6 adds under check 6 is
# nested inside a numbered-list item, so it is indented 3 spaces, matching every sibling check (3,
# 4, 8) in this file -- the original, unbounded `/^```bash/`/`/^```/`(column-1-only) pair here
# never matched that indentation, and lacked a stop condition at check 7's heading, so pre-fix it
# silently leaked past checks 7/8 into a later, unrelated bash fence elsewhere in the file instead
# of returning empty output. The net RED-state PASS/FAIL pattern this task's checkpoint predicts
# still held (verified by direct execution, not assumed), but the "Do not un-indent Check 6's fix
# to satisfy this regex" choice below only holds once the regex itself tolerates that indentation
# and is bounded at check 7 -- both fixed here, in the extractor, not in the production SKILL.md
# contract (same "fix the test harness, not the shipped contract" discipline as Section A's
# run_check1 trailing-exit-0 normalization).

# run_check6 <root> -- check 6's own contract reads $PWD directly (no <placeholder> to substitute),
# so the harness only needs to `cd` there before executing the extracted body. Unlike run_check1,
# check 6's own guard is phrased as "assert the good condition directly"
# ([ "$_bad" -eq 0 ] || exit 1), which already exits 0 cleanly on its own on the pass path -- no
# trailing-exit-0 normalization needed here (see this plan's Risk register for why Section A does
# need it and Section C does not).
run_check6() {
  ( cd "$1" && bash -c "$(extract_check6)" )
}

# C1 (static, genuine RED now): check 6 gains a runnable bash fence (today it is prose-only).
_c6_fence=$(awk '/^6\. \*\*hook_verified known/{grab=1;next} grab && /^[[:space:]]*```bash/{print "yes"; exit} grab && /^7\. /{exit}' "$NA_SKILL")
[ "$_c6_fence" = "yes" ] && ok "C1: check 6 has a runnable bash fence" || bad "C1: check 6 should have a runnable bash fence"

# C2 (static, genuine RED now): the explicit zero-manifest, non-blocking rule text is present.
grep -q 'no manifests exist yet' "$NA_SKILL" \
  && ok "C2: check 6 documents the explicit zero-manifest, non-blocking rule" \
  || bad "C2: check 6 should document the explicit zero-manifest, non-blocking rule"

# C3 (dynamic, genuine RED): zero manifests => PASS (exit 0), non-blocking.
mkdir -p "$TMP/c/zero/docs/manifests"
run_check6 "$TMP/c/zero" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "C3: zero manifests => PASS (exit 0), non-blocking" || bad "C3: zero manifests should PASS"

# C4 (dynamic, non-regression companion once Section C's fix lands): one manifest,
# hook_verified: false => PASS.
mkdir -p "$TMP/c/false/docs/manifests"
printf 'topic: "x"\nhook_verified: false\n' > "$TMP/c/false/docs/manifests/2026-07-01-x.manifest.yml"
run_check6 "$TMP/c/false" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "C4: hook_verified: false => PASS (exit 0)" || bad "C4: hook_verified: false should PASS"

# C5 (dynamic, non-regression companion once Section C's fix lands): one manifest,
# hook_verified: true => PASS.
mkdir -p "$TMP/c/true/docs/manifests"
printf 'topic: "x"\nhook_verified: true\n' > "$TMP/c/true/docs/manifests/2026-07-01-x.manifest.yml"
run_check6 "$TMP/c/true" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "C5: hook_verified: true => PASS (exit 0)" || bad "C5: hook_verified: true should PASS"

# C6 (dynamic, genuine RED): one manifest, hook_verified field absent/corrupted => ABORT (exit 1).
mkdir -p "$TMP/c/null/docs/manifests"
printf 'topic: "x"\n' > "$TMP/c/null/docs/manifests/2026-07-01-x.manifest.yml"
run_check6 "$TMP/c/null" >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "C6: hook_verified absent/corrupted => ABORT (exit 1)" || bad "C6: corrupted hook_verified should ABORT"
```

**Expected now (RED):** C1 fails (no fence exists at all). C2 fails (no such text exists anywhere in
the file). C3, C4, C5 accidentally appear to "pass" and C6 genuinely fails — with the corrected,
bounded `extract_check6` above (stops at check 7's heading), the pre-fix extraction returns empty
(no fence to extract), so `run_check6` executes an empty script, which has raw exit status 0
unconditionally regardless of fixture. **Verified during implementation, not merely assumed:**
before `extract_check6` was bounded at check 7's heading, it instead leaked past checks 7/8 into a
later, unrelated bash fence elsewhere in the file — a different failure mode than "returns nothing,"
but one that produced the identical net PASS/FAIL pattern by coincidence (the leaked fence also
always exited 0 for C3-C5's fixtures and never exited 1 for C6's). **Do not be misled by C3-C5's
accidental green**: confirm this explicitly in the checkpoint below by also checking
`extract_check6` returns empty output before Task 6, so the accidental pass is understood and not
mistaken for the real fix already working.

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/scope-guards.test.sh
extract_out=$(awk '/^6\. \*\*hook_verified known/{grab=1;next} grab && /^7\. /{exit} grab && /^[[:space:]]*```bash/{infence=1;next} grab && infence && /^[[:space:]]*```/{exit} grab && infence{print}' staging/plugin/skills/nightly-autopilot/SKILL.md)
[ -z "$extract_out" ] && echo "confirmed: check 6 has no fence yet, C3-C5's pass is accidental (empty-script exit 0), not the real fix" || echo "UNEXPECTED: a fence already exists -- stop and re-check before Task 6"
bash staging/plugin/scripts/tests/scope-guards.test.sh
# expect: PASS=15 (12 prior + C3 + C4 + C5, all accidental) FAIL=3 (C1, C2, C6) -- corrected from
# the original "PASS=16 ... FAIL=2" comment, which both inherited the Task 4 off-by-one (13 vs the
# true 12) and undercounted FAIL by one (it already lists three items, C1/C2/C6, but summed them as
# 2).
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 6 — GREEN: fix `nightly-autopilot/SKILL.md` check 6

- [x] Replace check 6's single prose bullet with the concrete bash contract (roadmap-wide validity
  check + documented, non-blocking zero-manifest branch).

**Files modified:**
- `staging/plugin/skills/nightly-autopilot/SKILL.md`

**Contract — replace check 6 in full (current lines 103-104):**
```
6. **hook_verified known (roadmap-wide, pre-flight):**
   ```bash
   _manifests=$(ls "$PWD"/docs/manifests/*.manifest.yml 2>/dev/null)
   if [ -z "$_manifests" ]; then
     echo "note: no manifests exist yet (Phase P has not created any feature manifest). Each"
     echo "feature's manifest defaults hook_verified: false (safe Agent-tool fallback dispatch,"
     echo "ADR-0016) at manifest-init.sh creation time, so there is nothing to validate yet and"
     echo "this is not an abort condition. No global cross-run smoke-test record exists"
     echo "(ADR-0029 Section 1, 'Gap flagged for issue #34') -- hook-verify-workflow.sh is"
     echo "deliberately read-only and stateless; this check does not depend on one existing."
   else
     _bad=0
     for _m in $_manifests; do
       _hv=$(python3 -c "import yaml; m=yaml.safe_load(open('$_m')); print(m.get('hook_verified'))" 2>/dev/null)
       if [ "$_hv" != "True" ] && [ "$_hv" != "False" ]; then
         echo "✗ hook_verified: $_m has hook_verified=$_hv (must be true/false). Manifest is corrupted or was hand-edited; fix or re-init."
         _bad=1
       fi
     done
     [ "$_bad" -eq 0 ] || exit 1
   fi
   ```
   (drives Workflow vs Agent-tool dispatch downstream, per manifest, exactly as before.)
```
The `python3 -c "import yaml..."` idiom and the `"True"`/`"False"` string comparisons are the *same*
ones `autopilot-build/SKILL.md`'s own Check 7 already uses — reused verbatim for consistency, not a
new convention.

**Expected (GREEN):** C1, C2, C3, C4, C5, C6 all pass **for real** now (C3-C5's Task 5 accidental
pass is superseded by the actual fix; re-verify they still pass, this time because the fix's
zero-manifest/false/true branches genuinely execute, not because the script body was empty).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/scope-guards.test.sh
# expect: PASS=18 FAIL=0 -- full file green (6 Section A + 6 Section B + 6 Section C = 18)
```
**Tally check (do this arithmetic explicitly, do not assume):** Section A = 6 (A1-A6). Section B = 6
(B1-B6, all pass once Task 4 lands — B1 through B4 and B6 flip GREEN, B5 stays GREEN throughout).
Section C = 6 (C1-C6). **Total: 18 assertions, 18 passed, 0 failed** once Task 6 lands. If Task 4's
checkpoint reported 12 (6+6=12, consistent) after Section B alone, and this task's total is 18,
the arithmetic is self-consistent (6 + 6 + 6 = 18) — confirm the actual printed `PASS=`/`FAIL=` line
equals this exactly; if it does not, stop and reconcile before Task 7, do not proceed on a mismatched
count. (Corrected during implementation: the original text here read "Section B = 7" and "Total: 19"
— an arithmetic error, since Section B's own Task 3 contract defines exactly six assertions, B1-B6,
not seven. Verified by direct execution: the actual harness prints PASS=18 FAIL=0, confirming 18 is
correct, not 19.)
```bash
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/nightly-autopilot/SKILL.md   # empty (SKILL.md is not a shell script, but keep the sweep habit)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 7 — Wire `docs-ci.yml`, full regression sweep, bash-safety sweep, scope verification

- [x] Add `scope-guards` to `docs-ci.yml`'s explicit `shell-tests` list; run the full local
  test-cmd; sweep for bash 3.2/BSD safety; confirm the changed-file set matches the Pre-flight
  "writes are confined to" list exactly.

**Files modified:**
- `.github/workflows/docs-ci.yml`

**Contract — `docs-ci.yml`, append `scope-guards` as the ninth entry in the `for t in ...` list
(current line 44):**
```
          for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates concept-to-code-manifest-helpers-guards scope-guards; do
```

**Verify (full, repo-wide):**
```bash
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done    # local test-cmd, 9/9 green
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                       # unchanged, exit 0
bash -n staging/plugin/scripts/tests/scope-guards.test.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/tests/scope-guards.test.sh   # empty
grep -nF '<<<' staging/plugin/scripts/tests/scope-guards.test.sh   # empty
echo "bash 3.2 / BSD safety: clean"
diff <(git show HEAD:staging/plugin/skills/autopilot-build/SKILL.md) staging/plugin/skills/autopilot-build/SKILL.md
# manually confirm: only Check 1's body (current lines 53-63) changed; Checks 2-8, the heading, the
# prerequisites bullet, and the verification checklist are untouched.
diff <(git show HEAD:staging/plugin/skills/project-conductor/SKILL.md) staging/plugin/skills/project-conductor/SKILL.md
# manually confirm: only the three ls -t one-liners and their one following sentence each changed.
diff <(git show HEAD:staging/plugin/skills/nightly-autopilot/SKILL.md) staging/plugin/skills/nightly-autopilot/SKILL.md
# manually confirm: only check 6 (current lines 103-104) changed.
diff <(git show HEAD:docs/GUIDA-USO-IT.md) docs/GUIDA-USO-IT.md
# manually confirm: only the two identified sentences (lines ~262-263, ~800-803) changed.
grep -c "scope-guards" .github/workflows/docs-ci.yml   # 1, the new ninth entry
git status   # confirm change set matches Pre-flight "writes are confined to" list; nothing under ~/.claude
```

**Report to dispatcher (accumulate for Task 8):**
- Full local `test-cmd` glob result (9/9 files green) pasted verbatim.
- `scope-guards.test.sh` final tally: expect `PASS=18 FAIL=0` (corrected from the original "19" —
  see Task 6's Tally check note).
- Confirmation each `SKILL.md` diff touches only the region named in Pre-flight's scoping note —
  nothing else.
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted.

---

## Task 8 — SPEC checkbox update, final report

- [x] Check off SPEC.md's satisfied success criteria and produce the final report for the
  dispatcher.

**Files modified:**
- `SPEC.md` — check off the success-criteria boxes genuinely satisfied (expect all 4: the three
  harness-test criteria, one per finding, plus "no file under `~/.claude` modified").

**Report to dispatcher:**
- ADR path: `docs/architecture/ADR-0030-34-scope-guards.md`.
- Plan path: `docs/superpowers/plans/2026-07-11-34-scope-guards.md`.
- Spec path: `SPEC.md` (= `docs/specs/34-scope-guards-autopilot-cwd-check-conduct.spec.md`).
- `scope-guards.test.sh` final tally (`PASS=18 FAIL=0`, corrected from the original "19" — see
  Task 6's Tally check note) and full local test-cmd result (9/9 files green), pasted verbatim
  from Task 7.
- Explicit flag for the human reviewer: Finding C's fix does **not** create the "global smoke-test
  record" SPEC.md's own literal text (`docs/specs/34-*.md:14`) describes — that record does not
  exist anywhere in the system (verified against `hook-verify-workflow.sh`'s own header and ADR-0029
  §1) and this plan deliberately does not invent one (ADR-0030 §3.3 Alt C1). Call this out explicitly
  at review time, since a reviewer skimming SPEC.md's literal wording would expect that record to
  exist after this fix.
- Explicit flag: two `docs/GUIDA-USO-IT.md` sentences were corrected beyond SPEC.md's literally-named
  file list (`staging/plugin/skills/**` only) — a small, disclosed scope nudge (ADR-0030 §2.1),
  reconciling the same contract Finding A's code fix restores.
- Explicit flag: the *deployed* copies (`~/.claude/skills/autopilot-build/SKILL.md`,
  `~/.claude/skills/project-conductor/SKILL.md`, `~/.claude/skills/nightly-autopilot/SKILL.md`) keep
  today's defective behavior until a human runs `sync-to-claude.sh --apply`.
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — wrapping Check 1's extracted snippet in `bash -c` and reading a raw `$?` without the
  `run_check1` helper's trailing `exit 0`.** The snippet's own last-executed statement on the pass
  path is an `if` guard whose *condition* is false (exit status 1), even though no `SCOPE ERROR` was
  printed and no `exit 1` ran — a naive test would see `$?=1` on an actually-passing scenario and
  wrongly report FAIL. **Mitigation:** Task 1's `run_check1` helper appends the trailing `exit 0`
  *only inside the generated test-fixture script*, never inside the production `SKILL.md` contract
  itself (Task 2's contract explicitly says not to add it there); do not "fix" this by adding `exit 0`
  to the shipped Check 1 body — that would be an unrequested behavior change to the actual skill (see
  ADR-0030 Consequences/Negative, last bullet).
- **Risk B — Task 5's C3/C4/C5 accidentally reporting PASS before Task 6 lands, and being mistaken
  for evidence the fix already works.** `extract_check6` returns empty output before Task 6 (no fence
  exists yet, given the corrected extractor that stops at check 7's heading and tolerates the file's
  list-item fence indentation — see Task 5's contract note), so `run_check6` executes an empty
  script, which is a vacuous, unconditional exit 0 — true regardless of which fixture ran. Only C1,
  C2, and C6 are genuine RED at that checkpoint. **Verified during implementation:** the *original*,
  unbounded `extract_check6` (no `^7\. ` stop, no indentation tolerance) did not actually return
  empty pre-fix — it leaked past checks 7/8 into a later, unrelated fence — but produced the
  identical PASS/FAIL pattern anyway, which is why this risk's practical mitigation held even before
  the extractor bug was found and fixed. **Mitigation:** Task 5's checkpoint explicitly greps for the
  empty extraction *before* asserting the tally, and the task's own contract states this plainly; do
  not skip that confirmation step, and do not treat C3-C5 passing at the Task 5 checkpoint as
  informative about Task 6's correctness — only the Task 6 checkpoint's re-run (after the fence
  exists) is real evidence.
- **Risk C — Task 4 applying the corrected lookup block at only one or two of the three
  `project-conductor` call sites.** Because fixing Site 1 shifts the line numbers of Sites 2 and 3,
  and all three snippets are textually identical, it is easy to edit one occurrence and believe the
  job is done. **Mitigation:** Task 4's checkpoint's `grep -c ... # expect: 3` is the automated
  backstop — a count of 1 or 2 means a site was missed; do not proceed to Task 5 until it reads
  exactly 3.
- **Risk D — the `????-??-??-` glob prefix being written with the wrong number of `?` characters**
  (e.g. 8 instead of 10, matching `YYYYMMDD`-without-dashes or truncating a digit), silently breaking
  the anchor for every real manifest (whose actual date prefix is always the fixed `YYYY-MM-DD`
  10-character form `manifest-init.sh` writes). **Mitigation:** Task 3's B4/B5/B6 fixtures use exactly
  that real format (`2026-07-01-...`); a wrong wildcard count fails B4/B5/B6 immediately and loudly,
  rather than silently matching too much or too little in production.
- **Risk E — scope creep into `hook-verify-workflow.sh`, its own test file, or
  `concept-to-code/SKILL.md`.** All three are adjacent, thematically related, and confirmed-safe files
  a coder might be tempted to "clean up while in the area" (Finding C references
  `hook-verify-workflow.sh`'s statelessness in a comment; `concept-to-code/SKILL.md` has its own,
  separate scope-guard prose). **Mitigation:** Pre-flight's "do not touch" list is explicit about all
  three; Task 7's `git status` and targeted `diff`s are the automated backstop.
- **Risk F — the deployed skill keeps all three defects until sync.** Not a defect in this plan's own
  execution, but a real operational risk this plan cannot itself close. **Mitigation:** flagged with
  explicit priority in Task 8's report, matching ADR-0025/26/27/28/29 precedent.

## HITL gates

- No HITL gate inside this plan itself (auto mode; every edit is additive/corrective text inside
  existing skill-instruction files, or a new, isolated hermetic test file; no destructive git
  operations; every live script invocation in Tasks 1-6 targets a disposable, isolated `mktemp -d`
  fixture, never a real project's `docs/manifests/`).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and push
  remain human-gated, as does the follow-up `sync-to-claude.sh --apply` that would actually deploy
  these fixes (Risk F) — that sync is explicitly out of this plan's scope and requires its own
  separate human action.
- No DB schema change, no permanent deletion, no production migration in this plan — none of the
  invariant HITL triggers beyond the standard commit/push gate apply here.
