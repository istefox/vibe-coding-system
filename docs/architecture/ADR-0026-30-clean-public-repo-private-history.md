# ADR-0026 — clean-public-repo: keep private history out of the public branch

**Status:** Accepted
**Date:** 2026-07-11
**Author:** istefox
**Supersedes:** none
**Superseded by:** none
**Related:**
- SPEC: `docs/specs/30-clean-public-repo-keep-private-history-o.spec.md` (= `SPEC.md` at repo root, GitHub issue #30)
- ADR-0011 (`clean-public-repo-anonymize`) — original design of `fresh-history-publish.sh` (D5) and
  `surgical-rewrite.sh` (D6), both safety-wrapped around core git and `git-filter-repo`
- ADR-0024 (`vendor-deployed-only-skills-and-hooks`) — vendored `clean-public-repo`'s `SKILL.md` + 4 scripts +
  `tests/run-tests.sh` into `staging/`, established `pairs-completeness.test.sh`'s hermetic self-test pattern and
  the local-glob-vs-CI-explicit-list split this ADR extends again
- ADR-0025 (`refresh-stale-staging-copies`) — the immediately preceding issue (#29); confirms `staging/` is
  currently at 107 PAIRS entries and that the 5-file harness (`phase1`, `prep`, `hook-probe`,
  `hook-verify-workflow`, `pairs-completeness`) is green as of this ADR's writing (independently re-verified
  below, §1)
- `staging/plugin/skills/clean-public-repo/SKILL.md`, `scripts/fresh-history-publish.sh`,
  `scripts/surgical-rewrite.sh`, `scripts/detect-tool-traces.sh` — the four files this ADR patches
- `git-filter-repo` upstream documentation (`newren/git-filter-repo`, `Documentation/git-filter-repo.txt`,
  fetched via Context7 2026-07-11) — verifies the exact internal pipeline `surgical-rewrite.sh` wraps
- Implementation plan: `docs/superpowers/plans/2026-07-11-30-clean-public-repo-private-history.md`

---

## 1. Context

`clean-public-repo` is the skill that prepares a repo for public release or retroactively cleans an
already-public one (ADR-0011). Its two history-rewrite strategies — `fresh-history-publish.sh` (default,
orphan-branch publish, D5) and `surgical-rewrite.sh` (option 2, `git-filter-repo` wrapper, D6) — were vendored
into `staging/` byte-identical to deployment by ADR-0024, together with `detect-tool-traces.sh` (the detector
that feeds both). SPEC.md (issue #30) reports three findings from an audit of those three files, one of them
severity P1:

**Finding 1 (P1, `fresh-history-publish.sh`).** `prepare` mode writes its mandatory `.git/` backup tarball
*inside* the work tree (`BACKUP_PATH="${ROOT}/${BACKUP_NAME}"`, line 52) and then runs `git add -A` (line 133)
to stage the clean commit. Since `.git-backup-*.tar.gz` is an ordinary untracked file at that point, `add -A`
picks it up along with everything else, and the printed HITL instructions tell the user to commit and push
exactly that staged set. Read literally: the artifact whose entire purpose is to let the user recover the
*private* history, if written inside `ROOT`, ends up shipped inside the "clean" commit that gets pushed to the
*public* repo — the fresh-history strategy's one hard guarantee (`docs/architecture/ADR-0011-clean-public-repo-anonymize.md`
D5: "Avoids force-pushing to the original repo entirely... top risk mitigated by design") is defeated by its own
backup step. Independently confirmed by reading the code (`staging/plugin/skills/clean-public-repo/scripts/fresh-history-publish.sh:52,105,133`)
before writing this ADR, not merely taken on SPEC's word.

**Finding 2 (`surgical-rewrite.sh`, rollback-story truthfulness).** Three sub-defects, all downstream of one
fact confirmed against `git-filter-repo`'s own documentation (fetched live via Context7, 2026-07-11, source
`newren/git-filter-repo/Documentation/git-filter-repo.txt`): a normal (non-`--partial`) run's internal pipeline
is `fetch remote-tracking refs → git remote rm origin → fast-export --all | filter | fast-import → update ALL
refs → reset --hard → gc`. Two consequences follow directly:

- `--all` in the fast-export step means *every* ref, including a backup branch created moments earlier in the
  same script run (`pre-rewrite-backup-<TS>`, line 178), gets rewritten identically to `HEAD`. The script's own
  verification instruction, `git diff ${BACKUP_BRANCH} --stat` (line 219), therefore always prints nothing —
  not because nothing changed, but because both sides of the diff are the post-rewrite state. It is not a
  weak verification; it is a non-functional one.
