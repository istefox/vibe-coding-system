# ADR-0028 — concept-to-code: manifest helper guards, exit codes, and YAML escaping

**Status:** Accepted
**Date:** 2026-07-11
**Author:** istefox
**Supersedes:** none
**Superseded by:** none
**Related:**
- SPEC: `docs/specs/32-manifest-helpers-count-guards-exit-codes.spec.md` (= `SPEC.md` at repo root, GitHub issue #32,
  confirmed byte-identical by diff before writing this ADR)
- ADR-0024 (`vendor-deployed-only-skills-and-hooks`) — the hermetic-test-file pattern (own `SCRIPTS`/`STAGING` path
  derivation, zero `$HOME` dependency) and the local-`test-cmd`-glob-vs-CI-explicit-list split this ADR's new test
  file reuses
- ADR-0025 (`refresh-stale-staging-copies`) — confirms `staging/` is this roadmap's working source of truth;
  deployed `~/.claude` stays out of scope by the same established convention
- ADR-0026 (`clean-public-repo-private-history`) — structural ADR precedent (per-finding Decision → Alternatives →
  Positive/Negative/Neutral Consequences) and the "disclose an environment-dependent coverage gap rather than
  assert unverified confidence" idiom this ADR reuses for a third such gap (§4 Negative)
