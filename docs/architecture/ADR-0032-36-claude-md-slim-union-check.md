# ADR-0032 — claude-md-slim: whole-line content-union-check matching

**Status:** Accepted
**Date:** 2026-07-11
**Author:** istefox
**Supersedes:** none
**Amends:** ADR-0019 (D6 — clarifies the content-preservation invariant's matching semantics
from ambiguous/buggy substring matching to whole-line, set-based matching; the underlying
decision — a hard content-preservation gate before the HITL diff — is unchanged, only its
implementation is corrected and its "union" wording is made explicit)
**Related:**
- SPEC: `docs/specs/36-claude-md-slim-whole-line-content-union.spec.md` (= `SPEC.md` at repo
  root, GitHub issue #36, confirmed byte-identical by diff before writing this ADR)
- ADR-0019 (`claude-md-slim-skill`) — original design of the skill and the content-preservation
  invariant this ADR patches; D6's "union(output) ≥ union(input)" framing is the textual basis
  for this ADR's set-vs-multiset decision (D2 below)
- ADR-0027 through ADR-0031 (`c2c-bsd-slug-autopilot-gates`, `manifest-helpers-guards`,
  `hook-verify-session-filter`, `scope-guards`, `refactor-snapshot-deep-refactor`) — structural
  and test-harness precedent this ADR reuses directly (hermetic `staging/plugin/scripts/tests/`
  file, disposable `mktemp` fixtures against the real script, `docs-ci.yml` explicit-list append,
  "verify by live execution, not assumed" discipline, "$HOME-coupled tests are confirmed
  compatible but out of scope" disclosure pattern)
- `staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh` — the file this ADR
  patches
- `staging/plugin/skills/claude-md-slim/tests/run-tests.sh` — confirmed `$HOME`-coupled
  (`$HOME/.claude/skills/claude-md-slim/...`), not part of the hermetic `docs-ci` harness, its
  T04 assertions are the only prior coverage of the script this ADR patches (§1 "Root cause")
- Implementation plan: `docs/superpowers/plans/2026-07-11-36-claude-md-slim-union-check.md`

---

## 1. Context

Issue #36 (audit finding 2.8) names one defect in `content-union-check.sh`, the sole script
implementing ADR-0019 D6's content-preservation hard gate for the `claude-md-slim` skill — the
gate that runs before the Step 6 HITL diff and again after Step 7's apply, and whose only job is
to abort the plan if any line from the original CLAUDE.md would be silently dropped.

### 1.1 The defect, reproduced live against the real, unmodified script

Line 55 reads:

```bash
if grep -qF -- "$line" "$outfile" 2>/dev/null; then
```

`-F` makes the pattern a literal, fixed string (correct — CLAUDE.md content routinely contains
regex metacharacters like `.`, `*`, `$`, `[` that must not be interpreted as regex). But `grep -F`
without `-x` is a **substring** search, not a whole-line search: it succeeds if `$line` appears
*anywhere inside* any line of `$outfile`, including as a prefix of a longer, unrelated line.

Reproduced directly against the real, unmodified script (not assumed):

```
$ printf '## Git\n' > original.md
$ printf '## GitHub Actions\n' > union.md
$ bash content-union-check.sh original.md union.md; echo "exit=$?"
exit=0
```

The original's only content line, `## Git`, is declared "preserved" because it is a literal text
prefix of the union's unrelated `## GitHub Actions` heading — the actual `## Git` section is not
present anywhere in the output, and the gate does not notice. This is exactly SPEC finding 2.8's
named reproduction. A second defect named in the same finding — duplicate original lines counting
as preserved when only one copy survives — was also checked live; see §1.3.

### 1.2 Root cause: the only prior coverage of this script never ran in CI

`content-union-check.sh`'s sole existing test coverage is T04 in
`staging/plugin/skills/claude-md-slim/tests/run-tests.sh`, which resolves its target paths from
`$HOME/.claude/skills/claude-md-slim/...` — the *deployed* copy, not this repository's
`staging/` source of truth. `run-tests.sh` is not one of `.github/workflows/docs-ci.yml`'s ten
explicitly-named `shell-tests` entries (confirmed by reading the file: `phase1 prep hook-probe
hook-verify-workflow pairs-completeness clean-public-repo-history-safety
concept-to-code-bsd-autopilot-gates concept-to-code-manifest-helpers-guards scope-guards
refactor-snapshot-deep-refactor`) and is not picked up by `.claude/test-cmd`'s glob (`staging/
plugin/scripts/tests/*.test.sh`) either. This script's only test has therefore never executed in
CI since the skill shipped (ADR-0019, 2026-06-06) — at minimum consistent with how a defect in
the project's sole content-preservation hard gate could ship and go unnoticed for five weeks until
a manual audit found it.

### 1.3 The duplicate-line question, checked live, not assumed

SPEC's second named symptom — "duplicate original lines count as preserved when a single copy
survives" — was checked directly against an isolated fixture (a line appearing twice in the
original, once in the union, nothing else different):

```
$ printf 'Never commit secrets.\n\nNever commit secrets.\n' > original.md
$ printf 'Never commit secrets.\n' > union.md
$ bash content-union-check.sh original.md union.md; echo "exit=$?"
exit=0
```

The current script already treats this as "preserved" — not as a second bug alongside the
substring defect, but as an inherent property of how the check has *always* worked: it iterates
original lines and asks "does this text exist somewhere in the union," never "how many times."
This is the same property under whole-line matching too (verified in §2.4) — the open question
SPEC leaves is not "is this currently broken" but "should whole-line matching newly start
enforcing multiplicity." §2.2 (D2) answers this.

### 1.4 A gap found during this review, confirmed, and explicitly left out of scope

While tracing every call-site of `content-union-check.sh` (SKILL.md, grepped in full), one
additional, pre-existing, orthogonal gap was found and is disclosed here rather than silently
carried forward or silently fixed: Step 3/4's `--global` duplication scan removes a `DUPLICATE`
section's lines from the trimmed CLAUDE.md entirely (`<!-- duplicate of ~/.claude/CLAUDE.md —
removed -->`), on the reasoning that they survive in the global file — but Step 5.2's invocation
of `content-union-check.sh` (SKILL.md lines 157-166) never passes `~/.claude/CLAUDE.md` as one of
the output-file arguments. A `--global` run that produces at least one `DUPLICATE` section was
therefore already relying on those lines accidentally surviving as a substring of some unrelated
line elsewhere in the local outputs — the same accident category as §1.1 — to pass the gate at
all. This is a real gap, but it is **not** SPEC finding 2.8 (SPEC's "Out" scope: "Other
claude-md-slim pipeline steps"), and fixing it would require deciding whether to add the global
file as a union input or to exempt `DUPLICATE`-removed lines by construction — a design question
this ADR does not have a mandate to answer. See Consequences (Negative) and the plan's risk
register for the recommended follow-up.

---

## 2. Decision

Rewrite the matching core of `content-union-check.sh` to whole-line, trailing-whitespace-trimmed,
set-based matching, and give the script real, continuously-run CI coverage for the first time via
a new hermetic test file. Four decisions, each verified by live execution against the real,
unmodified script (and, where relevant, against a deliberately naive alternative) before being
finalized — not reasoned about from source alone.

### D1 — Whole-line matching via a constructed union file (`grep -qxF` against one concatenated temp file)

Build one temp file (`UNION_TMP`) containing every output file's content, concatenated, with
trailing whitespace stripped per line (D3). Replace the per-original-line, per-outfile substring
loop with a single `grep -qxF -- "$trimmed_line" "$UNION_TMP"` call per original line.

```bash
UNION_TMP=$(mktemp /tmp/content-union-check.XXXXXX)
for outfile in "$@"; do
  sed 's/[[:space:]]*$//' "$outfile" >> "$UNION_TMP"
done
...
trimmed_line=$(printf '%s' "$line" | sed 's/[[:space:]]*$//')
if ! grep -qxF -- "$trimmed_line" "$UNION_TMP" 2>/dev/null; then
  missing=$((missing + 1))
fi
...
rm -f "$UNION_TMP"
```

`-x` (POSIX/GNU/BSD grep, both dialects) requires the pattern to match the *entire* line, not a
substring; combined with `-F` (already used today, unchanged rationale — no escaping needed for
CLAUDE.md content's regex metacharacters), this reproduces the invariant's actual intent: "does
this exact line exist somewhere in the union," not "does this text appear as a fragment
somewhere." Verified live: `grep -qxF -- "## Git"` against a file containing only `## GitHub
Actions` correctly fails to match (§2.4).

### D2 — Multiplicity (per-line occurrence counts) is a documented exemption, not enforced

The check does **not** compare how many times a line appears in the original against how many
times it appears in the union. A line duplicated in the original and collapsed to one copy in the
union is not flagged. This is added as an explicit, named subsection in SKILL.md (Step 5.2),
satisfying SPEC's "or document explicitly why multiplicity is out of scope" branch.

Three independent reasons converge on this choice, not one:

1. **ADR-0019 D6's own wording is set-based.** "Union(output) ≥ union(input)" and the script's own
   name (`content-union-check`) both name a **set** operation. A set union does not track
   occurrence counts by definition; enforcing multiplicity would be inventing a stricter
   invariant than D6 ever stated, not implementing D6 correctly.
2. **The pipeline's own designed behavior legitimately reduces multiplicity.** Step 7.4's MERGE
   path explicitly deduplicates by exact-line match against a target rules file's pre-existing
   content ("append only non-duplicate lines"); the `--global` duplication scan (Step 3/4)
   removes whole sections whose content already exists in the global file. Both are intentional,
   already-shipped features. A multiset invariant would make the content-preservation gate fail
   on the skill's own correct behavior — the exact failure mode ADR-0019 D6's "hard gate, not
   best-effort" rationale was written to prevent in the *other* direction (silent loss), not to
   cause in this one (false rejection of a legitimate consolidation).
3. **Verified live: the current, unmodified script already behaves this way.** §1.3's reproduction
   shows today's script already passes the isolated multiplicity-only case; whole-line matching
   does not change this (§2.4 re-confirms it under the new algorithm). Choosing the exemption is
   therefore *documenting existing, verified behavior*, not loosening a currently-stricter check.

### D3 — Trailing-whitespace trim on both sides (required companion to D1, not optional polish)

Before the whole-line comparison, strip trailing whitespace (`sed 's/[[:space:]]*$//'`) from every
output-file line (once, while building `UNION_TMP`) and from each original line being checked.
Leading whitespace and internal whitespace runs are left untouched.

This is not a nice-to-have. Verified live: the *current*, substring-based script already tolerates
trailing-whitespace-only differences **by accident** (a shorter line missing trailing whitespace
is always a text prefix of a longer line that has it). A naive fix that adds only `-x` **without**
this trim was built and tested as a strawman — it regresses this exact, currently-working case:

```
$ printf '## Heading\nBody text.\n' > original.md
$ printf '## Heading   \nBody text.\t\n' > union.md   # trailing space / tab only
$ bash content-union-check.sh original.md union.md; echo "exit=$?"     # current script
exit=0
$ bash naive-whole-line-no-trim.sh original.md union.md; echo "exit=$?" # -x added, no trim
2 lines missing
exit=1
```

Trimming trailing whitespace on both sides before the `-xF` comparison restores this tolerance by
design instead of by accident (verified: the final contract passes this exact case, §2.4).

### D4 — New hermetic CI test file, not an extension of the existing `$HOME`-coupled `run-tests.sh`

New file: `staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh`, wired
into `docs-ci.yml`'s explicit `shell-tests` list (eleventh entry) and picked up automatically by
`.claude/test-cmd`'s `staging/plugin/scripts/tests/*.test.sh` glob. It invokes
`content-union-check.sh` directly against disposable `mktemp -d` fixtures for the new edge cases,
and separately against the three **pre-existing** fixtures in `claude-md-slim/tests/fixtures/`
(mirroring `run-tests.sh`'s own T04 assertions), giving that pass/fail contract real, continuous
CI coverage for the first time. `run-tests.sh` itself is read for compatibility but is not
rewritten or extended — see Alternatives (§3, D4) for why.

### 2.4 Design-time verification performed before committing to this Decision

Every claim above was checked by direct execution in this repository's own runtime during
planning, not assumed:

- §1.1's substring reproduction, §1.3's multiplicity reproduction, and D3's naive-fix regression
  strawman were all run against the real, unmodified `content-union-check.sh` (and, for the
  strawman, an isolated scratch script) under the actual macOS system shell.
- The full proposed replacement (D1 + D2 + D3 combined, byte-identical to the plan's Task 2
  contract) was executed under `/bin/bash --version` confirmed `3.2.57(1)-release
  (arm64-apple-darwin25)` — the exact target runtime named by the bash 3.2 invariant — against:
  the substring-bug case (correctly fails now), an exact-match positive control (passes), the
  isolated multiplicity case (passes, unchanged from today), the trailing-whitespace case (passes,
  by design now), the empty-line/`<!--`-comment skip logic (unchanged, passes), and both of the
  three pre-existing fixtures' complete/incomplete combinations (pass/fail respectively, identical
  to the current script's outcomes — no regression).
- `sed`'s dialect was confirmed directly (`sed --version` → `illegal option --`, the BSD-sed
  signature, `/usr/bin/sed`) — the trim pattern (`s/[[:space:]]*$//`, a basic POSIX bracket
  expression, no GNU-only shorthand) needs no dialect-specific branching.
- No orphaned temp files were left behind after any run (`ls /tmp/content-union-check.*` empty
  after the full matrix), confirming the unconditional `rm -f "$UNION_TMP"` cleanup path is
  correct for both the pass and fail exit branches (there is no exit point between `mktemp` and
  that `rm -f`).

### 2.5 Test strategy

One new hermetic file, `staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh`,
five lettered sections (A: substring bug, B: multiplicity exemption, C: trailing-whitespace
tolerance + skip-logic non-regression, D: regression parity against the three pre-existing
fixtures, E: SKILL.md documentation anchor), nine assertions total. Sections A-C invoke the real
script directly against disposable `mktemp -d` fixtures; Section D invokes it against the real,
pre-existing `claude-md-slim/tests/fixtures/` files (resolved via the file's own
`STAGING`-relative path derivation, never `$HOME`); Section E is a static `grep` anchor on
SKILL.md's new subsection. Full task-by-task RED/GREEN predictions, each verified live during
planning, are in the implementation plan.

---

## 3. Alternatives considered

### D1 — how to make the match whole-line

- **Alt 1a — escape the line for ERE/BRE and use `grep -qE "^${line}\$"` (anchored regex)
  instead of `-xF`.** **Rejected:** reintroduces exactly the unescaped-interpolation-into-a-regex
  risk this same roadmap's ADR-0031 (Finding 2, `enumerate-sources.sh`) independently removed from
  a sibling script for the identical reason — CLAUDE.md content routinely contains `.`, `*`, `$`,
  `[`, `(` (e.g. literal text like `.claude/rules/*.md`), and correctly escaping every ERE
  metacharacter in arbitrary user content is its own bug surface, not a simplification. `-xF` is
  bash/grep-native whole-line **fixed-string** matching — zero escaping needed by construction —
  and is a one-flag addition to the `-F` already in use today for the same reason.
- **Alt 1b — keep the per-outfile loop, just add `-x` to the existing per-outfile `grep -qF`
  call (no combined union temp file).** **Rejected:** does not, by itself, solve trailing-whitespace
  tolerance (D3) — each outfile's raw lines would still need trimming somewhere, either inline per
  original-line-times-per-outfile (repeated, outfile re-read on every comparison) or via a
  normalized copy of each outfile built once. Building one combined, pre-trimmed union file
  amortizes the trim to exactly one `sed` pass per outfile regardless of how many original lines
  are checked, and reduces the per-line check to a single `grep` call instead of an outfile loop —
  simpler code that is also the version actually verified in §2.4.
- **Chosen: Alt 1c — single combined union temp file, `grep -qxF` once per original line.**
  Smallest, single-pass mechanism; matches the script's own name (`content-union-check` literally
  builds and checks against a union); verified correct and BSD/GNU-portable in §2.4.

### D2 — what to do about multiplicity

- **Alt 2a — implement full occurrence-count comparison** (count each distinct line's frequency
  in the original and in the union; fail if any line's union-count is lower). **Rejected:** (1)
  conflicts with ADR-0019 D6's own set-based "union(output) ≥ union(input)" wording and the
  script's own name; (2) would make Step 7.4's already-shipped merge-dedup feature and the
  `--global` duplicate-removal feature (Step 3/4) *fail the very gate meant to protect their
  output* — the invariant would reject the pipeline's own correct, intended behavior; (3) SPEC
  explicitly names the documented-exemption branch as an equally acceptable resolution, and this
  ADR's own root-cause analysis (§1.3) shows the current script has always behaved this way, so
  "fixing" it would be introducing new, stricter behavior under the same issue number as a
  substring-matching bugfix, conflating two different kinds of change.
- **Alt 2b — implement multiplicity, but only within a single output file (not across the whole
  union), to catch "the same section was pasted twice into one rules file" while still allowing
  cross-file consolidation.** **Rejected:** adds a second, narrower invariant with its own edge
  cases (what counts as "the same file" across CREATE vs MERGE plans; whether the pre-existing
  content of a MERGE target counts) for a scenario SPEC does not name as a required success
  criterion, and that the SPEC's own two edge cases do not exercise. Speculative scope beyond the
  stated requirement.
- **Chosen: Alt 2c — documented exemption, set-based union matching only.** Matches ADR-0019 D6's
  original wording, matches the pipeline's own already-shipped dedup/duplicate-removal design,
  matches SPEC's explicit "or document" branch, and matches the current script's actual,
  live-verified behavior (§1.3) — the smallest change that resolves the SPEC ambiguity without
  contradicting either the architecture or the shipped feature set.

### D3 — how to tolerate trailing whitespace

- **Alt 3a — do not trim; accept the regression as a documented new limitation.**
  **Rejected:** verified live (§2.3/D3) that this is a real, reproducible regression against a
  case the current script already handles (by accident) — trading a fixed bug for a newly broken
  one on a **hard gate** whose false-positive failure mode (aborting a valid extraction plan) has
  direct UX cost every time a real CLAUDE.md, edited across multiple tools with different
  trailing-whitespace-on-save behavior, is run through the skill. SPEC explicitly instructs
  trimming; this alternative would silently ignore that instruction.
- **Alt 3b — trim all whitespace (leading and trailing) or collapse internal whitespace runs.**
  **Rejected:** over-broad relative to SPEC's explicit "trailing-whitespace" scope. Leading
  whitespace is semantically meaningful in Markdown (list nesting level); collapsing internal
  whitespace runs could silently equate two lines that are meaningfully different content (e.g. a
  double space vs single space inside a sentence). Trailing-only trim is the minimal change that
  addresses the specific, verified failure mode (D3) without touching semantics SPEC did not ask
  to change.
- **Chosen: Alt 3c — trailing-whitespace-only trim, both sides, via `sed 's/[[:space:]]*$//'`.**
  POSIX bracket expression, verified identical under both BSD sed (macOS, this environment) and
  the GNU-sed dialect `docs-ci.yml`'s `ubuntu-latest` runner uses (no GNU-only shorthand like
  `\s` used); matches SPEC's literal instruction; verified in §2.4 to fix D3's regression while
  leaving leading/internal whitespace untouched.

### D4 — where the new tests live

- **Alt 4a — extend the existing `tests/run-tests.sh` (its T04 block) with the new assertions.**
  **Rejected:** `run-tests.sh` is `$HOME`-coupled and confirmed not part of `docs-ci.yml`'s
  explicit list (§1.2) — extending it adds assertions that still never execute in CI, leaving
  unaddressed the exact coverage gap this ADR's own root-cause analysis identifies as at least
  consistent with how the original bug shipped unnoticed. SPEC's own "Stack" section explicitly
  directs new fixtures and harness tests to `docs-ci` coverage, not to the legacy location.
- **Alt 4b — rewrite `run-tests.sh` itself to be hermetic** (resolve paths relative to the script
  instead of `$HOME`, drop the deployed-copy coupling). **Rejected for this issue:** a materially
  larger diff touching a file SPEC's "Out" scope excludes ("Other claude-md-slim pipeline steps");
  `run-tests.sh` covers nine other assertions (T01-T03, T05-T10) unrelated to this fix, and
  retrofitting its path convention is an independent, separately-scoped improvement. Flagged as a
  candidate follow-up issue (Consequences, Negative) rather than silently expanded into this ADR's
  scope or silently left unmentioned — the same "disclose, don't silently fix or silently ignore"
  discipline ADR-0031 applied to its own three `$HOME`-coupled test files.
- **Chosen: Alt 4c — new file, `staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh`,**
  following the established naming and structural convention of the ten existing files in that
  directory (`SCRIPTS`/`STAGING`-relative path derivation, `mktemp -d` + disposable fixtures,
  `ok()`/`bad()`/`PASS`/`FAIL` idiom), appended to `docs-ci.yml`'s explicit list and picked up
  automatically by `.claude/test-cmd`'s existing wildcard glob with no edit needed there.

---

## 4. Consequences

### Positive

- **Closes the named audit finding (2.8) in the sole content-preservation hard gate.** The
  specific reproduction SPEC names (`## Git` vs `## GitHub Actions`) is fixed and covered by a
  regression test, verified live both before (fails to catch it) and after (catches it) the fix.
- **Whole-line matching eliminates an entire class of false "preserved" claims, not only the one
  named example.** Any original line that happens to be a text prefix of some surviving,
  unrelated line was previously silently declared preserved. This class closes entirely, not just
  the specific heading pair SPEC cites.
- **The trailing-whitespace trim (D3) was proven necessary, not assumed necessary** — a live
  strawman test confirmed that a naive "just add `-x`" fix would have newly regressed a
  currently-accidentally-working case. Catching this during architecture, before the coder writes
  any code, avoids a real, disclosed round-trip.
- **The multiplicity question is resolved with a stated decision, not left ambiguous or silently
  deferred.** SKILL.md gains an explicit, named subsection explaining why occurrence counts are
  out of scope, grounded in ADR-0019's own wording and the pipeline's own shipped dedup/
  duplicate-removal design — a future reader (or auditor) does not have to re-derive this
  reasoning from scratch.
- **The script gains real, continuously-run CI coverage for the first time**, closing the gap
  this ADR's own root-cause analysis (§1.2) identifies as at least consistent with why the
  original substring bug shipped unnoticed for five weeks. The same new file also gives the three
  pre-existing fixtures' pass/fail contract CI coverage they never had via `run-tests.sh` alone.
- **Zero blast radius outside one script, one new test file, one `docs-ci.yml` line, and one
  SKILL.md subsection.** No manifest schema change, no new skill, no new hook, no agent change, no
  permission-mode change.
- **Every claim in this ADR was verified by live execution** — the bug reproduction, the
  multiplicity baseline, the naive-fix regression strawman, and the full final contract, all
  executed under the actual target runtime (`/bin/bash` 3.2.57, BSD `sed`) during architecture,
  not reasoned about from source alone. This matches, and extends to this ADR, the "verify by
  live execution" discipline ADR-0027 through ADR-0031 already established for this roadmap.
- **A pre-existing, orthogonal gap (the `--global`/`DUPLICATE`-vs-global-file interaction, §1.4)
  was found and explicitly disclosed rather than silently carried forward or silently expanded
  into this ADR's scope** — the sixth-or-so instance of this roadmap's "disclose an
  environment/design gap rather than silently assert completeness" idiom (ADR-0026 through
  ADR-0031).

### Negative

- **The documented multiplicity exemption (D2) is a real, disclosed limit on what the hard gate
  can catch.** It cannot distinguish "this line's count dropped from 2 to 1 because Step 7.4's
  sanctioned merge-dedup fired" from "this line's count dropped from 2 to 1 for some other,
  unintended reason" — it never rejects either outcome, because it never compares counts at all.
  In practice the only two designed ways multiplicity can drop are Step 7.4's merge-dedup and
  Step 3/4's `--global` duplicate-removal, but the check does not verify a given reduction
  actually came from one of these mechanisms.
- **The `--global`/`DUPLICATE`-vs-global-file gap (§1.4) is not fixed by this ADR.** A `--global`
  run producing at least one `DUPLICATE` section was already relying on accidental substring
  survival to pass the gate before this fix; after this fix, that accidental survival path is
  narrower (whole-line matching is strictly more precise), so such runs may newly and correctly
  start failing the gate where they previously passed by luck. This is not a regression introduced
  by this ADR's own reasoning (the gap already existed and the invariant was already being
  violated in that scenario) but it is a visible behavior change for any project using `--global`
  with duplicate sections, and it is flagged here as a candidate follow-up issue rather than
  silently left for a future bug report to rediscover.
- **The new hermetic test file does not exercise `run-tests.sh` itself.** Section D reimplements
  T04's two assertions against the real staging fixtures directly, but does not prove
  `run-tests.sh`, once deployed to `~/.claude`, will pass — that remains true only after a human
  runs the separately human-gated sync step, the same disclosed "deployed stays stale until sync"
  convention ADR-0025 through ADR-0031 already established.
- **`run-tests.sh`'s own `$HOME`-coupling is not fixed here** (Alt 4b, rejected for this issue) —
  it remains a standing, disclosed gap and a reasonable candidate for its own future issue,
  alongside the three `$HOME`-coupled files ADR-0031 already flagged for `refactor-snapshot` and
  `deep-refactor`.
- **Marginally larger script and one additional subprocess per original line.** The script grows
  from 70 to roughly 81 lines; each original line now spawns one `sed` invocation (trailing-
  whitespace trim) in addition to the existing `grep`, and each output file is now read once
  through `sed` to build the union. Bounded, linear cost on CLAUDE.md-sized files (hundreds of
  lines); not a performance concern for a documentation-tooling script invoked a handful of times
  per skill run.

### Neutral

- **No manifest schema change, no new skill, no new hook, no `settings.json` change, no
  permission-mode change** anywhere in this ADR.
- **The script's black-box contract is unchanged**: same argv shape (`<original> <output1>
  [<output2> ...]`), same exit codes (0/1), same stderr summary line format (`"<N> lines from
  original not found in any output file"`). Only which inputs pass or fail changes. SKILL.md's
  Step 5.2 caller needs no change beyond the new documentation subsection.
- **The deployed `~/.claude/skills/claude-md-slim` copy keeps today's defective (substring-
  matching) behavior until a human runs the separately human-gated `sync-to-claude.sh --apply`** —
  the same disclosed, established convention as ADR-0025 through ADR-0031, repeated here rather
  than assumed already understood.
- **This ADR neither opens nor forecloses a future fix for the `--global`/`DUPLICATE` gap
  (§1.4)** — it is explicitly left for a separately-scoped follow-up issue to decide between
  adding the global file as a union input and exempting `DUPLICATE`-removed lines by construction.

---

## 5. References

- `SPEC.md` (repo root) / `docs/specs/36-claude-md-slim-whole-line-content-union.spec.md` — this
  issue's spec (confirmed byte-identical)
- `docs/architecture/ADR-0019-claude-md-slim-skill.md` — original design of the skill and the
  content-preservation invariant (D6); amended by this ADR (matching semantics clarified, not the
  underlying decision)
- `docs/architecture/ADR-0027-31-c2c-bsd-slug-autopilot-gates.md`,
  `docs/architecture/ADR-0028-32-manifest-helpers-guards.md`,
  `docs/architecture/ADR-0029-33-hook-verify-session-filter.md`,
  `docs/architecture/ADR-0030-34-scope-guards.md`,
  `docs/architecture/ADR-0031-35-refactor-snapshot-deep-refactor.md` — structural, test-harness,
  and disclose-don't-assume precedent this ADR reuses directly
- `staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh` — the file this ADR
  patches
- `staging/plugin/skills/claude-md-slim/SKILL.md` — gains the "Content-preservation exemptions"
  subsection (Step 5.2)
- `staging/plugin/skills/claude-md-slim/tests/run-tests.sh`,
  `staging/plugin/skills/claude-md-slim/tests/fixtures/{sample-claude-md.md,expected-trimmed.md,
  expected-shell-rules.md}` — confirmed `$HOME`-coupled test file (not edited, §3 D4) and its
  three pre-existing fixtures (reused directly by the new hermetic test's Section D, unmodified)
- Implementation plan: `docs/superpowers/plans/2026-07-11-36-claude-md-slim-union-check.md`
