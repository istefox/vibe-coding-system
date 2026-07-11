# ADR-0030 — Scope guards: autopilot-build CWD check, project-conductor manifest binding, nightly-autopilot check 6

**Status:** Accepted
**Date:** 2026-07-11
**Author:** istefox
**Supersedes:** none
**Amends:** none
**Related:**
- SPEC: `docs/specs/34-scope-guards-autopilot-cwd-check-conduct.spec.md` (= `SPEC.md` at repo root,
  GitHub issue #34, confirmed byte-identical by diff before writing this ADR)
- ADR-0020 (`autopilot-build-skill`) — D3 #1 already documents the *intended* Check-1 contract this
  ADR restores in the *implementation*; ADR-0020's own text needs no correction (Context, "Cross-check
  against ADR-0020 and the existing prose bullets")
- ADR-0016 (`dynamic-workflows-step5`) — introduced `hook_verified` and the Workflow/Agent-tool
  dispatch-mode gate this ADR's Finding C keeps intact
- ADR-0029 (`hook-verify-session-filter`) — the immediately preceding issue in this roadmap; its
  Context section explicitly disclosed, and declined to close, the gap Finding C resolves ("Gap
  flagged for issue #34"); this ADR is that follow-up
- ADR-0022 (`nightly-autopilot-goal`), ADR-0023 (`nightly-auto-design`) — Phase P, the zero-manifest
  pre-flight moment Finding C's zero-manifest branch is written for
- ADR-0024/0025 (`vendor-deployed-only-skills-and-hooks`, `refresh-stale-staging-copies`) — confirms
  `staging/` is this roadmap's working source of truth; `~/.claude` stays untouched until a human sync
- ADR-0027 (`c2c-bsd-slug-autopilot-gates`), ADR-0028 (`manifest-helpers-guards`) — structural and
  test-harness precedent this ADR reuses (multi-finding ADR, one shared test file, lettered sections,
  static-anchor + dynamic-extract-and-execute dual coverage)
- `staging/plugin/skills/autopilot-build/SKILL.md`, `staging/plugin/skills/project-conductor/SKILL.md`,
  `staging/plugin/skills/nightly-autopilot/SKILL.md` — the three files this ADR patches
- `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh` — the manifest schema (`topic:`,
  `hook_verified:` defaults) both Finding B and Finding C's fixes depend on
- `docs/GUIDA-USO-IT.md` — two prose sites reconciled alongside Finding A
- Implementation plan: `docs/superpowers/plans/2026-07-11-34-scope-guards.md`

---

## 1. Context

Issue #34 (audit findings 2.5/P2, 3.10, 3.11) names three independent scope/binding defects across
three of the roadmap's unattended-execution skills. All three were verified against the current file
state (not assumed) before this ADR was written.

### Finding A — `autopilot-build/SKILL.md:60`, Check 1 scope guard is inverted and unanchored

Check 1 is the *first* thing `autopilot-build` runs, before it reads anything else from the manifest —
its job is to enforce the global session-scope invariant ("never operate on files or directories
outside the session's primary working directory," `~/.claude/CLAUDE.md`) for the one skill in this
system that runs fully unattended. ADR-0020 D3 #1 states the intended contract in plain language:
"If `project_root` is neither equal to CWD nor a subdirectory of CWD, emit a SCOPE ERROR and abort" —
i.e. the session may be opened at `project_root` itself, or at any ancestor of it (everything
`autopilot-build` would ever touch is then still reachable from CWD); it must abort if CWD is a
strict descendant of `project_root`, or an unrelated directory. `autopilot-build/SKILL.md:34` states
the same contract in its own prerequisites bullet: "Session CWD equals `manifest.project_root` or is
a parent of it." Both of these prose statements are already correct and need no edit — the defect is
only in the Bash that was supposed to implement them (`SKILL.md:51-64`):

```bash
project_root_n="${project_root%/}"
cwd_n="${cwd%/}"
if [ "$cwd_n" != "$project_root_n" ] && [ "${cwd_n##$project_root_n}" = "$cwd_n" ]; then
  echo "SCOPE ERROR: ..."
  exit 1
fi
```

`${cwd_n##$project_root_n}` strips `project_root_n`, as an *unquoted glob pattern*, from the front of
`cwd_n` — i.e. it tests whether `project_root_n` is a prefix of `cwd_n` (CWD is *inside*
`project_root`), the opposite of the direction ADR-0020 specifies (`project_root` must be inside, or
equal to, CWD). Traced by hand against all three scenarios the roadmap named, using the codebase's own
`cd "$dir" && pwd -P` normalization idiom (`stop-gate.sh`, `approve-test-cmd.sh`) to keep the trace
free of macOS's `/var` → `/private/var` symlink gotcha:

| Scenario | CWD | `project_root` | ADR-0020 says | Current code does |
|---|---|---|---|---|
| Parent CWD | `/Users/x` | `/Users/x/proj` | PASS (project_root beneath CWD) | **ABORTS** — `project_root_n` is longer than `cwd_n`, so the `##` strip is a no-op, the second `[ ]` is true, the `if` fires |
| Child CWD | `/Users/x/proj/sub` | `/Users/x/proj` | ABORT (project_root above CWD) | **PASSES silently** — `project_root_n` *is* a prefix of `cwd_n`, the strip leaves `/sub`, the second `[ ]` is false |
| Sibling | `/Users/x/myproj-backup` | `/Users/x/myproj` | ABORT (unrelated) | **PASSES silently** — `myproj` is a literal string-prefix of `myproj-backup`, and nothing checks for a `/` boundary after the stripped prefix |

Both defects — inverted direction and missing slash-anchoring — are independent; fixing only one still
leaves the other. This is the check-1 half of the session-scope invariant that autopilot-build is the
*only* automated enforcement point for, since it is the one skill that runs with no human turn to
catch a mistaken CWD.

### Finding B — `project-conductor/SKILL.md:59,164,247`, manifest lookup by bare substring

All three of project-conductor's manifest-lookup call sites (Step 0 reconciliation, Step 3 in-progress
check, Step 5 outcome evaluation) use the identical one-liner:

```bash
ls -t "$_root"/docs/manifests/*<topic-slug>*.manifest.yml 2>/dev/null | head -1
```

The manifest naming convention, fixed by `manifest-init.sh` (`manifest="$root/docs/manifests/$today-$slug.manifest.yml"`), is `YYYY-MM-DD-<topic-slug>.manifest.yml`. A bare `*<topic-slug>*` substring glob matches `<topic-slug>` **anywhere** in the filename, so a feature whose slug is a hyphen-prefix of another feature's slug collides: deriving slug `export` for one feature, with a manifest `2026-07-11-export-csv.manifest.yml` already on disk for an unrelated "Export CSV" feature, the glob `*export*.manifest.yml` matches **both** files, and `ls -t | head -1` silently picks whichever is newest — binding the wrong feature's `current_step` to the "Export" feature's state. Depending on that state, this can auto-mark `- [ ] Export` as `[x]` complete in `PROJECT.md` (Step 5A), or auto-resume the wrong in-progress chain (Step 3), **without the "Export" feature ever having actually run**. `PROJECT.md` is the human-facing source of truth for an entire multi-feature roadmap, so this is a state-corruption bug, not a cosmetic one.

`manifest-init.sh` also confirms the exact schema field this fix needs: `echo "topic: \"$slug\"" >> "$T"` — `topic:` **is** the kebab slug itself (not the display title; `topic_full_title:` is separate and on its own line, so a `^topic:`-anchored grep cannot collide with it).

### Finding C — `nightly-autopilot/SKILL.md:103`, check 6 has no command and assumes infrastructure that does not exist

Check 6 ("hook_verified known") currently reads, in full: "the roadmap's manifests carry
`hook_verified` true or false, not null (drives Workflow vs Agent-tool dispatch downstream)" — one
prose sentence, no fenced bash, unlike checks 3, 5, and 8 in the same list. SPEC.md's own proposed
fix text (`docs/specs/34-*.md:14`) says pre-flight should, on zero manifests, "consult the global
smoke-test record written by hook-verify-workflow.sh (ADR-0016 result is global per CC version)."

**No such record exists**, verified two independent ways before writing this ADR:

1. `hook-verify-workflow.sh`'s own header states its contract in plain text: "Bash 3.2 clean.
   Read-only: never writes a manifest, never touches the audit log." It only ever prints a
   `RECOMMEND hook_verified=<value>` line to stdout and returns an exit code; it has no write path at
   all, to any file, anywhere.
2. ADR-0029 §1 — the immediately preceding issue in this same roadmap, landed one commit before this
   ADR was written — independently traced the same question for a different reason and recorded, under
   its own heading "Gap flagged for issue #34 (per roadmap instruction: disclose, do not implement
   here)": *"No such record exists... This fix does not change that (the script stays read-only and
   stateless)... Issue #34's design will need either a new, separate persistent store, or a different
   pre-flight-check-6 design that does not assume one already exists."* ADR-0029 explicitly left this
   choice for this issue to make.

The only thing in the whole system that ever *persists* a `hook_verified` verdict is
`manifest-set-flag.sh <manifest> hook_verified <bool>`, called by `concept-to-code`'s own Step-5 gate —
and that writes to **one manifest's own YAML file**, not anywhere global. `manifest-init.sh` defaults
every newly created manifest to `hook_verified: false` unconditionally.

The check's own zero-manifest edge case is not hypothetical: ADR-0023's Phase P flow generates
`PROJECT.md` from a labeled GitHub backlog and runs nightly-autopilot's pre-flight *before any
feature's `concept-to-code` chain — and therefore before any `manifest-init.sh` call — has happened.
At that exact moment, `docs/manifests/` can be empty or entirely absent.

### Cross-check against ADR-0020 and the existing prose bullets

Before writing the Decision below, every other place in the codebase that describes or tests these
three checks' behavior was searched, not assumed clean:

- `autopilot-build/SKILL.md:34` (prerequisites bullet) and `docs/architecture/ADR-0020-autopilot-build-skill.md:79-81` (D3 #1) both already state the *correct* Check-1 contract in prose — confirmed, no edit needed to either.
- `concept-to-code/SKILL.md:145-146` — a **separate, independent** scope guard for that skill's own `resume` form ("If `project_root` is NOT equal to CWD and is NOT a subdirectory of CWD, abort") is prose-only at this location (no accompanying Bash to have inherited the same bug) and is **already correctly worded** in the same direction this ADR restores for autopilot-build. Confirmed compatible; not in SPEC.md's named scope (only `autopilot-build`, `project-conductor`, `nightly-autopilot` are); left untouched.
- `staging/plugin/skills/autopilot-build/tests/run-tests.sh` (a live-environment self-test against `$HOME/.claude`, not part of the hermetic `docs-ci` suite) asserts only `grep -q 'SCOPE ERROR'` and `grep -q 'hook_verified'` — loose presence checks that survive this fix's wording changes unmodified. Confirmed compatible; not edited.
- `docs/GUIDA-USO-IT.md:262-263` and `:800-803` (the Italian user guide) both describe Check 1 as "`project_root` must match CWD; if not, abort with SCOPE ERROR" — omitting the "or a subdirectory of it" exception entirely. This predates this fix, but leaving it as-is would make the guide describe a *stricter, still-incorrect* contract right after the actual implementation is corrected to properly support the parent-CWD case — a small, disclosed reconciliation is included in this ADR's Decision (§2.1), following the same "fix the whole stale paragraph, not only the literally-named part" precedent ADR-0028 §2.5/§3.5 already established in this roadmap.
- No other file in the repository references check-1's message text, project-conductor's glob, or nightly-autopilot's check 6 (grepped for `SCOPE ERROR`, the literal old glob string, and `hook_verified known` across `docs/*.md` and `staging/`; the only other hits are SPEC.md/its `docs/specs/` copy, which are source documents, not call-sites).

---

## 2. Decision

Fix all three findings in place, in their existing files, with no new skill, no new hook, no manifest
schema change, and no new global infrastructure. One shared hermetic test file
(`staging/plugin/scripts/tests/scope-guards.test.sh`) covers all three, following ADR-0027/0028's
established multi-finding, lettered-section convention.

### 2.1 Finding A — `case`-based, quoted, slash-anchored containment test

Replace the Check-1 body with:

```bash
project_root=$(grep '^project_root:' "<manifest-path>" | sed 's/project_root: *"//' | sed 's/".*//' | sed "s/project_root: *//")
cwd=$(pwd -P)
project_root_n="${project_root%/}"
cwd_n="${cwd%/}"
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

`case "$project_root_n" in "$cwd_n"/*)` is a POSIX `case` glob match with the **variable side quoted**
(so any accidental glob metacharacter inside an actual path is treated literally) and the pattern side
carrying an explicit, literal `/*` — so containment requires a real path-separator boundary, not a
bare string prefix. This is the dominant pattern-matching idiom already used for exactly this class of
"does X fall under Y" question elsewhere in this codebase (`auto-format.sh`, `post-md-tells-hint.sh`,
`hook-probe-verify.sh`, `set-branch-protection.sh`), not a new construct. All three named scenarios
resolve correctly by direct trace: parent CWD → equality check fails, `case` matches (`project_root_n`
starts with `"$cwd_n"/`) → PASS. Child CWD → equality fails, `case` does not match (`project_root_n` is
*shorter* than `cwd_n`, cannot match a pattern requiring `"$cwd_n"/` as a literal prefix) → ABORT.
Sibling (`myproj-backup` vs `myproj`) → equality fails, `case` does not match (`myproj-backup` does not
start with the literal string `myproj/`) → ABORT.

`autopilot-build/SKILL.md:34`, the verification checklist (`:320`, `:329`), and
`docs/architecture/ADR-0020-*.md:79-81` all already state the corrected contract; none of them need
editing.

**Documentation reconciliation (small, disclosed scope nudge — same paragraph, same contract):**
`docs/GUIDA-USO-IT.md:262-263` and `:800-803` both currently omit the "or subdirectory of it" exception. Both are corrected in the same task as Finding A's code fix, since they describe the exact same contract this fix restores and leaving them stale immediately after the fix lands would mislead a reader of the user-facing guide about what the corrected code actually does — the same reasoning ADR-0028 §2.5/§3.5 used for reconciling a whole paragraph rather than only the literally-SPEC-named part of it.

### 2.2 Finding B — anchor the glob to the naming convention, then verify the `topic:` field

Replace the one-liner at all three call sites with the identical block (each site substitutes its own
already-in-scope `<topic-slug>`/`<feature>` placeholder exactly as the existing duplicated one-liners
already do — see §2.4/§3.2 for why this stays duplicated rather than becoming a shared function):

```bash
# Anchor to the manifest naming convention (YYYY-MM-DD-<topic-slug>.manifest.yml) instead of a bare
# substring glob, then verify the winning candidate's own `topic:` field equals the derived slug
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

`????-??-??-"$_slug".manifest.yml` requires exactly ten glob-wildcard characters (`YYYY-MM-DD`) then a
literal, quoted `-$_slug` immediately before the literal `.manifest.yml` suffix — a slug can no longer
match as a mid-string substring of an unrelated, longer slug. The subsequent `topic:`-field check is a
second, independent layer: it defends against the (much rarer) case of a manifest whose filename
happens to satisfy the anchored glob but whose own internal `topic:` value disagrees (hand-edited or
corrupted state) — exactly the two-layer check SPEC.md's finding 3.10 text asks for ("Anchor the
glob... **and** verify the manifest's topic field... before acting on current_step"). Every downstream
read of `current_step` at all three sites is updated to read from `$_manifest` (empty means "no
verified manifest," which each site already has a graceful fallback for: Step 0 skips reconciliation
for that feature, Step 3 falls through to the standard gate, Step 5 falls into its existing branch C).

The `sed 's/topic: *"//' | sed 's/".*//' | sed "s/topic: *//"` three-stage pipeline is the *same*
defensive extraction idiom `autopilot-build`'s Check 1 already uses for `project_root:` (handles both
quoted and unquoted YAML scalar forms), applied to a different field name — chosen for consistency
over inventing a second idiom.

### 2.3 Finding C — concrete bash; zero-manifest branch is a documented non-blocker, not an invented record

Replace the single prose bullet with:

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

This is Alternative (b) of the two the roadmap posed (§3.3 below has the full comparison): rather than
inventing a new persistent record — which SPEC.md's own "Out" scope forbids doing *inside*
`hook-verify-workflow.sh`, and which ADR-0029 (landed one commit earlier in this same roadmap)
deliberately declined to add — check 6 is redefined to (1) validate `hook_verified` on every manifest
that **currently exists**, roadmap-wide, catching hand-edited/corrupted manifests before a nightly run
starts touching any of them, using the exact same `python3 -c "import yaml..."` idiom
`autopilot-build`'s own Check 7 already uses (same string comparisons, `"True"`/`"False"`, not a new
convention); and (2) treat the *zero-manifest* case — Phase P, before any feature has run
`manifest-init.sh` — as a **non-blocking pass**, because the invariant this check exists to protect
("hook_verified is known before the Step-5 dispatch-mode decision") is *already* structurally
guaranteed the moment any manifest is created: `manifest-init.sh` unconditionally writes
`hook_verified: false`, which is the safe Agent-tool fallback path (ADR-0016), never the unsafe one.
There is nothing for a zero-manifest pre-flight check to validate that manifest-init.sh does not
already guarantee by construction.