- `git remote rm origin` is unconditional and upstream-documented as deliberate ("removing the origin ... [is]
  a reminder that ... the repository is no longer compatible with the original," per the fetched docs). The
  script's printed push instruction, `git push --force-with-lease origin ${CURRENT_BRANCH}` (line 226), targets
  a remote that filter-repo has just deleted — it fails, unconditionally, every time apply mode is used.

The third sub-defect is independent of filter-repo's pipeline: `BACKUP_PATH="${ROOT}/${BACKUP_NAME}"` (line 121)
has the same inside-`ROOT` placement as Finding 1, though — confirmed by re-reading the apply-mode code path in
full — `surgical-rewrite.sh` never itself calls `git add`/`git commit`, so this is a hygiene/consistency defect
(a stray large binary sitting in what the user will next treat as a clean rewritten clone), not a second P1
staging exploit like Finding 1's.

SPEC additionally names a documentation staleness: SKILL.md line 354-355 asserts `` **Verified environment
(2026-05-23):** `git-filter-repo` PRESENT (`/opt/homebrew/bin`)... `` as if a point-in-time spot-check on one
machine were a durable fact. Re-checked on this machine during planning (2026-07-11): `git filter-repo
--version` → `git: 'filter-repo' is not a git command.` — the claim is not just architecturally fragile, it is
already, concretely false on this exact machine 49 days after it was written.

**Finding 3 (`detect-tool-traces.sh`, SHA matching).** Line 198's commit-boundary detector,
`grep -Eo '^[0-9a-f]{7} '`, requires an *exact* 7-hex-digit abbreviated SHA followed by a space. `git log
--format="%h %B"`'s `%h` is not fixed-width: it honors `core.abbrev`, which is `auto` by default (any length
git judges sufficient for the current object count, and can exceed 7 well before a repo is large) or any
explicit integer a user sets. With `core.abbrev` at 8+, the anchored 7-char-then-space pattern never matches
(the 8th character is another hex digit, not a space) — `MAYBE_SHA` stays empty, `CURRENT_SHA` is never
assigned, and every `commit-trailer` finding downstream of that point in the log carries an **empty** SHA
field, not merely a truncated or off-by-one one. Traced through the full loop logic (lines 195-214) before
writing this ADR, not inferred from the SPEC summary alone.

**Baseline, independently re-verified before planning (2026-07-11, not assumed from ADR-0025):** the 5-file
harness (`phase1`, `prep`, `hook-probe`, `hook-verify-workflow`, `pairs-completeness`) is green —
`pairs-completeness.test.sh` reports `PASS=107 FAIL=0`, matching ADR-0025's final count exactly, confirming
no drift since #29 landed. All three files this issue patches already carry PAIRS entries pointing at their
deployed counterparts (`sync-to-claude.sh` lines 87-89); the vendored `tests/run-tests.sh` (22 tests, all
`grep`-anchor or `$HOME/.claude`-targeting smoke tests) exercises `detect-public-remote.sh` and
`detect-tool-traces.sh` only — it has **zero** coverage of either history-rewrite script's actual behavior,
confirmed by re-reading it in full: this is genuinely new testing territory, not a gap in an existing suite.

## 2. Decision

Fix exactly the three findings, add one new hermetic test file wired into both the local `test-cmd` glob and
CI's explicit list (mirroring `pairs-completeness.test.sh`'s ADR-0024 precedent), touch no other behavior, and
add no new PAIRS entries (the three patched scripts already have them; the new test file, like
`pairs-completeness.test.sh` before it, gets none — its logic is meaningless outside a `staging/` checkout).

### 2.1 Finding 1 — relocate the backup tarball, add an independent hard-fail guard

Two complementary fixes in `fresh-history-publish.sh`, both required (neither alone is sufficient — see §3.1):

**Relocate, resolved via the canonical git top-level, not the raw `ROOT` argument.** Immediately after the
existing "must be a git repository" precondition check, add:
```bash
GIT_TOPLEVEL=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$GIT_TOPLEVEL" ]; then
  err "Could not resolve the repository top-level directory for: $ROOT"
  exit 2
fi
```
and change the single `BACKUP_PATH` assignment from `"${ROOT}/${BACKUP_NAME}"` to
`"$(dirname "$GIT_TOPLEVEL")/${BACKUP_NAME}"`. Resolving via `--show-toplevel` rather than `dirname "$ROOT"`
directly matters: if a caller passes a *subdirectory* of the repo as `ROOT` (the script never requires `ROOT`
to be the true root), `dirname "$ROOT"` can still land inside the work tree, silently reproducing Finding 1
under a slightly different call pattern. `--show-toplevel` always returns the repository's actual root
regardless of what subdirectory was passed, so `dirname` of *that* is guaranteed outside the work tree. Because
`BACKUP_PATH` is a single variable read by both `dry-run`'s printed plan and `prepare`'s actual `tar` call, one
change fixes both.

