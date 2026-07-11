# Plan — Skill text corrections across five standalone skills

**Date:** 2026-07-11
**ADR:** [ADR-0035](../../architecture/ADR-0035-39-skill-text-corrections.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/39-skill-text-corrections-across-five-stand.spec.md`,
issue #39, confirmed byte-identical)
**Style:** TDD (red → green → checkpoint). Auto mode active, no intermediate HITL inside this plan;
commit/push stay HITL per repo `CLAUDE.md` invariant (see HITL gates, end of file). Six findings
across five files, one shared test file, one commit — ADR-0035 §3.1 records why this bundles at the
issue's own granularity rather than splitting into five ADRs/plans/commits. ADR-0035 §3.8 records why
this plan uses one combined RED task followed by five per-file GREEN tasks, instead of the
interleaved RED/GREEN-per-section structure ADR-0027/0028/0030 used: every assertion here is a
static content/positional grep against prose, with no runtime behavior to extract and execute, so
interleaving would add task-count overhead without adding safety.

**Task checklist (seven tasks — checked off by the coder as each completes; both `concept-to-code`
SKILL.md's Step 5 pre-dispatch check and `autopilot-build` SKILL.md's Check 5 grep this file for
`- [ ]`, so every task gets one, unlike this plan's own prose elsewhere):**

- [x] Task 1 — RED: `skill-text-corrections.test.sh` (new file, all five lettered sections at once).
- [x] Task 2 — GREEN: fix `claude-md-generator/SKILL.md` (Finding A) + add its `PAIRS` entry.
- [x] Task 3 — GREEN: fix `prompt-builder/SKILL.md` (Finding B).
- [x] Task 4 — GREEN: fix `git-repo-init/SKILL.md` (Finding C — both defects, one Fase 5 rewrite).
- [x] Task 5 — GREEN: fix `swiftui-pro/SKILL.md` (Finding D).
- [x] Task 6 — GREEN: fix `find-skills/SKILL.md` (Finding E).
- [x] Task 7 — Wire `docs-ci.yml`, full regression sweep, scope verification, SPEC.md checkboxes, final report.

---

## Why every RED in this plan is genuine RED (except explicitly-labeled companions)

Every genuine-RED assertion below was traced by hand against the real, unfixed files during
planning (ADR-0035 §1 reproduces all six defects directly, with exact current line numbers and
excerpts). Seven assertions are **non-regression companions**, verified to already pass today
because they check a property this plan's edits never touch (frontmatter still parses, on all five
files: A4/B4/C7/D4/E4) or a phrase that survives the fix unchanged verbatim (B3: prompt-builder's
"NON usare per ricerche Perplexity Vibrofer" wording; D2: swiftui-pro's original "iOS 26 exists..."
bullet). The other seventeen are genuine RED, individually re-verified below, not assumed:

| # | Section | Assertion | Fails today because |
|---|---|---|---|
| A1 | A | old "root CLAUDE.md" string absent | the old string is present (current line 13) |
| A2 | A | "output path given by the caller" present | this phrase does not exist in the file yet |
| A3 | A | "Never touch `CLAUDE.md` directly..." present | this phrase does not exist in the file yet |
| A5 | A | `claude-md-generator` `PAIRS` line present | no such line exists in `sync-to-claude.sh` yet |
| B1 | B | `vibrofer-perplexity-prompt` count = 0 | count is 1 today (current line 3) |
| B2 | B | `skill-creator` count = 0 | count is 1 today (current line 3) |
| C1 | C | old "Ordine fisso, nessuna domanda aggiuntiva:" absent | present today (current line 48) |
| C2 | C | old `` `gh repo view --web` NO `` absent | present today (current line 58) |
| C3 | C | "Gate di conferma (HITL)" count = 1 | count is 0 today (no gate exists yet) |
| C4 | C | `"Approva (Recommended)"` present | does not exist in the file yet |
| C5 | C | "mai aprire il browser" present | today's text reads "non aprire il browser" — a different string (different first word) |
| C6 | C | gate line falls between scaffolding and commit anchors | the gate anchor does not exist yet, so the positional check has nothing to compare |
| D1 | D | declared-target scoping phrase present | does not exist in the file yet |
| D3 | D | scoping bullet line < iOS 26 bullet line | the scoping-bullet anchor does not exist yet |
| E1 | E | "explicitly asks to find, search for, or install" on line 3 | not present today |
| E2 | E | "Do NOT use" on line 3 | not present today |
| E3 | E | "already-installed skill already covers the request" on line 3 | not present today |

**Tally arithmetic (verify this explicitly at each checkpoint, do not assume):** 7 non-regression +
17 genuine RED = 24 total assertions. Task 1's checkpoint expects `PASS=7 FAIL=17`. Task 2 flips
A1/A2/A3/A5 (+4/-4) → `PASS=11 FAIL=13`. Task 3 flips B1/B2 (+2/-2) → `PASS=13 FAIL=11`. Task 4 flips
C1-C6 (+6/-6) → `PASS=19 FAIL=5`. Task 5 flips D1/D3 (+2/-2) → `PASS=21 FAIL=3`. Task 6 flips
E1/E2/E3 (+3/-3) → `PASS=24 FAIL=0`. 4+2+6+2+3 = 17 (matches the genuine-RED count); the running
total after each task is restated in that task's own checkpoint below — confirm the actual printed
line matches exactly before moving on, per the ADR-0029/0030-style "verify against real behavior,
not assumed" discipline.

## Fixture and path conventions (read once, applies to every task below)

- **File to create:** `staging/plugin/scripts/tests/skill-text-corrections.test.sh` (new file).
- **Header, path derivation, PASS/FAIL idiom** (copy verbatim from `scope-guards.test.sh`'s own
  preamble, the closest structural precedent — multi-finding, lettered sections — adapted here to
  five `SKILL.md` files plus `sync-to-claude.sh` instead of three `SKILL.md` files):
  ```bash
  #!/bin/bash
  set -u

  SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
  STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
  CMG_SKILL="$STAGING/plugin/skills/claude-md-generator/SKILL.md"
  PB_SKILL="$STAGING/plugin/skills/prompt-builder/SKILL.md"
  GRI_SKILL="$STAGING/plugin/skills/git-repo-init/SKILL.md"
  SUI_SKILL="$STAGING/plugin/skills/swiftui-pro/SKILL.md"
  FS_SKILL="$STAGING/plugin/skills/find-skills/SKILL.md"
  SYNC="$STAGING/sync-to-claude.sh"

  PASS=0; FAIL=0
  ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
  bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
  ```
  Full header comment block (file docstring, summarizing the five sections) is specified in Task
  1's contract — do not skip it; every existing file in this directory has one.
- **No `mktemp -d`, no `trap`, no dynamic fixtures anywhere in this file.** Unlike
  `scope-guards.test.sh`/`concept-to-code-bsd-autopilot-gates.test.sh`, every assertion here is a
  static `grep`/`sed`/`awk` check against real file content already on disk — there is no runtime
  bash logic inside any of the five `SKILL.md` files to extract and execute (ADR-0035 §2.6/§3.8).
  Do not add a `TMP`/`trap` block; it would be dead weight.
- **Shared helper — define once, call from all five sections:**
  ```bash
  # frontmatter_ok <file> -- structural sanity check, not a real YAML parser: file opens with a
  # `---` line, a second `---` closing line exists, and `name:`/`description:` both appear between
  # them. Bash-only, zero dependency (no python, no yq), matching this directory's own convention.
  frontmatter_ok() {
    _f="$1"
    [ "$(sed -n '1p' "$_f")" = "---" ] || return 1
    _close=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$_f")
    [ -n "$_close" ] || return 1
    _fm=$(sed -n "2,${_close}p" "$_f")
    printf '%s\n' "$_fm" | grep -q '^name:' || return 1
    printf '%s\n' "$_fm" | grep -q '^description:' || return 1
    return 0
  }
  ```
- **Quoting rule for this file specifically:** any `grep` pattern containing an apostrophe (Finding
  D's "project's") **must** use double quotes, not single quotes, in the shell command — bash single
  quotes cannot contain a literal `'` character. Every other pattern in this file has no apostrophe
  and uses single quotes (`-qF`/`-cF`) for literal-string safety, matching this directory's
  established convention. Task 5's contract flags this explicitly at the one place it applies.
- **Isolating a check to one physical line (Sections B, E):** use `sed -n '3p' "$FILE" | grep -qF
  '<phrase>'` rather than a bare `grep -qF '<phrase>' "$FILE"` whenever the assertion is scoped to
  SPEC's own cited line (line 3, the frontmatter `description`) — this prevents the check from
  passing by accident against unrelated body prose elsewhere in the same file (e.g. `find-skills`'s
  own body repeats "how do I do X"-style language in its "When to Use This Skill" section, which
  this plan deliberately does not edit — ADR-0035 §3.6).
- **Bash 3.2 / BSD safety (every file touched this plan):** no `${var,,}`, no `mapfile`, no `<()`,
  no `declare -A`, no GNU-only regex shorthands (`\s`, `\d`) in any `grep -E`/`awk` pattern — plain
  `grep -q`/`grep -c`/`grep -F` (BRE/fixed-string) and `awk`/`sed` only, matching every existing file
  in this directory.
- **Per-task checkpoint (three checks, all must pass before moving to the next task):**
  1. `bash -n staging/plugin/scripts/tests/skill-text-corrections.test.sh` (the only `.sh` file this
     plan creates; `SKILL.md`/`sync-to-claude.sh`'s `PAIRS` data block are not executable scripts in
     the relevant sense here — use the content-diff/grep checks in each task instead for those, plus
     `bash -n sync-to-claude.sh` once, in Task 2, since that file *is* a script).
  2. `grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/tests/skill-text-corrections.test.sh` — must be empty.
  3. `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — must stay green; from Task 2
     onward its real-check `PASS` count is expected to read 109 (was 108), never a regression below
     108.

## Pre-flight constraints

- Confirmed baseline before Task 1 (re-verified during planning, not assumed):
  `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` → 12/12 files
  green (this is also `.claude/test-cmd`'s literal content — confirmed by reading the file).
  `pairs-completeness.test.sh`'s real-check phase currently reports `PASS=108 FAIL=0` (counted
  directly from `sync-to-claude.sh` before writing this plan).
- Writes are confined to: `staging/plugin/scripts/tests/skill-text-corrections.test.sh` (new),
  `staging/plugin/skills/claude-md-generator/SKILL.md`, `staging/plugin/skills/prompt-builder/SKILL.md`,
  `staging/plugin/skills/git-repo-init/SKILL.md`, `staging/plugin/skills/swiftui-pro/SKILL.md`,
  `staging/plugin/skills/find-skills/SKILL.md`, `staging/sync-to-claude.sh` (one appended `PAIRS`
  line only), `.github/workflows/docs-ci.yml`, `SPEC.md` (checkbox updates, final task),
  `docs/architecture/` and `docs/superpowers/plans/` (already written by this ADR/plan pass).
- Do not touch: any file under `~/.claude` (the deployed copies stay defective until a separate,
  human-gated `sync-to-claude.sh --apply` — same convention as ADR-0025 through ADR-0034),
  `staging/plugin/skills/concept-to-code/SKILL.md` (its Branch B dispatch prompt already matches the
  contract this plan gives `claude-md-generator`'s own text — ADR-0035 §1 "Cross-check" — no edit
  needed), `staging/plugin/skills/project-init/SKILL.md` (confirmed compatible, path-agnostic
  references to `claude-md-generator` — ADR-0035 §1 "Cross-check" — no edit needed),
  `staging/plugin/skills/research-prompt/SKILL.md` (checked as a candidate substitute name and
  confirmed not a fit — ADR-0035 §3.3 — read-only during this plan, not edited),
  `staging/plugin/skills/swiftui-pro/references/*.md` (the nine reference files `SKILL.md` points
  to — SPEC's cited defect is `SKILL.md:29` only, not any reference file), `staging/plugin/skills/
  find-skills/SKILL.md`'s own body (`## When to Use This Skill` and below — ADR-0035 §3.6, the fix
  is scoped to the frontmatter `description`, current line 3, only), `staging/plugin/skills/
  git-repo-init/references/*.md` and `assets/*` (Fase 5's fix is text-only inside `SKILL.md` itself;
  no template or reference file changes), `.claude/test-cmd` (its existing wildcard glob already
  covers the new file by pattern, confirmed by reading it — no edit needed), any historical ADR
  (immutable records; ADR-0011/0012/0013/0024/0025 are **related to, not amended by**, this ADR),
  any file under `docs/manifests/` (out of this plan's scope).
- `claude-md-generator/SKILL.md` edits are scoped exactly to the output-path paragraph (current line
  13, expanding to a short new paragraph plus the immediately-following "Generate..." sentence) —
  lines 1-12 (frontmatter, the `Read SPEC.md/ARCH.md` line, the template-selection block) and the
  three bullet points (current lines 14-16, content unchanged) are untouched.
- `prompt-builder/SKILL.md` edits are scoped exactly to the closing sentence of line 3 (the NEGATIVE
  clause) — the rest of line 3, and all of lines 4 onward (the entire body, `references/` pointers,
  Fasi 0-4, anti-pattern list), are untouched.
- `git-repo-init/SKILL.md` edits are scoped exactly to `## Fase 5 - Esecuzione` (current lines
  46-58) — Fasi 0-4 (current lines 23-44), `## Fase 6 - Report finale`, `## Gestione errori`, and
  `## Risorse` are untouched. Neither `## Fase 6` nor `## Gestione errori` references a step number
  from Fase 5, confirmed by reading both before this plan was written, so renumbering steps 6-9 to
  7-10 inside Fase 5 needs no cross-section reconciliation.
- `swiftui-pro/SKILL.md` edits are scoped exactly to one new bullet inserted at the top of `##
  Core Instructions` (current line 27's block) — the review-process numbered list (lines 12-24), the
  `## Output Format` section and its worked example, and the `## References` list, are untouched.
- `find-skills/SKILL.md` edits are scoped exactly to the frontmatter `description` (current line 3)
  — every other line in the file (the entire body from `# Find Skills` onward) is untouched.

## Anchor invariants (HARD — must stay true after every task)

- `bash staging/plugin/scripts/tests/phase1.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/prep.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/hook-probe.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh` → exit 0, unchanged 39/39 (untouched).
- `bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` → exit 0, unchanged 17/17 (untouched).
- `bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` → exit 0, unchanged 21/21 (untouched).
- `bash staging/plugin/scripts/tests/scope-guards.test.sh` → exit 0, unchanged 18/18 (untouched).
- `bash staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh` → exit 0, unchanged 19/19 (untouched).
- `bash staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh` → exit 0, unchanged 11/11 (untouched).
- `bash staging/plugin/scripts/tests/hook-hardening.test.sh` → exit 0, unchanged 6/6 (untouched).
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` → exit 0 throughout; real-check
  `PASS` reads 108 before Task 2, 109 from Task 2 onward — never below 108, never any `FAIL`.
- `git status` shows changes only under the Pre-flight "writes are confined to" list. Nothing under
  `~/.claude` is ever touched.

---

## Task 1 — RED: `skill-text-corrections.test.sh` (new file, all five lettered sections at once)

- [x] Create `staging/plugin/scripts/tests/skill-text-corrections.test.sh` with the file header,
  the shared preamble and `frontmatter_ok` helper ("Fixture and path conventions" above), and all
  five sections' 24 assertions in one pass.

**Files modified:**
- `staging/plugin/scripts/tests/skill-text-corrections.test.sh` (new).

**Contract — file docstring (top of file, immediately after the shebang, before `set -u`):**
```bash
# skill-text-corrections test harness (ADR-0035) -- six instruction-layer defects from the audit
# (SPEC.md / issue #39, range "3.1, 3.17 to 3.21") across five staging skills. Five lettered
# sections, one per file (git-repo-init carries two findings, fixed in one Fase 5 rewrite):
#   Section A -- claude-md-generator/SKILL.md:13 hardcoded "root CLAUDE.md" as the only write
#     target, conflicting with concept-to-code Branch B's own dispatch prompt ("Generate
#     CLAUDE.md.proposed ... Do NOT overwrite CLAUDE.md"). Fixed with an explicit
#     caller-provided-output-path contract; also adds the file's first sync-to-claude.sh PAIRS
#     entry (none existed -- ADR-0025 SS2.3 flagged this gap for this issue by name).
#   Section B -- prompt-builder/SKILL.md:3 NEGATIVE clause named two ghost skills
#     (vibrofer-perplexity-prompt, which exists nowhere in this system; skill-creator, a
#     marketplace/catalog plugin -- docs/plugins-and-mcp-catalog.md:21 -- not a staging skill).
#     Fixed with plain-terms exclusions, no skill names.
#   Section C -- git-repo-init/SKILL.md's Fase 5: line 48 asserted "no further questions" while
#     line 58 instructed, then contradicted itself on, opening a browser. Fixed with one HITL
#     recap gate (path, visibility, files, remote; Approve/Abort, recommended-option convention)
#     inserted between scaffolding and the first commit, and a browser-free verify step.
#   Section D -- swiftui-pro/SKILL.md:29 asserted iOS 26/Swift 6.2 as unconditional defaults,
#     fighting a project's own declared target. Fixed with a scoping bullet placed before the
#     specific defaults it governs.
#   Section E -- find-skills/SKILL.md:3 triggered on any "how do I do X" question, overlapping
#     virtually every installed skill. Fixed with an explicit-intent-only trigger and a NEGATIVE
#     clause.
# Every assertion is a static grep/sed/positional check against real file content -- no mktemp -d
# fixtures, no dynamic extract-and-execute (unlike scope-guards.test.sh/*-autopilot-gates.test.sh):
# none of these five files has runtime bash logic to pin down (ADR-0035 SS2.6/SS3.8).
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Never point any variable at $HOME/.claude/... -- that is the deployed copy, out of scope.
# Bash 3.2 clean. Run: bash skill-text-corrections.test.sh
```

**Contract — preamble + shared helper:** exactly the block already given in "Fixture and path
conventions" above (`SCRIPTS`/`STAGING`/five `*_SKILL` vars/`SYNC`, `PASS`/`FAIL`/`ok`/`bad`,
`frontmatter_ok`). Insert immediately after the docstring, before Section A.

**Contract — Section A, insert verbatim after the preamble:**
```bash
# =====================================================================================
# Section A -- Finding A: claude-md-generator output-path contract
# =====================================================================================

# A1 (static, genuine RED now): the old unconditional "root CLAUDE.md" instruction is gone.
if grep -qF 'Generate a root `CLAUDE.md` that is **lean and Anthropic-compliant**' "$CMG_SKILL"; then
  bad "A1: old unconditional 'root CLAUDE.md' instruction is still present"
else
  ok "A1: old unconditional 'root CLAUDE.md' instruction is gone"
fi

# A2 (static, genuine RED now): the caller-provided-output-path contract is present.
grep -qF 'output path given by the caller' "$CMG_SKILL" \
  && ok "A2: caller-provided output-path contract is present" \
  || bad "A2: caller-provided output-path contract should be present"

# A3 (static, genuine RED now): the never-touch-CLAUDE.md-from-the-chain rule is present.
grep -qF 'Never touch `CLAUDE.md` directly when invoked from the chain' "$CMG_SKILL" \
  && ok "A3: never-touch-CLAUDE.md-from-the-chain rule is present" \
  || bad "A3: never-touch-CLAUDE.md-from-the-chain rule should be present"

# A4 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$CMG_SKILL" && ok "A4: claude-md-generator frontmatter still parses" \
  || bad "A4: claude-md-generator frontmatter should still parse"

# A5 (static, genuine RED now): sync-to-claude.sh gains claude-md-generator's first PAIRS entry.
grep -qF 'plugin/skills/claude-md-generator/SKILL.md|skills/claude-md-generator/SKILL.md' "$SYNC" \
  && ok "A5: claude-md-generator has a PAIRS entry in sync-to-claude.sh" \
  || bad "A5: claude-md-generator should have a PAIRS entry in sync-to-claude.sh"
```

**Contract — Section B, insert verbatim after Section A:**
```bash
# =====================================================================================
# Section B -- Finding B: prompt-builder ghost skill names
# =====================================================================================

# B1 (static, genuine RED now): 'vibrofer-perplexity-prompt' is gone from the whole file.
_b1=$(grep -cF 'vibrofer-perplexity-prompt' "$PB_SKILL")
[ "$_b1" -eq 0 ] && ok "B1: 'vibrofer-perplexity-prompt' is gone from prompt-builder" \
  || bad "B1: 'vibrofer-perplexity-prompt' should be gone, found $_b1 occurrence(s)"

# B2 (static, genuine RED now): 'skill-creator' is gone from the whole file.
_b2=$(grep -cF 'skill-creator' "$PB_SKILL")
[ "$_b2" -eq 0 ] && ok "B2: 'skill-creator' is gone from prompt-builder" \
  || bad "B2: 'skill-creator' should be gone, found $_b2 occurrence(s)"

# B3 (static, non-regression companion, already passing today): the NEGATIVE clause's own subject
# survives in plain terms, isolated to the frontmatter description line (line 3) so this cannot
# pass by accident against unrelated prose.
sed -n '3p' "$PB_SKILL" | grep -qF 'NON usare per ricerche Perplexity Vibrofer' \
  && ok "B3: NEGATIVE clause still excludes Perplexity Vibrofer research, in plain terms" \
  || bad "B3: NEGATIVE clause should still exclude Perplexity Vibrofer research"

# B4 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$PB_SKILL" && ok "B4: prompt-builder frontmatter still parses" \
  || bad "B4: prompt-builder frontmatter should still parse"
```

**Contract — Section C, insert verbatim after Section B:**
```bash
# =====================================================================================
# Section C -- Finding C: git-repo-init Fase 5 HITL gate + browser fix
# =====================================================================================

# C1 (static, genuine RED now): the old "no further questions" preamble is gone.
if grep -qF 'Ordine fisso, nessuna domanda aggiuntiva:' "$GRI_SKILL"; then
  bad "C1: old 'nessuna domanda aggiuntiva' preamble is still present"
else
  ok "C1: old 'nessuna domanda aggiuntiva' preamble is gone"
fi

# C2 (static, genuine RED now): the old, self-contradicting browser instruction is gone.
if grep -qF '`gh repo view --web` NO' "$GRI_SKILL"; then
  bad "C2: old self-contradicting browser instruction is still present"
else
  ok "C2: old self-contradicting browser instruction is gone"
fi

# C3 (static, genuine RED now): exactly one HITL gate marker (SPEC success criterion: "exactly one").
_c3=$(grep -cF 'Gate di conferma (HITL)' "$GRI_SKILL")
[ "$_c3" -eq 1 ] && ok "C3: exactly one HITL gate marker present" \
  || bad "C3: expected exactly one HITL gate marker, found $_c3"

# C4 (static, genuine RED now): the recommended-option convention is honored.
grep -qF '"Approva (Recommended)"' "$GRI_SKILL" \
  && ok "C4: recommended-option convention honored ('Approva (Recommended)')" \
  || bad "C4: 'Approva (Recommended)' should be present"

# C5 (static, genuine RED now): the browser is explicitly never opened. Today's text reads "non
# aprire il browser" (a different string -- different first word) inside the self-contradicting
# sentence C2 already targets; this checks for the NEW phrasing specifically.
grep -qF 'mai aprire il browser' "$GRI_SKILL" \
  && ok "C5: 'mai aprire il browser' present" \
  || bad "C5: 'mai aprire il browser' should be present"

# C6 (static, genuine RED now, positional): the gate sits between scaffolding (step 4) and the
# first commit, not before or after. Anchors are content-based (stable across the renumbering
# steps 6-9 -> 7-10 undergo), not step-number-based.
_scaffold_line=$(grep -nF '4. Genera `CLAUDE.md` e `PROJECT_BRIEF.md`' "$GRI_SKILL" | head -1 | cut -d: -f1)
_gate_line=$(grep -nF 'Gate di conferma (HITL)' "$GRI_SKILL" | head -1 | cut -d: -f1)
_commit_line=$(grep -nF 'Primo commit, sempre conventional' "$GRI_SKILL" | head -1 | cut -d: -f1)
if [ -n "$_scaffold_line" ] && [ -n "$_gate_line" ] && [ -n "$_commit_line" ] \
   && [ "$_gate_line" -gt "$_scaffold_line" ] && [ "$_gate_line" -lt "$_commit_line" ]; then
  ok "C6: HITL gate sits between scaffolding and the first commit"
else
  bad "C6: HITL gate should sit between scaffolding (line $_scaffold_line) and first commit (line $_commit_line), found at line $_gate_line"
fi

# C7 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$GRI_SKILL" && ok "C7: git-repo-init frontmatter still parses" \
  || bad "C7: git-repo-init frontmatter should still parse"
```

**Contract — Section D, insert verbatim after Section C (note the double quotes on D1/D3's `grep`
patterns — see "Quoting rule," an apostrophe in "project's" forbids single-quoting these two):**
```bash
# =====================================================================================
# Section D -- Finding D: swiftui-pro scoping line
# =====================================================================================

# D1 (static, genuine RED now): the scoping bullet is present. Double-quoted (apostrophe in
# "project's" -- see this file's Quoting rule).
grep -qF "the project's own declared deployment target and Swift version" "$SUI_SKILL" \
  && ok "D1: scoping bullet (declared deployment target and Swift version) is present" \
  || bad "D1: scoping bullet should be present"

# D2 (static, non-regression companion, already passing today): the original iOS 26 default
# bullet is untouched.
grep -qF 'iOS 26 exists, and is the default deployment target for new apps.' "$SUI_SKILL" \
  && ok "D2: original iOS 26 default bullet is unchanged" \
  || bad "D2: original iOS 26 default bullet should be unchanged"

# D3 (static, genuine RED now, positional): the scoping bullet precedes the specific default it
# governs. Double-quoted for the same reason as D1.
_scope_line=$(grep -n "the project's own declared deployment target and Swift version" "$SUI_SKILL" | head -1 | cut -d: -f1)
_ios26_line=$(grep -n 'iOS 26 exists, and is the default deployment target for new apps.' "$SUI_SKILL" | head -1 | cut -d: -f1)
if [ -n "$_scope_line" ] && [ -n "$_ios26_line" ] && [ "$_scope_line" -lt "$_ios26_line" ]; then
  ok "D3: scoping bullet precedes the iOS 26/Swift 6.2 defaults it governs"
else
  bad "D3: scoping bullet should precede the iOS 26/Swift 6.2 defaults (scope=$_scope_line, ios26=$_ios26_line)"
fi

# D4 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$SUI_SKILL" && ok "D4: swiftui-pro frontmatter still parses" \
  || bad "D4: swiftui-pro frontmatter should still parse"
```

**Contract — Section E, insert verbatim after Section D:**
```bash
# =====================================================================================
# Section E -- Finding E: find-skills narrowed trigger + NEGATIVE clause
# =====================================================================================

# E1 (static, genuine RED now, isolated to the frontmatter description line): narrowed to explicit
# skill-discovery intent.
sed -n '3p' "$FS_SKILL" | grep -qF 'explicitly asks to find, search for, or install' \
  && ok "E1: description narrows to explicit skill-discovery intent" \
  || bad "E1: description should narrow to explicit skill-discovery intent"

# E2 (static, genuine RED now, isolated to line 3): a NEGATIVE clause is present.
sed -n '3p' "$FS_SKILL" | grep -qF 'Do NOT use' \
  && ok "E2: NEGATIVE clause ('Do NOT use') is present" \
  || bad "E2: NEGATIVE clause should be present"

# E3 (static, genuine RED now, isolated to line 3): the NEGATIVE clause excludes requests already
# covered by an installed skill (not just a generic exclusion).
sed -n '3p' "$FS_SKILL" | grep -qF 'already-installed skill already covers the request' \
  && ok "E3: NEGATIVE clause excludes requests covered by an installed skill" \
  || bad "E3: NEGATIVE clause should exclude requests covered by an installed skill"

# E4 (static, non-regression companion, already passing today): frontmatter still parses.
frontmatter_ok "$FS_SKILL" && ok "E4: find-skills frontmatter still parses" \
  || bad "E4: find-skills frontmatter should still parse"
```

**Contract — file footer, insert verbatim after Section E:**
```bash
printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

**Expected now (RED):** `PASS=7 FAIL=17` (see "Why every RED in this plan is genuine RED" table
above for the full per-assertion breakdown).

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/skill-text-corrections.test.sh
bash staging/plugin/scripts/tests/skill-text-corrections.test.sh
# expect: PASS=7 FAIL=17
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
# expect: PASS=108 FAIL=0 (unchanged -- Task 1 adds no PAIRS entry, only the test file)
```

---

## Task 2 — GREEN: fix `claude-md-generator/SKILL.md` (Finding A) + add its `PAIRS` entry

- [x] Replace the output-path instruction (current line 13) with the caller-provided contract;
  append `claude-md-generator`'s first `PAIRS` line to `sync-to-claude.sh`.

**Files modified:**
- `staging/plugin/skills/claude-md-generator/SKILL.md`
- `staging/sync-to-claude.sh`

**Contract — `claude-md-generator/SKILL.md`, replace current line 13 in full with:**
```
Write to the output path given by the caller (for example `<project-root>/CLAUDE.md.proposed` when
invoked from the concept-to-code chain); if the caller gives no path, default to
`<project-root>/CLAUDE.md`. Never touch `CLAUDE.md` directly when invoked from the chain. Write only
to the `.proposed` path the chain provides.

Generate a project memory file at that output path, **lean and Anthropic-compliant**:
```
Lines 14-16 (the three bullet points) follow immediately after, byte-identical to today (`-
Inherits...`, `- Include only...`, `- Target < 100 lines...`).

**Contract — `sync-to-claude.sh`, append one new line at the end of the `PAIRS` block (current line
127, `plugin/skills/research-prompt/SKILL.md|skills/research-prompt/SKILL.md`, is today's last
entry before the closing `"` on line 128):**
```
plugin/skills/claude-md-generator/SKILL.md|skills/claude-md-generator/SKILL.md
```
Nothing else in `sync-to-claude.sh` changes — not the copy/diff logic, not the `--apply` gating, not
the trailing `NOTE` heredoc.

**Expected (GREEN):** A1, A2, A3, A5 pass; A4 unchanged (was already passing).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/skill-text-corrections.test.sh
# expect: PASS=11 FAIL=13 (Section A complete: 5/5; Sections B-E not yet added)
bash -n staging/sync-to-claude.sh
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
# expect: PASS=109 FAIL=0 (was 108 -- the one new entry is real, its source file exists, so the
# real-check phase picks it up automatically with no code change)
```

---

## Task 3 — GREEN: fix `prompt-builder/SKILL.md` (Finding B)

- [x] Replace the NEGATIVE clause's ghost-skill parentheticals with plain-terms exclusions.

**Files modified:**
- `staging/plugin/skills/prompt-builder/SKILL.md`

**Contract — replace, on line 3 only, the closing sentence:**
```
NON usare per ricerche Perplexity Vibrofer (usa vibrofer-perplexity-prompt) né per creare skill (usa skill-creator).
```
with:
```
NON usare per ricerche Perplexity Vibrofer né per creare una nuova skill da zero.
```
Every other word on line 3 (the full technique/trigger-phrase description preceding this sentence)
is untouched; this is a single-sentence replacement at the very end of the line.

**Expected (GREEN):** B1, B2 pass; B3, B4 unchanged (were already passing).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/skill-text-corrections.test.sh
# expect: PASS=13 FAIL=11 (Sections A+B complete: 5+4=9 of 9; Sections C-E not yet added)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
# expect: PASS=109 FAIL=0 (unchanged from Task 2)
```

---

## Task 4 — GREEN: fix `git-repo-init/SKILL.md` (Finding C — both defects, one Fase 5 rewrite)

- [x] Replace `## Fase 5 - Esecuzione` in full (current lines 46-58) with the ten-step version:
  new step 6 (the HITL recap gate) inserted after the `clean-public-repo` invocation and before the
  first commit; steps 6-9 renumbered 7-10; step 10 (was 9) rewritten to drop the browser-opening
  contradiction.

**Files modified:**
- `staging/plugin/skills/git-repo-init/SKILL.md`

**Contract — replace `## Fase 5 - Esecuzione` through its last line (current lines 46-58) in full
with:**
```
## Fase 5 - Esecuzione

Ordine fisso, con un solo gate di conferma prima del primo commit (step 6):

1. `mkdir` nella posizione canonica (vedi "Posizione del progetto") e `git init -b main`
2. Genera i file dello scaffolding scelto. Per .gitignore usa i template ufficiali GitHub (`gh repo gitignore view <Template>` o https://github.com/github/gitignore). Per la licenza usa il testo ufficiale (gh o choosealicense.com) con anno corrente e nome utente.
3. **Se stack = Swift**: esegui il setup Tuist/Xcode da `references/swift-xcode-setup.md` (manifesti, sorgenti skeleton, `tuist generate`, build + test verde). Per gli altri stack genera la struttura sorgenti standard.
4. Genera `CLAUDE.md` e `PROJECT_BRIEF.md` dai template in `assets/`, compilati con TUTTE le risposte del wizard. Non lasciare placeholder vuoti. Per Swift usa il blocco Commands e il working agreement indicati in `references/swift-xcode-setup.md`.
5. **Se visibilita = public e l'utente ha accettato l'audit**: invoca la skill `clean-public-repo` ORA, prima del primo commit/push.
6. **Gate di conferma (HITL)**: prima di procedere, mostra un riepilogo (percorso locale, visibilita, elenco file generati, remote che verra creato se applicabile) e usa AskUserQuestion con due opzioni: "Approva (Recommended)" per procedere con commit e push, "Interrompi" per fermarti qui senza commit ne push. Assegna "(Recommended)" ad "Approva" solo se lo scaffolding e pulito (nessun avviso residuo dall'audit `clean-public-repo`, nessuna directory preesistente sovrascritta); in caso contrario raccomanda "Interrompi" e spiega perche in una riga. Su interruzione: la repo locale resta cosi com'e, nessun commit, nessun push.
7. Primo commit, sempre conventional: `chore: initial project scaffolding`
8. Se gh disponibile: `gh repo create <nome> --<visibilita> --source . --push --description "<descrizione>"`
9. Se richiesta branch protection: applicala via `gh api` dopo il push.
10. Verifica: `git log --oneline` e, se remoto, stampa l'URL della repo con `gh repo view --json url -q .url` (mai `--web`, mai aprire il browser).
```
`## Fase 6 - Report finale` (current line 60 onward) follows immediately after, byte-identical to
today — confirmed during planning that it references no Fase-5 step number, so no cross-section
edit is needed there or in `## Gestione errori`.

**Expected (GREEN):** C1, C2, C3, C4, C5, C6 pass; C7 unchanged (was already passing).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/skill-text-corrections.test.sh
# expect: PASS=19 FAIL=5 (Sections A+B+C complete: 5+4+7=16 of 16; Sections D-E not yet added)
grep -c '^[0-9]\+\. ' staging/plugin/skills/git-repo-init/SKILL.md
# sanity count only (this file's numbered-list convention is not unique to Fase 5, informational)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
# expect: PASS=109 FAIL=0 (unchanged)
```

---

## Task 5 — GREEN: fix `swiftui-pro/SKILL.md` (Finding D)

- [x] Insert the scoping bullet at the top of `## Core Instructions`, before the existing iOS
  26/Swift 6.2 bullets.

**Files modified:**
- `staging/plugin/skills/swiftui-pro/SKILL.md`

**Contract — insert, as the new first bullet immediately under `## Core Instructions` (current line
27), before current line 29 (`- iOS 26 exists...`):**
```
- Respect the project's own declared deployment target and Swift version when it declares one
  (Package.swift, project.yml, Tuist manifest, Xcode project settings). iOS 26 and Swift 6.2 below
  are defaults for a project that declares none, not an override for one that does.
```
Every existing bullet in `## Core Instructions` (iOS 26 default, Swift 6.2 target, UIKit avoidance,
third-party frameworks, per-type file layout, feature-driven folder structure) follows immediately
after, byte-identical to today, just shifted down by one bullet.

**Expected (GREEN):** D1, D3 pass; D2, D4 unchanged (were already passing).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/skill-text-corrections.test.sh
# expect: PASS=21 FAIL=3 (Sections A+B+C+D complete: 5+4+7+4=20 of 20; Section E not yet added)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
# expect: PASS=109 FAIL=0 (unchanged)
```

---

## Task 6 — GREEN: fix `find-skills/SKILL.md` (Finding E)

- [x] Replace the frontmatter `description` (current line 3) with the narrowed-intent, NEGATIVE-clause version.

**Files modified:**
- `staging/plugin/skills/find-skills/SKILL.md`

**Contract — replace line 3 in full with:**
```
description: Use this skill only when the user explicitly asks to find, search for, or install a new agent skill, using phrasing like "find a skill for X", "is there a skill that can...", "search skills for X", "npx skills find X", "install a skill for X". Do NOT use for general "how do I do X" questions, for requests answerable directly without a new skill, or when an already-installed skill already covers the request.
```
`name: find-skills` (line 2) and the closing `---` (line 4) are unchanged; the entire body from `#
Find Skills` (line 6) onward is unchanged — see ADR-0035 §3.6 for why the body's own "Asks 'how do I
do X'" bullet is deliberately not also rewritten in this plan.

**Expected (GREEN):** E1, E2, E3 pass; E4 unchanged (was already passing). Full file green:
`PASS=24 FAIL=0`.

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/skill-text-corrections.test.sh
# expect: PASS=24 FAIL=0 -- full file green (5 Section A + 4 Section B + 7 Section C + 4 Section D
# + 4 Section E = 24)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
# expect: PASS=109 FAIL=0 (unchanged)
```
**Tally check (do this arithmetic explicitly, do not assume):** Section A = 5 (A1-A5). Section B = 4
(B1-B4). Section C = 7 (C1-C7). Section D = 4 (D1-D4). Section E = 4 (E1-E4). **Total: 24
assertions, 24 passed, 0 failed** once Task 6 lands. Confirm the actual printed `PASS=`/`FAIL=` line
equals this exactly; if it does not, stop and reconcile before Task 7, do not proceed on a
mismatched count.

---

## Task 7 — Wire `docs-ci.yml`, full regression sweep, scope verification, SPEC.md checkboxes, final report

- [x] Add `skill-text-corrections` to `docs-ci.yml`'s explicit `shell-tests` list; run the full
  local test-cmd (13/13 files green); sweep for bash 3.2/BSD safety; confirm the changed-file set
  matches the Pre-flight "writes are confined to" list exactly; check off SPEC.md's satisfied
  success criteria; produce the final report.

**Files modified:**
- `.github/workflows/docs-ci.yml`
- `SPEC.md`

**Contract — `docs-ci.yml`, append `skill-text-corrections` as the thirteenth entry in the `for t in
...` list (current line 44):**
```
          for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates concept-to-code-manifest-helpers-guards scope-guards refactor-snapshot-deep-refactor claude-md-slim-content-union-whole-line hook-hardening skill-text-corrections; do
```

**Contract — `SPEC.md`, check off every success-criteria box genuinely satisfied (expect all 5):**
```
- [x] Each frontmatter description still parses and stays within its skill's language conventions
- [x] claude-md-generator explicitly supports the .proposed contract when called from concept-to-code
- [x] git-repo-init Fase 5 contains exactly one HITL gate before the first commit, and no browser-opening instruction survives
- [x] No ghost skill names remain in any NEGATIVE clause
- [x] No file under `~/.claude` modified
```

**Verify (full, repo-wide):**
```bash
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done    # local test-cmd, 13/13 green
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                       # PASS=109 FAIL=0
bash -n staging/plugin/scripts/tests/skill-text-corrections.test.sh
bash -n staging/sync-to-claude.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/tests/skill-text-corrections.test.sh   # empty
grep -nF '<<<' staging/plugin/scripts/tests/skill-text-corrections.test.sh   # empty
echo "bash 3.2 / BSD safety: clean"

diff <(git show HEAD:staging/plugin/skills/claude-md-generator/SKILL.md) staging/plugin/skills/claude-md-generator/SKILL.md
# manually confirm: only the output-path paragraph (current line 13, now three lines plus a blank)
# changed; the frontmatter and the three "lean and Anthropic-compliant" bullets are untouched.
diff <(git show HEAD:staging/plugin/skills/prompt-builder/SKILL.md) staging/plugin/skills/prompt-builder/SKILL.md
# manually confirm: only line 3's closing sentence changed.
diff <(git show HEAD:staging/plugin/skills/git-repo-init/SKILL.md) staging/plugin/skills/git-repo-init/SKILL.md
# manually confirm: only ## Fase 5 (current lines 46-58) changed; Fasi 0-4, Fase 6, Gestione
# errori, and Risorse are untouched.
diff <(git show HEAD:staging/plugin/skills/swiftui-pro/SKILL.md) staging/plugin/skills/swiftui-pro/SKILL.md
# manually confirm: only one new bullet inserted at the top of ## Core Instructions.
diff <(git show HEAD:staging/plugin/skills/find-skills/SKILL.md) staging/plugin/skills/find-skills/SKILL.md
# manually confirm: only line 3 changed.
diff <(git show HEAD:staging/sync-to-claude.sh) staging/sync-to-claude.sh
# manually confirm: only one line appended to the PAIRS block; nothing else in the script changed.

grep -c "skill-text-corrections" .github/workflows/docs-ci.yml   # 1, the new thirteenth entry
git status   # confirm change set matches Pre-flight "writes are confined to" list; nothing under ~/.claude
```

**Report to dispatcher (accumulate for the final report):**
- Full local `test-cmd` glob result (13/13 files green) pasted verbatim.
- `skill-text-corrections.test.sh` final tally: `PASS=24 FAIL=0`.
- `pairs-completeness.test.sh` final tally: `PASS=109 FAIL=0` (was 108 before Task 2).
- Confirmation each `SKILL.md` diff (and `sync-to-claude.sh`'s diff) touches only the region named
  in Pre-flight's scoping note — nothing else.
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted.
- Explicit flag for the human reviewer: `find-skills/SKILL.md`'s own body (`## When to Use This
  Skill`, Step 1) still describes broader usage rationale than the newly-narrowed frontmatter
  trigger now permits — deliberately left this way, disclosed in ADR-0035 §3.6/Consequences-Negative,
  not a missed spot.
- Explicit flag: the *deployed* copies (`~/.claude/skills/claude-md-generator/SKILL.md`,
  `~/.claude/skills/prompt-builder/SKILL.md`, `~/.claude/skills/git-repo-init/SKILL.md`,
  `~/.claude/skills/swiftui-pro/SKILL.md`, `~/.claude/skills/find-skills/SKILL.md`) keep today's six
  defects until a human runs `sync-to-claude.sh --apply` — for `claude-md-generator`, this is the
  *first* time that sync path exists at all (Task 2 added its first-ever `PAIRS` entry).
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — Section C5's grep matching the wrong "browser" string.** Today's text contains "non
  aprire il browser" (the retraction half of the self-contradicting old sentence); the fix's text
  contains "mai aprire il browser" (a different first word). A coder who writes "non aprire il
  browser" instead of the plan's literal "mai aprire il browser" in the fix would make C5 pass by
  accident against the *old* wording still partially present, masking an incomplete fix.
  **Mitigation:** Task 4's contract gives the exact replacement text verbatim, including "mai," not
  "non"; C2's own check (old `` `gh repo view --web` NO `` string gone) independently catches an
  incomplete rewrite of the same sentence even if C5 alone were somehow satisfied.
- **Risk B — Section D1/D3's apostrophe breaking the shell command if single-quoted.** `"the
  project's declared deployment target and Swift version"` contains a literal `'` character. Single-
  quoting this pattern in bash breaks the command (the string is truncated at the apostrophe, and
  bash then tries to interpret the remainder as shell syntax). **Mitigation:** Task 1's contract for
  Section D explicitly uses double quotes for D1 and D3's `grep` patterns and calls this out in an
  inline comment; this is the one place in the whole file this rule applies, since no other
  assertion's pattern contains an apostrophe.
- **Risk C — Task 4 renumbering steps 6-9 to 7-10 but missing one, or leaving a duplicate/skipped
  number.** The rewrite touches every step from 6 onward, not just the two literally-defective
  lines. **Mitigation:** Task 4's contract gives the entire `## Fase 5` section as one literal
  replacement block (not a line-by-line diff instruction), so a coder copying it verbatim cannot
  produce a partial renumbering; C6's positional check is the automated backstop (it would fail if
  the gate ends up anywhere other than strictly between the scaffolding and commit anchors).
- **Risk D — Section C3's "exactly one" count silently passing at 0 or 2+ instead of exactly 1** if
  a coder pastes the new step 6 twice, or if "Gate di conferma (HITL)" is accidentally also
  introduced elsewhere (e.g. in a comment). **Mitigation:** C3 explicitly asserts `-eq 1`, not just
  presence (`grep -q`); this is the automated backstop for SPEC's own literal "exactly one" success
  criterion.
- **Risk E — Task 2's `PAIRS` line landing with a typo in either the `src` or `dst` half** (e.g. a
  missing `/SKILL.md` suffix, or copy-pasting a different skill's `dst` path). **Mitigation:**
  `pairs-completeness.test.sh`'s real-check phase asserts the `src` half resolves to a real file
  under `staging/`; a typo there fails loudly at the very next checkpoint (Task 2's own). The `dst`
  half is not independently validated by any harness (by design — ADR-0024 §3.4, `dst` correctness
  is confirmed by the human at `sync-to-claude.sh --apply` time, via its printed diff, not by CI);
  Task 2's contract gives the exact literal line to prevent a typo in the first place.
  A5's own check (`grep -qF` on the *exact* full line, both halves) additionally catches a `dst`-side
  typo, since a wrong `dst` half would make A5's exact-string match fail too.
- **Risk F — scope creep into `git-repo-init/references/swift-xcode-setup.md`,
  `find-skills/SKILL.md`'s body, or `staging/plugin/skills/concept-to-code/SKILL.md`.** All three are
  adjacent, thematically related files a coder might be tempted to "clean up while in the area"
  (Fase 5's step 3 references the Swift setup file; Finding E's fix narrows a trigger whose body
  still says something broader; Finding A's fix is explicitly designed to match
  `concept-to-code/SKILL.md`'s existing dispatch prompt). **Mitigation:** Pre-flight's "do not touch"
  list is explicit about all three; Task 7's `git status` and targeted `diff`s are the automated
  backstop.
- **Risk G — the deployed skill keeps all six defects until sync.** Not a defect in this plan's own
  execution, but a real operational risk this plan cannot itself close. **Mitigation:** flagged with
  explicit priority in Task 7's report, matching ADR-0025 through ADR-0034 precedent.

## HITL gates

- No HITL gate inside this plan itself (auto mode; every edit is additive/corrective text inside
  existing skill-instruction files, one additive line in a sync script, or a new, isolated hermetic
  test file; no destructive git operations; nothing in Tasks 1-6 executes against a real project's
  `docs/manifests/` or touches `~/.claude`).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and push
  remain human-gated, as does the follow-up `sync-to-claude.sh --apply` that would actually deploy
  these fixes (Risk G) — that sync is explicitly out of this plan's scope and requires its own
  separate human action.
- No DB schema change, no permanent deletion, no production migration in this plan — none of the
  invariant HITL triggers beyond the standard commit/push gate apply here.