### 2.4 Test strategy

One new hermetic file, `staging/plugin/scripts/tests/scope-guards.test.sh`, three lettered sections
(A/B/C, one per finding), each pairing static SKILL.md-content anchors with dynamic
extract-substitute-execute assertions against disposable `mktemp -d` fixtures — the same dual-coverage
convention ADR-0027/0028/0029 already established in this exact directory. Wired into
`.github/workflows/docs-ci.yml`'s explicit `shell-tests` list (append `scope-guards`, ninth entry) and
picked up automatically by `.claude/test-cmd`'s wildcard glob (`staging/plugin/scripts/tests/*.test.sh`)
with no edit needed there. `staging/sync-to-claude.sh`'s `PAIRS` list is **not** extended — confirmed by
reading it before writing this ADR that none of its three closest structural siblings
(`pairs-completeness.test.sh`, `concept-to-code-bsd-autopilot-gates.test.sh`,
`concept-to-code-manifest-helpers-guards.test.sh`, all of which validate *staging* content the same way
this new file does) are themselves listed there either; only the "real," deployed-environment hook
suites (`phase1`, `prep`, `hook-verify-workflow`, `db-backup-guardrail`, `pre-flight-pattern-enforce`,
`run-hook-tests`) are synced.

Each finding's three verified/required scenarios get a dynamic assertion (Finding A: parent-passes,
child-aborts, sibling-aborts, plus an exact-match non-regression companion; Finding B: `export` binds
to its own manifest not `export-csv`, `export-csv` still binds correctly, a filename/internal-field
mismatch does not bind; Finding C: zero manifests passes, `hook_verified: false`/`true` both pass, a
corrupted/absent field aborts), plus 2-3 static presence/absence anchors per finding — roughly 18
assertions total across the three sections. See the implementation plan for exact contracts.