- ADR-0027 (`c2c-bsd-slug-autopilot-gates`) — the immediately preceding issue (#31) in this same roadmap and same
  directory; its own §1 baseline and §3.5 explicitly deferred every finding this ADR now fixes (the manifest
  helper exit codes, the title-escaping crash, the five PATH-RULE call sites, and the "44 total" pair-count line)
  to issue #32 — this ADR is that deferred work
- `staging/plugin/skills/concept-to-code/scripts/manifest-set-flag.sh` — the already-correct, already-shipped
  contract (`mktemp` + `trap` cleanup + exit 4 on write failure) this ADR's Finding 2 fix mirrors verbatim into
  `manifest-set-artifact.sh` and `manifest-set-gate.sh`
- `staging/plugin/skills/autopilot-build/SKILL.md` — the `yaml.safe_load` pre-flight consumer whose crash motivates
  Finding 3, and independent confirmation that PyYAML is already a project dependency, not one newly introduced by
  this ADR's test design
- Implementation plan: `docs/superpowers/plans/2026-07-11-32-manifest-helpers-guards.md`

---

## 1. Context

`concept-to-code` is the orchestrator skill implementing the concept→code workflow (blueprint §11) as a YAML
manifest-driven state machine (ADR-0003), extended with Express/Hybrid routing (ADR-0017) and an in-chain autopilot
mode (ADR-0020). It was vendored byte-identical to the deployed copy by ADR-0024 (#28). Issue #31 (ADR-0027) fixed
five separate defects in the same skill and, in doing so, explicitly identified and deferred five more to this
issue, #32 — SPEC.md (issue #32) formalizes exactly those five as three objectives (findings 3.3–3.7 in the
originating audit's own numbering). This ADR calls them Finding 1–5 for readability, cross-referenced to SPEC's
scope bullets throughout.

**Baseline, re-verified before planning (2026-07-11):** `for t in staging/plugin/scripts/tests/*.test.sh; do bash
"$t" || exit 1; done` (the repo's own `.claude/test-cmd`) is green, 7/7 — one more file than ADR-0027's own 6/6
baseline, because #31 added `concept-to-code-bsd-autopilot-gates.test.sh` (17 assertions) during its own execution.
Re-run in this session, not assumed. `grep -rln "hitl_gates\|gate_count" staging/plugin/scripts/tests/*.test.sh`
returns nothing — confirmed zero collision risk between Finding 1's fix and any existing test.

**Line-number relocation methodology.** SPEC's five findings cite line numbers from "the 2026-07-10 deployed
copy" — i.e., the state `SKILL.md` was in immediately after #31 (ADR-0027) landed. Every findings-adjacent line
number in this ADR was independently re-derived by diffing the pre-#31 commit (`5e87329`, ADR-0024's own vendoring
commit — confirmed via `git log --oneline -- staging/plugin/skills/concept-to-code/SKILL.md`, which shows exactly
two commits: `5e87329` then `103886e`, ADR-0027's own fix) against the current working tree, matching each cited
line's **content** (not its position) and re-locating that exact string in the file as it stands today. Every
relocated line number below was confirmed this way, not guessed from context.

### Finding 1 (P2, invariant 9 count guard, `manifest-validate.sh:147`, was SPEC's line 130)

```bash
gate_count="$(grep -c '^  - gate:' "$MANIFEST" 2>/dev/null || echo 0)"
```
`grep -c PATTERN FILE` already prints a numeric count on **every** outcome, including zero matches — `grep -c`'s
only variable behavior is its **exit status** (0 if at least one match, 1 if none), not whether it prints a count.
When there are zero lines matching `- gate:` (2-space indented), `grep -c` prints `0` to stdout **and** exits `1`; the `||` then fires,
running `echo 0`, which prints a **second** `0`. The command substitution captures both, embedded-newline and all:
`gate_count` becomes the three-character string `"0\n0"`, not the integer `0`. The subsequent
`[ "$gate_count" -lt "$min_gates" ]` then receives a two-line, non-integer operand.

**Empirically verified in this session** against a hand-built fixture (a real manifest from `manifest-init.sh`
with its `hitl_gates:` block's four `- gate:` entries (2-space indented) stripped by `awk`, key line retained):
```
$ bash manifest-validate.sh empty-gates.yml
manifest-validate.sh: line 155: [: 0
0: integer expression expected
$ echo $?
0
```
`[` prints its error to stderr and returns exit status 2, which the surrounding `if` treats as **false** — `fail`
is never called, `ERRORS` is never incremented for invariant 9, and the manifest **validates successfully**
despite having zero HITL gates recorded. This is a silent skip, not a crash: nothing in the script's own exit code
or the visible pass/fail summary reveals invariant 9 never actually ran.

### Finding 2 (P2, exit-code contract, `manifest-set-artifact.sh:35-45`, `manifest-set-gate.sh:46-55`, was SPEC's
lines 45/55)

Both scripts perform their write as `awk ... > "$TMP" && mv "$TMP" "$MANIFEST"` with **no** `||` failure handling
on either the target-field write or the `last_updated_at` bump, and both end in an unconditional `exit 0`.
`manifest-set-flag.sh` (already shipped, already the reference contract every other manifest-mutation helper in
this file is measured against) already does this correctly: `TMP=""`, `trap 'rm -f "${TMP:-}" ...' EXIT` set
before the first `mktemp`, and `... || { echo "...: write failed..." >&2; exit 4; }` after every write.

**Empirically verified in this session**, real (unfixed) `manifest-set-artifact.sh` against a manifest whose
containing directory was `chmod 555`'d (read + execute, no write — confirmed this reliably fails a same-filesystem
`mv` via `rename(2)`'s directory-write-permission requirement, independent of the target file's own permission
bits, on this session's real Darwin/BSD environment, non-root, `id -u`=`501`):
```
$ bash manifest-set-artifact.sh <manifest> spec /some/path/SPEC.md
mv: rename ... Permission denied
mv: rename ... Permission denied
$ echo $?
0
```
Exit `0`, and the manifest's `spec:` field is left `null` — the caller has no way to distinguish this from a
genuine, successful no-op write. The same reproduction, same technique, was independently repeated for
`manifest-set-gate.sh` (targeting an existing gate's `status` field) with the identical outcome: exit `0` on a
provably failed write.

### Finding 3 (P2, unescaped title, `manifest-init.sh:61`, was SPEC's line 61 — unchanged position, #31 never
touched this file)

```bash
echo "topic_full_title: \"$title\"" >> "$T"
```
`$title` is interpolated into a YAML double-quoted scalar with **no** escaping. A title containing a literal `"`
breaks the scalar's own delimiters; a title containing `\` is not itself YAML-illegal but, once quotes are also
escaped, backslash-then-quote ordering matters for round-trip correctness (see Decision 2.3).

**Empirically verified in this session**, real (unfixed) `manifest-init.sh` with title `Feature "Quoted" Title`:
```
$ grep topic_full_title <manifest>
topic_full_title: "Feature "Quoted" Title"
$ python3 -c "import yaml; yaml.safe_load(open('<manifest>'))"
yaml.parser.ParserError: while parsing a block mapping ... expected <block end>, but found '<scalar>'
```
This is the exact crash SPEC's finding describes against `autopilot-build`'s own pre-flight, which calls
`yaml.safe_load(open(manifest))` at four separate checks (`staging/plugin/skills/autopilot-build/SKILL.md`,
Checks 3/4/6/7, confirmed by reading) — any of the four aborts the same way on an affected manifest, not a
hypothetical future consumer.

### Finding 4 (P2, PATH RULE violations, `SKILL.md`, was SPEC's lines 531/533/1146/121/1323)

`SKILL.md:230` states the file's own rule: "**PATH RULE — all scripts use the absolute prefix
`~/.claude/skills/concept-to-code/scripts/`... Every bash call below must use the full absolute path.**" Five
specific `manifest-set-flag.sh` invocation sites violate it (content-matched from SPEC's stale line numbers to
their current positions, confirmed by direct reading, all five 100% distinct surrounding text — no two collide):

| SPEC's line (stale) | Current line | Text today |
|---|---|---|
| 121 | 120 | `` (via `scripts/manifest-set-flag.sh <manifest> anonymize true`); proceed to step 8b. `` |
| 531 | 547 | `` **exit 0 (VERIFIED)** → `bash manifest-set-flag.sh <manifest> hook_verified true` `` |
| 533 | 549 | `` **exit 1 (REFUTED)** → `bash manifest-set-flag.sh <manifest> hook_verified false`. `` |
| 1146 | 1175 | `` `[y]` → set `manifest.anonymize = true` (via `scripts/manifest-set-flag.sh <manifest> anonymize true`); proceed. `` |
| 1323 | 1352 | `` `[yes]` → `scripts/manifest-set-flag.sh <manifest> anonymize true`; proceed. `` |

`grep -n "manifest-set-flag.sh" SKILL.md` returns 10 total mentions; 4 others are already correct and 1 (the bare mention at SKILL.md:569, disclosed in §3.6) is deliberately deferred
(`SKILL.md:249`, the canonical "Helper scripts:" declaration, and `SKILL.md:1612`, both already
`~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh`) or are descriptive prose that never instructs a
call (`SKILL.md:554` "do not call `manifest-set-flag.sh`"; `SKILL.md:734` "NOT via `manifest-set-flag.sh`"). This
10-mentions/5-violations/4-already-fine/1-deferred split independently reproduces SPEC's own count of exactly five — strong
corroboration that the relocation above is correct and complete, not an approximation.

One additional bare mention was found during this ADR's research and is **not** one of the five: `SKILL.md:569`,
inside the Step 5 autopilot-default bracket, "record `hook_verified = false` via `manifest-set-flag.sh`." This is
disclosed, not silently fixed nor silently ignored — see Decision 2.4 and Alternatives §3.6 for why it is
deliberately left out of this ADR's scope.

### Finding 5 (P2, transition-pair count reconciliation, `SKILL.md:221/237` + `manifest-transition.sh:50`, was
SPEC's lines 213/229/50)

Three numbers claim to describe the same "total legal transition pairs" metric and disagree with each other and
with the actual script:
- `SKILL.md:221`: "Legal transition pairs (**44** total — 26 standard + 6 express + 12 hybrid...)"
- `SKILL.md:237`: "...performs legal state transitions atomically (**51** pairs)."
- `manifest-transition.sh:50`: "# Build legal transition pairs into temp file (spec §3.3, **16** transitions)"

**Independently recounted in this session** (not taken on faith from SPEC or from ADR-0027's own prior count) by
direct line-by-line enumeration of `manifest-transition.sh`'s `PAIRS` block (lines 52–101), cross-checked with a
second, mechanical extraction (`awk` range-match on the block boundaries, piped through
`grep -Ec '^ *echo "[a-z_0-9]+,[a-z_0-9]+" >'`, deliberately avoiding GNU-only regex shorthands like `\s`): **48
total** — 28 in the unlabeled/standard section (lines 52–79, includes the four Gate 0d routing pairs and the two
direct-close shortcuts), 6 in the Express section (lines 81–86, includes the `gate_e3_verify,completed`
direct-close shortcut), 14 in the Hybrid section (lines 88–101, includes the two `gate_h1c_macos_ux` pairs). This
matches ADR-0027 §1's own aside ("confirmed... 28 standard + 6 express + 14 hybrid = 48 actual pairs") exactly,
now independently re-derived rather than merely cited.

Separately, `SKILL.md:224`'s Hybrid pair enumeration lists only 12 items — missing
`gate_h1b_brainstorm→gate_h1c_macos_ux` and `gate_h1c_macos_ux→step_h2_plan` (confirmed absent: `grep -n
'gate_h1c_macos_ux→step_h2_plan'` against the no-space compact-list format returns nothing today; the only
matches are the differently-formatted, pre-existing prose sentences at `SKILL.md:1020` and `:1025`, which use
spaces around the arrow and are untouched by this finding).

During this same recount, two **more** inconsistencies in the identical four-line paragraph (`SKILL.md:221-224`)
were found, neither named by SPEC's literal "44, 51, 16" list:
- `SKILL.md:222`, the Standard bullet: "all **21** existing pairs unchanged" — disagrees with both the header's
  own "26 standard" (itself already wrong) and the actual "28 standard."
- `SKILL.md:223`, the Express bullet: enumerates only 5 of the section's 6 actual pairs, omitting
  `gate_e3_verify→completed` (the direct-close shortcut backing Gate E3's "Commit later" option, per ADR-0027
  §2.5 — a real, used pair, not dead code).

See Decision 2.5 and Alternatives §3.5 for the scope-boundary reasoning covering both of these.

## 2. Decision

Fix exactly the five findings above, add one new hermetic test file (21 assertions) wired into both the local
`test-cmd` glob and CI's explicit list, and touch no other behavior. `manifest-transition.sh`'s legal-pair
**table** is not modified (only its line-50 **comment**); no new `PAIRS` entries are needed in `sync-to-claude.sh`
(all four scripts already have `PAIRS` mappings, confirmed by reading — this issue edits existing synced files, it
does not add new ones).

### 2.1 Finding 1 — drop `|| echo 0`, guard the truly-empty case explicitly

```bash
gate_count="$(grep -c '^  - gate:' "$MANIFEST" 2>/dev/null)"
if [ -z "$gate_count" ]; then
  gate_count=0
fi
```
One line becomes four: the `grep -c` call loses its `|| echo 0`, and a defensive `-z` guard handles the case
`grep` itself cannot run at all (e.g., a read error the `2>/dev/null` swallowed, leaving stdout genuinely empty —
distinct from the "zero matches, prints `0`, exits 1" case `grep -c` already handles correctly on its own).
Invariant 9's four subsequent lines (`chain_path_val` computation, `min_gates` case, the final `if`/`fail`) are
byte-identical, unchanged. **Empirically verified in this session** against the same fixture used in Finding 1's
Context: the fix produces a clean single-line `gate_count=0`, and `[ "0" -lt 4 ]` correctly evaluates true, so
`fail` fires as intended.

Invariant 9's own pre-existing `chain_path_val` computation (a separate, identical three-line pipeline four lines
below invariant 7's own copy, added by #31/ADR-0027) is left **completely untouched** — same reasoning ADR-0027
§3.3 already gave for not touching it (this issue is scoped to the `gate_count` line only; deduplicating the two
computations is not named by SPEC and is not attempted here — see Alternatives §3.2).

### 2.2 Finding 2 — mirror `manifest-set-flag.sh`'s exit-4 contract into both scripts, verbatim

Both `manifest-set-artifact.sh` and `manifest-set-gate.sh` gain, immediately before their first `mktemp` call:
```bash
TMP=""
TMP2=""
trap 'rm -f "${TMP:-}" "${TMP2:-}"' EXIT
```
and each of their two `awk ... > "$TMP{,2}" && mv "$TMP{,2}" "$MANIFEST"` lines gains
`|| { echo "<script-name>: write failed for $MANIFEST" >&2; exit 4; }`. The final `exit 0` is otherwise unchanged
(only reached if both writes succeeded). Each script's own header "Exit:" comment gains `| 4 write failed`,
matching `manifest-set-flag.sh`'s own header exactly. No other line in either script changes.

**Empirically verified in this session**, both fixed scripts, both directions: happy path (writable directory)
still exits `0` with the target field correctly written; failure path (`chmod 555` on the manifest's containing
directory) exits `4` with the field **unchanged** from its pre-call value — confirming the existing
`awk > TMP && mv` pattern's atomicity is preserved on failure (a failed `mv` never touches the original file; only
a successful one replaces it), a property worth stating explicitly since the exit-code fix alone does not
guarantee it.

### 2.3 Finding 3 — escape backslash before quote, embed the escaped value

```bash
title_esc="$(printf '%s' "$title" | sed 's/\\/\\\\/g; s/"/\\"/g')"
```
inserted once, before the `T="$(mktemp)"` atomic-write block; line 61 becomes
`echo "topic_full_title: \"$title_esc\"" >> "$T"`. Order matters: backslashes are escaped **first** (`\` →
`\\`), then quotes (`"` → `\"`) — reversing the order would re-escape the backslashes the quote-escaping step
itself just inserted, corrupting the round-trip. `sed`'s `s///g` with literal backslash/quote character classes is
POSIX BRE, identical on BSD and GNU `sed` — no OS branch needed, same "portable by construction" reasoning
ADR-0027 §2.1 used for its own `awk` fix.

**Empirically verified in this session**, fixed `manifest-init.sh`, title `Feature "Quoted" \Backslash\`
(containing both characters SPEC's edge case names): the manifest's `topic_full_title:` line becomes
`"Feature \"Quoted\" \\Backslash\\"`, and `yaml.safe_load` parses it back to the **exact original string**
(`repr()`-compared, not just "parses without error") — confirmed via a Python one-liner that receives both the
manifest path and the expected value through environment variables rather than inline string interpolation (see
Alternatives §3.7 for why — a first attempt at inline interpolation genuinely failed during this session's own
test design, for the same class of reason this finding exists at all: a string containing quotes and backslashes
breaking the syntax of whatever it gets embedded into unescaped).

No other field in `manifest-init.sh` is escaped by this change — `slug` is already regex-validated to
`^[a-z0-9-]{1,40}$` (no special characters possible) and `root`/`mode` are not free-text. SPEC's finding and edge
case name `topic_full_title` specifically; no other field has a demonstrated defect.

### 2.4 Finding 4 — absolute-prefix all five named sites; disclose, do not touch, the sixth

Each of the five sites gets its own `scripts/manifest-set-flag.sh` or bare `manifest-set-flag.sh` replaced with
`~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh`, with the surrounding sentence otherwise
byte-identical (this is a path-prefix substitution, not a rewrite). `SKILL.md:569`'s sixth, unnamed bare mention
is **left untouched** — recorded here as a disclosed, deliberately-deferred candidate, not silently fixed and not
silently missed. See Alternatives §3.6 for the reasoning distinguishing this from Finding 5's broader treatment
below.

### 2.5 Finding 5 — reconcile the whole paragraph to the mechanically-verified 48, not just the three named
numbers

`SKILL.md:221`'s header becomes "Legal transition pairs (**48** total — **28** standard + 6 express + **14**
hybrid, including Gate 0d routing and direct-close shortcuts):" — all four numbers on this one line change
together, since they are one arithmetic statement (44 = 26+6+12 was already self-consistent-but-wrong; 48 =
28+6+14 must be self-consistent-and-right). `SKILL.md:237`'s "(51 pairs)" becomes "(48 pairs)".
`manifest-transition.sh:50`'s comment becomes "...(spec §3.3, **48** transitions)" — a comment-only edit; the
`PAIRS` table itself is untouched.

`SKILL.md:224`'s Hybrid enumeration gains the two missing items, inserted in the state machine's own order (after
`gate_h1b_brainstorm→step_h2_plan`, matching the script's own line sequence): `gate_h1b_brainstorm→gate_h1c_macos_ux`,
`gate_h1c_macos_ux→step_h2_plan` — 12 items become 14.

Additionally, and disclosed as a deliberate extension beyond SPEC's literal "44, 51, 16" list (Alternatives §3.5):
`SKILL.md:222`'s Standard bullet becomes "all **28** existing pairs unchanged" (number only, sentence structure
untouched), and `SKILL.md:223`'s Express enumeration gains its own missing pair,
`gate_e3_verify→completed`, appended at the end (5 items become 6). Both are objectively-verifiable numeric/list
corrections in the exact same four-line block this finding names, not new judgment calls the way, say, Hybrid's
Gate H3 `Abort` wording was for ADR-0027 §3.4.

### 2.6 Test strategy and CI wiring

One new file, `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh`, hermetic (own
`SCRIPTS`/`STAGING` path derivation, zero `$HOME` dependency, mirrors the six existing files in the same
directory), 21 assertions across five lettered sections mapped 1:1 to the findings above:

- **Section A (Finding 1, 2 tests).** A1 (dynamic, genuine RED): a `manifest-init.sh` fixture with its
  `hitl_gates:` block's four entries stripped by `awk` (key line retained, zero `- gate:` lines under it) must
  FAIL validation with invariant 9's own message. A2 (dynamic, non-regression companion, already passing): an
  unmodified default fixture (4 gate lines) must keep validating PASS.
- **Section B (Finding 2, 4 tests).** B1/B3 (dynamic, genuine RED): `manifest-set-artifact.sh` /
  `manifest-set-gate.sh` against a manifest whose containing directory is `chmod 555`'d must exit `4` (directory
  permissions restored to `755` immediately after each assertion, before the file's own final cleanup trap runs).
  B2/B4 (dynamic, non-regression companions): both scripts' happy paths must keep exiting `0` and keep writing the
  target field correctly.
- **Section C (Finding 3, 3 tests).** C1 (dynamic, genuine RED): a title containing both `"` and `\` must produce
  a manifest whose `topic_full_title` round-trips through `yaml.safe_load` to the **exact original string** (env-
  var-passed expected value, not inline string interpolation — see Decision 2.3). C2 (static, genuine RED): the
  old unescaped `echo "topic_full_title: \"$title\""` source line is gone from `manifest-init.sh`; the new
  `title_esc` variable is present. C3 (dynamic, non-regression companion, already passing): a title with no
  special characters keeps round-tripping correctly.
- **Section D (Finding 4, 5 tests).** D1–D5 (static, genuine RED, one per site): each of the five relocated lines
  (current 120/547/549/1175/1352) is checked via a **compound** anchor — the absolute-prefixed script path plus
  enough of that specific line's own surrounding, non-shared text to be unique among the five (necessary because
  three of the five sites produce textually-similar, but not identical, resulting lines) — present.
- **Section E (Finding 5, 7 tests).** E1–E3 (static, genuine RED): the corrected header, the corrected
  `(48 pairs)` helper description, and `manifest-transition.sh`'s corrected comment are each present. E4 (static,
  genuine RED): both new Hybrid `gate_h1c` items are present, anchored on the no-space compact-list format
  specifically so the pre-existing, differently-formatted prose sentences at `SKILL.md:1020`/`:1025` (which use
  spaces around the arrow) cannot false-positive the check before the fix lands (verified empirically: the
  no-space form is confirmed absent today, the spaced form is confirmed present and untouched). E5/E6 (static,
  genuine RED): the corrected Standard-bullet "28" and the Express bullet's added `gate_e3_verify→completed` item
  are present. E7 (dynamic, mechanical proof, already passing today and expected to stay passing after this
  task's `SKILL.md` edits): a live re-count of `manifest-transition.sh`'s actual `PAIRS` block, independent of
  whatever the prose currently claims, equals exactly `48` — a permanent drift-detector: if a future edit adds or
  removes a pair without updating the prose, this assertion (not a static text match) is what catches it.

**CI wiring**, mirroring ADR-0024/26/27: `concept-to-code-manifest-helpers-guards` appended to
`.github/workflows/docs-ci.yml`'s explicit `for t in phase1 prep hook-probe hook-verify-workflow
pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates` list. No `.claude/test-cmd`
edit needed — its existing single line already globs `staging/plugin/scripts/tests/*.test.sh`. No
`sync-to-claude.sh` `PAIRS` entry for the new test file (same established exclusion as its three predecessors);
no new `PAIRS` entries for the four edited scripts either, since all four already have mappings (confirmed by
reading `sync-to-claude.sh` before writing this ADR).

**Explicitly not covered by an automated test:** SPEC's success criterion "No file under `~/.claude` modified" —
same process/review property ADR-0026/0027 already treated identically: enforced by the Pre-flight "writes are
confined to" list and a final `git status` check in the plan's last task, not by a hermetic unit test.

## 3. Alternatives considered

### 3.1 Finding 1's counting mechanism

**Chosen:** keep `grep -c`, remove only the erroneous `|| echo 0`, add an explicit `-z` guard (§2.1).

- **Alternative — replace `grep -c` with `grep PATTERN FILE | wc -l | tr -d ' '`.** Rejected. `grep -c` already
  prints a correct count on every outcome (zero matches included) — the *only* defect is the redundant `|| echo 0`
  appending a second value. Switching counting mechanisms entirely is a larger diff than the one-line defect
  requires, and introduces a **new** BSD-portability risk of exactly the class ADR-0027 Finding 1 was about: BSD
  `wc -l` right-pads its output with leading spaces (e.g. `"       0"`), which breaks the subsequent
  `[ "$gate_count" -lt "$min_gates" ]` integer comparison unless trimmed — the `tr -d ' '` needed to fix that is
  exactly the kind of "looks portable, isn't" trap this roadmap has repeatedly had to un-learn the hard way.

### 3.2 Whether to deduplicate invariant 7's and invariant 9's `chain_path_val` computations

**Chosen:** leave both untouched; fix only the `gate_count` line invariant 9 actually names.

- **Alternative — compute `chain_path_val` once near the top of the script and reuse it at both invariants,
  deleting the now-redundant second copy.** Rejected for the same reason ADR-0027 §3.3 gave when it made the
  identical decision in the opposite direction (leaving invariant 9 alone while fixing invariant 7): a duplicate
  three-line `grep`/`sed` pipeline computed twice is negligible runtime cost and zero functional risk, and this
  issue's own named scope is the `gate_count` line specifically, not a general invariant-9 refactor. Touching a
  second invariant's existing, working line to save three lines is not worth it.

### 3.3 Finding 2's failure-detection mechanism

**Chosen:** explicit `&& ... || { ...; exit 4; }` after each write, mirroring `manifest-set-flag.sh` verbatim
(§2.2).

- **Alternative — add `set -e` at the top of both scripts instead of per-write `||` handling.** Rejected. `set -e`
  is a well-documented bash footgun: it does not fire inside conditionals, inside command substitutions, for every
  command but the last in a pipeline, or inside functions called from a context that itself suppresses it — using
  it here would not reliably catch the `awk ... && mv ...` failure the way an explicit `||` does, and
  `manifest-set-flag.sh` (the already-shipped, already-correct reference) deliberately does not use `set -e`
  either. Mirroring the proven pattern beats introducing a differently-shaped, less-reliable one.
- **Alternative — retry the write once (e.g., after a short sleep) before failing.** Rejected. The failure modes
  this fix targets (permission denial, full disk, missing directory) are not transient — a retry would not resolve
  any of them, would add nondeterminism and latency to a helper script called synchronously inside a chain step,
  and `manifest-set-flag.sh`'s own contract has no retry either. Consistency with the established, simpler
  contract wins over speculative resilience nothing in this issue's scope asks for.

### 3.4 Finding 3's response to an unsafe title

**Chosen:** escape the offending characters so any title still produces a valid manifest (§2.3).

- **Alternative — reject titles containing `"` or `\` at `manifest-init.sh`'s existing validation stage (it
  already rejects a malformed slug the same way).** Rejected outright by SPEC's own edge case: "Title containing
  `"` or `\`: resulting manifest must parse with `yaml.safe_load`" describes a title that **must still work**, not
  one that must be refused. A reject-on-input design would also be a materially worse user experience for a
  legitimately common title shape (e.g. `Add "Quick Search" panel`), with no compensating safety benefit — the
  escape-on-write fix closes the actual defect (a crash) without narrowing what a human can name a feature.
- **Alternative — construct the whole manifest via a small Python script (using `yaml.dump` for every field, not
  just the title) instead of the existing bash `echo`/`printf` sequence.** Rejected. `manifest-init.sh` is
  bash-3.2 by explicit stack requirement (SPEC: "Bash 3.2-compatible scripts") and by its own header comment;
  introducing a Python dependency into the **write** path (as opposed to `autopilot-build`'s read-only pre-flight,
  which already depends on it) would be a disproportionately large architectural change for a single-field
  escaping defect, and would break this roadmap's consistent all-bash-helpers convention for every other script in
  this directory.

### 3.5 Finding 5's scope — the three named numbers only, or the whole paragraph

**Chosen:** reconcile the entire four-line `SKILL.md:221-224` paragraph (all four header numbers, the Standard
bullet, both incomplete enumerations) to the mechanically-verified 48, not just the three numbers SPEC's finding
text names by digit (§2.5).

- **Alternative — fix only `SKILL.md:221`'s "44 total" (with its own 26/12 sub-numbers, since they're
  arithmetically inseparable from "44" on the same line), `SKILL.md:237`'s "51 pairs", `manifest-transition.sh:50`'s
  "16 transitions", and complete the Hybrid enumeration — leave `SKILL.md:222`'s "21" and the Express bullet's
  missing pair untouched, symmetric with Finding 4's strict five-sites-only treatment.** This is the alternative
  most seriously considered, and the one this ADR treats differently from Finding 4 for four stated reasons: (1)
  unlike Finding 4's five sites — independent, scattered, unrelated locations across the whole 1875-line file —
  this finding's numbers all live in **one** four-line block that SPEC's own finding text already treats as a
  single unit to "reconcile," not a flat enumerated list; (2) fixing the header's 26→28 and 12→14 while leaving the
  immediately-adjacent "21" and the Express bullet's 5-of-6 enumeration untouched would leave the **same paragraph
  freshly self-contradictory** the moment this task's own diff lands — worse for a reviewer than not having touched
  the paragraph at all, and directly undermines "reconcile" as a stated goal; (3) both additions are
  objectively-verifiable numeric/list corrections (recount the script, compare to a listed count), not
  interpretive judgment calls the way, say, ADR-0027 §3.4's Hybrid Gate H3 wording question was — there is no
  plausible reading under which "21" or a 5-of-6 Express list is *already correct*; (4) the roadmap coordination
  note assigns this file's "pair-count text sync" to issue #32 with no further, later issue to defer to (unlike
  ADR-0027, which had #32 itself — this issue — as an explicit deferral target for exactly these numbers). None of
  these four reasons applies to Finding 4's sixth, unnamed `manifest-set-flag.sh` mention at `SKILL.md:569` — see
  §3.6 for why that one *is* left disclosed-but-untouched, preserving the same discipline in the case where it
  actually applies.

### 3.6 Finding 4's sixth mention (`SKILL.md:569`)

**Chosen:** leave it untouched; disclose it in this ADR's Context and Decision instead.

- **Alternative — fix it too, on the theory that it is the same defect class as the other five.** Rejected. Both
  SPEC ("at all five sites") and this issue's own orchestrator brief ("the five SKILL.md PATH-RULE call sites")
  treat the count as an already-settled, precisely-counted fact — independently re-derived and confirmed correct
  in this ADR's Context via the 10-mentions/5-violations/4-already-fine/1-deferred breakdown. `SKILL.md:569` is also
  grammatically distinct from the other five (a "via `X`" clause embedded in a longer conditional autopilot-default
  sentence, not a standalone "click/exit-code → `command`" bullet), and — critically, unlike Finding 5's
  paragraph — fixing the five named sites does not make line 569 newly or visibly self-contradictory; it simply
  remains exactly as under-specified as it always was. Expanding a scope both SPEC and the brief present as a
  closed, counted list is the "fix while you're in there" pattern this roadmap has repeatedly and explicitly
  rejected (ADR-0024 §3.2/§3.4, ADR-0025 §3.1/§3.2/§3.4, ADR-0026 §3.4, ADR-0027 §3.4) — recorded as a candidate
  follow-up, not silently fixed and not silently missed.

### 3.7 Finding 3's test oracle

**Chosen:** validate via a real `python3 -c "import yaml; yaml.safe_load(...)"` check, with the manifest path and
the expected original title passed through environment variables (§2.6, Section C).

- **Alternative — validate with a hand-written bash/awk structural check (quote-parity counting, escape-sequence
  matching) instead of depending on PyYAML.** Considered and used only as an informal, local verification aid
  during this ADR's own research — not adopted for the shipped test. A hand-derived check can only prove "my
  escaper produced what I, the same author, expected it to produce" — a tautology if the author's mental model of
  correct YAML escaping is itself subtly wrong (e.g., escape-order errors, which this exact finding's fix design
  had to get right). SPEC's own success criterion names `yaml.safe_load` specifically, and PyYAML is **already** a
  hard dependency of this project (`autopilot-build/SKILL.md`'s four pre-flight checks call it directly, confirmed
  by reading, predating this ADR) — using the same authoritative, independent parser as the oracle is strictly
  stronger evidence than re-deriving expected output by hand, and introduces no dependency this project did not
  already have.
- **Alternative — interpolate the expected title directly into the Python source via shell string substitution
  (e.g., a triple-quoted literal built from `$TITLE`).** Rejected after a genuine failure during this session's own
  test design: a title containing both `"` and `\` (the exact class this finding is about) breaks naive
  interpolation into an embedded language's own string-literal syntax — the identical failure mode as the
  underlying bug, one level up the stack. Passing both the manifest path and the expected value through
  `os.environ` instead sidesteps the interpolation problem entirely and is bash-3.2-safe (`VAR=val cmd` is basic
  POSIX shell syntax).

### 3.8 Simulating a write failure for Finding 2's tests

**Chosen:** `chmod 555` the manifest's containing directory (removing write permission while keeping read+execute)
immediately before the call, restore `755` immediately after asserting the exit code (§2.6, Section B).

- **Alternative — point the script at a nonexistent manifest path instead of an unwritable existing one.**
  Rejected: both scripts' own pre-flight already returns a **different**, already-correct exit code (`2`, "not
  found") for that case — it would not exercise the write-failure path (exit `4`) at all, only a code path this
  issue does not touch.
- **Alternative — exhaust disk space or use a read-only bind mount to force the failure.** Rejected as
  disproportionately heavy machinery (requires elevated setup, is not portable to a hermetic CI job, and is far
  more invasive than the defect being tested) for a failure mode a simple directory permission change already
  reproduces reliably, confirmed empirically in this session on the real target platform (see the Negative
  consequence below for the one genuine caveat this technique carries: CI's execution-user identity).

## 4. Consequences

### Positive

- Closes three defects **empirically reproduced against the real, current scripts in this session** (not merely
  inferred from reading): invariant 9's silent skip on zero gate lines, both `manifest-set-artifact.sh` and
  `manifest-set-gate.sh` exiting `0` on a provably failed write, and `manifest-init.sh` producing YAML that
  genuinely crashes `yaml.safe_load` on an unescaped-quote title. Each reproduction's exact transcript is recorded
  in this ADR's Context, not merely asserted.
- `manifest-set-artifact.sh` and `manifest-set-gate.sh` now share an identical failure contract with
  `manifest-set-flag.sh` (exit `4`, `mktemp`+`trap` cleanup) across all three manifest-mutation helpers — closes a
  real inconsistency where two of the concept-to-code chain's three field-writing scripts could silently lie about
  success while the third (already) could not.
- Verified empirically that the fix preserves atomicity on failure: a failed write leaves the manifest's previous,
  valid content completely intact in both scripts (the `awk > TMP && mv` pattern never partially overwrites the
  target) — worth stating explicitly, since the exit-code fix alone does not by itself guarantee this, and a caller
  now gets both a truthful exit code **and** a guarantee the manifest was not left half-written.
- `manifest-init.sh`'s title field can now safely hold any title a human is likely to type, including one
  containing a quoted phrase or a backslash, without corrupting the manifest — closes a live crash path into
  `autopilot-build`'s own pre-flight, an already-shipped, already-relied-upon consumer of this exact field, not a
  hypothetical future one.
- PATH RULE is now genuinely enforced at all five of its own explicitly-named violation sites; a chain step
  reaching any of the five branches no longer depends on the current working directory happening to already be
  `~/.claude/skills/concept-to-code/`, or on an accidental relative-path resolution.
- The pair-count paragraph and `manifest-transition.sh`'s own comment now state the same, independently
  mechanically-verified number (48) in four places, replacing three numbers (44/51/16) that had stood side by side
  in the same document, contradicting each other, for an unknown but non-trivial period. A new mechanical test
  (E7) makes any future prose/script drift self-detecting rather than silently re-accumulating.
- The new 21-assertion harness gives `manifest-validate.sh`'s invariant 9, `manifest-set-artifact.sh`,
  `manifest-set-gate.sh`, and `manifest-init.sh` their first behavioral test coverage of any kind in `staging/`.
- Zero `manifest-transition.sh` `PAIRS`-table changes (a 1-line **comment** edit only), zero `sync-to-claude.sh`
  `PAIRS` additions, zero manifest schema changes — the smallest-blast-radius outcome available for five
  independent findings, consistent with this roadmap's established discipline.

### Negative

- Section B's write-failure simulation (`chmod 555` on the manifest's containing directory) is a **new** technique
  for this test suite — confirmed zero prior `chmod`-based tests exist anywhere in
  `staging/plugin/scripts/tests/*.test.sh` before this ADR. Its correctness depends on the executing user
  respecting Unix permission bits. Verified empirically, both directions (RED pre-fix, GREEN post-fix), on this
  session's own machine (macOS, non-root, `id -u`=`501`). A targeted web search during this session surfaced
  genuinely conflicting signals on whether a plain (non-containerized) `runs-on: ubuntu-latest` GitHub Actions job —
  this repo's actual job shape, confirmed by reading `docs-ci.yml`, which has no `container:` key — executes as
  root or as the conventional non-root `runner` account; this ADR does not resolve that ambiguity with the same
  first-hand certainty ADR-0026/0027 achieved for their own environment-gated findings, and says so plainly rather
  than asserting unverified confidence. If CI does run as root, B1/B3 would false-pass (silently always green, not
  a true RED/GREEN differentiator) without indicating the underlying script fix is wrong — the fix itself carries
  low independent risk regardless, being a verbatim mirror of `manifest-set-flag.sh`'s already-accepted,
  already-production contract, and B2/B4's happy-path companions exercise the actual write logic on every run
  regardless of this specific gap.
- Finding 5's fix deliberately extends beyond the three literally-digit-named numbers (44/51/16) to also correct
  the adjacent "21" Standard-bullet figure and complete the Express bullet's own missing pair (Alternatives §3.5).
  This is disclosed and reasoned explicitly, not a silent expansion, but a reviewer scanning only SPEC's literal
  three-number list should not be surprised to see two more numbers change in the same diff hunk.
- `SKILL.md:569`'s sixth, unnamed bare `manifest-set-flag.sh` mention (Finding 4) is confirmed but deliberately
  left unfixed, a known, disclosed gap rather than a regression this ADR introduces (Alternatives §3.6).
- The currently-**deployed** `concept-to-code` copy (`~/.claude/skills/concept-to-code/`) keeps all five of this
  issue's defects until a human runs `sync-to-claude.sh --apply` — the same disclosed, established "deployed stays
  defective until sync, by design" convention this roadmap has used since ADR-0025/0026/0027, repeated here rather
  than assumed to already be understood.

### Neutral

- This ADR changes no hook wiring, no `settings.json`, no `hooks.json`, and no file under `~/.claude` — consistent
  with every prior ADR in this roadmap's stated invariant that staging-side fixes stay staging-side until an
  explicit, separate, human-gated sync.
- Extends (does not invent) the "one new hermetic test file per issue, appended to both the local `test-cmd` glob
  and CI's explicit list" convention from ADR-0024/0026/0027 — the fourth consecutive issue in this roadmap to
  follow it without modification.
- The "disclose an environment-dependent test-coverage gap rather than assert unverified confidence" idiom
  (ADR-0026 §2.4/§3.5 for `git-filter-repo`'s absence; ADR-0027 §2.6/§4-Negative for BSD `sed` semantics on CI) is
  reused here for a third, distinct environmental gap: CI's execution-user identity for permission-based tests.
  Worth carrying forward again the next time this roadmap needs to test a Unix-permission-dependent code path (see
  `DURABLE NOTES` in the report).
- The env-var-passing technique for handing a shell string containing quotes and backslashes to an embedded
  `python3 -c` check, instead of inline string interpolation, resolves a real, first-hand-encountered shell/Python
  quoting trap discovered while designing Section C's tests (Alternatives §3.7) — worth reusing for any future test
  that must hand arbitrary, special-character-bearing content to an embedded interpreter.
- The mechanical, script-derived regression test (E7: recount the actual `PAIRS` block, compare to a hardcoded
  expected total) is a stronger and more durable guard than a purely textual/static assertion for any "the prose
  must match the code" finding — worth reaching for by default the next time this roadmap needs to keep a summary
  number in sync with a script that can drift independently of its own documentation.

## 5. References

- `SPEC.md` (repo root) / `docs/specs/32-manifest-helpers-count-guards-exit-codes.spec.md` — this issue's spec
  (confirmed byte-identical)
- `docs/architecture/ADR-0003-concept-to-code-chain.md` — original manifest-driven state machine design
- `docs/architecture/ADR-0017-chain-type-routing-gate0.md` — original Express/Hybrid/Gate-0d routing and the
  `manifest-transition.sh` pair table this ADR's Finding 5 recounts but does not modify
- `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md` — hermetic test-file pattern and
  `PAIRS`-mapping convention this ADR's new test file and edited scripts both already participate in
- `docs/architecture/ADR-0025-29-refresh-stale-staging-copies.md` — confirms `staging/` as this roadmap's working
  source of truth
- `docs/architecture/ADR-0026-30-clean-public-repo-private-history.md` — structural ADR precedent and the
  disclosed-environment-gap idiom this ADR reuses a third time
- `docs/architecture/ADR-0027-31-c2c-bsd-slug-autopilot-gates.md` — immediately preceding issue in this roadmap;
  explicitly deferred every finding this ADR fixes to issue #32
- `staging/plugin/skills/concept-to-code/SKILL.md`, `scripts/manifest-validate.sh`,
  `scripts/manifest-set-artifact.sh`, `scripts/manifest-set-gate.sh`, `scripts/manifest-init.sh`,
  `scripts/manifest-transition.sh`, `scripts/manifest-set-flag.sh` — the files this ADR patches or mirrors
- `staging/plugin/skills/autopilot-build/SKILL.md` — the `yaml.safe_load` pre-flight consumer motivating Finding 3
- `staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` — structural precedent (path
  derivation, `PASS`/`FAIL` idiom, compound-anchor technique) the new test file follows
- `staging/sync-to-claude.sh` — confirmed all four edited scripts already have `PAIRS` mappings; no new entries
  needed
- `.claude/test-cmd` — confirmed unchanged, already globs the new test file
- `.github/workflows/docs-ci.yml` — the CI job gaining one new entry in its explicit test list
- Implementation plan: `docs/superpowers/plans/2026-07-11-32-manifest-helpers-guards.md`
