# ADR-0027 — concept-to-code: BSD-safe slug stamp and autopilot gate fixes

**Status:** Accepted
**Date:** 2026-07-11
**Author:** istefox
**Supersedes:** none
**Superseded by:** none
**Related:**
- SPEC: `docs/specs/31-concept-to-code-bsd-safe-slug-stamp-and.spec.md` (= `SPEC.md` at repo root, GitHub issue #31,
  confirmed byte-identical by diff before writing this ADR)
- ADR-0014 (`architect-proposes-test-cmd`) — the TOFU SHA-pinned trust model this ADR's Gate 2b fix must not
  weaken: "trust is born only from explicit human SHA-pinned consent"
- ADR-0017 (`chain-type-routing-gate0`) — original design of the Express/Hybrid/Standard `chain_path` routing
  and the 44-pair state machine this ADR's Gate-order fix reconciles against, without revisiting the routing
  decision itself
- ADR-0020 (`autopilot-build-skill`) — D2 autonomy boundary ("local and reversible only"; push/PR/merge never
  unattended) and D4 ("TOFU trust must pre-exist — never auto-granted in autopilot") this ADR's Gate 2b and
  Gate 0d/Step-7 fixes enforce inside `concept-to-code` itself, not just in the standalone `autopilot-build` skill
- ADR-0022 (`nightly-autopilot-goal`) — D5/D6: confirms (re-verified by grep before writing this ADR — zero
  "nightly" references in `concept-to-code/SKILL.md`) that the nightly publish path runs entirely through
  `project-conductor`'s `publish-feature.sh`, never through `concept-to-code`'s own Step 7, which is why this
  ADR's Step-7 push guard needs no nightly-aware exception
- ADR-0024 (`vendor-deployed-only-skills-and-hooks`) — established the `pairs-completeness.test.sh` hermetic
  self-test pattern and the local-`test-cmd`-glob-vs-CI-explicit-list split this ADR's new test file reuses
- ADR-0025 (`refresh-stale-staging-copies`) — confirms `staging/` is the working source of truth this ADR edits;
  deployed `~/.claude` is out of scope by the same established roadmap convention
