# ADR-0031 — refactor-snapshot filter append and deep-refactor scope glob

**Status:** Accepted
**Date:** 2026-07-11
**Author:** istefox
**Supersedes:** none
**Amends:** none
**Related:**
- SPEC: `docs/specs/35-refactor-snapshot-filter-append-and-deep.spec.md` (= `SPEC.md` at repo root,
  GitHub issue #35, confirmed byte-identical by diff before writing this ADR)
- ADR-0002 (`refactor-snapshot-harness`), ADR-0006 (`refactor-snapshot-runs-configurable`) —
  original design of the harness this ADR's Finding 1 patches; historical, immutable, not amended
- ADR-0018 (`deep-refactor-skill`) — original design of the audit/fix pipeline and its global
  circuit breaker; historical, immutable, not amended; confirms the `CIRCUIT BREAKER FIRED AT:
  <dimension>` tag convention this ADR's Finding 3 leaves untouched
- ADR-0027 (`c2c-bsd-slug-autopilot-gates`), ADR-0028 (`manifest-helpers-guards`), ADR-0029
  (`hook-verify-session-filter`), ADR-0030 (`scope-guards`) — structural and test-harness
  precedent this ADR reuses directly (multi-finding ADR, one shared test file, lettered
  sections, disclose-don't-assume discipline, "verify against real behavior, not assumed")
- `staging/plugin/skills/refactor-snapshot/scripts/capture.sh`,
  `staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh`,
  `staging/plugin/skills/deep-refactor/SKILL.md` — the three files this ADR patches
- `staging/plugin/skills/refactor-snapshot/tests/run-tests.sh`,
  `staging/plugin/skills/deep-refactor/tests/{run-tests.sh,enumerate-sources.test.sh}` —
  confirmed `$HOME`-coupled (point at `$HOME/.claude/skills/...`), not part of the hermetic
  `docs-ci` harness, traced compatible, not edited (§1 "Cross-check")
- Implementation plan: `docs/superpowers/plans/2026-07-11-35-refactor-snapshot-deep-refactor.md`

---

## 1. Context

Issue #35 (audit findings 2.6/P2, 3.8, 3.9) names three independent defects across two of the
roadmap's refactor-safety skills. All three were verified against the current file state and, for
Findings 1 and 2, against live execution of the real, unmodified scripts — not assumed — before
this ADR was written.

### Finding 1 — `refactor-snapshot/scripts/capture.sh:53-57`, RFS_FILTER lands on a new line and masks the real exit code

`capture.sh` reads `.claude/test-cmd` into `CMD_CONTENT` via a loop (lines 32-41) that appends
each accepted line followed by a literal newline character:

```bash
CMD_CONTENT="$CMD_CONTENT$line
"
```

This means `CMD_CONTENT` always carries exactly one trailing newline after the loop, for any
non-empty test-cmd file (verified directly against this exact bash build, ANSI-C `od -c` byte
trace: a single-line test-cmd `pytest -q\n` produces `CMD_CONTENT` = `"pytest -q\n"`, 10 bytes,
ending `\n`). The command is then built at lines 53-57:

```bash
if [ "$RFS_FULL" = "1" ] || [ -z "$RFS_FILTER" ]; then
  EXEC_CMD="$CMD_CONTENT"
else
  EXEC_CMD="$CMD_CONTENT $RFS_FILTER"
fi
```

When a filter is set, `EXEC_CMD` becomes `"$CMD_CONTENT $RFS_FILTER"` — with the pre-existing
trailing newline sitting between `$CMD_CONTENT` and the appended space + `$RFS_FILTER`. Traced
directly (`od -c`): `EXEC_CMD` for `CMD_CONTENT="pytest -q\n"`, `RFS_FILTER="-k foo"` is the
**two-line** string `"pytest -q\n -k foo"`, not the single line `"pytest -q -k foo"` the
`RFS_FILTER` contract (`refactor-snapshot/SKILL.md:84`: "pattern passed to test-cmd") implies.

All three timeout branches (lines 66-88) execute this same `EXEC_CMD` via `bash -c "$EXEC_CMD"`.
`bash -c` with a multi-line string runs **every** line as a separate, sequential statement and
reports `$?` for the **last** one executed. So the real flow is: line 1 (`pytest -q`) runs and
produces the real result — but it is not final; line 2 (`-k foo`, a bare filter fragment with a
leading space) is then executed as an attempt to run a command literally named `-k` (or whatever
the filter's first token is), which fails with "command not found," conventionally exit 127. The
snapshot's `EXIT=` field records this final, bogus 127 — **unconditionally**, regardless of
whether the real, filtered suite passed or failed. Because `CMD_CONTENT` and `RFS_FILTER` are
identical inputs for both the PRE and POST captures (same `.claude/test-cmd` file, same env var),
both snapshots land on the identical constant 127, so `diff.sh`'s exit-code comparison channel
**always reports a match** — it can never again detect a real regression that manifests only as
an exit-code change under the narrowed, filtered scope. This is reproduced end-to-end against the
real, unmodified `capture.sh` (see the implementation plan's Task 1/Task 2 fixture): a fake test
runner that prints `ran-full`/exits 9 when invoked with no args and prints `ran-subset`/exits 0
when invoked with `SUBSET` — set as `.claude/test-cmd`, with `RFS_FILTER=SUBSET`, `capture.sh PRE`
records `EXIT=127`, stdout `ran-full` (the *unfiltered* line ran; the filter never reached the
runner) — not the real, filtered 0/`ran-subset` result at all.

`refactor-snapshot/SKILL.md:84`'s own doc comment ("`RFS_FILTER` (default empty) — pattern passed
to test-cmd, e.g. `pytest -k <pat>`") already states the *intended* contract correctly; the defect
is purely in the string-construction Bash, not in the documented design.

### Finding 2 — `deep-refactor/scripts/enumerate-sources.sh:43-59`, glob override interpolated raw into `grep -E`

The script's own header (lines 3-5) documents `<path-override>` as an "optional glob/dir prefix,"
but the implementation only ever builds one mechanism — an ERE pattern handed to `grep -E`:

```bash
CLEAN_OVERRIDE="$(printf '%s' "$PATH_OVERRIDE" | sed 's|/$||')"
grep -E "^${CLEAN_OVERRIDE}(/|$)" "$TMP_FILTERED" > "$TMP_SCOPED" 2>/dev/null || true
if [ ! -s "$TMP_SCOPED" ]; then
  grep -E "^${CLEAN_OVERRIDE}" "$TMP_FILTERED" > "$TMP_SCOPED" 2>/dev/null || true
fi
```

`CLEAN_OVERRIDE` is interpolated **unescaped** into an ERE. For a bare glob override like
`*.swift`, the pattern becomes `^*.swift(/|$)`: a leading `*` has no preceding atom to repeat, an
undefined case in POSIX ERE that (depending on the grep implementation) is either a hard parse
error or is read as a literal `*` character — no git-tracked path starts with a literal `*`, so
either way the primary match is empty. The unanchored fallback (`^${CLEAN_OVERRIDE}`, no `(/|$)`)
reuses the identical unescaped interpolation and fails identically. For a directory-scoped glob
like `Sources/*.swift`, the `*` **does** have a preceding atom (`/`) to repeat, so the pattern
parses validly as ERE but means something unintended — "`Sources` then zero-or-more literal `/`
characters then any-character then `swift`" — which does not match a real nested path like
`Sources/App/normal.swift` (`App/normal` is not "zero or more slashes"). Both cases were verified
by **live execution of the real, unmodified script** against a disposable git fixture
(`Sources/App/normal.swift`, `Sources/Models/Model.swift`, `AppDelegate.swift`,
`OtherSources/Other.swift`): override `*.swift` → empty output, exit 0; override `Sources/*.swift`
→ empty output, exit 0; only the plain directory-literal override `Sources/` (no metacharacters)
returns the expected two files. The script itself never errors (exit stays 0 on an empty match —
`enumerate-sources.sh` only ever exits 1 for a non-git `<root>`); the abort happens one layer up,
at `deep-refactor/SKILL.md`'s own Step 0.6 ("If `SOURCE_FILE_COUNT=0`, abort").

The directory-literal form (no metacharacters, e.g. `Sources`, `Sources/Foo`) already works
correctly today and is exercised by 5 of the 13 assertions in the existing, `$HOME`-coupled
`deep-refactor/tests/enumerate-sources.test.sh` (tests 7, 8, 9, 12, 13) — any fix must not
regress this path.

### Finding 3 — `deep-refactor/SKILL.md:585`, circuit-breaker text recommends a destructive blanket revert on a dirty tree

Step 0.7 (lines 166-172) explicitly permits starting an audit on a dirty working tree — it only
sets `DIRTY_TREE=true` and lets Gate 0 (line 187) **warn**, not block. Later, if the global
circuit breaker fires mid-fix (Phase 2, any RED test run — lines 423-428), HITL Gate 2's message
(lines 569-595) unconditionally suggests, at line 585:

```
Unstaged changes from <CIRCUIT_BREAKER_DIMENSION> are present in the working tree (run 'git diff' to inspect; 'git checkout -- .' to revert if unwanted).
```

`git checkout -- .` discards **every** uncommitted change in the working tree, not only the fired
dimension's own fix attempts. Each completed dimension is already committed before the next one
starts (Phase 2, "This commit-per-dimension provides auditability"), so those are safe from this
command — but on a run that started dirty, the uncommitted set at the moment the breaker fires is
a **mix** of the user's own pre-existing edits (never committed by this run) and the fired
dimension's own failed attempt. `git checkout -- .` would destroy both indiscriminately. The
`DIRTY_TREE` variable, set once at Step 0.7, is referenced exactly **once** more in the whole file
(Gate 0's own warning, line 187) — confirmed by grep across the full file — and is never consulted
at Gate 2, where the actual destructive suggestion lives.

### Cross-check across the whole repository (verified, not assumed)

Before writing the Decision below, every plausible call-site of the three changed contracts was
grepped across the full repository (not only the three target files):

- **`RFS_FILTER`** appears in: `SPEC.md`/`docs/specs/35-*.md` (source documents describing this
  finding, not call-sites), `refactor-snapshot/SKILL.md:84` (already-correct purpose-level
  description, needs no edit — see Finding 1), `refactor-snapshot/scripts/pre-runs.sh` (only
  passes the env var through to `capture.sh` as an inherited subprocess environment variable; it
  never itself builds `EXEC_CMD`, so it needs no change and automatically inherits the fix),
  `staging/plugin/agents/refactorer.md:42` and `docs/guida-workflow-orchestrazione.md:367,513`
  (purpose-level usage notes, e.g. `RFS_FILTER=<pattern>`, accurate before and after this fix,
  make no claim about the internal newline mechanics), and historical ADR-0002/ADR-0006 plus their
  companion plans (original design docs, immutable). None require edits.
- **`git checkout -- .`** appears in: `SPEC.md`/`docs/specs/35-*.md` (source documents),
  `deep-refactor/SKILL.md:585` (the one file this ADR patches), and
  `docs/vibe-coding-system.md:97,1836` — confirmed, by reading both sites, to describe an
  **unrelated** Claude Code product feature (CC 2.1.183's native auto-mode blocking of
  destructive git commands), not deep-refactor's own Gate 2 message; out of scope, not edited.
  `CIRCUIT BREAKER FIRED AT:` (the tag immediately preceding the patched sentence) appears in
  `BRAINSTORM.md`, the project's own root `CLAUDE.md`, `ADR-0018`, and its companion 2026-05-30
  plan — all reference only the **tag string convention** (unchanged by this fix), never the
  `git checkout -- .` sentence itself; no edit needed anywhere.
- **`path-override`** appears in: `SPEC.md`/`docs/specs/35-*.md` (source documents),
  `enumerate-sources.sh` itself, `deep-refactor/SKILL.md:153` (a bare usage line, `enumerate-
  sources.sh <project_root> [<path-override>]`, with no glob-syntax prose elsewhere in the file to
  reconcile), and `deep-refactor/tests/enumerate-sources.test.sh` (the `$HOME`-coupled test,
  traced compatible below). No other file describes the override's matching semantics.
- **`refactor-snapshot/tests/run-tests.sh`** and **`deep-refactor/tests/{run-tests.sh,
  enumerate-sources.test.sh}`** are confirmed `$HOME`-coupled (`SK="$HOME/.claude/skills/
  refactor-snapshot"`, `SCRIPT="$HOME/.claude/skills/deep-refactor/scripts/enumerate-sources.sh"`,
  `SKILL="$HOME/.claude/skills/deep-refactor/SKILL.md"`), not part of the hermetic `docs-ci`
  harness, and traced by hand for compatibility with every fix in this ADR:
  - `refactor-snapshot/tests/run-tests.sh`'s 18 assertions contain **zero** references to
    `RFS_FILTER` (grepped, confirmed empty) — none of them exercise the code path Finding 1
    changes; its own file's target "PASS=18 FAIL=0" (`refactor-snapshot/SKILL.md:91`) stays
    accurate, no edit needed.
  - `deep-refactor/tests/enumerate-sources.test.sh`'s 13 assertions were traced one by one against
    the new matching design (§2.2 below): tests 1-6 (inclusion/exclusion, no override) are
    untouched by this change; tests 7-9, 12, 13 (the directory-literal `"Sources/"` override
    scenarios) all continue to pass under the new unified `case`-based matcher — independently
    re-verified in this ADR's own design-time probe (§2.4).
  - `deep-refactor/tests/run-tests.sh` asserts only `grep -qF 'CIRCUIT BREAKER FIRED AT:'` for the
    circuit-breaker text (line 83-85) — the tag itself, unchanged by Finding 3's fix — and
    delegates to `enumerate-sources.test.sh` as a sub-test; both stay green.
  - `refactor-snapshot/scripts/diff.sh` was checked for any independent `EXEC_CMD`/`CMD_CONTENT`
    coupling — none found; it only reads and compares the two already-written snapshot files.

---

## 2. Decision

Fix all three findings in place, in their existing files, with one shared hermetic test file
(`staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh`), three lettered sections,
following ADR-0027/28/29/30's established multi-finding convention. Unlike ADR-0030's sections
(which had to extract Bash fences out of `SKILL.md` prose, because the fixed logic ran only inside
agent-read instructions), Sections A and B here test **real, directly-executable shell scripts**
(`capture.sh`, `enumerate-sources.sh`) by invoking them directly against disposable `mktemp`
fixtures — no fence-extraction machinery is needed. Section C (pure Gate 2 HITL-message prose)
uses static `grep` anchors scoped to the Gate 2 block, matching ADR-0030's own static-anchor
convention for non-executable text.

### 2.1 Finding 1 — strip the loop's trailing newline before building `EXEC_CMD`

Insert one statement immediately before the `if [ "$RFS_FULL" = "1" ] ...` block (current line 53,
i.e. immediately after `RFS_TIMEOUT="${RFS_TIMEOUT:-120}"` at line 51):

```bash
# Strip the single trailing newline the read loop always appends after the last accepted
# command line (bash 3.2-safe ANSI-C quoting; verified against this exact bash build).
# Without this, appending RFS_FILTER below lands it on a NEW line -- bash -c then runs it as
# a second, separate command (typically "command not found"), and the LAST command's exit
# status becomes EXIT_CODE below, masking the real, filtered suite result behind an unrelated
# failure every time RFS_FILTER is set.
CMD_CONTENT="${CMD_CONTENT%$'\n'}"
```

`${CMD_CONTENT%$'\n'}` is bash's own suffix-removal parameter expansion (`%`, shortest match)
with an ANSI-C-quoted literal newline as the pattern — verified directly, in this exact
environment's bash 3.2.57, to strip exactly the one trailing newline the read loop always
produces while leaving any **internal** newlines (a genuinely multi-line test-cmd file, e.g. `cd
/tmp\npytest -q\n`) untouched, so the filter still lands correctly on only the final command line.
The three timeout branches (lines 66-88) are untouched — they already share one `EXEC_CMD`
variable, so fixing its construction upstream fixes all three at once, exactly as the SPEC's own
instruction requires ("keep all three timeout branches on the same EXEC_CMD"). No other file needs
a change (§1 "Cross-check").

### 2.2 Finding 2 — a single, unified `case`-pattern matching engine (no external regex dialect)

Replace the header comment (lines 3-9) with a precise description of the two supported forms, and
replace the override-application block (lines 43-59) with:

```bash
# Apply optional path-override if provided. Two supported forms, both matched via bash's
# native `case` pattern engine (no external regex dialect, no ERE-injection surface):
#   1. Directory/path-literal prefix (no glob metacharacters, e.g. "Sources", "Sources/Foo"):
#      restricts to that exact path or anything nested below it.
#   2. Shell glob (contains *, ?, or [ -- e.g. "*.swift", "Sources/*.swift"): matched against
#      the full relative path. `case` pattern matching operates on a literal string (it does
#      not do filesystem pathname expansion), so `*` matches across `/` boundaries -- verified
#      directly against this repository's own bash: `case "Sources/App/x.swift" in *.swift)`
#      matches.
if [ -n "$PATH_OVERRIDE" ]; then
  TMP_SCOPED="$(mktemp)"
  # Strip a single trailing slash so "Sources/" and "Sources" behave identically.
  CLEAN_OVERRIDE="$(printf '%s' "$PATH_OVERRIDE" | sed 's|/$||')"
  case "$CLEAN_OVERRIDE" in
    *[\*\?\[]*)
      # Glob form: match every candidate path against the override pattern as-is.
      GLOB_PAT="$CLEAN_OVERRIDE"
      while IFS= read -r _f; do
        case "$_f" in
          $GLOB_PAT) printf '%s\n' "$_f" >> "$TMP_SCOPED" ;;
        esac
      done < "$TMP_FILTERED"
      ;;
    *)
      # Directory/path-literal form: match the override itself, or anything nested under it.
      DIR_PAT="$CLEAN_OVERRIDE"
      while IFS= read -r _f; do
        case "$_f" in
          "$DIR_PAT"|"$DIR_PAT"/*) printf '%s\n' "$_f" >> "$TMP_SCOPED" ;;
        esac
      done < "$TMP_FILTERED"
      ;;
  esac
  cat "$TMP_SCOPED"
  rm -f "$TMP_SCOPED"
else
  cat "$TMP_FILTERED"
fi
```

`*[\*\?\[]*` is a `case` bracket-expression test for "does this string contain a literal `*`, `?`,
or `[` anywhere" — verified directly (this ADR's own design-time probe, §2.4) to correctly flag
`*.swift`, `Sources/*.swift`, `file?.swift`, `file[0-9].swift` as glob-form and correctly leave
`Sources`, `Sources/Foo`, `normal-path/no-meta.swift` as directory-literal-form. `grep -E` is
removed from the override-matching path entirely — not merely escaped — which also removes the
cross-implementation ambiguity a leading `*` has under POSIX ERE (§1 Finding 2) as a side effect,
not only the one named symptom. The directory-literal branch reproduces the *intent* of the old
two-tier primary/fallback `grep -E` attempt (match the override itself, or anything nested below
it) as a single `case` alternation (`"$DIR_PAT"|"$DIR_PAT"/*`) instead of a "try strict, then retry
loose" two-pass strategy — the two-pass structure existed only to route around the old mechanism's
own inability to express "this OR that" in one anchored ERE pass without also risking the
leading-`*` defect; `case`'s native `pattern1|pattern2` alternation expresses the same intent
directly, in one pass, with the same result for every scenario the existing 13-test suite
exercises (verified below). `TMP_SCOPED="$(mktemp)"` (an always-existing file, even when no line
ever matches) is kept exactly as today, so `cat "$TMP_SCOPED"` on a zero-match run still reports a
clean empty output, not a missing-file error.

### 2.3 Finding 3 — condition the Gate 2 suggestion on `DIRTY_TREE`

Replace line 585 (the sole occurrence in the file) with:

```
    Unstaged changes from <CIRCUIT_BREAKER_DIMENSION> are present in the working tree (run 'git diff' to inspect).
    [If DIRTY_TREE=true:]
    This run started with a dirty working tree (Gate 0 warning). The unstaged changes above are
    now a MIX of your own pre-existing edits and this dimension's failed fix attempts --
    'git checkout -- .' would discard both indiscriminately. Inspect 'git diff' file by file and
    revert selectively ('git checkout -- <path>' per file), or run 'git stash' to set everything
    aside non-destructively until you have reviewed it.
    [If DIRTY_TREE=false:]
    This run started from a clean working tree, so 'git checkout -- .' safely reverts these
    unstaged changes if unwanted.
```

This reuses the file's own `[If <condition>:]` bracket-conditional convention, already used four
times elsewhere in this exact file (Gate 0's own `DIRTY_TREE`/`BASELINE` branches at lines 187 and
192, Gate 2's own `CIRCUIT_BREAKER_FIRED`/`BASELINE` branches at lines 581 and 587) — not a new
pattern. The `DIRTY_TREE=false` branch keeps the original, safe suggestion verbatim in spirit (the
common case — most runs start clean — loses nothing). The `DIRTY_TREE=true` branch does not invent
a mechanism to distinguish "the user's edits" from "this dimension's edits" within the mixed
uncommitted set — no such mechanism exists anywhere in the skill today (§3.3 records why building
one is out of scope for this issue) — it instead discloses the mix plainly and offers two
genuinely safe paths: manual, file-scoped inspection-then-revert, or a non-destructive `git stash`.
The `CIRCUIT BREAKER FIRED AT: <CIRCUIT_BREAKER_DIMENSION>` tag and the two lines immediately above
it (`Commits landed for:`, `Remaining dimensions: SKIPPED`) are untouched.

### 2.4 Design-time verification performed before committing to this Decision

Before writing this Decision, both Finding 1's and Finding 2's exact mechanics, and this ADR's
proposed replacement logic, were verified by direct execution in this repository's own runtime
(disposable scratch fixtures, not the project tree) — not assumed:

- Finding 1: the read loop's trailing-newline byte trace (`od -c`), the resulting
  two-statement `EXEC_CMD` split, and the `${CMD_CONTENT%$'\n'}` fix's correctness (single
  trailing newline stripped, internal newlines in a genuinely multi-line test-cmd preserved) were
  all traced directly in this exact bash 3.2.57 build.
- Finding 2: the real, unmodified `enumerate-sources.sh` was executed end-to-end against a
  disposable git fixture for overrides `*.swift`, `Sources/*.swift`, and `Sources/` — confirming
  the two glob cases return empty and the directory-literal case already works, exactly as
  reasoned from the source. The proposed replacement logic (§2.2) was independently implemented in
  a standalone scratch probe and executed against an equivalent fixture, confirming: bare glob
  `*.swift` returns all matching files; `*.py` (no matches in the fixture) returns empty cleanly,
  not an error; scoped glob `Sources/*.swift` matches nested files under `Sources/` and correctly
  excludes a top-level file; the directory-literal `Sources/` case is unchanged. One incidental,
  environment-specific artifact was found and **excluded** from this ADR's reasoning after
  isolating its cause: this developer's interactive tool shell wraps a `grep` shell function around
  `ugrep` (a Claude Code convenience feature, from a shell snapshot) that raised a hard parse error
  for `^*.swift(/|$)` when the pattern was tested as a standalone inline command — but a live,
  direct `bash script.sh` subprocess invocation of the real script did **not** exhibit this (shell
  functions do not propagate across a `bash file.sh` subprocess boundary), confirming the
  parse-error variant is an artifact of this one interactive session's tooling, not a property of
  the real script's actual runtime behavior in CI (`ubuntu-latest`, GNU grep) or on a user's Mac
  (`/usr/bin/grep`, BSD grep). This ADR's Decision does not depend on which grep flavor is present
  at all, since Finding 2's fix removes `grep -E` from the override-matching path entirely.

### 2.5 Test strategy

One new hermetic file, `staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh`,
three lettered sections (A/B/C, one per finding), 19 assertions total. Sections A and B invoke the
real staging scripts directly (`bash "$CAPTURE_SH" PRE`, `bash "$ENUM_SH" "$REPO" "<override>"`)
against disposable `mktemp -d` fixtures — Section A uses a tiny fake test-runner script that
branches its own exit code and stdout on whether it received a filter argument, so a PASS
requires the real, filtered result to come through faithfully in both directions (success and
failure), not merely "no longer 127"; Section B reuses a small git-repo fixture with the same
directory/naming shape as the existing `enumerate-sources.test.sh`. Section C uses an `awk`-scoped
extraction of Gate 2's own message block (bounded between the `### HITL Gate 2` heading and its
closing fence) plus `grep -F` anchors within that scoped text, so a marker landing in the *wrong*
place in the file (e.g. accidentally only in Gate 0's pre-existing, unrelated `DIRTY_TREE` warning)
would not be mistaken for a pass. Wired into `.github/workflows/docs-ci.yml`'s explicit
`shell-tests` list (append `refactor-snapshot-deep-refactor`, tenth entry) and picked up
automatically by `.claude/test-cmd`'s wildcard glob with no edit needed there. `staging/
sync-to-claude.sh`'s `PAIRS` list is **not** extended, following the same, already-established
convention this roadmap's prior staging-only correctness tests all use (confirmed: none of this
new file's closest structural siblings — `scope-guards.test.sh`,
`concept-to-code-bsd-autopilot-gates.test.sh`, `concept-to-code-manifest-helpers-guards.test.sh`
— are listed in `PAIRS` either).

---

## 3. Alternatives considered

### 3.1 Finding 1 — how to remove the trailing newline

- **Alt 1a — restructure the read loop itself** to insert the newline **before** each subsequent
  line instead of **after** every line (track a `FIRST` flag, only prepend a separator from the
  second accepted line onward), so a trailing newline is never produced in the first place.
  **Rejected:** a materially larger diff (touches the loop body, introduces a new state variable)
  for the exact same end result as a one-line fix applied after the loop; no additional
  correctness benefit, and a bigger diff surface for a reviewer to verify by eye in a
  safety-relevant harness component.
- **Alt 1b — external `sed`-based trailing-newline removal**, e.g. piping `CMD_CONTENT` through a
  `sed` script that drops a final blank line. **Rejected:** spawns an extra process for something
  bash's own parameter expansion already does in-process; `sed`'s line-oriented model is also
  comparatively awkward for stripping a **newline character** (as opposed to a trailing blank
  *line*) portably across BSD sed (macOS) and GNU sed (CI's `ubuntu-latest`), reintroducing exactly
  the kind of cross-platform ambiguity Finding 2's chosen fix (§3.2) independently argues against.
- **Alt 1c — change the mechanism entirely**: pass `RFS_FILTER` to `bash -c` as a separate
  positional argument (`bash -c '"$0" "$@"' "$CMD_CONTENT" "$RFS_FILTER"`-style) instead of string
  concatenation onto the same line. **Rejected:** `CMD_CONTENT` is arbitrary, potentially
  multi-line shell text (a real, legitimate use case per the read loop's own design — e.g. `cd
  /project\npytest -q`), not guaranteed to be a single command name that would sensibly consume a
  trailing positional argument; string concatenation onto the final line is what the documented
  contract (`refactor-snapshot/SKILL.md:84`, "pattern passed to test-cmd") and downstream
  documentation (`refactorer.md:42`) already assume. Changing the mechanism is a bigger, riskier
  redesign for a bug that is purely a trailing-newline defect, not a wrong-mechanism defect.
- **Chosen: Alt 1d — single-line `CMD_CONTENT="${CMD_CONTENT%$'\n'}"` insertion**, placed once,
  immediately before `EXEC_CMD` is built. Smallest possible diff; reuses this codebase's own
  established trailing-character-strip idiom (`"${cwd%/}"`, `"${project_root%/}"`, both already in
  this exact file and elsewhere in the roadmap, e.g. ADR-0030 §2.1); verified directly in this
  environment's real bash 3.2.57 to strip exactly the one guaranteed trailing newline while
  preserving internal newlines for genuinely multi-line test-cmd files.

### 3.2 Finding 2 — how to make the glob override actually work

- **Alt 2a — escape the override for ERE, keep `grep -E`, treat it purely as an (now-safe) literal
  substring/prefix match** (the SPEC's first suggested option). **Rejected:** fails the SPEC's own
  explicit, named success criterion — "enumerate-sources with override `*.swift` returns the
  fixture's swift files." Escaping turns `*.swift` into the literal four-character-plus-dot string
  nobody's tracked path actually contains, so behavior moves from "aborts via a zero-match parse
  artifact" to "silently, cleanly returns zero files because glob syntax is now inert" — still
  functionally broken for the one use case the header comment and the SPEC both name, merely
  without the confusing intermediate symptom.
- **Alt 2b — hand-write a POSIX-glob-to-ERE translator** (`*` → `.*`, `?` → `.`, pass `[...]`
  through, escape literal ERE metacharacters elsewhere), then keep using `grep -E` with the
  translated pattern. **Rejected:** reinvents, with hand-rolled edge cases (character-class
  negation, escaping order, anchoring), a translation bash already provides natively and for free
  via `case` pattern matching — verified directly in this exact runtime (§2.4). There is also zero
  existing precedent anywhere in this codebase for a glob-to-regex translator to build on or match
  style with, unlike the `case`-based containment idiom ADR-0030 §2.1/§3.1 already established as
  this codebase's dominant pattern for "does X match/contain Y" questions.
- **Alt 2c — keep two independent matching engines**: `grep -E` (fixed, properly escaped) for the
  directory-literal branch, `case`-based glob matching only when metacharacters are detected.
  **Rejected in favor of 2d:** this still leaves `grep -E`, and its ERE dialect's own edge cases
  (e.g. the leading-`*` ambiguity Finding 2 itself is caused by), alive in the file for one of the
  two branches, and forces a future maintainer to keep two independently-behaving matching engines'
  boundary semantics (ERE's `(/|$)` anchor vs `case`'s implicit whole-string match) mentally in
  sync. A single mechanism for both branches is simpler to reason about and to test.
- **Chosen: Alt 2d — one unified `case`-pattern matching engine** (bash builtin, no external
  process, no regex dialect at all) for both the directory-literal branch (pattern rewritten as
  `"$CLEAN_OVERRIDE"|"$CLEAN_OVERRIDE"/*`) and the glob branch (pattern used as-is). Verified
  directly, not assumed, that `case` pattern matching treats `*` as "any sequence of characters,
  including `/`" (it operates on a literal string, not filesystem pathname expansion — an
  intuition trap this ADR explicitly checked before relying on it, §2.4). Removes the
  ERE-interpolation surface entirely, rather than merely neutralizing one instance of it, and as a
  documented side effect (§2.4) sidesteps a real, observed cross-grep-implementation ambiguity for
  a leading, unescaped `*` in an ERE pattern.

### 3.3 Finding 3 — what to safely recommend on a dirty-tree circuit-breaker firing

- **Alt 3a — delete the `git checkout -- .` suggestion unconditionally**, always direct the user to
  `git diff` and a manual decision, even on a clean-start run. **Rejected:** strictly worse UX for
  the common case (`DIRTY_TREE=false` — most runs start clean), where the blanket revert **is**
  safe and is the fastest, correct remedy; the SPEC's own instruction is explicitly scoped ("When
  `DIRTY_TREE` is true, replace...", not "replace unconditionally").
- **Alt 3b — auto-stash the pre-existing dirty state at Gate 0**, before Phase 1 starts, so that if
  the circuit breaker later fires, the working tree's uncommitted set is *guaranteed* to be only
  this run's own changes, and the original, unconditional `'git checkout -- .'` suggestion becomes
  safe again by construction (the user's stash sits untouched, poppable afterward). **Rejected for
  this issue:** a genuinely more thorough fix, but a materially larger mechanism — it adds a new
  stash-create/stash-restore lifecycle spanning Gate 0 through Phase 4 (create stash if
  `DIRTY_TREE`; explain to the user, at the end of a *successful* run too, how to reconcile a stash
  they may have forgotten about; handle a stash-pop conflict if the fix itself touched the same
  files the user had staged) — none of which the SPEC's literal finding text asks for ("replace
  with a selective-revert note or a stash *suggestion*," i.e. a corrected message, not a new
  automated mechanism). Left as a candidate for a future, separately-scoped issue if a message-only
  fix later proves insufficient in practice.
- **Alt 3c — track exactly which files the fired dimension touched** (diff `git status
  --porcelain` immediately before Phase 1 against the same command at circuit-breaker time) and
  print an automatically-generated, file-scoped `git checkout -- <path>` list. **Rejected:** the
  same reasoning as 3b, plus a sharper technical problem — a before/after `git status --porcelain`
  diff cannot actually distinguish "this dimension's fix touched file X" from "the user had already
  modified file X before Gate 0, and the fix also happened to touch the same file" (both look
  identical in that diff). Reliably disambiguating the two needs the same stash-based boundary as
  3b to be trustworthy, at which point this alternative is just 3b with extra steps and no
  independent benefit.
- **Chosen: Alt 3d — condition the existing message on `DIRTY_TREE`**, exactly as the SPEC
  instructs: keep `'git checkout -- .'` for the `DIRTY_TREE=false` branch (safe, unchanged
  intent), replace it for `DIRTY_TREE=true` with an explicit disclosure that the uncommitted set is
  now a mix of pre-existing and this-run changes, plus a `git diff`-then-selective-revert-per-file
  or `git stash` (non-destructive) recommendation. Matches the SPEC's literal scope; reuses the
  file's own `[If <condition>:]` bracket convention, already used four times elsewhere in this
  exact file; smallest change that actually closes the named data-loss risk.

### 3.4 Bundling three independent findings into one ADR, one plan, one test file, one commit

- **Alt 4a — three separate ADRs/plans/commits, one per finding.** **Rejected**, for the same
  reason ADR-0030 §3.4 rejected it for its own three-finding issue: issue #35 already bundles all
  three findings under one GitHub issue and one SPEC.md (confirmed byte-identical against
  `docs/specs/35-*.md`); splitting ADR granularity finer than the issue granularity it answers
  would break with this roadmap's established one-issue-one-ADR precedent (ADR-0024 through
  ADR-0030) for no additional safety benefit, since the three fixes touch three disjoint files with
  zero shared state or ordering dependency between them.
- **Chosen: Alt 4b — one ADR, one plan, one shared test file with lettered sections, one commit**,
  mirroring SPEC's own single-issue framing and ADR-0027/28/29/30's already-established precedent.
  Each finding's tasks remain independently revertible by file/hunk if a reviewer wants to accept
  fewer than all three; nothing about this choice forecloses that.

---

## 4. Consequences

### Positive

- Closes a real correctness defect in `refactor-snapshot`'s **core safety mechanism**: today,
  whenever `RFS_FILTER` is used, the harness's own exit-code comparison channel is permanently
  frozen at a constant, uninformative 127 and can never again detect a real regression that
  manifests as an exit-code change under the narrowed scope — silently defeating the exact purpose
  the harness exists for (behavior-preservation verification) for every refactor cycle that uses
  filtering. This is a correctness bug in a safety-critical component, not a cosmetic one.
- `enumerate-sources.sh`'s override now genuinely implements what its own header comment has
  always claimed ("optional glob/dir prefix"), closing the gap between documented and actual
  behavior rather than merely making the documentation match a narrower reality.
- Gate 2 no longer risks silently discarding a user's own pre-existing, uncommitted work on a
  dirty-tree run — closing a real, disclosed data-loss risk in an interactive HITL flow, using the
  file's own existing conditional-message idiom rather than inventing a new one.
- All three fixes are corrective, in-place edits to existing files; zero new schema fields, zero
  new hook wiring, zero new skill, zero permission-mode change, zero new external dependency.
- Finding 2's fix removes an entire class of injection/ambiguity risk (unescaped user input
  interpolated into a regex engine) rather than only neutralizing the one named symptom — verified,
  not assumed, to also route around a real, observed cross-grep-implementation ambiguity for a
  leading unescaped `*` (§2.4).
- Both executable-script fixes (Findings 1 and 2) were verified by **live execution** against the
  real, unmodified scripts and against standalone probes of the proposed replacement logic, before
  this ADR was finalized — not reasoned about from source alone. This includes an explicit,
  disclosed dead end (an interactive-shell-specific `ugrep` artifact investigated and ruled out,
  §2.4) rather than silently incorporating an unverified claim into the ADR's reasoning.
- Reuses, a sixth time across this roadmap, the "disclose an environment-dependent gap rather than
  silently assert a fact" idiom (ADR-0026 through ADR-0030) — this time for a grep-implementation
  difference discovered mid-investigation, not a design gap, but the same underlying discipline.
- Follows the exact multi-finding, lettered-section test structure ADR-0027/28/29/30 already
  established, so a reviewer familiar with this test suite's conventions can read the new file with
  zero ramp-up; unlike those four ADRs, Sections A and B test real executables directly rather than
  extracting fences from `SKILL.md` prose, which is a simpler, lower-risk test mechanism precisely
  because the fixed logic lives in a real, standalone script rather than agent-read instructions.

### Negative

- Finding 1's fix only helps when `RFS_FILTER` is actually set — a project that never uses the
  performance-narrowing feature was never exposed to this specific defect (though its snapshot
  harness had no visible symptom either, since the bug is invisible until a filter is applied, so
  a project could have been silently exposed without ever noticing). The real-world blast radius
  before this fix depended entirely on adoption of a documented but not-yet-observed-in-use-here
  feature.
- Finding 2's new `case`-based matcher, while verified against the existing 13-assertion `$HOME`-
  coupled suite by hand-trace and against an independent scratch probe during design, is not
  itself executed by that live suite as part of this ADR (design-time verification only, per
  architect scope) — the coder implementing the plan must re-confirm empirically via the actual
  `bash tests/run-tests.sh` invocation, not merely trust this ADR's trace.
- Finding 3's redesign does **not** build a mechanism to reliably distinguish the user's
  pre-existing edits from the fired dimension's own fix attempts within the mixed uncommitted set
  — no such mechanism exists anywhere in the skill today, and this ADR deliberately does not build
  one (§3.3, Alt 3b/3c rejected). A `DIRTY_TREE=true` circuit-breaker firing still requires the
  user to do their own manual, file-by-file reconciliation (or take the non-destructive `git
  stash` escape hatch); it only stops the skill from suggesting a command that would make that
  reconciliation impossible by destroying the evidence first.
- Finding 2's rewrite changes the exact wording of `enumerate-sources.sh`'s header comment (lines
  3-9) to describe the two supported override forms precisely; any external note or muscle-memory
  quoting the old, vaguer "optional glob/dir prefix" phrasing verbatim goes stale. Grepped for
  other call-sites before writing this ADR (§1 "Cross-check"); no other file quotes that exact
  phrase.
- Finding 1's fix changes `capture.sh`'s internal `EXEC_CMD` value whenever `RFS_FILTER` is set
  (from a two-line, filter-ignored-in-practice string to a correct single-line, filter-applied
  string) — any external tooling that happened to depend on the *old*, broken behavior (e.g. a
  script parsing the snapshot file and expecting `EXIT=127` as a sentinel when `RFS_FILTER` is set)
  would need to be updated. Grepped across the repository (§1 "Cross-check"): no such dependency
  exists today.
- Three independent findings land in one ADR/plan/commit rather than three (§3.4); a reviewer
  wanting to approve exactly one or two of the three fixes without the others cannot do so at
  *commit* granularity, only at file/hunk granularity. Mitigated by, but not eliminated by, the
  fact that the upstream GitHub issue (#35) already bundles all three at the same granularity.
- The new test file adds 19 assertions and one more entry to `docs-ci.yml`'s explicit
  `shell-tests` list (tenth of ten) and to the directory `.claude/test-cmd`'s wildcard glob already
  covers — a small, bounded, linear increment to CI runtime, consistent with the existing
  nine-file harness's own growth pattern to date.

### Neutral

- No manifest schema change, no new skill, no new hook, no `settings.json` change, no
  permission-mode change anywhere in this ADR.
- `refactor-snapshot/scripts/pre-runs.sh` needs no edit and automatically inherits Finding 1's fix
  (it only ever passes `RFS_FILTER` through as an inherited subprocess environment variable; it
  never constructs `EXEC_CMD` itself) — confirmed by reading the file, not assumed (§1
  "Cross-check").
- `refactor-snapshot/SKILL.md`'s own env-var documentation (line 84) and self-test target
  (`PASS=18 FAIL=0`, line 91) both already describe the *post-fix* reality accurately and need no
  edit — the doc comment was always correct about intent; only the code diverged from it, and the
  self-test file's 18 assertions never exercised the buggy path in the first place.
- The `$HOME`-coupled skill-local test files (`refactor-snapshot/tests/run-tests.sh`,
  `deep-refactor/tests/{run-tests.sh,enumerate-sources.test.sh}`) are confirmed compatible with
  every fix in this ADR and are deliberately left unedited — they test the *deployed* `~/.claude`
  copy, out of this roadmap's `staging/`-is-source-of-truth scope (ADR-0024/0025), and stay
  defective/stale there, like every other skill this roadmap has touched, until a human runs
  `sync-to-claude.sh --apply`.
- The deployed `~/.claude` copies of `capture.sh`, `enumerate-sources.sh`, and `deep-refactor/
  SKILL.md` keep today's defective behavior until a human runs `sync-to-claude.sh --apply` — the
  same disclosed, established "deployed stays defective until sync" convention as ADR-0025 through
  ADR-0030, repeated here rather than assumed already understood.
- This ADR neither opens nor forecloses Alt 3b's "auto-stash at Gate 0" design; it is explicitly
  left for a future issue to pick up if the message-only fix is ever demonstrated insufficient.

---

## 5. References

- `SPEC.md` (repo root) / `docs/specs/35-refactor-snapshot-filter-append-and-deep.spec.md` — this
  issue's spec (confirmed byte-identical)
- `docs/architecture/ADR-0002-refactor-snapshot-harness.md`,
  `docs/architecture/ADR-0006-refactor-snapshot-runs-configurable.md` — original, historical
  design of the harness Finding 1 patches; not amended
- `docs/architecture/ADR-0018-deep-refactor-skill.md` — original, historical design of the
  audit/fix pipeline and its global circuit breaker; not amended; confirms the `CIRCUIT BREAKER
  FIRED AT:` tag convention Finding 3 leaves untouched
- `docs/architecture/ADR-0027-31-c2c-bsd-slug-autopilot-gates.md`,
  `docs/architecture/ADR-0028-32-manifest-helpers-guards.md`,
  `docs/architecture/ADR-0029-33-hook-verify-session-filter.md`,
  `docs/architecture/ADR-0030-34-scope-guards.md` — structural, test-harness, and
  disclose-don't-assume precedent this ADR reuses directly
- `staging/plugin/skills/refactor-snapshot/scripts/capture.sh`,
  `staging/plugin/skills/refactor-snapshot/scripts/pre-runs.sh`,
  `staging/plugin/skills/refactor-snapshot/SKILL.md`,
  `staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh`,
  `staging/plugin/skills/deep-refactor/SKILL.md` — the files this ADR patches or confirmed
  compatible without edits
- `staging/plugin/skills/refactor-snapshot/tests/run-tests.sh`,
  `staging/plugin/skills/deep-refactor/tests/run-tests.sh`,
  `staging/plugin/skills/deep-refactor/tests/enumerate-sources.test.sh` — confirmed `$HOME`-coupled,
  not part of the hermetic `docs-ci` suite, traced compatible, not edited (§1 "Cross-check")
- `staging/plugin/agents/refactorer.md`, `docs/guida-workflow-orchestrazione.md` — confirmed
  compatible purpose-level `RFS_FILTER` usage notes, not edited
- `docs/vibe-coding-system.md:97,1836` — confirmed unrelated `git checkout -- .` mentions (CC
  native auto-mode blocking, a different feature), not edited
- `staging/sync-to-claude.sh`, `staging/plugin/scripts/tests/pairs-completeness.test.sh` —
  confirmed no new `PAIRS` mapping entry needed for the new test file (§2.5)
- Implementation plan: `docs/superpowers/plans/2026-07-11-35-refactor-snapshot-deep-refactor.md`