**Independent hard-fail guard**, inserted after the existing `git add -A` step (`prepare` mode), before the
"STOP FOR HITL" instructions print:
```bash
STAGED_BACKUP=$(git -C "$ROOT" ls-files 2>/dev/null | grep -E '(^|/)\.git-backup-.*\.tar\.gz$')
if [ -n "$STAGED_BACKUP" ]; then
  err "SAFETY ABORT: the following .git-backup-*.tar.gz path(s) are staged for commit:"
  printf '%s\n' "$STAGED_BACKUP" | while read -r p; do err "  $p"; done
  err "Committing this would ship the full private git history inside the public release."
  err "Unstage it and investigate, e.g.: git -C \"$ROOT\" reset -- <path>"
  exit 5
fi
```
`git ls-files` (index-based, not `git diff --cached`) is used because it needs no "diff against what" reasoning
on a branch with no prior commits (the orphan branch's first-ever state) — it just lists what is in the index,
which is exactly "staged" for this check's purpose. New exit code 5 (documented in the file's own header
comment) is dedicated to this safety class, distinct from exit 2's generic precondition-not-met — see §3.2 for
why a new code, not a reused one. This check is deliberately redundant with the relocation fix: relocation
closes the *mechanism* this specific bug used; the guard closes the *pattern* regardless of mechanism (a stray
backup left inside `ROOT` by an interrupted prior run, a user's own file coincidentally matching the name,
etc.) — belt-and-suspenders is the existing design idiom throughout this skill (tar backup + dry-run + HITL +
per-category confirmation are all already independent, overlapping safety layers per ADR-0011 D8).

**SKILL.md mirror**, scoped exactly to the lines SPEC names (249-262, the fresh-history "Mandatory backup" flow
step) plus one bullet appended to the existing "Safety notes" list (lines 277-282): the backup command example
gains the outside-work-tree path and a one-line note that `prepare` hard-fails (exit 5) if a `.git-backup-*`
path is ever found staged. No other SKILL.md prose changes for this finding.

### 2.2 Finding 2 — relocate the tarball, capture `origin` pre-rewrite, replace the dead verification instruction

Same `GIT_TOPLEVEL`/`dirname` relocation as §2.1, applied independently in `surgical-rewrite.sh` (inserted
after its own "must be a git repository" check, before the fresh-clone check block; the fresh-clone protection
itself — dirty-tree and stash-list checks, `git-filter-repo`'s own refusal to run on a non-fresh clone — is
unmodified, out of scope).

**Capture `origin`'s URL before Step 3 (the `git filter-repo` call) removes it**, alongside the existing
`CURRENT_BRANCH` capture in Step 2 (both are "state that becomes unreadable after the rewrite" concerns,
co-located deliberately):
```bash
ORIGIN_URL=$(git -C "$ROOT" remote get-url origin 2>/dev/null)
```

**Replace the apply-mode "STOP FOR HITL" message block** (lines 212-232). Remove the dead
`git diff ${BACKUP_BRANCH} --stat` line entirely (per §1, it is not weak, it is non-functional — keeping it
alongside a caveat was considered and rejected, see §3.3) and replace it with: an explicit note that
`git-filter-repo` rewrites all refs including the backup branch, so a diff against it is never meaningful; a
pointer to `$GIT_DIR/filter-repo/commit-map` (confirmed via the fetched upstream docs to be written on every
non-`--partial`, non-dry-run apply — a header line then one `old-SHA new-SHA` pair per commit in the rewrite
range, an all-zero `new` meaning that commit was dropped) as the actual before/after record; an explicit
statement that the tar backup is the sole rollback; and, conditioned on whether `ORIGIN_URL` was captured, either
the exact `git remote add origin ${ORIGIN_URL}` command or a manual fallback instruction, inserted immediately
before the existing (unmodified) force-push instructions.

**SKILL.md**, scoped exactly to the stale claim SPEC names (lines 354-355), nothing else in the surgical-rewrite
section (see §3.4 for why the "Flow" prose step is deliberately left untouched, unlike Finding 1's explicit
mirror instruction). Reworded to stop asserting a point-in-time fact as durable truth and instead point at the
script's own existing, already-correct graceful-degrade check (`git filter-repo --version`, exit 3 with install
instructions when absent — unmodified by this ADR, already correct) as the authoritative, self-updating source.