---

## 3. Alternatives considered

### 3.1 Finding A — how to express the corrected containment test

- **Alt A1 — keep the `${var##pattern}` parameter-expansion family, only fix direction and
  anchoring.** E.g. `case "$cwd_n" in "$project_root_n"|"$project_root_n"/*) ;; esac` reversed, or a
  hand-rolled `${project_root_n#$cwd_n/}` variant. **Rejected:** the *family* of unquoted,
  glob-parameter-expansion prefix-stripping is exactly the mechanism that produced the original bug's
  fragility (easy to get the direction and the anchor both subtly wrong at once, as the original code
  did). Continuing it risks reproducing a different variant of the same class of defect, and it is not
  the codebase's dominant idiom for this kind of check to begin with.
- **Alt A2 — canonicalize with `realpath`/`readlink -f`, then string-prefix compare.** **Rejected:**
  neither is available in stock BSD/macOS userland without a Homebrew coreutils install; the codebase
  already deliberately avoids this exact trap (`stop-gate.sh`'s own comment: `pwd -P` resolves symlinks
  specifically *because of* the `/var` → `/private/var` portability gap `realpath` would otherwise be
  reached for). Introducing a `realpath` dependency into an unattended pre-flight check that must never
  hang or fail on a stock macOS machine is a worse trade than the one-line `case` fix.
