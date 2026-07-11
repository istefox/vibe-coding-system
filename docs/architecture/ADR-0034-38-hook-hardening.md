# ADR-0034 — Hook hardening: enum value, lock ownership, trust hash

**Status:** Accepted
**Date:** 2026-07-11
**Author:** istefox
**Supersedes:** none
**Superseded by:** none
**Related:**
- SPEC: `docs/specs/38-hook-hardening-enum-value-lock-ownership.spec.md` (= `SPEC.md` at repo root,
  GitHub issue #38)
- ADR-0001 (`coder-preflight-pattern-classifier`), ADR-0004 (`pre-flight-pattern-enforce-hook`) — the
  `PATTERN:` gate whose block outcome this ADR moves onto the verified enum
- ADR-0009 (`db-backup-guardrail`) — source of the verified `permissionDecision` contract
  (`allow|deny|ask|defer`) this ADR brings `pre-flight-pattern-enforce.sh` into line with
- ADR-0012 (`agent-memory-orchestrator-mediated`), ADR-0016 (`dynamic-workflows-step5`), ADR-0021
  (`chain-memory-posttooluse-native-store`) — `chain-memory-capture.sh`'s origin and its
  orchestrator-only firing guarantee (why hook-propagation-into-subagents is out of scope here)
- ADR-0022 (`nightly-autopilot-goal`) — introduced `staging/sync-to-claude.sh` and its trailing
  MANUAL STEP checklist, extended by this ADR
- ADR-0024 (`vendor-deployed-only-skills-and-hooks`, issue #28) — vendored the four hooks this ADR
  patches; §2.3 named issue #38 by number as the future consumer of the legacy-test split it recorded
- ADR-0025 (`refresh-stale-staging-copies`, issue #29) — immediate predecessor issue; confirmed these
  four hook files are unaffected by staging/deployment drift, and established the "historically
  accurate, not a live-status claim" disposition this ADR reuses for two blueprint/ADR-0005 references
- ADR-0033 (`vibe-status-recursion-chains`, issue #37) — set the literal precedent this ADR follows for
  leaving a historical ADR (`ADR-0005`) unedited and amending it by reference instead
- `docs/superpowers/plans/2026-05-20-path-case-tofu-fix.md` — original design of the shared `norm_path`
  case-invariant convention `approve-test-cmd.sh`/`stop-gate.sh`/`migrate-trust-paths.sh` all use
- `staging/plugin/scripts/pre-flight-pattern-enforce.sh`, `chain-memory-capture.sh`,
  `approve-test-cmd.sh`, `stop-gate.sh`, `prompt-en-prose-detect.sh`, `migrate-trust-paths.sh`,
  `staging/plugin/scripts/tests/pre-flight-pattern-enforce.sh` (legacy test),
  `staging/sync-to-claude.sh`, `docs/vibe-coding-system.md` — the files this ADR patches or examines
- Implementation plan: `docs/superpowers/plans/2026-07-11-38-hook-hardening.md`

---

## 1. Context

Five findings from an audit of `staging/plugin/scripts/` hooks (vendored by ADR-0024/issue #28),
confirmed by reading each file in full during planning, not assumed from SPEC's line numbers alone
(all five line citations below are re-verified against the current vendored copy):

**Finding 1 — `pre-flight-pattern-enforce.sh:151-153`, out-of-enum `permissionDecision`.** The
coder-gate block path emits `permissionDecision:"block"` in both the `jq` template and its `printf`
fallback. ADR-0009 independently verified (`code.claude.com/docs`) that the enum is
`allow|deny|ask|defer` — `"block"` is not a member. The hook works today only because Claude Code
currently appears to accept it loosely; a stricter future validation pass would silently fail-open the
coder's own pattern-discipline gate — the opposite of what this hook exists to guarantee, and a
regression that would not announce itself.

**Finding 2 — `chain-memory-capture.sh:145-150`, lock-ownership.** The `mkdir "$LOCK"` retry loop, on
timeout (40 iterations) or on `sleep` itself failing, falls through to `trap 'rmdir "$LOCK" ...' EXIT`
unconditionally. Read closely: the trap line is reached by **both** exit paths of the loop — the
mkdir-succeeded path (which legitimately owns the lock) and the timeout/`break` path (which does not).
On timeout the script also proceeds directly into the MEMORY.md read-modify-write section without ever
holding the lock. The two bugs compound: a concurrent writer's lock directory gets deleted out from
under it by a process that never acquired it, while this process's own unlocked write races that
writer. `chain-memory-capture.sh` fires only from the orchestrator session (ADR-0016/ADR-0021 — manifest
helpers are orchestrator-run, so PostToolUse fires reliably), but "orchestrator session" still permits
overlapping invocations from rapid sequential manifest-helper calls.

**Finding 3 — `approve-test-cmd.sh:25-30`, hash-after-normalize.** `ROOT=$(norm_path "$ROOT")` runs
**before** `TCF="$ROOT/.claude/test-cmd"` is built and hashed. `norm_path` lowercases on Darwin
(case-invariant trust matching, by original design —
`docs/superpowers/plans/2026-05-20-path-case-tofu-fix.md`). On a case-sensitive volume with a
mixed-case project root, the lowercased `TCF` does not exist; `shasum`/`sha256sum` fails silently
(stderr redirected, no exit-code check on the pipeline), `H` comes back empty, and the script writes a
hash-less trust line (`"\t<root>"`) and reports success. No abort, no visible symptom at approval time.

**Finding 3b (found during planning, not named by SPEC) — `stop-gate.sh:65-78` carries the identical
bug, by the identical original design decision.** `docs/superpowers/plans/2026-05-20-path-case-tofu-fix.md`
shows both scripts were built from the same template on 2026-05-20: `stop-gate.sh` also normalizes
`ROOT` before building `TCF` and hashing it. This means SPEC's own stated symptom for finding 3 — "the
stop-gate test gate goes silently inert" — is not actually fixed by patching `approve-test-cmd.sh`
alone. Even with a correct trust line on disk, `stop-gate.sh`'s own hash computation would independently
land on the same empty-`H` result on a case-sensitive volume and take its documented fail-open exit at
`[ -z "$H" ] && exit 0` (spec §7) before ever reaching the trust comparison — silently skipping test
verification on every single run, indefinitely. See Decision D3 for why this ADR fixes both scripts
under one finding rather than leaving `stop-gate.sh`'s mirror-image bug for a future issue.

**Finding 4 — `backup-before-deploy.sh`, retired.** Confirmed absent from `staging/plugin/scripts/`
(directory listing taken before writing this ADR). ADR-0024 (issue #28) vendored the other hooks but
never vendored this one. `docs/architecture/ADR-0005-vibe-status-skill.md` (line 201, inside a Q5
*example report*) and `docs/vibe-coding-system.md` §7.6 (line 1437, inside an ASCII tree explicitly
labeled `AS-BUILT 2026-05-19`) both still name it. See Decision D5 for why neither reference is edited
in place.

**Finding 5 — `prompt-en-prose-detect.sh:29-43` (SPEC: PLAUSIBLE), wrong output shape — now VERIFIED.**
SPEC flagged this finding as unverified and directed dual-emission as a no-runtime-probe-needed
mitigation. This ADR upgrades it to verified: `code.claude.com/docs/en/hooks`, "Add context for Claude"
section, documents exactly one valid shape for a `UserPromptSubmit` context injection —
`{"hookSpecificOutput":{"hookEventName":"...","additionalContext":"..."}}` — and states a plain
top-level `additionalContext` key "is not documented as valid anywhere" (fetched and quoted directly
during planning, corroborated by an independent web search of the same page). The script's current
output, `{"additionalContext": ctx}`, is the undocumented shape.

**Confirmed before planning, not assumed:**
- `docs-ci.yml`'s `shell-tests` job has an explicit 11-file list; none of the four target hooks nor
  `stop-gate.sh` has any hermetic (`*.test.sh`) coverage in it today.
- `chain-memory-capture.sh` is vendored into `staging/` but has **no `sync-to-claude.sh` PAIRS entry**
  (confirmed by grep) — a pre-existing, disclosed gap this ADR does not close (Consequences, Negative).
- `migrate-trust-paths.sh` re-normalizes only the *stored path string* of existing trust entries; it
  never recomputes or reads a hash itself, so it does not share findings 3/3b's bug (confirmed by
  reading it in full).
- `docs/RUNBOOK.md` and `staging/sync-to-claude.sh`'s PAIRS table never name `backup-before-deploy.sh`
  (grep, whole repo); the sync script's trailing `MANUAL STEP` heredoc is the only existing mechanism
  for a note a `--apply` run cannot act on by itself.
- Section 15's installation checklist and section 8.6's "Deployed custom skills" table — the two
  locations `docs/vibe-coding-system.md`'s own established convention treats as live-status claims
  (most recently applied by the 2026-07-11 "project-bootstrap retired" changelog entry, three positions
  above this ADR's own new entry) — never name `backup-before-deploy.sh` at all; 8.6 is scoped to
  skills, not hooks, so it could not have.

## 2. Decision

Patch five scripts under `staging/plugin/scripts/` (the four SPEC names plus `stop-gate.sh`, disclosed
below as D3's scope extension), update one legacy test's expectations, add one new hermetic test file
covering all five fixes, wire it into `docs-ci.yml`, and record `backup-before-deploy.sh`'s retirement
through a new blueprint changelog entry and a new `sync-to-claude.sh` checklist note — never through an
in-place edit of either stale reference. No file under `~/.claude` is touched.

### D1 — `pre-flight-pattern-enforce.sh`: `block` → `deny`

Change `permissionDecision:"block"` to `permissionDecision:"deny"` in both the `jq -nc` template
(current line 152) and the `printf` fallback (current line 153) — the two sites SPEC names. The
`log_audit "$SID" "$TOOL" "block" ...` call (current line 150) is **not** changed: its third argument is
a free-text label in this hook's own internal audit-log vocabulary (sibling values: `allow`,
`bypass-env`, `bypass-file`, `bypass-noncoder`, `fail-open`), not part of the JSON contract the enum
governs, and the legacy test's two greps (below) assert only on the JSON `permissionDecision` field, not
on the audit log. A version-comment entry (`v1.5 fix (2026-07-11, issue #38)`) is added to the script's
own header, matching its existing `v1.1`-through-`v1.4` running changelog convention.

### D2 — `chain-memory-capture.sh`: lock ownership by construction, not by flag

Restructure the `mkdir` retry loop so the `trap` line is reachable **only** through the loop's
mkdir-succeeded exit path:

```bash
LOCK="$MEM_DIR/.chain-memory.lock"
i=0
while ! mkdir "$LOCK" 2>/dev/null; do
  i=$((i+1))
  if [ "$i" -ge 40 ]; then
    exit 0
  fi
  sleep 0.05 2>/dev/null || exit 0
done
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
```

Both former `break` targets become `exit 0`. This is deliberately not a boolean ownership flag checked
before the trap line — control flow itself makes the trap unreachable unless `mkdir` actually succeeded,
which cannot silently drift out of sync the way a flag could if a future edit reordered statements. On
timeout, the script exits before the MEMORY.md read-modify-write section (current section 8) ever
starts; the per-slug `chain-history/<slug>.md` write (current section 7, already completed by this
point) is unaffected, since it is not lock-protected and does not need to be — it targets a per-slug
file, not the single shared `MEMORY.md`. This mirrors the ownership-marker discipline ADR-0033 already
established for `harness-runner.sh`'s watchdog-owned kill marker (§2.2 "Fifth outcome") — a resource is
only released by the code path that is provably the one that acquired it.

### D3 — `approve-test-cmd.sh` **and** `stop-gate.sh`: hash the real path, normalize only for storage/lookup

**Scope note (deviation from SPEC's literal file list, disclosed):** SPEC names only
`approve-test-cmd.sh`. This ADR also patches `stop-gate.sh`, for the reason given in Finding 3b: without
it, SPEC's own stated goal for this finding is not achieved — `stop-gate.sh` would keep silently
fail-opening on a case-sensitive volume even after `approve-test-cmd.sh` starts writing correct trust
lines, because it independently re-derives and re-hashes the same broken path. The fix is the same bug
class, the same one-line reordering technique, and preserves both scripts' existing contracts exactly
(see Alternatives §3.3 for why this was not deferred to a follow-up issue instead).

**`approve-test-cmd.sh`:** move `TCF="$ROOT/.claude/test-cmd"` and the hash computation to **before**
`ROOT=$(norm_path "$ROOT")`, and add an explicit abort:

```bash
TCF="$ROOT/.claude/test-cmd"
if command -v shasum >/dev/null 2>&1; then H=$(shasum -a 256 "$TCF" 2>/dev/null | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then H=$(sha256sum "$TCF" 2>/dev/null | awk '{print $1}')
else echo "approve-test-cmd: no sha256 tool available" >&2; exit 1; fi
[ -z "$H" ] && { echo "approve-test-cmd: hash computation failed for $TCF (empty digest) — aborting, not writing an invalid trust line" >&2; exit 1; }
ROOT=$(norm_path "$ROOT")
```

`ROOT` is reassigned in place, after hashing — safe here because nothing downstream of this point in
`approve-test-cmd.sh` re-derives a filesystem path from `ROOT` again (the final `CMD=$(awk ... "$TCF")`
line still reads the original, never-reassigned `TCF`, itself now built from the pre-normalization
`ROOT`, which is why `TCF` stays correct end to end too — an incidental correctness improvement, not
something SPEC asked for, at zero extra cost).

**`stop-gate.sh` — same technique, different shape, and this difference matters.** `stop-gate.sh` still
needs the real, case-preserving `ROOT` *after* hashing, because `run_with_timeout` later does
`cd $(printf %q "$ROOT") && ( $CMD )` to actually execute the test command — `cd`-ing into a lowercased
path would fail on exactly the case-sensitive volume this fix targets, silently reintroducing a second,
adjacent bug at the moment the first one stops masking it. So `stop-gate.sh` gets a **second variable**
instead of an in-place reassignment:

```bash
TCF="$ROOT/.claude/test-cmd"
CMD=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$TCF" 2>/dev/null)
[ "$CMD" = "NONE" ] && exit 0
[ -z "$CMD" ] && exit 0
sha256_of() { ... }   # unchanged
H=$(sha256_of "$TCF") || { echo "stop-gate: no sha256 tool — fail-open" >&2; exit 0; }
[ -z "$H" ] && exit 0
ROOT_NORM=$(norm_path "$ROOT")
LINE=$(printf '%s\t%s' "$H" "$ROOT_NORM")
```

`ROOT` (real path) stays what `run_with_timeout` and `emit_block`'s human-facing message use;
`ROOT_NORM` (case-invariant) exists only for the trust-file `LINE`/lookup. **`stop-gate.sh`'s existing
fail-open contract on empty `H` is deliberately unchanged** — `[ -z "$H" ] && exit 0` stays exit 0, not
an abort, consistent with its documented "never exit non-zero / never block on internal error" contract
(spec §7, unrelated to and pre-dating this fix). Only `approve-test-cmd.sh` — a CLI that persists state
to disk — gets the hard abort; `stop-gate.sh` is a hook whose fail-mode is deliberately permissive by an
existing, separate design decision this ADR does not revisit.

Both scripts' trust-line **format is unchanged**: `<sha256>\t<lowercased-normalized-root>`. On the
default, case-insensitive Darwin volume (the common case, unaffected by this bug), the hash value for
any entry approved before this fix is byte-identical to what the fixed code would compute today — the
fix changes *when* normalization happens, not the stored representation. Existing trust entries remain
valid; no migration is required.

### D4 — `prompt-en-prose-detect.sh`: emit the documented envelope, keep the legacy top-level key

```python
print(json.dumps({
    'additionalContext': ctx,
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit',
        'additionalContext': ctx
    }
}))
```

The nested `hookSpecificOutput.additionalContext` form is now verified correct (§1, Finding 5). The
top-level key is kept alongside it: this repo has no live probe of which shape the *currently installed*
Claude Code version actually reads for this hook today, and removing a field that might be the one
currently working, in the same change that adds the one that is documented to work, is an avoidable risk
for zero benefit — SPEC's own dual-emission directive already reached this conclusion independently;
this ADR's verification confirms the mitigation was the right one, not merely a cautious guess. A
follow-up issue can drop the legacy top-level key once a live runtime check confirms the envelope form
alone suffices — not this issue's job.

### D5 — `backup-before-deploy.sh`: retire without editing either stale reference

`docs/architecture/ADR-0005-vibe-status-skill.md` line 201 and `docs/vibe-coding-system.md` §7.6 line
1437 are **left unedited**. Both are dated, point-in-time illustrations (`ADR-0005`'s Q5 is a labeled
example report mock-up; §7.6's tree is explicitly headed `AS-BUILT 2026-05-19`), not live-status
assertions — the same category `docs/vibe-coding-system.md`'s own 2026-07-11 "project-bootstrap retired"
changelog entry (written by the immediately preceding issue, #29/ADR-0025, the same day) already applied
to a structurally identical case (§8.3's design catalog, left untouched with an explicit "historically
accurate, not a live-status claim" note). `ADR-0005` additionally has a harder, git-verified precedent:
ADR-0033 amended it for a different staleness (the `harness-runner.sh` timeout mechanism) without
touching one line of its body or header — confirmed by `git log -p` on `ADR-0005` showing no commit
since a 2026-05-31 header-normalization pass touched it. This ADR is the amendment of record for both
references; a new `docs/vibe-coding-system.md` changelog entry (below) records the correction without
rewriting either dated snapshot. Section 15's checklist and section 8.6's table — the two locations that
do make live-status claims — never named this hook, so nothing there needs correcting either.

**New changelog entry**, inserted immediately after the current most-recent top-block entry (`###
Correction 2026-07-11 (project-bootstrap retired from staging)`, ending at current line 440) and before
the next one (`### Update 2026-06-23 (workflow model pinning)`, starting at current line 441) — full
text specified in the implementation plan.

**`staging/sync-to-claude.sh`** gains a second `MANUAL STEP` note in its existing trailing heredoc
(the only precedent in this repo for "an action a `--apply` run cannot itself perform"), pointing a
future human at the deployed-side `~/.claude/hooks/backup-before-deploy.sh` for manual deletion. This
repo does not write under `~/.claude`; the note is the only artifact this ADR can produce for that
action.

### Test strategy

One new hermetic file, `staging/plugin/scripts/tests/hook-hardening.test.sh`, covering all five fixes
against the `staging/` originals directly (not the deployed copies the legacy test targets — see below),
appended to `docs-ci.yml`'s explicit 11-file list (→ 12) and automatically picked up by
`.claude/test-cmd`'s `*.test.sh` glob with no edit needed there. `unset CLAUDE_CODE_SESSION_ID` at the
top, matching the ADR-0029/issue #33 hermeticity convention, defensively — none of the five target
scripts actually reads that variable (confirmed by reading each in full), but every other hermetic file
in this harness now carries the same guard and a future script might.

The finding-3/3b assertion needs two distinct techniques: an `empty-hash-aborts` case is made fully
portable by stubbing `shasum`/`sha256sum` on `PATH` (deterministic, no filesystem dependency), while the
`mixed-case-root-round-trips-correctly` case genuinely requires a case-sensitive filesystem to
manifest — impossible to fake portably, since a case-insensitive host cannot even construct two
distinctly-addressable mixed-case paths. That case uses a standard case-sensitivity self-probe
(`mkdir X; test -d x`) and reports `SKIP` (counted, not silently dropped, not a false PASS or FAIL) on a
case-insensitive host such as this repo's own default macOS development machine — it still runs for real
on `docs-ci.yml`'s `ubuntu-latest` runner (ext4, case-sensitive), which is where CI-enforced coverage of
this specific bug actually matters most.

`staging/plugin/scripts/tests/pre-flight-pattern-enforce.sh` (the legacy, `$HOME`-coupled harness) gets
its two greps updated from `"permissionDecision":"block"` to `"permissionDecision":"deny"` (SPEC's own
literal instruction), plus matching label-text updates. This harness targets
`$HOME/.claude/hooks/pre-flight-pattern-enforce.sh` — the **deployed** copy, not `staging/`'s — by
original design (ADR-0024 §2.3 already named issue #38 as the future editor of this exact file). It
therefore reads red against today's still-deployed `"block"` hook until a human runs
`sync-to-claude.sh --apply`; this is expected, not a regression, and is why the new hermetic file (which
targets `staging/` directly) is the one that gives this fix actual CI-enforced protection today.

## 3. Alternatives considered

### 3.1 Finding 1 — enum fix mechanism

- **Leave `"block"` and rely on Claude Code continuing to tolerate it.** Rejected. This is precisely the
  latent-regression risk the finding exists to close; "it has worked so far" is not evidence it will
  keep working after an unannounced validation tightening, and ADR-0009 already establishes `deny` as
  the correct, verified member for exactly this semantic (blocks tool execution, sub-agent stops and
  receives the reason).
- **Switch to the legacy `{"decision":"block","reason":...}` root-level contract instead of the
  `hookSpecificOutput.permissionDecision` envelope**, matching `stop-gate.sh`'s own format. Rejected.
  ADR-0009 §Neutral already recorded why `pre-flight-pattern-enforce.sh` stays on the modern envelope
  format deliberately (its `PreToolUse` matcher and audience make the enum-based contract the correct
  one going forward); swapping formats here would be a larger, unrequested rewrite for a one-word fix
  and would touch every downstream consumer of this hook's JSON shape, not just the two literal strings
  SPEC names.

### 3.2 Finding 2 — lock ownership mechanism

- **A boolean `LOCK_OWNED` flag, checked before the `trap` line.** Rejected in favor of the
  control-flow-only version. A flag can silently desynchronize from reality if a future edit reorders
  statements around it (the exact class of bug this finding already is — the original code's `trap` line
  was unconditionally reachable, which is a flag-less version of the same mistake); making the trap
  genuinely unreachable except via the success path removes an entire category of future regression at
  no extra cost.
- **Retry with a longer timeout or exponential backoff instead of skipping the event.** Rejected. SPEC is
  explicit ("on timeout, skip the event rather than proceed unlocked"), and this hook's own header
  already documents it as "observational... always exits 0" — a longer wait only delays the Bash tool's
  return to the agent for a hook whose entire value proposition is that a missed event is a
  one-line-in-`MEMORY.md` cost, not a correctness failure. The per-slug `chain-history/<slug>.md` file
  (unlocked, but not shared, so uncontended) still records the transition either way.

### 3.3 Finding 3/3b — scope (one script vs. two) and fix shape

- **Fix only `approve-test-cmd.sh`, exactly as SPEC names, and leave `stop-gate.sh`'s mirror-image bug
  for a future issue.** Rejected. Finding 3b (§1) shows this would not actually close SPEC's own stated
  symptom for this finding — the "stop-gate test gate goes silently inert" sentence in SPEC's own
  objectives describes `stop-gate.sh`'s behavior, not `approve-test-cmd.sh`'s, and `stop-gate.sh` would
  keep exhibiting it indefinitely, unchanged, after a partial fix. Deferring a same-day, same-bug-class,
  one-line-reordering companion fix to a hypothetical future issue — while shipping an ADR whose own
  title names "trust hash" as a hardening target — would leave the actual security property (tests
  genuinely verified before every Stop, not silently skipped) unfixed while appearing fixed. This is
  disclosed prominently (D3's scope note, this ADR's own References, the plan's risk register) rather
  than silently folded in, per the standing instruction to surface rather than quietly resolve a scope
  conflict.
- **Give `stop-gate.sh` the same single-variable in-place `ROOT` reassignment as `approve-test-cmd.sh`,
  for symmetry.** Rejected — this would be a *wrong* fix, not just an inconsistent one. `stop-gate.sh`
  needs the real, case-preserving path again after hashing (`run_with_timeout`'s `cd`); reassigning
  `ROOT` in place would make that `cd` target a lowercased, nonexistent path on exactly the case-sensitive
  volume this fix is for, trading today's silent-fail-open bug for a silent-`cd`-failure bug one line
  later. The two-variable (`ROOT` / `ROOT_NORM`) shape is not stylistic — it is the specific correctness
  requirement `stop-gate.sh`'s later `cd` imposes that `approve-test-cmd.sh` (which never re-`cd`s after
  hashing) does not share.
- **Also make `approve-test-cmd.sh`'s empty-hash case fail-open (exit 0, matching `stop-gate.sh`) instead
  of aborting (exit 1).** Rejected. SPEC is explicit: "abort with an error if the hash is empty before
  writing the trust line." The two scripts have different failure philosophies by original design and
  by role: `approve-test-cmd.sh` is a CLI that **persists** state a human is trusting; silently
  fail-opening there would silently write a corrupt, permanent trust-file entry — worse than doing
  nothing. `stop-gate.sh` is a hook whose worst failure mode is "skip verification once," already an
  accepted, documented trade-off (spec §7) predating this fix and out of this ADR's scope to revisit.

### 3.4 Finding 4 — dual-emission vs. envelope-only

- **Emit only the now-verified `hookSpecificOutput.additionalContext` envelope, dropping the legacy
  top-level key.** Rejected for this issue, though it is very likely the eventually-correct end state.
  Verifying the documented shape does not verify which shape the *currently deployed* Claude Code CLI
  version on this machine actually reads — no live probe was run (none is available offline during
  planning), and removing a field in the same change that adds its replacement, on a hook whose entire
  job is a soft reminder (not a security gate), is exactly the kind of unforced risk this codebase's
  "empirically verified, not assumed" discipline argues against taking without a probe. SPEC's own
  dual-emission directive already reached the same conclusion; this ADR's verification strengthens the
  case for keeping it, not for abandoning it.

### 3.5 Finding 5 (backup-before-deploy.sh) — where to record the retirement

- **Edit `ADR-0005` line 201 and `docs/vibe-coding-system.md` line 1437 directly, as SPEC's literal
  wording asks.** Rejected. Two independent, same-repo precedents — one git-verified (ADR-0033 left
  `ADR-0005` untouched for a different staleness), one same-day (the 2026-07-11 "project-bootstrap"
  changelog entry explicitly left a structurally identical dated design-catalog reference untouched,
  with the same "historically accurate, not a live-status claim" reasoning this ADR reuses) — establish
  that this repository's convention is to record such corrections forward, in a new artifact, rather than
  rewrite a dated historical snapshot in place. Following SPEC's literal line numbers over two converging,
  recent, in-repo precedents would be the less consistent choice, not the more faithful one; this
  deviation is disclosed here and in the Consequences section rather than silently substituted.
- **Scrub every mention of `backup-before-deploy.sh` repo-wide** (RUNBOOK, guides, historical
  `docs/superpowers/` plans/specs). Rejected, same reasoning ADR-0025 §3.4 already gave for the
  identical shape of decision about `project-bootstrap`: SPEC names exactly two references, a repo-wide
  grep confirms those are the only two, and historical dated plan/spec files under `docs/superpowers/`
  are records that should never be rewritten after the fact.

## 4. Consequences

### Positive

- Closes the specific, time-sensitive risk framed by SPEC's objective 1: a future stricter Claude Code
  validation pass can no longer silently fail-open the coder pattern-discipline gate, because `deny` is
  already a verified enum member today, not a hopeful guess.
- `chain-memory-capture.sh` can no longer delete a lock directory it does not own. The failure mode on
  timeout changes from "silent data race + destroyed foreign lock" to "silent, single-event skip" —
  strictly safer, and consistent with the hook's own documented "observational, always exits 0" contract.
- The actual, complete symptom named by SPEC's objective 3 — "stop-gate test gate goes silently inert" —
  is closed, not half-closed: both the write side (`approve-test-cmd.sh`) and the read side
  (`stop-gate.sh`) of the TOFU trust mechanism now hash the real, on-disk path on a case-sensitive
  volume. `approve-test-cmd.sh` additionally now refuses to persist a corrupt trust entry instead of
  writing one silently.
- `prompt-en-prose-detect.sh` now emits the one JSON shape independently verified against
  `code.claude.com/docs` to be documented and valid for `UserPromptSubmit` context injection, while
  keeping its previous shape as a zero-cost safety net.
- `backup-before-deploy.sh`'s retirement is now recorded in a reviewable artifact (this ADR) and a
  concrete, actionable checklist note (`sync-to-claude.sh`'s MANUAL STEP block) — the first place either
  fact has been written down anywhere in this repo, without disturbing either of the two dated documents
  that motivated the finding.
- One new hermetic test file gives CI-enforced regression coverage, for the first time, to four hook
  scripts and one CLI utility that previously had zero hermetic coverage of any kind — the legacy test's
  grep update alone could not have provided this, since it targets the deployed tree, not `staging/`.
- No file under `~/.claude` is touched; no `docs-ci.yml` entry removed or reordered (append-only,
  consistent with ADR-0024's PAIRS discipline extended here to the shell-tests list); no existing trust
  entry is invalidated (format unchanged, common-case hash values unchanged).

### Negative

- **The legacy test's updated greps read red immediately after this change, against today's still-live
  deployment**, until a human runs `sync-to-claude.sh --apply`. This is disclosed, expected, and
  consistent with ADR-0024 §2.3's documented split between `staging/`-testing and deployment-testing —
  but a reviewer skimming only the legacy harness's pass/fail tally without this context could mistake
  it for a regression this ADR introduced.
- **`chain-memory-capture.sh`'s pre-existing missing `sync-to-claude.sh` PAIRS entry is not closed by
  this ADR.** This fix, like the four others, reaches deployment only through `docs/RUNBOOK.md`'s bulk
  copy path, not the lightweight incremental one every other patched hook already has. Flagged, not
  fixed — the same category of decision ADR-0025 §2.3 already made explicitly for a different set of
  files (add PAIRS entries only where SPEC asks), and this issue's SPEC does not ask for PAIRS growth.
- **The finding-3b scope extension (`stop-gate.sh`) is, by this ADR's own count, a second file beyond
  what SPEC's five-item list names**, decided unilaterally during planning under "auto mode, no
  intermediate HITL." The reasoning is disclosed at length (D3, §3.3) specifically so a human reviewing
  the eventual PR can override it if they disagree that this extension was warranted — it is a
  deliberate, argued judgment call, not an oversight, but it remains a judgment call made without a
  human turn in the loop.
- **Test 3b (mixed-case root round-trip) cannot produce a real PASS on this repo's own default
  development machine** (case-insensitive APFS) — only `SKIP`. The fix it verifies is real and the CI
  runner does exercise it for real, but a developer running the full suite locally will never see this
  specific assertion go green, only skip, which could read as "untested" at a glance without reading the
  skip reason.
- **Deployed copies of all five patched files keep today's bugs live** until a human runs
  `sync-to-claude.sh --apply` — not a defect in this ADR's own scope (`~/.claude` is read-only for this
  task, consistent with every ADR in this roadmap since ADR-0024), but a real, unclosed operational gap
  between "fixed in this repo" and "fixed where it runs," worth flagging with priority given two of the
  five findings (2 and 3/3b) are data-integrity and security-adjacent (lock corruption, TOFU trust).

### Neutral

- `migrate-trust-paths.sh` was read in full during planning and confirmed unaffected (it never computes
  a hash, only re-normalizes already-computed ones) — recorded here so a future reader does not have to
  re-derive that conclusion from scratch.
- The blueprint's "only section 15 / section 8.6 make live-status claims" convention, applied here for
  the second time in two consecutive issues (this one and #29/ADR-0025), is now a load-bearing,
  twice-applied precedent rather than a one-off judgment call — worth citing directly in any future issue
  that touches a stale reference inside `docs/vibe-coding-system.md` or an old ADR.
- `prompt-en-prose-detect.sh`'s dual-emission is explicitly a transitional state (§3.4) — a natural,
  small follow-up exists (drop the legacy top-level key once a live probe confirms it is dead weight),
  not owned by any issue today.
- This ADR's five (six, counting 3b) findings span four independent bug classes (enum compliance, lock
  ownership, hash-input ordering, output-shape documentation) unified only by "hooks vendored in issue
  #28, hardened in issue #38" — there is no deeper architectural theme connecting them beyond that shared
  origin, which is why the fix for each is independent and none depends on another landing first (Task
  ordering in the implementation plan is for review/checkpoint clarity, not because of any cross-finding
  dependency).

## 5. References

- `SPEC.md` (repo root) / `docs/specs/38-hook-hardening-enum-value-lock-ownership.spec.md` — this
  issue's spec
- `docs/architecture/ADR-0009-db-backup-guardrail.md` — verified `permissionDecision` enum
  (`allow|deny|ask|defer`) and the "no output = allow" convention this ADR relies on for Finding 1
- `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md` §2.3 — the legacy-vs-hermetic
  test split, and its explicit naming of issue #38 as the future editor of the legacy pattern-enforce
  test
- `docs/architecture/ADR-0025-29-refresh-stale-staging-copies.md` §2.4/§3.4 — the "historically accurate,
  not a live-status claim" disposition this ADR reuses for `ADR-0005` line 201 and blueprint line 1437,
  and the precedent for scoping a stale-reference correction to exactly what SPEC names
- `docs/architecture/ADR-0033-37-vibe-status-recursion-chains.md` §Amends, §2.2 "Fifth outcome" — the
  git-verified "leave `ADR-0005` unedited, amend by reference" precedent, and the ownership-marker
  pattern this ADR's lock-ownership fix (D2) mirrors
- `docs/superpowers/plans/2026-05-20-path-case-tofu-fix.md` — original design and rationale for
  `norm_path`'s case-invariant (lowercase-on-Darwin) trust-storage convention, confirming both
  `approve-test-cmd.sh` and `stop-gate.sh` inherited today's hash-after-normalize bug from the same
  original template
- `code.claude.com/docs/en/hooks`, "Add context for Claude" section (fetched during planning) — verified
  the `UserPromptSubmit` `hookSpecificOutput.additionalContext` envelope shape and that a top-level
  `additionalContext` key is not documented as valid for any hook event
- `staging/plugin/scripts/pre-flight-pattern-enforce.sh`, `chain-memory-capture.sh`,
  `approve-test-cmd.sh`, `stop-gate.sh`, `prompt-en-prose-detect.sh`, `migrate-trust-paths.sh` (read in
  full during planning), `staging/plugin/scripts/tests/pre-flight-pattern-enforce.sh` (legacy test),
  `staging/sync-to-claude.sh`, `.github/workflows/docs-ci.yml`, `docs/vibe-coding-system.md` (changelog
  block and §7.6), `docs/architecture/ADR-0005-vibe-status-skill.md`
- Implementation plan: `docs/superpowers/plans/2026-07-11-38-hook-hardening.md`