### 2.3 Finding 3 — widen the SHA-boundary regex

One-line change, `staging/plugin/skills/clean-public-repo/scripts/detect-tool-traces.sh:198`:
```
-  MAYBE_SHA=$(echo "$LOG_LINE" | grep -Eo '^[0-9a-f]{7} ')
+  MAYBE_SHA=$(echo "$LOG_LINE" | grep -Eo '^[0-9a-f]{7,40} ')
```
`{7,40}` covers git's practical abbreviation range (7 through a full 40-hex-char SHA-1); the interval-expression
syntax is unchanged from what the line already used (`{7}` → `{7,40}`, same BSD/POSIX ERE class, zero new
dependency or compatibility risk). No other line in either script or in `SKILL.md`'s illustrative
`commit-trailer|auto-removable|a1b2c3d|...` example is touched — the example remains illustrative prose, not a
normative width constraint, and SPEC does not name it.

### 2.4 Test strategy: live fixtures for Findings 1 and 3, source-anchors for Finding 2 — and why the split is real, not inconsistent

One new file, `staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh`, hermetic (own
`SCRIPTS`/`STAGING` path derivation, same idiom as `pairs-completeness.test.sh`; zero `$HOME` dependency),
14 assertions in three lettered sections:

- **Section A (Finding 1, 5 tests, live subprocess execution against real fixture git repos):** a clean fixture
  reaches `prepare` mode's success path with the backup verifiably outside the fixture directory and verifiably
  absent from inside it (A1); a *second* fixture, invoked with a **subdirectory** of the repo as `ROOT`, still
  resolves the backup to the true top-level's parent — proving the `--show-toplevel` design choice, not just
  "moved the string" (A2); a fixture with a pre-staged `.git-backup-*.tar.gz` decoy triggers exit 5 and a
  `SAFETY ABORT` message (A3); the same clean fixture from A1 still reaches the HITL-stop message with no false
  trigger of the new guard — a non-regression companion, not a bug-reproduction (A4); a SKILL.md anchor
  confirming the "Mandatory backup" step's example now shows an outside-work-tree path (A5).
- **Section B (Finding 3, 2 tests, live subprocess execution):** a two-commit fixture with `core.abbrev`
  explicitly set to 8 asserts the reported SHA for a trailer finding equals the commit's real 8-char `%h`,
  non-empty (B1, the real bug reproduction); a companion fixture at git's natural ~7-char default confirms the
  widened range does not regress the pre-existing case (B2, non-regression companion, mathematically
  guaranteed by `{7,40}` being a strict superset of `{7}` but kept as an explicit, cheap, visible check rather
  than left implicit).
- **Section C (Finding 2, 7 tests, static `grep` anchors against the script source and SKILL.md, no subprocess
  execution of `surgical-rewrite.sh` itself):** the old `${ROOT}/${BACKUP_NAME}` assignment is absent (C1) and
  the new `dirname "$GIT_TOPLEVEL"` form is present (C2); `ORIGIN_URL` capture is present (C3); a
  `remote add origin` instruction is present (C4); a `filter-repo/commit-map` reference is present (C5); the
  literal dead `diff ${BACKUP_BRANCH} --stat` line is absent (C6); the SKILL.md stale-claim rewording is
  present, verified against a specific new anchor phrase rather than mere absence of the old text (C7).

Section C's asymmetry from A/B is a direct, forced consequence of §1's pipeline finding, not a shortcut: every
mode of `surgical-rewrite.sh` — dry-run *and* apply — is gated behind an unconditional
`git filter-repo --version` check that runs before mode dispatch (lines 51-63, unmodified, correctly designed,
out of scope to reorder). `git-filter-repo` is confirmed absent on this development machine right now (2026-07-11,
§1) and is not installed by any step in `.github/workflows/docs-ci.yml`; a live subprocess test would return
exit 3 (graceful degrade) in both environments that matter — local dev and CI — before ever reaching the code
this ADR changes, providing zero actual coverage of the fix while *looking* like a real test. Static
source-anchors, by contrast, run identically and meaningfully regardless of `git-filter-repo`'s local presence.
This is not a novel pattern for this skill: the vendored `tests/run-tests.sh`'s 11 "structural anchor" tests on
`SKILL.md` already use the identical grep-anchor technique for content that cannot otherwise be exercised
hermetically. §3.5 records the two alternatives rejected here.