- **Alt A3 — split both paths into `/`-separated segment arrays and compare element by element.**
  **Rejected:** bash 3.2 arrays are usable but this codebase's own established style never reaches for
  them for path-comparison logic (greп across `staging/` found zero precedent), and it is materially
  more code for equivalent correctness once the pattern is properly slash-anchored via `case`. A larger
  diff surface for a security-relevant, first-checked guard is a worse property, not a better one, for
  a reviewer to verify by eye.
- **Chosen: Alt A4 — `case "$project_root_n" in "$cwd_n"/*)`, quoted variable, literal `/*` anchor.**
  Portable (POSIX `case`, no external tool), naturally slash-anchored, matches the codebase's own
  dominant existing idiom for "does X fall under Y" (used ~15+ times already in this exact tree:
  `auto-format.sh`, `post-md-tells-hint.sh`, `hook-probe-verify.sh`, `set-branch-protection.sh`,
  `db-backup-guardrail.sh`), one-line diff.

### 3.2 Finding B — anchor vs verify vs both; shared function vs duplicated inline

- **Alt B1 — anchor the glob to the naming convention only, drop the `topic:`-field check.**
  **Rejected:** still has a residual gap when a manifest's filename and its own internal `topic:` value
  disagree (renamed/hand-edited file); SPEC.md's finding 3.10 text explicitly asks for both layers
  ("Anchor the glob... and verify the manifest's topic field... before acting on current_step"), not
  either one alone.