- ADR-0026 (`clean-public-repo-private-history`) — the immediately preceding issue (#30) in this same roadmap;
  structural precedent this ADR follows closely (Context → per-finding Decision → Alternatives →
  Positive/Negative/Neutral Consequences; one new hermetic test file in `staging/plugin/scripts/tests/`, CI-wired
  by explicit-list append)
- `staging/plugin/skills/concept-to-code/SKILL.md`, `scripts/manifest-validate.sh`,
  `scripts/manifest-transition.sh` — the files this ADR patches
- Implementation plan: `docs/superpowers/plans/2026-07-11-31-c2c-bsd-slug-autopilot-gates.md`

---

## 1. Context

`concept-to-code` is the orchestrator skill implementing the concept→code workflow (blueprint §11) as a YAML
manifest-driven state machine with three routable sub-graphs (Standard/Express/Hybrid, ADR-0017) and an
in-chain autopilot mode (ADR-0020's Gate-4 entry point). It was vendored byte-identical to the deployed copy by
ADR-0024. SPEC.md (issue #31) reports five findings from an audit of the vendored copy, one P1 and four P2:

**Finding 1 (P1, slug stamp, `SKILL.md:272-273`).** Step 1's idempotent "stamp slug marker" command is:
```bash
grep -q '\*\*Topic slug:\*\*' "<project-root>/SPEC.md" || \
  sed -i.bak '/^# /a\\n**Topic slug:** <topic-slug>' "<project-root>/SPEC.md"
```
The `a\` (append) command's single-line form — backslash immediately followed by text on the same line, with
`\n` processed as an embedded-newline escape inside that text — is a GNU sed extension. BSD/macOS sed requires
the appended text to start on its own literal line after the backslash and does not process `\n` as an escape
inside it. **Empirically verified in this session** (this environment's `Platform: darwin`, real BSD sed, not a
GNU shadow — confirmed via `sed --version` returning `illegal option --`, BSD's signature non-response):
```
$ sed -i.bak '/^# /a\\n**Topic slug:** some-slug' OLD.md
sed: 1: "/^# /a\\n**Topic slug:* ...": extra characters after \ at the end of a command
$ echo $?
1
```
The file is left unmodified and the marker is never written. Downstream, `gate0-detect.sh`'s `spec_topic_match`
stays `unknown` on every greenfield macOS run, which prepends a warning to every Gate 0 display
(`SKILL.md:1083`) — a P1 because it fires on the single most common path (macOS, greenfield, Standard/Hybrid),
not an edge case.

**Finding 2 (P2, Gate 2b, `SKILL.md:1501`).** The autopilot default for the test-cmd TOFU gate is: "Approve" →
run `approve-test-cmd.sh` and proceed, unconditionally. This directly contradicts ADR-0014's invariant ("trust
is born only from explicit human SHA-pinned consent") and ADR-0020's D4 ("TOFU trust must pre-exist — never
auto-granted in autopilot... It never calls `approve-test-cmd.sh` to create trust"). D4 was written for the
standalone `autopilot-build` skill's pre-flight, but the invariant it encodes is general — `concept-to-code`'s
own in-chain autopilot (the Gate-4 entry point, ADR-0020's "in-chain autopilot entry point" section) currently
violates it directly at the one gate that exists specifically to gate unattended trust-granting.

**Finding 3 (P2, Gate 0d autopilot + Step 7 push, `SKILL.md:1187` and `SKILL.md:819-846`).** Gate 0d's autopilot
default sets `initial_commit_push: "push"` whenever a git remote is already configured (`_git_remote` non-empty)
— i.e., autopilot pushes unattended on any project that already has `origin` set, which is the common case for
an existing repo. Step 7's push block itself has no autopilot guard at all: `if manifest.initial_commit_push =
"push"` fires regardless of `manifest.autopilot`. Both violate ADR-0020 D2 ("`git push`... never unattended")
and the Gate-4 entry point's own documented contract two paragraphs above it in the same file ("continues into
Steps 5-7 in the same session: implement, local commit via `commit --autopilot`, **no push, no PR**").
Re-verified before writing this ADR: `grep -n -i "nightly" concept-to-code/SKILL.md` returns zero matches, and
ADR-0022 D5/D6 confirm the nightly publish path runs `publish-feature.sh` directly from
`project-conductor`'s roadmap loop, strictly after `concept-to-code` autopilot hands back a local commit — never
through this Step-7 block. There is no legitimate case, nightly or otherwise, where `concept-to-code`'s own
Step 7 should push under `autopilot=true`.

**Finding 4 (P2, Gate order contradiction, `SKILL.md` §2 Form A lines 100-127 vs §5 Gate 0/0d lines 1075-1329).**
Two independently-written descriptions of the same routing decision have drifted apart:
- §2 Form A (the invocation contract) and §5 Gate 0's own click handlers both transition `step_0_init` **directly**
  to `step_e1_plan` (Express) or `step_h1_interview` (Hybrid) the instant the user picks a path, and route only
  `[s]`/`[auto]` (Standard) through Gate 0b. §2's Standard branch then transitions `step_0_init → step_1_interview`
  directly (line 126) — skipping Gate 0c and Gate 0d entirely.
- §5's Gate 0d block (lines 1183-1329), immediately below, is a **fully-specified, unconditional** ("Always fires
  ... every new chain needs scaffolding decisions recorded") gate with its own git-auto-detect, license, Xcode,
  and commit survey, whose transition table explicitly branches on **all three** `chain_path` values
  (`gate_0d_scaffolding → step_1_interview | step_e1_plan | step_h1_interview`, lines 1326-1329) — logic that
  presupposes every path passes through it.

Read together: Gate 0c and Gate 0d are fully documented but **structurally unreachable** by the procedure §2/§5
Gate 0 actually describe, for any of the three paths. `manifest-transition.sh`'s legal-pair table already
contains every pair the corrected flow needs (`step_0_init,gate_0d_scaffolding` and all three
`gate_0d_scaffolding,{step_1_interview,step_e1_plan,step_h1_interview}` pairs, confirmed present by direct
reading before writing this ADR) — the defect is entirely in which pairs the documented procedure *uses*, not a
missing pair in the script.

**Finding 5 (P2, invariant 7, `manifest-validate.sh:108-119` and `SKILL.md:943-947`).** Invariant 7 requires
`artifacts.spec`/`adr`/`plan` to all be non-null quoted absolute paths whenever `status: completed`,
unconditionally. Express produces none of the three (no sub-agents, no SPEC/ARCH/ADR, `EnterPlanMode` replaces
architecture — confirmed by re-reading §4 Express's own header: "No sub-agents. No fresh session. No SPEC, ARCH,
or ADR."). Hybrid produces `spec` only (`artifacts.spec` is set at Step H1, confirmed at `SKILL.md:977`) but
never `adr`/`plan` ("Produces SPEC.md only — no ARCH, no ADR. Plan mode replaces the architect step," §4 Hybrid
header). Every real Express or Hybrid completion therefore fails invariant 7 today. Separately, Gate E3's
`Commit later` and `Abort` options share one transition call, `manifest-transition.sh <m> completed completed`
(`SKILL.md:943-947`) — `Abort`'s own option description ("Stop here. Changes remain in the working tree.") is an
abandonment, not a completion, and recording it as `completed` both misrepresents the chain's outcome and, once
invariant 7 is corrected to accept null Express artifacts, would let an aborted run silently validate as a
legitimate completed one.

**Baseline, re-verified before planning (2026-07-11):** `for t in staging/plugin/scripts/tests/*.test.sh; do
bash "$t" || exit 1; done` (the repo's own `.claude/test-cmd`, already TOFU-trusted from features #28-#30 in this
same roadmap) is green, 6/6. None of the six existing test files (`phase1`, `prep`, `hook-probe`,
`hook-verify-workflow`, `pairs-completeness`, `clean-public-repo-history-safety`) mention `concept-to-code`
anywhere (`grep -ln "concept-to-code"` across all six returns nothing) — confirmed this issue's edits carry zero
collision risk with the existing harness. `staging/plugin/skills/concept-to-code/tests/{run-tests.sh,
smoke-e2e.sh,agent-notes-roundtrip.sh}` all hardcode `SKILL_DIR="$HOME/.claude/skills/concept-to-code"` (the
**deployed** copy) — confirmed by reading all three — so, per this roadmap's own established and unchanged
convention (ADR-0026 §1/§4-Negative: "deployed stays defective until sync, by design"), they exercise neither
this issue's bugs nor this issue's fixes, and are correctly left untouched.

## 2. Decision

Fix exactly the five findings SPEC names, add one new hermetic test file wired into both the local `test-cmd`
glob and CI's explicit list (ADR-0024/ADR-0026 precedent), touch no other behavior, and add no new PAIRS entries
(the two patched files already have them; the new test file, like its two predecessors, gets none). The
`manifest-transition.sh` legal-pair table is **not modified** — every pair Finding 4's fix needs already exists.

### 2.1 Finding 1 — replace the sed `a\` one-liner with a portable `awk` + temp-file + `mv` form

```bash
grep -q '\*\*Topic slug:\*\*' "<project-root>/SPEC.md" || {
  cp "<project-root>/SPEC.md" "<project-root>/SPEC.md.bak" &&
  awk -v slug="<topic-slug>" '
    { print }
    !done && /^# / { print ""; print "**Topic slug:** " slug; done=1 }
  ' "<project-root>/SPEC.md" > "<project-root>/SPEC.md.tmp" &&
  mv "<project-root>/SPEC.md.tmp" "<project-root>/SPEC.md"
}
```
`awk`'s basic pattern-match/`print` semantics (used here: a `-v`-assigned variable, one flag variable, two
pattern-action rules) are POSIX and behave identically across BSD awk (macOS, confirmed this session — "awk
version 20200816," the bundled one-true-awk, not a Homebrew GNU shadow), `mawk` (Ubuntu's default), and `gawk`.
No OS branch is needed because no GNU-only feature is used at all — this is portable by construction, not by
having been tested twice. **Empirically verified in this session, same fixture, real BSD/macOS awk:** exit 0 on
first run, file becomes `# Some Feature Title\n\n**Topic slug:** some-slug\n\nBody text.\n` (H1, blank line,
marker, blank line, body — the intended shape); a second run is a byte-for-byte no-op (the pre-existing
`grep -q ... ||` idempotency guard is unchanged and still correct). The `cp ... .bak` step preserves the
original's backup safety property (global CLAUDE.md: "Back up before modifying critical files") that the old
`sed -i.bak` incidentally provided; `*.bak`/`*.bak-*` are already `.gitignore`d (confirmed, lines 17-18).

The GNU-sed side is exercised on every future PR by this ADR's new CI test (§2.6); the BSD side was proven by
hand in this session, on the actual target platform, not merely assumed — see the Consequences/Neutral note on
why CI alone cannot close this gap and what closes it instead.

### 2.2 Finding 2 — Gate 2b autopilot checks pre-existing trust; never grants it

Replace the unconditional `approve-test-cmd.sh` call with a **read-only** probe of the trust store, reusing the
exact mechanism the Form-B resume-path TOFU guard already uses (`SKILL.md:152-158`, unmodified by this ADR):
`TRUSTED` (the SHA-pinned `(hash, normalized-root)` pair already exists, i.e. a prior interactive session
approved this exact command) → proceed silently to `step_3_project_memory`; **reading** existing trust is not
**granting** it, so this is not a TOFU violation. `NOT_TRUSTED` → do exactly what the interactive "Skip" branch
already does two lines above (`manifest.test_cmd_placeholder = true`, transition to `step_3_project_memory`) and
emit a distinct, greppable status line recording why autopilot did not proceed with a trusted command — the same
"record for later inspection via the transcript" idiom every other autopilot default in this file already uses
(none of the ~15 existing autopilot-default brackets write a new manifest field for their own reasoning either;
see §3.1 for why this ADR does not introduce one just for this gate). Neither branch ever invokes
`approve-test-cmd.sh`.

`test_cmd_placeholder` is a pre-existing schema field (`manifest-init.sh:80`); no schema addition.

### 2.3 Finding 3 — Gate 0d autopilot always "commit"; Step 7 push independently guarded on `autopilot != true`

**Gate 0d (`SKILL.md:1187`):** drop the `_git_remote`-conditional branch entirely — autopilot always sets
`initial_commit_push: "commit"`, regardless of whether a remote is already configured.

**Step 7 (`SKILL.md:819-821`):** add `AND manifest.autopilot != true` to the block's own trigger condition, with
an explicit guard sentence at the top of the block stating the block is skipped unconditionally under autopilot,
and why a nightly-opt-in exception is deliberately *not* threaded through here (Finding 3's Context above; ADR-
0022 D5/D6). This is intentionally a **second, independent** layer on top of the Gate 0d fix, not a replacement
for it — matching this file's own established belt-and-suspenders idiom elsewhere (ADR-0020 D5/D6: hooks stay
active, autopilot only suppresses the human-prompt layer). A future manifest that somehow reaches Step 7 with
`initial_commit_push: "push"` and `autopilot: true` set (a hand-edited or legacy manifest, not one produced by
the corrected Gate 0d) is still caught.

### 2.4 Finding 4 — one canonical Gate order: `0` (choice only) → `0b` → `0c` → `0d` (single routing transition)

Gate 0 (§2 Form A step 7, both the fast-path prefix branch and the normal-path `[e]`/`[h]`/`[s]`/`[auto]` click
handlers, and the mirrored §5 Gate 0 block) is reduced to **setting `chain_path` only** — no `[e]`/`[h]` branch
performs a direct `manifest-transition.sh` call anymore. Every branch, for every `chain_path` value, proceeds
uniformly into step 8 (Gate 0b). §2 Form A gains two new numbered steps, 8b (Gate 0c) and 8c (Gate 0d), each a
short pointer to §5's already-correct, already-fully-specified gate definitions (no duplication of their content
into §2 — the duplication between two descriptions of the same gate is exactly how the two drifted apart in the
first place, so the fix collapses to one source of truth with a pointer, not two sources kept in sync by hand).
§2's old step 9 (the direct `step_0_init → step_1_interview` transition) is removed outright: Gate 0d's existing
transition block (`SKILL.md:1326-1329`, unmodified — it was already correct, just unreachable) becomes the
**single** documented `current_step` transition out of `step_0_init`, for all three paths. `manifest-transition.sh`
is not modified: `step_0_init,gate_0d_scaffolding` and all three `gate_0d_scaffolding,{step_1_interview,
step_e1_plan,step_h1_interview}` pairs already exist (confirmed by direct reading). The three now-superseded
direct pairs (`step_0_init,step_1_interview` / `,step_e1_plan` / `,step_h1_interview`) are **left in the script,
unremoved** — they become legal-but-unused-by-the-documented-procedure, which is harmless, and removing them
would be an uninstructed count change in a file issue #32 is concurrently editing (§2.6 and Risk register).

One consequence, stated explicitly rather than left implicit: Gate 0b (anonymize) and Gate 0c (humanize), which
previously fired for Standard only, now fire for Express and Hybrid too, and Gate 0d's scaffolding survey
(license/Xcode/git/commit) — previously reachable by **no** path — now fires, unconditionally, for all three.
This is not a new behavior invented by this ADR; it is Gate 0d's own pre-existing, already-written transition
table (branching on all three `chain_path` values) finally being exercised by a procedure that reaches it. See
§3.2 for the alternative (Standard-only) considered and rejected.

One minor, directly-downstream wording fix bundled into this same task: §4 Step E1's opening line, "Immediately
after Gate 0 selects express:" (`SKILL.md:887`), is corrected to "Immediately after Gate 0d routes to
`step_e1_plan`:" — the state is unchanged, only the description of how the chain arrived there. §4 Step H1 has
no equivalent phrase (checked; none present) and needs no corresponding edit.

### 2.5 Finding 5 — invariant 7 conditional on `chain_path`; Gate E3 `Abort` transitions to `aborted`, not `completed`

**`manifest-validate.sh`,** invariant 7: compute `chain_path_val` once (a fresh, local computation placed
immediately before invariant 7 — deliberately **not** shared with invariant 9's own pre-existing identical
computation four invariants later, to avoid touching invariant 9's block at all; see §3.3), then branch:
- `express` → invariant 7 does not apply; no artifact file is ever produced on this path.
- `hybrid` → require `artifacts.spec` only (still a quoted absolute path); `adr`/`plan` are not checked.
- anything else (`standard`, `null`, or the field absent entirely — legacy pre-1.3 manifests) → the original
  unconditional three-way check, byte-identical wording, preserving today's strict behavior exactly.

**`SKILL.md` Gate E3 (`:943-947`):** split the shared `Commit later` / `Abort` block into two, each with its own
`manifest-transition.sh` call — `Commit later` keeps `<manifest-path> completed completed` (implementation is
genuinely done, commit is merely deferred — a legitimate completion); `Abort` becomes
`<manifest-path> aborted aborted`, matching the option's own stated description and the general `status` enum
(`in_progress|failed|completed|aborted`, invariant 6, unchanged). No `manifest-transition.sh` change needed:
"any state → `aborted`" is already unconditionally legal (`manifest-transition.sh:47`, confirmed by reading).
Hybrid's own Gate H3 `Abort` line (`SKILL.md:1050`, "`Abort` → abort.") is deliberately **not** touched — it is
vague but not provably wrong the way Express's is (it does not visibly route to `completed`), SPEC names only
line 945 (Express), and #32's roadmap-coordination note governs this same file's other count-adjacent edits; see
§3.4.

### 2.6 Test strategy and CI wiring

One new file, `staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh`, hermetic (own
`SCRIPTS`/`STAGING` path derivation, zero `$HOME` dependency — mirrors `pairs-completeness.test.sh` and
`clean-public-repo-history-safety.test.sh` exactly), 17 assertions across four lettered sections mapped 1:1 to
the findings above:

- **Section A (Finding 1, 3 tests).** A1/A2 are static anchors against the SKILL.md text (old GNU `a\` pattern
  absent; new `awk -v slug=` pattern present) — genuine RED-now/GREEN-after on any runner, including CI's
  `ubuntu-latest`. A3 is a live extract-and-execute test (grab the fenced bash block by its stable heading
  anchor, substitute the two placeholders, run against a fixture, assert exit 0 + correct insertion +
  idempotency on a second run) — disclosed honestly as **not** a RED-before/GREEN-after pair on `ubuntu-latest`
  specifically (GNU sed's `a\` one-liner extension, unlike BSD's, is documented to accept and correctly process
  this exact syntax, so the old command likely also "works" on GNU sed — the bug is platform-specific and
  `ubuntu-latest` is not the affected platform); it is included as a permanent forward-correctness and
  idempotency regression guard, with the BSD-specific claim resting on this session's direct empirical test
  (§2.1), not on CI. This is the same asymmetry ADR-0026 §2.4/§3.5 already established for a different
  platform-gated finding, applied here for the same underlying reason (the bug's environment precondition is not
  satisfiable in this repo's CI).
- **Section B (Findings 2+3, 4 tests, static anchors).** B1/B2 target Gate 2b's autopilot-default bracket
  specifically (old unconditional `approve-test-cmd.sh` invocation phrase absent; new TRUSTED/NOT_TRUSTED-check
  phrase present). B3 targets Gate 0d's autopilot bracket specifically, using a compound anchor
  (`` `_git_remote` non-empty → `initial_commit_push: "push"` ``) chosen because the bare string
  `initial_commit_push: "push"` alone also legitimately appears in the **interactive** Q4 "Commit and push to
  remote" option (`SKILL.md:1271-1272`, unmodified, correctly still an option for a human) — a naive whole-file
  grep would false-negative forever regardless of whether the autopilot bug is fixed; the compound anchor avoids
  this. B4 targets the Step-7 trigger line for the new `autopilot != true` clause.
- **Section C (Finding 5, 6 tests).** C1 (express, `completed`, null everything → validate PASS — the RED case),
  C2 (standard/legacy, `completed`, null artifacts → validate FAIL, unchanged — non-regression companion,
  already passing before and after), C3 (hybrid, `completed`, `spec` set + `adr`/`plan` null → validate PASS),
  C4 (hybrid, `completed`, `spec` also null → validate FAIL — proves the hybrid branch is a narrower carve-out
  than express's, not a second blanket skip), C5 (static: the old shared `` `Commit later` / `Abort`: `` label
  line is gone from SKILL.md), C6 (dynamic: a fresh manifest, `manifest-transition.sh <m> aborted aborted`
  succeeds, and the resulting `status: "aborted"` manifest passes `manifest-validate.sh`).
- **Section D (Finding 4, 4 tests).** D1/D2/D3 (dynamic: for each of `chain_path` = standard/express/hybrid, the
  two-hop `step_0_init → gate_0d_scaffolding → {step_1_interview|step_e1_plan|step_h1_interview}` sequence is
  legal end-to-end against the **unmodified** `manifest-transition.sh` — the mechanical proof that Finding 4's
  fix needed zero script changes). D4 (static: the old fast-path bypass phrase,
  `` `express` → transition `step_0_init → step_e1_plan` ``, is gone from §2 Form A).

**CI wiring**, mirroring ADR-0024 §2.4 / ADR-0026 §2.4 exactly: `concept-to-code-bsd-autopilot-gates` appended to
`.github/workflows/docs-ci.yml`'s explicit `for t in phase1 prep hook-probe hook-verify-workflow
pairs-completeness clean-public-repo-history-safety` list. No `.claude/test-cmd` edit needed — its existing
single line, `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` (confirmed
unchanged, re-read before writing this ADR), already globs the new file automatically. Like
`pairs-completeness.test.sh` and `clean-public-repo-history-safety.test.sh` before it, the new file gets **no**
`sync-to-claude.sh` PAIRS entry — its assertions target `staging/` paths directly and are meaningless outside a
repo checkout.

**Explicitly not covered by an automated test:** SPEC's success criterion "No file under `~/.claude` modified."
Testing "a future coder's diff stays within `staging/`" is a process/review property, not a hermetic unit-testable
product behavior — it is enforced by the Pre-flight "writes are confined to" list and a final `git status` check
in the plan's last task, the same treatment ADR-0026's plan gave the identical constraint.

## 3. Alternatives considered

### 3.1 Finding 2's "record the halt reason"

**Chosen:** the emitted transcript status line plus the existing `test_cmd_placeholder` boolean field (§2.2) —
no new manifest field.

- **Alternative — add a new free-text manifest field** (e.g. `test_cmd_autopilot_halt_reason`) via
  `manifest-set-flag.sh`. Rejected on inspection of the actual script contracts: `manifest-set-flag.sh` only
  *sets* a top-level key that already exists (`grep -q "^${KEY}: "` gates it) and only accepts the literal values
  `true`/`false` — it cannot create a new key or hold free text. Introducing one would mean a `manifest-init.sh`
  default-field addition plus (arguably) a validator update — a schema change. SPEC's explicit "Out" scope names
  "Manifest helper defects beyond invariant 7 (issue #32)," and the roadmap coordination note assigns this exact
  file's other count/field concerns to #32. Reusing the pre-existing `test_cmd_placeholder` boolean, already
  written for precisely this "unapproved, provisional test-cmd" state, is both sufficient and zero-schema-risk.
- **Alternative — record the reason via `manifest-set-gate.sh` under a "2b" gate entry.** Rejected: the script
  requires the target gate number to already exist in `hitl_gates` (`grep -q "^  - gate: ${GATE}$"`, else exit
  3), and `manifest-init.sh` only pre-registers gates `1`, `2`, `3`, `5` (confirmed by reading) — "2b" is not a
  registered slot, so this call would fail outright, not degrade gracefully.

### 3.2 Finding 4's scope — which paths pass through Gate 0b/0c/0d

**Chosen:** all three `chain_path` values (Standard, Express, Hybrid) pass through Gate 0b → 0c → 0d uniformly
(§2.4).

- **Alternative — Standard-only, leave Express/Hybrid's existing direct `step_0_init → step_e1_plan` /
  `→ step_h1_interview` shortcuts as-is, and treat Gate 0d's express/hybrid transition branches (lines 1327-1328)
  as dead code to be deleted.** Rejected for three independent reasons. First, it contradicts Gate 0d's own
  unconditional trigger language ("Always fires... **every new chain** needs scaffolding decisions recorded,"
  `SKILL.md:1185`) at face value — treating that sentence as wrong rather than as the thing to make reachable is
  a bigger, unstated reinterpretation than making the routing match it. Second, it would require *removing* two
  pairs' worth of documented intent (and, if taken to its logical conclusion, arguably the
  `gate_0d_scaffolding,step_e1_plan`/`,step_h1_interview` pairs from `manifest-transition.sh` too, since nothing
  would use them) — an uninstructed count change in the exact file issue #32 is concurrently editing, which the
  roadmap coordination note explicitly asks this issue to avoid ("if you must touch counts, leave them exactly
  as the script encodes"). Third, and most simply: it is a materially larger diff (deleting and rewriting settled
  content) than making three-plus-one already-correct sentences reachable via a routing fix — SPEC's own framing
  ("align... Form A never mentions 0c/0d") reads as "Form A is the incomplete side," not "Gate 0d's transition
  table is the wrong side."
- **Alternative — Standard + Hybrid only (Express stays direct), on the theory that Express's "no sub-agents, no
  fresh session" philosophy implies minimal ceremony.** Rejected: Gate 0d's own transition table explicitly names
  `chain_path = express → gate_0d_scaffolding → step_e1_plan` as one of exactly three branches — there is no
  textual basis in the existing, unmodified Gate 0d definition for treating Express as an exception, and "minimal
  ceremony" is not actually in tension with a one-time scaffolding survey (license/git/commit) that has nothing
  to do with how many files or sub-agents the implementation phase uses.

### 3.3 Where to compute `chain_path_val` for invariant 7

**Chosen:** a fresh, local computation immediately before invariant 7; invariant 9's pre-existing identical
computation (four invariants later) is left completely untouched.

- **Alternative — compute `chain_path_val` once near the top of the script (e.g. alongside `status_val`) and
  reuse it at both invariant 7 and invariant 9, deleting the now-redundant second computation.** Rejected
  despite being the more conventionally "clean" refactor: it requires editing invariant 9's existing line, and
  SPEC's own coordination constraint for this file is explicit — "#32 owns... coordinate... if you must touch
  counts, leave them exactly as the script encodes" (referring to this same script's other invariants, which #32
  is concurrently patching under issue #32's separate "Manifest helpers: count guards, exit codes, YAML escaping"
  scope). A duplicate three-line `grep`/`sed` pipeline computed twice is a negligible runtime cost and zero
  functional risk; touching a second invariant's existing line to save it is not worth the collision surface
  with a concurrently-edited file.

### 3.4 Hybrid Gate H3's `Abort` line

**Chosen:** leave `SKILL.md:1050` (`` `Abort` → abort. ``) exactly as-is; fix only Express's Gate E3 (§2.5).

- **Alternative — tighten Hybrid's line to the same explicit `<manifest-path> aborted aborted` form, for
  consistency with the Express fix.** Rejected. SPEC's finding 5 names line 945 specifically (Express) and does
  not name Hybrid's Gate H3 at all; the two lines are not equivalently defective — Express's provably routes both
  "Commit later" and "Abort" to the identical `completed completed` call (visible, verifiable in the current
  text), while Hybrid's is merely under-specified (it says "abort" without showing the literal command, which
  could reasonably be read as "invoke Form C" or an equivalent call already covered by the general "any state →
  `aborted` is legal" script invariant) — not a confirmed bug the way Express's is. This same roadmap's own prior
  ADRs (ADR-0024 §3.2/§3.4, ADR-0025 §3.1/§3.2/§3.4, ADR-0026 §3.4, all re-read before writing this section)
  independently and repeatedly reject "expand a named scope for consistency" as a recurring failure mode; this
  ADR follows that established discipline rather than re-litigating it. Recorded as a candidate follow-up, not
  silently fixed.

### 3.5 SPEC's success criterion 4 ("transition-pair count... matches the script exactly") vs. the roadmap
coordination note

**Chosen:** interpret Finding 4's fix as "Form A's routing only invokes transitions that already exist as legal
pairs" (verified mechanically by §2.6 Section D) — and explicitly do **not** attempt to correct the "44 total —
26 standard + 6 express + 12 hybrid" summary line (`SKILL.md:213`), which this ADR independently confirms is
already numerically wrong today regardless of this issue's changes (direct count during research: 28 standard +
6 express + 14 hybrid = 48 actual pairs in the unmodified script, not 44/26/12 — a pre-existing drift, not one
this ADR introduces or fixes).

- **Alternative — also correct the "44 total" line's arithmetic to match the script, satisfying SPEC's criterion
  literally.** Rejected. The task's own roadmap-coordination note is explicit and more specific than SPEC's
  general criterion where the two would otherwise collide: "#31 owns the Gate-0c/0d ORDER and reachability, #32
  owns the pair-count text sync... if you must touch counts, leave them exactly as the script encodes." Since
  this ADR's Finding 4 fix requires zero changes to `manifest-transition.sh` (§2.4 — every needed pair already
  exists), there is nothing forcing a count edit here, and making one unprompted would risk a direct textual
  collision with issue #32, which is concurrently assigned exactly this reconciliation. Deferred, explicitly, not
  silently dropped.

## 4. Consequences

### Positive

- Closes a live P1 defect affecting the single most common chain invocation shape (macOS, greenfield) — the
  slug-stamp marker is now written correctly, `spec_topic_match` resolves instead of staying permanently
  `unknown`, and the Gate 0 warning it currently triggers on every affected run disappears. Verified against real
  BSD sed/awk in this session, not assumed.
- Closes two genuine unattended-safety violations (Gate 2b TOFU auto-grant, Gate 0d/Step-7 unattended push) that
  directly contradicted this repository's own already-accepted invariants (ADR-0014, ADR-0020 D2/D4) — the fix
  brings `concept-to-code`'s in-chain autopilot mode into actual compliance with a safety boundary the roadmap
  had already decided, not a new boundary being introduced now.
- Gate 0c (humanize) and Gate 0d (scaffolding: license, Xcode, git, commit) become reachable for the first time
  on any path — previously fully-specified, fully-written functionality that no documented procedure ever
  invoked. Every new chain, regardless of path, now actually asks the scaffolding questions its own manifest
  schema (`license`, `xcode_project`, `git_init`, `initial_commit_push`, etc., all pre-existing fields) was
  already designed to record.
- Express and Hybrid chains can now reach `status: completed` without failing manifest validation on artifacts
  they were never designed to produce — closing a defect that, before this fix, made *every* real Express/Hybrid
  completion since ADR-0017 introduced those paths fail invariant 7 (not an edge case: the ordinary happy path).
- Zero `manifest-transition.sh` pair changes and zero PAIRS changes were needed for any of the five findings,
  confirmed rather than assumed by direct reading before planning — the smallest-blast-radius outcome available,
  and the one least likely to collide with issue #32's concurrent, same-file work.
- The new 17-assertion harness gives `concept-to-code`'s Gate-order and autopilot-safety logic its first
  behavioral test coverage of any kind in `staging/` — previously zero (the only existing coverage,
  `tests/run-tests.sh`/`smoke-e2e.sh`, targets the deployed copy exclusively).

### Negative

- Section A's Finding-1 dynamic assertion (A3) provides real forward-correctness and idempotency coverage but
  cannot itself prove BSD-sed correctness on `ubuntu-latest` CI — that half of the portability claim rests on
  this session's one-time manual verification plus the "no GNU-only feature used" structural argument, not on a
  repeatable automated check. Residual risk, disclosed rather than hidden: a future edit to this same command
  block that reintroduces a GNU-only construct would not be caught by CI alone. Mitigated by Section A1/A2's
  static anchors, which *would* catch a reintroduction of the specific old pattern, though not every possible new
  GNU-only pattern.
- Gate 0b/0c/0d now firing unconditionally for Express and Hybrid (previously: never) is a genuine behavior
  change for those two paths, not merely a bug fix in the narrow sense — a chain run choosing Express for a
  quick prototype now answers up to three additional prompts (anonymize, humanize, scaffolding survey) it never
  saw before. This is the corrected, intended behavior per Gate 0d's own pre-existing specification (§2.4,
  §3.2), but it is a real, user-visible change in the Express/Hybrid experience, flagged here explicitly rather
  than folded silently into "just a bug fix."
- The currently-*deployed* `concept-to-code` copy (`~/.claude/skills/concept-to-code/`) keeps all five defects,
  including the P1, until a human runs `sync-to-claude.sh --apply`. Same "deployed stays defective until sync"
  design this roadmap has already established (ADR-0025, ADR-0026), flagged again here because Finding 1 is a
  P1 affecting the most common invocation path.
- The pre-existing "44 total — 26/6/12" pair-count summary line remains wrong after this ADR (§3.5) — a known,
  disclosed, deliberately-deferred gap, not a regression this ADR introduces.

### Neutral

- This ADR changes no hook wiring, no `settings.json`, no `hooks.json`, and no file under `~/.claude` — consistent
  with every prior ADR in this roadmap's stated invariant that staging-side fixes stay staging-side until an
  explicit, separate, human-gated sync.
- The "static anchors for a platform- or environment-gated finding, live execution for everything else" test
  strategy (§2.6, Section A) is the same discipline ADR-0026 §2.4/§3.5 established for a different environmental
  gate (`git-filter-repo` absence). Worth reusing again the next time this roadmap hits a finding whose bug
  precondition is not reproducible in this repo's own CI (see DURABLE NOTES in the report).
- Section B's compound-anchor technique (grep a phrase specific enough to distinguish an autopilot-only code path
  from an adjacent, legitimately-similar interactive one, rather than a bare substring that would match both) is
  a reusable pattern for any future SPEC finding that fixes one of several structurally-similar branches in the
  same file — also worth carrying forward (see DURABLE NOTES).

## 5. References

- `SPEC.md` (repo root) / `docs/specs/31-concept-to-code-bsd-safe-slug-stamp-and.spec.md` — this issue's spec
  (confirmed byte-identical)
- `docs/architecture/ADR-0014-architect-proposes-test-cmd.md` — TOFU trust model Finding 2's fix enforces
- `docs/architecture/ADR-0017-chain-type-routing-gate0.md` — original Express/Hybrid/Standard routing design
  Finding 4's fix reconciles against
- `docs/architecture/ADR-0020-autopilot-build-skill.md` — D2 autonomy boundary and D4 TOFU-pre-existing-only
  invariant Findings 2 and 3 bring `concept-to-code`'s own autopilot mode into compliance with
- `docs/architecture/ADR-0022-nightly-autopilot-goal.md` — D5/D6, confirms the nightly publish path never runs
  through `concept-to-code`'s own Step 7
- `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md` — hermetic test-file pattern and
  local-glob-vs-CI-list split this ADR's new test file reuses
- `docs/architecture/ADR-0025-29-refresh-stale-staging-copies.md` — confirms `staging/` as the working source of
  truth
- `docs/architecture/ADR-0026-30-clean-public-repo-private-history.md` — immediately preceding issue in this
  roadmap; structural precedent for this ADR's shape and for the static-anchor-under-environment-gate test
  discipline (§2.6/§4-Neutral)
- `staging/plugin/skills/concept-to-code/SKILL.md`, `scripts/manifest-validate.sh`,
  `scripts/manifest-transition.sh` — the files this ADR patches
- `staging/plugin/scripts/tests/pairs-completeness.test.sh`,
  `staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` — structural precedent the new test
  file follows
- `.claude/test-cmd` — confirmed unchanged (`for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" ||
  exit 1; done`), already globs the new file
- `.github/workflows/docs-ci.yml` — the CI job gaining one new entry in its explicit test list
- Implementation plan: `docs/superpowers/plans/2026-07-11-31-c2c-bsd-slug-autopilot-gates.md`