**CI wiring**, mirroring ADR-0024 §2.4's precedent exactly: `clean-public-repo-history-safety` appended to
`.github/workflows/docs-ci.yml`'s explicit `for t in phase1 prep hook-probe hook-verify-workflow
pairs-completeness` list. The local `.claude/test-cmd` glob (`staging/plugin/scripts/tests/*.test.sh`) picks up
the new file automatically — no edit needed there, confirmed by re-reading `.claude/test-cmd`'s current content
before writing this ADR (unchanged single line). This local-glob-vs-CI-explicit-list split was already an
established, documented fact before this issue (ADR-0024 §1, point 4) — this decision applies the already-known
pattern, it does not discover or introduce it.

### 2.5 No PAIRS changes, no RUNBOOK.md changes

Confirmed by reading `staging/sync-to-claude.sh` before planning: all three patched scripts already carry PAIRS
entries (`plugin/skills/clean-public-repo/scripts/{fresh-history-publish,surgical-rewrite,detect-tool-traces}.sh`,
lines 87-89) and `SKILL.md` likewise (line 85) — a future human `sync-to-claude.sh --apply` deploys every fix
in this ADR through those existing entries with zero new lines. The new test file gets no PAIRS entry, matching
`pairs-completeness.test.sh`'s own precedent exactly (ADR-0024 §2.4: "not itself vendored to `~/.claude`; its
logic is meaningless outside a repo checkout"). `docs/RUNBOOK.md`'s bulk disaster-recovery path
(`cp -R staging/plugin/skills/* ~/.claude/skills/`, line 101) already globs the whole `clean-public-repo/`
subtree, so the SKILL.md edits need no RUNBOOK edit either; the new test file is staging-only by design (§2.4)
and is correctly outside RUNBOOK's scope for the same reason it is outside PAIRS's.

## 3. Alternatives considered

### 3.1 Backup-relocation strategy

**Chosen:** `dirname` of the git-resolved top-level (§2.1), relying on the script's pre-existing
tar-failure exit-2 guard as the sole fallback for a non-writable parent directory — no new fallback logic.

- **Alternative A — write to `mktemp -d` / `$TMPDIR`.** Rejected. The entire point of this backup, restated
  explicitly by Finding 2 ("document the tar as the SOLE rollback"), is that it is the one durable artifact a
  user can restore from after either history-rewrite strategy runs. `/tmp` on macOS is not guaranteed to
  survive a reboot, and OS-level periodic cleanup of temp directories is a real, documented risk for a file
  whose whole job is long-lived durability, not transience. Using it would trade one safety defect for another,
  quieter one.
- **Alternative B — a fixed, dedicated location, e.g. `$HOME/.claude-backups/`.** Rejected as unrequested scope
  expansion beyond SPEC's literal ask ("outside the work tree," nothing more specific), and as a new,
  undocumented filesystem convention this single-user, single-machine system has no other precedent for. It
  also does not obviously generalize better than the chosen approach: a dedicated directory still needs its own
  writability/existence handling, and `dirname(GIT_TOPLEVEL)` — the directory the user already had permission
  to create the repo inside in the first place — is the lower-assumption choice.
- **Alternative C — add an explicit permission-check-and-fallback path** (try the parent directory; on failure,
  fall back to a temp directory with a loud durability warning). Rejected as scope creep relative to SPEC's two
  literal asks ("create it outside the work tree" and "hard-fail if staged"). The script's existing
  `tar ...; if [ $? -ne 0 ]; then err ...; exit 2; fi` guard already fails closed (aborts, does not silently
  continue) on any `tar` failure for any reason, including a non-writable parent — introducing a second,
  bespoke fallback path for one specific failure cause, when the generic guard already handles it safely, adds
  complexity without adding safety.

### 3.2 Hard-fail guard exit code

**Chosen:** a new, dedicated exit code 5 ("safety abort: a `.git-backup-*.tar.gz` path was staged"), documented
in the script's own header comment alongside the existing 0/2 codes.

- **Alternative — reuse exit code 2 ("not a git repository or precondition error").** Rejected. A staged
  private-history artifact is not a *precondition* failure (the operation's inputs were all valid; the check
  runs mid-flow, after real work — a tar backup and an orphan-branch checkout — has already happened) — it is a
  *safety-invariant violation* discovered during execution, a materially different failure class a caller or
  test should be able to distinguish from "the directory you pointed me at is not a git repo." A dedicated code
  also lets the plan's own test assertions (§2.4, A3) check for exactly this failure mode unambiguously, rather
  than inferring intent from message text alone.

### 3.3 Finding 2's dead verification instruction

**Chosen:** delete the `git diff ${BACKUP_BRANCH} --stat` line outright; replace it with commit-map-based
guidance and an explicit "the backup branch is not reliable" note (§2.2).

- **Alternative — keep the line but add a caveat comment above it** ("this may print nothing; see note below").
  Rejected. The instruction does not "may" print nothing — per the confirmed upstream pipeline (§1), it
  *always* prints nothing, unconditionally, for every apply run, because `--all` guarantees the backup branch is
  rewritten identically to `HEAD`. Keeping a command that is proven to never produce useful output, even
  caveated, invites a future reader to run it anyway "just in case" and waste a verification step on a check
  that cannot ever succeed. A verification instruction that can never verify anything is worse than no
  instruction at all — replacing it, not merely annotating it, is the honest fix SPEC's own language
  ("truthful... rollback story") calls for.

### 3.4 Scope of Finding 2's SKILL.md edit

**Chosen:** touch only lines 354-355 (the stale environment claim); leave the "Flow" section's backup-command
example (item 2, near line 311) untouched, even though it shares the same inside-`ROOT` pattern as Finding 1's
example (§2.1's SKILL.md mirror).

- **Alternative — mirror the "outside the work tree" wording into surgical-rewrite's Flow section too, for
  parity with Finding 1's explicit SKILL.md mirror.** Rejected, deliberately, even though it is a small,
  low-risk, arguably-nice-to-have edit. SPEC's finding-2 bullet names exactly one SKILL.md location ("Refresh
  the stale claim at SKILL.md line 355") where finding-1's bullet names a full range with an explicit "Mirror
  the change" instruction ("Mirror the change in SKILL.md lines 249–262") — SPEC is precise and deliberate about
  which doc edits each finding requires, and ADR-0024 §3.2/§3.4 and ADR-0025 §3.1/§3.2/§3.4 (all read before
  writing this ADR) each independently reject "expand a named scope for consistency" as a recurring failure
  mode in this exact roadmap. The asymmetry is SPEC's own, not an oversight this ADR is introducing.

### 3.5 Test strategy for Finding 2

**Chosen:** static `grep`-anchor assertions against the script source and SKILL.md (§2.4, Section C) — no live
subprocess execution of `surgical-rewrite.sh`.

- **Alternative A — a conditional live test** (`if command -v git-filter-repo / git filter-repo --version
  succeeds, run full behavioral apply-mode assertions; else print a SKIP notice`). Rejected as the worse trade
  for this specific case, even though it is not unreasonable in general. `git-filter-repo` is confirmed absent
  on this development machine right now and is not installed by any existing `docs-ci.yml` step — meaning the
  conditional's "skip" branch is the *only* branch that would ever execute in either environment that actually
  matters (local dev, CI), making the "live" branch dead code providing zero real coverage while adding real
  complexity (environment-detection logic, a third possible test outcome beyond pass/fail that the existing
  PASS/FAIL harness idiom has no established convention for). If `git-filter-repo` is reinstalled on this
  machine in the future, static anchors still catch a regression; a conditional-live test would have caught
  nothing in the meantime it was needed.
- **Alternative B — install `git-filter-repo` as a step in `docs-ci.yml` so a full live test can run in CI.**
  Rejected. `docs-ci.yml`'s own header comment states its harnesses are deliberately "Offline, hermetic, no
  network" — adding an install step (`pip3 install git-filter-repo` or a `brew` step) contradicts that stated
  invariant for the sake of one finding's tests, is a materially larger and riskier change than the three
  findings SPEC scopes this issue to, and does not even solve the *local* dev-machine gap (this machine would
  still need a manual, separate install to get live coverage when running the suite locally via `test-cmd`).
- **Alternative C — refactor `surgical-rewrite.sh` into sourceable functions so the tar-relocation logic (Step 1,
  which does not itself depend on `git-filter-repo`) can be tested in isolation without invoking the whole
  script.** Rejected. This is a structural rewrite of the script's shape, not a bug fix — squarely inside
  SPEC's explicit "Out: Behavioral changes beyond the three findings," and it does not even fully solve the
  problem: the graceful-degrade check (line 51) runs unconditionally before *any* mode dispatch in the current
  design, so isolating Step 1 would itself already be a scope-expanding restructure, not a narrow extraction.

### 3.6 New-file placement and granularity

**Chosen:** one new file, `staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh`, covering all
three findings in one hermetic harness, following `pairs-completeness.test.sh`'s exact structural precedent
(own path derivation, `PASS`/`FAIL` counters, final `PASS=N FAIL=N` line, non-zero exit on any `FAIL`).

- **Alternative A — three separate files, one per finding.** Rejected. This repo's own precedent (this very
  skill's vendored `tests/run-tests.sh`, 22 assertions in one file; `pairs-completeness.test.sh`, a self-test
  plus a real check in one file) favors one file per *concern cluster*, not one file per individual defect. Three
  files would also mean three new entries in `docs-ci.yml`'s explicit list instead of one, for no discoverability
  gain — the three findings are already clearly separated by lettered sections (A/B/C) and comments inside a
  single file.
- **Alternative B — extend the skill's own `staging/plugin/skills/clean-public-repo/tests/run-tests.sh`
  instead of adding a file under `staging/plugin/scripts/tests/`.** Rejected. That file targets
  `$HOME/.claude/skills/clean-public-repo/...` (the *deployed* copy) by hardcoded design (`S="$HOME/.claude/..."`
  at its own top) — confirmed by re-reading it before this decision — and is consequently outside both the local
  `test-cmd` glob and `docs-ci.yml`'s scope entirely (PRIOR AGENT NOTES; independently re-confirmed structurally:
  the glob only covers `staging/plugin/scripts/tests/`, a different directory). Extending it would test whatever
  happens to be deployed on the machine that runs it — which, per this same roadmap's own established convention
  (PRIOR AGENT NOTES: "the deployed clean-public-repo copy stays defective until the next human
  sync-to-claude.sh --apply; that is by design"), is *guaranteed* to still be defective immediately after this
  very fix lands, since deployment only updates on a separate, human-gated sync. A test targeting deployment
  would assert against staging's own known-current defect, the opposite of what a regression test for this fix
  should do. This task's explicit instruction to wire new tests through the `test-cmd` glob (§2.4) already
  settles this in the same direction independently.

## 4. Consequences

### Positive

- Closes a live P1 information-disclosure defect: the mechanism by which the fresh-history publish strategy's
  private-history backup could end up committed and pushed into a public repository is closed at two
  independent points (relocation removes the specific cause; the hard-fail guard catches the pattern
  regardless of cause), matching this skill's own established belt-and-suspenders safety idiom rather than a
  single point of failure.
- `surgical-rewrite.sh`'s rollback story becomes actually true instead of only documented as true: the
  verification instruction a user is told to run now produces real information (`commit-map`) instead of
  guaranteed-empty output, and the push instruction a user is told to run now succeeds (origin re-added) instead
  of guaranteed-failing every single time apply mode is used.
- `detect-tool-traces.sh`'s commit-history findings carry correct SHAs regardless of a repo's `core.abbrev`
  setting, closing a class of false/empty-attribution findings that would have made cleanup reports misleading
  on any repo not using git's older 7-char default.
- The new harness gives this skill's two history-rewrite scripts their first behavioral test coverage at all
  (previously zero, confirmed in §1) for the two findings where live testing is possible (Findings 1 and 3),
  plus durable, environment-independent regression protection for the third (Finding 2) via source anchors —
  proportionate to what each finding's environment constraints actually allow, not a uniform technique applied
  regardless of fit.
- Zero PAIRS changes and zero RUNBOOK.md changes were needed (§2.5), confirmed rather than assumed by reading
  `sync-to-claude.sh` and `RUNBOOK.md` before planning — the smallest-blast-radius outcome available given the
  three files already had deploy paths.
- `pairs-completeness.test.sh`'s count stays at 107 throughout this issue (no new PAIRS entries), giving a
  trivial, precise regression anchor: any deviation from `PASS=107 FAIL=0` at any checkpoint in the plan signals
  an out-of-scope change.

### Negative

- Finding 2's test coverage is structurally weaker than Findings 1 and 3's: static source-anchors prove the
  expected *text* is present/absent in the script, not that the live apply-mode flow behaves correctly end to
  end with a real `git-filter-repo` run. A syntactically-plausible but semantically-wrong edit (e.g., a typo'd
  variable name that still happens to satisfy a loosely-written grep pattern) could theoretically pass. Mitigated
  by writing precise, specific anchors tied to exact variable names and exact literal strings (§2.4, C1-C7) and
  flagged here explicitly as a residual risk rather than an eliminated one, not for false reassurance.
- The currently-*deployed* `clean-public-repo` skill (at `~/.claude/skills/clean-public-repo/`) remains
  defective — still capable of leaking private history via Finding 1's exact mechanism — until a human runs
  `sync-to-claude.sh --apply` after this fix merges. This is the same "deployed stays defective until sync"
  design already established for this exact roadmap (PRIOR AGENT NOTES), but the severity is materially higher
  here than for a typical staging-ahead-of-deployed gap: this is a live P1 security-relevant defect sitting in
  the actively-used deployed copy for as long as the sync is deferred. Flagged with elevated urgency in this
  ADR's risk register and the plan's report, though the fix itself, by this roadmap's own established and
  unchanged convention, is scoped to `staging/` only.
- A latent, pre-existing false-positive class in `detect-tool-traces.sh`'s commit-boundary heuristic (any commit
  message *body* line that itself happens to start with 7-40 hex characters followed by a space would be
  misidentified as a new commit boundary) is not fixed by this ADR and is, if anything, nominally widened in
  surface by `{7,40}` versus the old `{7}` (a body line starting with an 8-39-character hex-looking token now
  also matches, where before only an exactly-7-character one did). This is inherited, not introduced: the
  identical class of risk already existed for exactly-7-character matches before this fix, is not one of SPEC's
  three named findings, and fixing it would require the sentinel-log-format redesign SPEC itself offered as an
  alternative and this ADR did not choose (§2.3) — explicitly out of scope, recorded here so it is not later
  mistaken for a defect this issue introduced.
- `surgical-rewrite.sh` and `fresh-history-publish.sh` now duplicate an near-identical 5-line
  `GIT_TOPLEVEL`/`BACKUP_PATH` resolution block rather than sharing it via a common sourced helper. A small,
  known, accepted duplication (§3.1 does not cover this specifically — noted here for completeness): introducing
  a new shared-helper/sourcing convention would be a structural change to this skill's script layout, which has
  no existing precedent for sourcing between its own scripts, and is a larger change than three targeted bug
  fixes warrant.

### Neutral

- `SKILL.md`'s illustrative `commit-trailer|auto-removable|a1b2c3d|...` example (7-character SHA) is left
  as-is; it is prose illustration, not a normative width constraint, and SPEC does not name it. A future reader
  could reasonably wonder whether it should show a longer example given Finding 3 — it is deliberately not
  updated here, matching this ADR's general discipline of not touching SKILL.md prose SPEC does not explicitly
  name (§3.4).
- The stale-environment-claim rewording (§2.2) deliberately avoids embedding a new dated "as of 2026-07-11:
  absent" claim in its place — doing so would only recreate the same staleness problem in a different form the
  next time the machine's toolchain changes. The chosen wording instead defers to the script's own live
  `git filter-repo --version` check as the durable source of truth. This is a documentation-writing pattern
  worth reusing the next time this roadmap encounters a similar dated-claim staleness finding (see DURABLE
  NOTES in the report).
- This ADR changes no hook wiring, no `settings.json`, no `hooks.json`, and no file under `~/.claude` — fully
  consistent with every prior ADR in this roadmap's stated invariant that staging-side fixes stay staging-side
  until an explicit, separate, human-gated sync.

## 5. References

- `SPEC.md` (repo root) / `docs/specs/30-clean-public-repo-keep-private-history-o.spec.md` — this issue's spec
- `docs/architecture/ADR-0011-clean-public-repo-anonymize.md` — original D5/D8 design this ADR patches without
  revisiting (fresh-history-first default, layered HITL/backup safety idiom)
- `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md` — vendored the four patched files;
  established `pairs-completeness.test.sh`'s hermetic self-test pattern and the local-glob-vs-CI-list split
  this ADR's §2.4 reuses
- `docs/architecture/ADR-0025-29-refresh-stale-staging-copies.md` — confirms the 107-entry PAIRS baseline and
  5-file-green baseline this ADR's plan checkpoints against
- `staging/plugin/skills/clean-public-repo/SKILL.md`, `scripts/fresh-history-publish.sh`,
  `scripts/surgical-rewrite.sh`, `scripts/detect-tool-traces.sh` — the four files this ADR patches
- `staging/plugin/scripts/tests/pairs-completeness.test.sh` — structural precedent this ADR's new test file
  follows (own path derivation, PASS/FAIL idiom)
- `staging/sync-to-claude.sh` — confirmed unmodified by this ADR (all three patched scripts already have PAIRS
  entries; the new test file deliberately gets none, §2.5)
- `.github/workflows/docs-ci.yml` — the CI job gaining one new entry in its explicit test list
- `docs/RUNBOOK.md` — confirmed unmodified by this ADR (line 101's existing glob already covers the SKILL.md
  edit; the new test file is staging-only by design, §2.5)
- `newren/git-filter-repo`, `Documentation/git-filter-repo.txt` (fetched via Context7, 2026-07-11) — verifies
  the internal pipeline (`fetch → remote rm origin → fast-export --all | filter | fast-import → update all
  refs → reset --hard → gc`) and the `$GIT_DIR/filter-repo/commit-map` output format this ADR's Finding 2 fix
  relies on
- Implementation plan: `docs/superpowers/plans/2026-07-11-30-clean-public-repo-private-history.md`