- **Alt B2 — verify every manifest's internal `topic:` field by scanning the whole directory, drop the
  glob anchor.** **Rejected:** loses the cheap, already-correct "most recent by date-prefix" shortcut
  `ls -t | head -1` gives for free; requires reading every file in `docs/manifests/` on every call
  instead of the cheapest-matching candidate; a bigger behavioral change for no additional correctness
  once combined with anchoring anyway, and slower as a project's manifest history grows over its
  lifetime.
- **Chosen: Alt B3 — anchor first (cheap, narrows to the naming-convention-correct candidate,
  preserves "most recent wins" via `ls -t | head -1`), then verify that single candidate's `topic:`
  field (defense-in-depth against the rarer corruption case).** Combines both alternatives' strengths;
  matches SPEC's literal two-part instruction; smallest diff that closes the actual named collision
  (`export`/`export-csv`) and the corruption case in the same pass.
- **Alt B4 — define the corrected lookup once as a shared Bash function (e.g. in Step 0), call it by
  name from Steps 3 and 5.** **Rejected on an execution-model constraint, not a style preference:**
  each `` ```bash `` fenced block in a `SKILL.md` is executed as an independent Bash-tool invocation by
  the agent following the skill's instructions (this environment's own documented behavior: "Agent
  threads always have their cwd reset between bash calls" — and, more strongly, a function defined in
  one tool call's subprocess does not survive into a later, separate tool call's subprocess at all). A
  function defined at Step 0 would not exist by the time Step 3 or Step 5 runs. The existing file
  already duplicates the (buggy) one-liner identically at all three sites for exactly this reason; this
  fix corrects the content of that existing duplication rather than changing its architecture.

### 3.3 Finding C — the central open question ADR-0029 deliberately left for this issue

- **Alt C1 — add a new, global, CC-version-keyed persistent smoke-test record**, either (a) inside
  `hook-verify-workflow.sh` via a new `--check --persist` mode that writes a verdict file, or (b) a
  brand-new, separate wrapper script that calls `hook-verify-workflow.sh` and persists its verdict to
  e.g. `~/.claude/state/hook-verify/<cc-version>.verdict`. **Rejected**, for four independent reasons,
  any one of which is sufficient on its own:
  1. Option (a) modifies `hook-verify-workflow.sh` internals, which SPEC.md's own "Out" section for
     this issue explicitly forbids ("hook-verify-workflow.sh internals (issue #33)").
  2. ADR-0029 — landed one commit before this ADR, in this same roadmap — deliberately hardened and
     re-affirmed the script's read-only, stateless contract as a first-class, intentional property
     ("a property some future issue could still choose to change, but this one deliberately does
     not"), explicitly framing "some future issue," not this one, as the place to revisit it.
  3. Even option (b) (a new, separate script, technically outside `hook-verify-workflow.sh` itself)
     still requires designing a global record's storage location, on-disk format, and — the genuinely
     hard part — its **invalidation policy** (a CC version bump, multiple concurrent repos on one
     machine, multiple machines, a stale record from a since-uninstalled hook configuration): none of
     that design work exists today, and all of it is a legitimate, separate SPEC/ADR-sized question,
     not a rider on a scope-guard/pre-flight-check bugfix issue.
  4. No caller in the system today invokes `hook-verify-workflow.sh` other than a human running the
     ADR-0016 interactive smoke-test procedure once per environment. A "global record" would sit
     permanently unpopulated until *that* flow is *also* redesigned to write to it — a second,
     independent scope expansion beyond what issue #34 asks for.
- **Chosen: Alt C2 — redefine check 6's zero-manifest branch as a documented, non-blocking pass**,
  reasoning from what `manifest-init.sh` already, unconditionally guarantees (every new manifest starts
  `hook_verified: false`, the safe fallback), and keep a real, roadmap-wide validity check for whatever
  manifests *do* already exist. Needs zero new infrastructure, stays inside SPEC's scope boundary
  exactly as drawn (`hook-verify-workflow.sh` is untouched; no new file, no new global path), and is
  explicitly the reading the roadmap's own dispatch note for this task endorsed ahead of time:
  "`hook_verified=false` only means the SAFE fallback dispatch is used — a lenient check-6 default is
  defensible."
- **Alt C3 — make the zero-manifest case an unconditional abort**, forcing a human to run the
  interactive smoke test before nightly-autopilot can ever complete its very first Phase-P-originated
  run. **Rejected:** this is *stricter* than the safety margin the check actually protects — the worst
  consequence of an unknown `hook_verified` is already just "use the slower, always-safe Agent-tool
  fallback dispatch," never an unsafe outcome — while actively defeating Phase P's own stated purpose
  (ADR-0023: turn a labeled backlog into PR-ready branches "with no evening design work") for every
  repo's first-ever nightly run.

### 3.4 Bundling three independent findings into one ADR, one plan, one test file, one commit

- **Alt D1 — three separate ADRs/plans/commits, one per finding**, mirroring the one-finding-per-issue
  granularity ADR-0026 through ADR-0029 used. **Rejected for this issue specifically:** the roadmap's
  own issue #34 already bundles all three findings under a single GitHub issue and a single SPEC.md
  (confirmed byte-identical against `docs/specs/34-*.md`); splitting the *ADR* granularity finer than
  the *issue* granularity it is answering would be inconsistent with how every other issue in this
  roadmap has been handled (one issue → one ADR), and would triple the number of small, low-risk PRs
  for no additional safety benefit, since all three fixes are independent, non-overlapping file regions
  with zero shared state between them.
- **Chosen: Alt D2 — one ADR, one plan, one shared test file with lettered sections, one commit**,
  matching SPEC.md's own single-issue framing and ADR-0027/0028's already-established precedent for a
  multi-finding issue in this exact roadmap. Each finding's tasks remain independently revertible by
  file/hunk if a reviewer wants to accept two of three; nothing about this choice forecloses that.

---

## 4. Consequences

### Positive

- Check 1 now matches its own already-correct documented contract (`autopilot-build/SKILL.md:34`,
  ADR-0020 D3 #1) for the first time since the skill was written — the exact three-scenario regression
  the roadmap named (parent CWD aborts, child CWD passes, sibling passes) is closed and pinned by tests
  that trace all three by direct execution against disposable fixtures, not by inspection alone.
- The scope guard is the *first* thing `autopilot-build` checks, before any manifest content is
  trusted, and is the primary automated defense for the global CLAUDE.md session-scope invariant in the
  one skill in this system that runs with no human turn to catch a mistake. Fixing an
  inverted-plus-unanchored containment test here closes a real safety gap in an unattended-execution
  path, not a cosmetic one.
- `project-conductor`'s manifest binding becomes correct under the exact adversarial case the SPEC
  names (`export` vs `export-csv`), which today can silently mark a feature `[x]` complete, or
  auto-resume the wrong in-progress chain, off a different feature's manifest — a state-corruption bug
  whose blast radius is `PROJECT.md`, the human-facing source of truth for an entire multi-feature
  roadmap.
- `nightly-autopilot` check 6 goes from "no command, no rule, silently ambiguous for the exact Phase P
  scenario ADR-0023 introduced" to a concrete, testable Bash contract with an explicit, load-bearing
  rationale for its zero-manifest branch — closing a real gap in the newest (Phase P) code path before
  it has ever driven an unattended overnight run.
- All three fixes are corrective, in-place edits to existing files; zero new schema fields, zero new
  hook wiring, zero new skill, zero permission-mode change.
- Reuses, a fifth time across this roadmap, the "disclose an environment/design gap rather than
  silently assert a fact or invent infrastructure to paper over it" idiom (ADR-0026 §2.4/§3.5, ADR-0027
  §2.6/Negative, ADR-0028 §4/Negative, ADR-0029 §4/Negative) for Finding C's zero-manifest branch —
  consistent engineering culture across the whole audit-fix roadmap, not a one-off judgment call.
- Follows the exact "extract-and-execute + static anchor" dual-test-coverage pattern already
  established by ADR-0027/0028/0029, so a reviewer already familiar with this test suite's conventions
  can read the new file with zero ramp-up; the multi-finding, lettered-section structure directly
  mirrors ADR-0027/0028's own precedent for a bundled issue.
- Directly answers, with a verified concrete decision rather than leaving it open a second time, the
  exact question ADR-0029 deliberately deferred one commit earlier ("Gap flagged for issue #34") — the
  roadmap's own disclose-don't-assume discipline compounding correctly across sequential issues.

### Negative

- Finding C's redesign does **not** close the underlying gap ADR-0029 disclosed: no global,
  cross-manifest, cross-run smoke-test record exists anywhere after this ADR either. It only makes the
  *absence* of that record a well-reasoned, disclosed non-blocker for the specific zero-manifest
  pre-flight moment, instead of an unhandled ambiguity with no command behind it. A given repo's first
  nightly run still pays the full "interactive smoke test once, per environment" cost the moment any
  manifest's `hook_verified` needs to flip from its `manifest-init.sh` default of `false` to `true`;
  there is still no "verified once, trusted forever across every project" mechanism, and this ADR
  deliberately does not build one (§3.3 Alt C1).
- Finding B's fix trusts a manifest's own internal `topic:` field as the tie-breaker; if a manifest is
  hand-edited so that **both** its filename and its internal `topic:` field are wrong in the same,
  mutually consistent way, the fix cannot detect that — an internal-consistency check, not an
  external-ground-truth check. Deliberately out of scope: SPEC.md's own edge cases do not name this
  case either, and it requires two independent, coordinated manual edits to trigger (a materially
  different threat than the single-glob-collision bug this fix actually closes).
- Finding A's rewrite changes the exact wording of the `SCOPE ERROR` message (from "is outside this
  session's CWD" to "is not this session's CWD... and is not a subdirectory of it") to correctly
  describe the now-correct contract; any human muscle-memory or external notes quoting the old message
  text verbatim go stale. Grepped for other call-sites before writing this ADR (§1 "Cross-check"); the
  only other file quoting comparable message text is `docs/GUIDA-USO-IT.md`, itself corrected by this
  same ADR's Decision §2.1.
- Three independent findings land in one ADR/plan/commit rather than three (§3.4); a reviewer wanting
  to approve exactly one of the three fixes without the other two cannot do so at the *commit*
  granularity, only at the file/hunk granularity. Mitigated by, but not eliminated by, the fact that the
  upstream GitHub issue (#34) already bundles all three at the same granularity — this ADR mirrors an
  already-made upstream decision rather than introducing a new one.
- The new test file adds roughly 18 assertions and one more entry to `docs-ci.yml`'s explicit
  `shell-tests` list (ninth of nine) and to the directory `.claude/test-cmd`'s wildcard glob already
  covers — a small, bounded, linear increment to CI runtime, consistent with the existing eight-file
  harness's own growth pattern to date.
- Check 1's corrected Bash relies on a `case` pattern-match test whose pass-path final command has an
  ambiguous raw exit status when the containing snippet is run in isolation outside the agent's own
  interpretation model (an `if` guard whose *condition* is false has exit status 1 even though no abort
  fires) — harmless for the real caller (an agent reading printed output, exactly as the *original*,
  buggy code already required, since it has the identical property), but it means a test harness
  wrapping the extracted snippet in `bash -c` plus a raw `$?` check must account for this explicitly
  (the implementation plan's `run_check1` test helper does, entirely inside the test file — the
  production contract itself is not changed to work around a test-harness concern, see the plan's Risk
  register).

### Neutral

- No manifest schema change, no new skill, no new hook, no `settings.json` change, no permission-mode
  change anywhere in this ADR.
- `nightly-autopilot/SKILL.md`'s own check 1 stays prose-only ("same rule as autopilot-build check 1")
  rather than gaining a second, duplicated inline Bash block; SPEC.md explicitly frames it as
  "inherits by reference," so once `autopilot-build`'s check 1 is correct, `nightly-autopilot`'s pointer
  is automatically correct in spirit with no further edit required.
- `concept-to-code/SKILL.md:145-146`'s own, separate scope-guard prose for its `resume` form was
  checked and found already correctly worded in the same direction this ADR restores for
  `autopilot-build` — confirms consistency across the codebase's two independent scope-guard
  descriptions without requiring either to change to match the other.
- The deployed `~/.claude` copies of all three `SKILL.md` files (and `docs/GUIDA-USO-IT.md`, which is
  not part of the plugin/sync tree at all) keep today's defective Check-1/glob/Check-6 behavior until a
  human runs `sync-to-claude.sh --apply` — the same disclosed, established "deployed stays defective
  until sync" convention as ADR-0025 through ADR-0029, repeated here rather than assumed to already be
  understood.
- This ADR neither opens nor forecloses Alt C1's "future global smoke-test record" design; it is
  explicitly left for a future issue to pick up if the need is ever demonstrated, exactly as ADR-0029
  already flagged it.

---

## 5. References

- `SPEC.md` (repo root) / `docs/specs/34-scope-guards-autopilot-cwd-check-conduct.spec.md` — this
  issue's spec (confirmed byte-identical)
- `docs/architecture/ADR-0020-autopilot-build-skill.md` — D3 #1, the original, already-correct Check-1
  design; not amended, its own text needed no correction
- `docs/architecture/ADR-0016-dynamic-workflows-step5.md` — `hook_verified` and the Workflow/Agent-tool
  dispatch-mode gate this ADR's Finding C leaves intact
- `docs/architecture/ADR-0029-33-hook-verify-session-filter.md` — §1 "Gap flagged for issue #34," the
  disclosed, deliberately-unresolved question this ADR answers
- `docs/architecture/ADR-0022-nightly-autopilot-goal.md`, `docs/architecture/ADR-0023-nightly-auto-design.md` — Phase P, the zero-manifest pre-flight moment Finding C's branch is written for
- `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md`, `docs/architecture/ADR-0025-29-refresh-stale-staging-copies.md` — confirms `staging/` as this roadmap's working source of truth
- `docs/architecture/ADR-0027-31-c2c-bsd-slug-autopilot-gates.md`, `docs/architecture/ADR-0028-32-manifest-helpers-guards.md` — structural and test-harness precedent this ADR reuses directly
- `staging/plugin/skills/autopilot-build/SKILL.md`, `staging/plugin/skills/project-conductor/SKILL.md`, `staging/plugin/skills/nightly-autopilot/SKILL.md` — the files this ADR patches
- `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh` — manifest schema source of truth (`topic:`, `hook_verified:` default)
- `staging/plugin/skills/autopilot-build/tests/run-tests.sh`, `staging/plugin/skills/concept-to-code/SKILL.md:145-146` — confirmed compatible, not edited (§1 "Cross-check")
- `docs/GUIDA-USO-IT.md` — two prose sites reconciled (§2.1)
- `staging/sync-to-claude.sh`, `staging/plugin/scripts/tests/pairs-completeness.test.sh` — confirmed no new mapping entry needed for the new test file (§2.4)
- Implementation plan: `docs/superpowers/plans/2026-07-11-34-scope-guards.md`
