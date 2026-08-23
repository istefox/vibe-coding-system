---
name: autopilot
description: >
  Unattended roadmap-to-PR runner for long sessions (ADR-0022, repositioned by ADR-0127). Given a
  target repo with an opt-in marker, a PROJECT.md roadmap, and TOFU-trusted tests, it drives
  project-conductor in roadmap-autopilot mode: each feature is implemented, reviewed, committed on
  feat/*, pushed, and opened as a PR to main with CI green. Use it whenever you are stepping away
  from the machine — an afternoon, a long build, or overnight. Never merges, never force-pushes,
  never touches main. An autopilot-guard hook halts on real trouble and leaves a run report.
  Set with /goal as the outer keep-alive loop and a non-blocking permission mode.
---

# `autopilot` — Unattended Roadmap-to-PR Runner

Runs an already-designed roadmap unattended and delivers PR-ready branches. The human approves
SPEC/ADR/plan first (still HITL), sets `/goal` plus a non-blocking permission mode, launches this
skill, and walks away. Nothing is merged to `main`.

**Duration is not what defines this runner (ADR-0127).** It was built for an overnight window, and
that framing was load-bearing rather than cosmetic: a night is a fixed, self-limiting budget, so the
original design never had to decide how much a run should attempt or what stops it. A run you start
after lunch is open-ended. Run scoping and the token bound exist because of that, and they apply to
a night exactly as they apply to an afternoon.

**Architecture reference:** ADR-0022. Report schema: `ADR-0022-morning-report-schema.md`.

Relationship to the rest of the stack: this skill owns launch, publish, guard wiring, CI setup, and
the morning report. It delegates the per-feature roadmap loop to `project-conductor` (roadmap-autopilot
mode), which reuses `concept-to-code` autopilot / `autopilot-build` for the implement-review-commit
mechanics unchanged.

---

## 1. When to invoke

```
/skill autopilot [--features N] [--only <token>[,<token>]] [--dry-run]
```

Project root = `$PWD`. Run this only after the evening design gate is done: SPEC/ADR/plan approved for
each roadmap feature, or a roadmap of features whose chains will run in autopilot.

**Arguments (issue #365, ADR-0129 §D1/§D3):**
- `--features N` — cap the run at `N` successful publishes, `N` a positive integer. Absent means
  uncapped, exactly as before this feature. A publish is a slot consumed; a feature skipped for a
  known contained reason is not (§D4) — `--features 2` promises two PRs or an exhausted roadmap,
  never two rows examined.
- `--only <token>[,<token>]` — scope the run to specific roadmap rows. Each token resolves, in
  order: first as an issue number (`293`) matched against the roadmap's `(issue #N)` marker with
  the **closing parenthesis included** in the needle, so `29` never resolves to `(issue #293)`;
  second as a full topic-slug, for a hand-written row that carries no issue marker (§D3). A token
  resolving as neither, or resolving to more than one row, aborts Phase 0 pre-flight before any
  feature starts, naming the token — a bound nobody wrote is worse than no bound.
- `--dry-run` — resolve and print the scope, touch nothing, and stop. See Phase S below.

**Passing `--features` or `--only` discards the WHOLE `.claude/autopilot.yml` `scope:` block, not
just the keys it names (ADR-0129 A4).** Per-key override was considered and rejected on a concrete
failure: an `only:` list left in the marker from last week would survive a `--features 2` that meant
something else entirely, the operator would get one feature instead of two, and nothing on screen
would explain why. One source is in effect at a time, printed by Phase S below, never a silent merge
of two.

With no scoping argument the run behaves exactly as before this feature: uncapped, reading a
`scope:` block from the opt-in marker if one is present there, none if not (§1.5 Phase P).

**Launch order (see `docs/RUNBOOK-autopilot.md`):**
1. Set **`bypassPermissions`**. It is the only mode under which no per-tool prompt can fire, and
   an overnight run is exactly the case that needs that.
   **`acceptEdits` is NOT equivalent and the difference is not cosmetic** (issue #339): it
   auto-accepts *edits*, while a Bash command outside `permissions.allow` still prompts — and the
   chain's Bash surface (`bash ~/.claude/skills/*/scripts/manifest-*.sh`, `sed`, `awk`, `mkdir`,
   `git push`, `gh pr create`, the project's own test-cmd) is not in a default allowlist. Choose
   `acceptEdits` only if you have checked that yours covers all of it.
   **Three ways to set it, and `/permissions` is not one of them** — that command manages
   allow/ask/deny rules, and hooks are a third axis it does not touch either:
   - **Shift+Tab** cycles `default → acceptEdits → plan → bypassPermissions → auto → default`.
     Read the mode off the status line rather than counting presses.
   - `claude --permission-mode bypassPermissions` at launch.
   - `permissions.defaultMode` in `~/.claude/settings.json` for the durable default.

   The safety layer does not go away with the prompts: `stop-gate`, `pre-flight-pattern-enforce`,
   `protect-files`, `db-backup-guardrail`, `write-scope-enforce`, `agent-write-scope`,
   `agent-command-scope` and `autopilot-guard` all still fire, and a hook deny overrides any
   permission mode. That is the design ADR-0022 states: autopilot bypasses the human-decision
   layer, never the safety layer.
2. Set the outer loop: paste the `/goal` template this skill prints (Phase 1).
3. Invoke this skill.

`/goal` is the outer keep-alive; this skill runs with or without it, but without `/goal` the session
will not re-enter after a turn ends.

---

## 1.3 Phase S — Resolve the run scope (issue #365, ADR-0129)

**Runs FIRST, before Phase M.** A `--features 0` typo must not cost a Phase P run, and a `--dry-run`
must not trigger Phase P's writes — both phases downstream do real work (Phase M can stall on a
blocking permission prompt with nobody present, Phase P writes `.claude/test-cmd`, `PROJECT.md` and
per-feature SPECs), so the argument-and-marker parse that can reject the launch outright runs before
either gets a turn.

It reads the `--features`/`--only`/`--dry-run` arguments and the opt-in marker
(`.claude/autopilot.yml`) and **nothing else** — in particular not `PROJECT.md`, which in
auto-design mode does not exist yet at this point in the launch (§D7).

**This is a CHECKER: the caller branches on the exit code** — the opposite idiom from a REPORTER,
which always exits 0 and signals through stdout alone (ADR-0047 §D8: this file names no fourth
call site for that mechanism, so the contrast is stated generically here).

<!-- fence-contract: autopilot-scope-args -->
```bash
# ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not
# under the host shell. The Bash tool executes a fence under whatever shell the session has — zsh
# 5.9 here — and zsh does not word-split an unquoted parameter expansion, so the parser call below
# received ONE argument where bash gives it four, and --features/--only bounded nothing at all
# from ADR-0129's first run onward. `export` forwards this body's caller-bound free variables
# across the new process boundary, since a plain shell variable does not survive it. The
# terminator sits at COLUMN 0 on purpose: an indented one is swallowed into the here-document and
# destroys this fence's exit code silently. Do not tidy either line.
export _args _root CLAUDE_PLUGIN_ROOT
bash <<'FENCE_BASH'
# The initialisers and the argument parse loop live in scope-args-parse.sh (issue #385,
# ADR-0132 §D1/§D2). This markdown body is RENDERED before the model executes it, and the
# renderer substitutes this skill's own invocation arguments into every positional-parameter
# token in it — a fence is just text. The parse loop is the code that reads those tokens, so it
# was the first thing that rewriting corrupted, silently and into valid shell. A file is never
# rendered. ONLY that loop moved: everything below — the marker branch, the positive-integer
# guard, the SCOPE-PARSE line — deliberately stays here, where a human approving an overnight
# launch reads the mechanism at the point of decision.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/autopilot/scripts/scope-args-parse.sh" ]; then
  _sap="$CLAUDE_PLUGIN_ROOT/skills/autopilot/scripts/scope-args-parse.sh"
elif [ -f "$HOME/.claude/skills/autopilot/scripts/scope-args-parse.sh" ]; then
  _sap="$HOME/.claude/skills/autopilot/scripts/scope-args-parse.sh"
else
  # Exit 3, this fence's own documented code for "the check DID NOT RUN". Phase M below exits 1
  # on its own unresolved helper: the two are NOT reconciled and must not be (ADR-0132 §D4).
  # Each fence carries its own exit vocabulary, its own tests assert it, and a "consistency" pass
  # that renumbers either one changes a contract.
  echo "✗ scope: scope-args-parse.sh not deployed — DID-NOT-RUN, the arguments were not parsed"
  echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 3
fi
# scope-args-parse.sh above is a CHECKER: this caller branches on ITS exit code (ADR-0047 §D8).
# scope-file-read.sh below is the OPPOSITE idiom, a REPORTER (ADR-0167 §D6): it always exits 0
# on every state of the preserved file it was asked about and signals through a `state=...`
# stdout line alone, never through $?. Resolved here, at the same not-deployed exit-3 cost as
# the CHECKER above it, so a missing deployment fails the same way at the same point rather than
# only inside the "no CLI argument" branch several lines down.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/autopilot/scripts/scope-file-read.sh" ]; then
  _sfr="$CLAUDE_PLUGIN_ROOT/skills/autopilot/scripts/scope-file-read.sh"
elif [ -f "$HOME/.claude/skills/autopilot/scripts/scope-file-read.sh" ]; then
  _sfr="$HOME/.claude/skills/autopilot/scripts/scope-file-read.sh"
else
  echo "✗ scope: scope-file-read.sh not deployed — DID-NOT-RUN, the preserved bound was not read"
  echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 3
fi
# UNQUOTED on purpose, and the split is guaranteed BY THE WRAPPER above (issue #394, ADR-0133):
# this body runs under bash, which word-splits an unquoted expansion, so
# `--features 2 --only 293,294` arrives as five arguments and not as one opaque word. It stays
# unquoted for exactly that reason. The previous wording here claimed the split "reproduces the
# word split the moved `set --` performed" — under the host shell it reproduced nothing, and a
# comment asserting a mechanism that does not run is what let this survive unnoticed. Quoting it
# would collapse every multi-token launch into a single unrecognised token, which the parser's
# skip-anything arm would then discard in silence.
_sap_out=$(bash "$_sap" $_args) || {
  echo "✗ scope: scope-args-parse.sh failed — DID-NOT-RUN, the arguments were not parsed"
  echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 3
}
_has_scoping_arg=$(printf '%s\n' "$_sap_out" | sed -n 's/^has_scoping_arg=//p')
_seen_features=$(printf '%s\n' "$_sap_out" | sed -n 's/^seen_features=//p')
_seen_only=$(printf '%s\n' "$_sap_out" | sed -n 's/^seen_only=//p')
_cli_features=$(printf '%s\n' "$_sap_out" | sed -n 's/^cli_features=//p')
_cli_only=$(printf '%s\n' "$_sap_out" | sed -n 's/^cli_only=//p')
_dry_run=$(printf '%s\n' "$_sap_out" | sed -n 's/^dry_run=//p')

_source=none
_features=""
_only=""
_scope_preserved=""

# Preserved-bound probe (ADR-0167 §D3 point 2, §D6, §D7). Runs regardless of which source ends
# up winning: an explicit CLI argument still overwrites unconditionally below, but a
# MALFORMED/UNREADABLE preserved file has to be known about either way, since check 9's write is
# a truncating `>` redirect that itself fails on a mode-000 existing file (§D7) -- probing once,
# here, is what lets check 9 remove it before writing regardless of which source wins.
_sfr_out=$(bash "$_sfr" "$_root")
_scope_preserved=$(printf '%s\n' "$_sfr_out" | sed -n 's/^state=//p')

if [ "$_has_scoping_arg" -eq 1 ]; then
  # Any scoping argument discards the marker's scope: block WHOLE (ADR-0129 A4) — no per-key
  # merge, so a stale only: left in the marker cannot silently survive a --features override.
  _source=arguments
  # An absent value is exactly as much an operator error as `0` or `x`, and only the latter two
  # were ever caught. A bound nobody wrote is worse than no bound, so refuse rather than proceed.
  if [ "$_seen_features" -eq 1 ] && [ -z "$_cli_features" ]; then
    echo "✗ scope: --features was passed with no value — say how many features, or omit the flag"
    exit 2
  fi
  if [ "$_seen_only" -eq 1 ] && [ -z "$_cli_only" ]; then
    echo "✗ scope: --only was passed with no value — name the features, or omit the flag"
    exit 2
  fi
  _features="$_cli_features"
  _only="$_cli_only"
else
  if [ "$_scope_preserved" = "REUSABLE" ]; then
    # The bound is the preserved file's own already-resolved contents (ADR-0167 §D3 point 2):
    # its only= lines hold the roadmap row's exact TEXT (ADR-0129 §D2), not comma-separated
    # tokens, so check 9 must not feed them back through its token resolver -- that would match
    # nothing and abort the launch. Reuse means use the file as it stands.
    _source=preserved
    _sf_path="$_root/.claude/autopilot-state/scope"
    _features=$(printf '%s\n' "$_sfr_out" | sed -n 's/^features=//p')
    _only=$(grep '^only=' "$_sf_path" 2>/dev/null | sed 's/^only=//' | tr '\n' ';' | sed 's/;$//')
  elif [ "$_scope_preserved" = "MALFORMED" ] || [ "$_scope_preserved" = "UNREADABLE" ]; then
    # Warn and fall through (ADR-0167 §D6/§D7). Check 9, not this fence, does the removal: it
    # needs to know the state either way (carried below on the SCOPE-PARSE line), and removal
    # belongs at the point where the guard is about to be armed.
    echo "⚠ scope: preserved file $_root/.claude/autopilot-state/scope is $_scope_preserved -- ignoring it, falling back to marker/unbounded resolution"
  fi

  _marker="$_root/.claude/autopilot.yml"
  if [ "$_source" != "preserved" ] && [ -f "$_marker" ]; then
    if [ ! -r "$_marker" ]; then
      echo "✗ scope: $_marker exists but is not readable — DID-NOT-RUN"
      exit 3
    fi
    if grep -qE '^scope:[[:space:]]*$' "$_marker"; then
      # Field-free on purpose (ADR-0132): a bare /re/ pattern already matches the whole record, so
      # naming the record adds nothing and would put a token the skill-argument substituter
      # rewrites into a bash fence. Same program; do not "simplify" the record back in.
      _scope_block=$(awk '
        /^scope:[[:space:]]*$/ { found=1; next }
        found && /^[[:space:]]+/ { print; next }
        found { exit }
      ' "$_marker")
      if [ -z "$_scope_block" ]; then
        echo "✗ scope: the scope: block is empty (in $_marker) — a malformed bound must not read as an absent one"
        exit 2
      fi
      _source=marker
      # Both keys are unwrapped of surrounding double quotes, in the SAME two-step shape, because
      # they come from one YAML block and `features: "2"` is as legal as `only: "293,294"`.
      # Stripping one and not the other made a quoting style this very doc block demonstrates
      # hard-abort the pre-flight. If a third key is ever read here, give it this shape too.
      _marker_features_raw=$(printf '%s\n' "$_scope_block" | grep -E '^[[:space:]]*features:' | head -1 | sed -E 's/^[[:space:]]*features:[[:space:]]*//')
      _marker_features=$(printf '%s' "$_marker_features_raw" | sed -E 's/^"//; s/"$//')
      _marker_only_raw=$(printf '%s\n' "$_scope_block" | grep -E '^[[:space:]]*only:' | head -1 | sed -E 's/^[[:space:]]*only:[[:space:]]*//')
      _marker_only=$(printf '%s' "$_marker_only_raw" | sed -E 's/^"//; s/"$//')
      _features="$_marker_features"
      _only="$_marker_only"
    fi
  fi
fi

if [ -n "$_features" ]; then
  _feat_bad=0
  case "$_features" in
    *[!0-9]*) _feat_bad=1 ;;
  esac
  if [ "$_feat_bad" -eq 0 ] && [ "$_features" -eq 0 ]; then
    _feat_bad=1
  fi
  if [ "$_feat_bad" -eq 1 ]; then
    # Name the SOURCE: this branch is shared by the CLI flag and the marker file, and a message
    # that always says "--features" sends whoever set `features:` in .claude/autopilot.yml
    # hunting through their command line for a value that is not there.
    echo "✗ scope: features value '$_features' (from $_source) must be a positive integer"
    exit 2
  fi
fi

_line="SCOPE-PARSE: OK source=$_source features=$_features"
if [ -n "$_only" ]; then
  _line="$_line only=$_only"
fi
_line="$_line dry_run=$_dry_run"
if [ -n "$_scope_preserved" ]; then
  _line="$_line scope_preserved=$_scope_preserved"
fi
echo "$_line"
echo "autopilot scope: source '$_source' is in effect (dry_run=$_dry_run)"
exit 0
FENCE_BASH
```

On exit 0, the `SCOPE-PARSE:` line is authoritative; carry `source`, `features`, `only`, `dry_run`
and `scope_preserved` into Phase M and check 9 (the last as check 9's own `_scope_preserved` free
variable, §2 — the raw state `scope-file-read.sh` reported for the preserved file: `ABSENT`,
`REUSABLE`, `SPENT`, `NOT-REUSABLE`, `MALFORMED` or `UNREADABLE`). On exit 2 (bad invocation — the
offending value or the malformed block is named in the message) or exit 3 (the check DID NOT RUN —
the marker exists but could not be read), abort the launch: an unread scope is not a resolved one.

**`--dry-run` routing.** When `dry_run=true`, skip Phase M, Phase P and Phase 0 checks 1–8 entirely,
run check 9's fence (`autopilot-scope-resolve`, §2) in read-only mode against the arguments this
fence already parsed, print the resolved list and its source, and **stop** — no guard is armed, no
file is written to `.claude/autopilot-state/`, and Phase 1 never runs. Checks 1–8 are deliberately
skipped: they answer "may this run start" (`gh auth`, TOFU trust, branch protection), not "what
would this run touch", and two of them make network calls a scope-only probe has no reason to pay
for. **A dry run requires an existing `PROJECT.md`** — check 9 resolves tokens against the roadmap,
and a roadmap Phase P has not yet generated cannot be dry-run; the fence exits 3 naming the file in
that case (ADR-0129 §D8).

**`source=preserved` routing (ADR-0167 §D8).** When Phase S instead resolves `source=preserved` (a
REUSABLE preserved bound with no `--features`/`--only` argument on the command line), Phase M and
Phase 0 run as usual, but this launch **skips Phase P** entirely — the same skip branch `--dry-run`
above already takes. The continuation's own Phase P already ran once, and a preserved bound carries
concrete, already-resolved roadmap rows rather than raw `--only` tokens, so §1.5 step 3 below has
nothing to bound a fresh selection with.

On pass with `dry_run=false`, fall into Phase M.

---

## 1.4 Phase M — Permission posture (issue #320, ADR-0110)

**Runs after Phase S, before Phase P.** Phase P writes `.claude/test-cmd`, `PROJECT.md` and per-feature
SPECs; a blocking mode stalls all of that before Phase 0 would ever get a turn, which is the same
silent-and-late failure this check exists to close, one phase up.

Item 1 of the launch order above was stated in prose three times in this file and **verified
nowhere**. On 2026-07-31 pre-flight printed `PASSED`, the guard armed, the roadmap started, and the
chain died at its first Gate 0 write with nobody present to answer the prompt. Every other
precondition fails loudly and early; this one is also the only one whose failure is *guaranteed*
fatal rather than conditional.

<!-- fence-contract: autopilot-permission-posture -->
```bash
# ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes. `export` forwards this body's caller-bound free variables across the new process
# boundary — a plain shell variable does not survive it. The terminator sits at COLUMN 0 on purpose:
# an indented one is swallowed into the here-document and destroys this fence's exit code silently.
export CLAUDE_PLUGIN_ROOT
bash <<'FENCE_BASH'
_pms=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/permission-mode-state.sh" ]; then
  _pms="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/permission-mode-state.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/permission-mode-state.sh" ]; then
  _pms="$HOME/.claude/skills/concept-to-code/scripts/permission-mode-state.sh"
else
  echo "✗ permission posture: permission-mode-state.sh not found — the check DID NOT RUN."
  echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 1
fi
_pm=$(bash "$_pms" 2>&1); _pmrc=$?
if [ "$_pmrc" -eq 3 ]; then
  echo "✗ permission posture: the check DID NOT RUN — $_pm"
  echo "  An unrun check is not a clean result. Fix the environment and relaunch."
  exit 1
fi
[ "$_pmrc" -eq 0 ] || { echo "✗ permission posture: bad invocation — $_pm"; exit 1; }
_pmtok="${_pm%%|*}"; _pmval="${_pm#*|}"
case "$_pmtok" in
  NONBLOCKING)
    # The two NONBLOCKING modes get DIFFERENT sentences, because they are not the same guarantee
    # (issue #339). Promising acceptEdits that nothing can interrupt it is false whenever a Bash
    # command falls outside permissions.allow, and this is the operator-facing line that decides
    # whether someone walks away from the machine. This comment deliberately does not quote the
    # old wording: a guard bans that phrase where it is unqualified, and a scan whose needle is a
    # literal counts its own explanation (rule 12).
    if [ "$_pmval" = "bypassPermissions" ]; then
      echo "✓ permission posture: bypassPermissions — no per-tool prompt can fire."
    else
      echo "✓ permission posture: $_pmval — edits are auto-accepted, but a Bash command outside"
      echo "  permissions.allow STILL PROMPTS, and there is nobody to answer it. Proceeding"
      echo "  because you may have an allowlist that covers this chain's Bash surface; if you"
      echo "  have not checked, stop and relaunch with bypassPermissions."
    fi ;;
  BLOCKING)
    echo "✗ permission posture: this session is in '$_pmval', which can prompt or deny."
    echo "  Nobody is here to answer it, so the run would stall with state half-written."
    echo "  Set a non-blocking mode and relaunch. /permissions does NOT do this — it manages"
    echo "  allow/ask/deny rules. Hooks are a separate axis and stay enabled either way:"
    echo "    launch with: claude --permission-mode bypassPermissions   (the mode to use)"
    echo "    or Shift+Tab through default → acceptEdits → plan → bypassPermissions → auto,"
    echo "    reading the mode off the status line rather than counting presses,"
    echo "    or set permissions.defaultMode in ~/.claude/settings.json."
    echo "  acceptEdits is accepted too, but it only auto-accepts EDITS — Bash outside"
    echo "  permissions.allow still prompts. Use it only with an allowlist you have checked."
    exit 1 ;;
  UNCLASSIFIED)
    echo "✗ permission posture: mode '$_pmval' is UNCLASSIFIED — not known-bad, just unmeasured."
    echo "  Nobody has established whether it prompts, so a pre-flight refuses it rather than"
    echo "  gamble a night on it. Use bypassPermissions, or measure '$_pmval' and add it to"
    echo "  permission-mode-state.sh's enumeration."
    exit 1 ;;
  UNOBSERVABLE)
    echo "✗ permission posture: the effective mode could not be observed — $_pmval"
    echo "  This is a fact about this build, not a bad mode: the transcript field is CC 2.1.220+."
    echo "  Verify the mode by hand before relaunching; this gate fails closed on purpose,"
    echo "  because the alternative is the silent PASSED that cost the 2026-07-31 run."
    exit 1 ;;
  *)
    echo "✗ permission posture: unrecognised token '$_pmtok'"; exit 1 ;;
esac
FENCE_BASH
```

On pass, fall into Phase P.

---

## 1.5 Phase P — Prep: auto-generate the design inputs (ADR-0023)

Runs before pre-flight, and only when the opt-in marker declares a prep source. Idempotent: each
step skips whatever already exists. With no `prep:` block the phase is a no-op and the run behaves
exactly as ADR-0022 (roadmap and specs must pre-exist). **Also skipped whole when Phase S resolved
`source=preserved` (ADR-0167 §D8, §1.3 above):** the continuation this launch is resuming already
ran Phase P once, and a preserved bound holds resolved roadmap rows, not `--only` tokens, so there
is nothing left for this phase to select against.

Read the source from `.claude/autopilot.yml`:
```yaml
publish: true
prep:
  source: issues
  issues_label: release-blocker
scope:
  features: 2
  only: "293,294"
```

**The `scope:` block is optional and sets the DURABLE default Phase S reads when no `--features` or
`--only` argument is given (issue #365, ADR-0129 §D1).** Absent, the run behaves exactly as it did
before this feature. Passing `--features` or `--only` at launch discards this block whole, never
merges with it (§D3/A4 — see §1 "When to invoke").

Steps (each is skip-if-present):

1. **test-cmd file** — if `.claude/test-cmd` is absent, run
   `~/.claude/hooks/detect-test-cmd.sh --root "$PWD"` to write a candidate from stack detection.
   This writes the FILE only; it never grants trust (that stays human, D3).
2. **Roadmap** — if `PROJECT.md` is absent, run
   `~/.claude/hooks/roadmap-from-issues.sh --root "$PWD" --label "<issues_label>"` to build
   `PROJECT.md` (one feature per issue) and `docs/specs/_issue-map.tsv`.
3. **Per-feature SPEC — bound by the row's state and the resolved scope, not by coverage alone
   (issue #399, ADR-0134).** For each row in `docs/specs/_issue-map.tsv` this step now reads three
   facts: whether `docs/specs/<slug>.spec.md` already exists (today's coverage rule, unchanged),
   the row's own state in `PROJECT.md` (`[x]`/`[~]`/`[ ]`/anything else), and Phase S's resolved
   `--only` (empty when the run is unscoped). A completed (`[x]`) or permanently-skipped (`[~]`)
   row is never selected, even when no SPEC exists for it on disk — coverage alone cannot tell a
   completed feature whose SPEC was never archived under the map's own slug apart from a pending
   one, and the fresh SPEC it would otherwise generate describes shipped work, written into the
   same `docs/specs/` namespace ADR-0106 uses as the archive.

   **ADR-0129 §D7's exclusion does not extend to this step, and this is where that is decided.**
   §D7 keeps Phase S away from `PROJECT.md` because in auto-design mode the roadmap does not exist
   yet at Phase S time. This step runs after step 2 has already generated the roadmap, so
   `PROJECT.md` exists here on every path — the reason does not carry forward, and it is written
   here so a later reader does not read §D7 as covering this step too and "fix" the reference back
   (ADR-0134 §D7, R-02).

   **`--features` does not bound this step.** That argument counts publishes (ADR-0129 §D4); using
   one number to also cap design work is the same defect class issue #242 already cost this
   repository once (ADR-0134 §D6).

   A row suppressed because it is completed or out of scope is counted in **neither**
   `features_generated` nor `features_skipped_thin` below — the latter means a thin issue was
   refused by `spec-issue-gate.sh`, and overloading it would report a finished feature as thin.
   Both counts, and `covered`/`orphan`/`unrecognised`/`duplicate`, are on the helper's own
   `PREP-SELECT:` summary line, on stderr (ADR-0134 §D11).

   The selection itself lives in a helper, not in this fence: a three-column TSV parse wants awk
   field references, and an awk field reference is exactly a positional-parameter token in a
   rendered document (ADR-0132) — this markdown body is substituted with this skill's own
   invocation arguments before a model ever executes it. A file is never rendered. This fence
   resolves the helper, branches on its exit code, and prints what it selected.

   <!-- fence-contract: autopilot-prep-row-select -->
   ```bash
   # ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not
   # under the host shell (zsh 5.9 here). `export` forwards this body's caller-bound free variables
   # across the new process boundary -- a plain shell variable does not survive it. The terminator
   # sits at COLUMN 0 ON PURPOSE, even though this fence is indented inside a numbered list item
   # exactly like check 8/9 above it: an indented terminator is swallowed into the here-document
   # and destroys this fence's exit code silently. Do not tidy either line.
   export _root _scope_only CLAUDE_PLUGIN_ROOT
   bash <<'FENCE_BASH'
   # Free variables: _root ($PWD) and _scope_only (Phase S's resolved SCOPE-PARSE `only=` value,
   # empty when the run is unscoped). No numbered positional parameter and no awk field reference
   # appears anywhere below -- the TSV parse lives in prep-row-select.sh instead, for the reason
   # stated above the fence (ADR-0132, ADR-0134 §D1). Guarded by
   # skill-fence-positional-tokens.test.sh.
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
      && [ -f "$CLAUDE_PLUGIN_ROOT/skills/autopilot/scripts/prep-row-select.sh" ]; then
     _prs="$CLAUDE_PLUGIN_ROOT/skills/autopilot/scripts/prep-row-select.sh"
   elif [ -f "$HOME/.claude/skills/autopilot/scripts/prep-row-select.sh" ]; then
     _prs="$HOME/.claude/skills/autopilot/scripts/prep-row-select.sh"
   else
     echo "✗ step 3: prep-row-select.sh not deployed -- Phase P HALTS here and NEVER falls back"
     echo "  to generating every uncovered row: a fallback would restore exactly the unbounded"
     echo "  behaviour this step exists to remove, on the machine least likely to notice."
     echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
     exit 3   # DID-NOT-RUN: never fall back to generating every uncovered row
   fi

   # Branch on emptiness rather than always passing --only "$_scope_only": prep-row-select.sh's
   # own arg parser treats an empty --only VALUE as a missing one and exits 2, so an unconditional
   # pass would turn an unscoped run into a bad invocation. Mirrors autopilot-scope-resolve's own
   # branch, for its stated reason: the two readings of "empty" are the difference between an
   # unscoped run and a run that does nothing.
   if [ -n "$_scope_only" ]; then
     _prs_out=$(bash "$_prs" --root "$_root" --only "$_scope_only")
   else
     _prs_out=$(bash "$_prs" --root "$_root")
   fi
   _prc=$?

   # Exit-code mapping: helper 0 -> continue, helper 2 -> fence exit 2, anything else -> fence
   # exit 3. Phase S's fence uses exit 3 for its own did-not-run state and Phase M's uses exit 1
   # for the same state; this fence's own resolution-failure branch above ALSO uses exit 3. The
   # three are NOT reconciled and must not be (ADR-0132 §D4): each fence carries its own exit
   # vocabulary, asserted by its own tests, and a "consistency" pass that renumbers any of them
   # changes a contract.
   case "$_prc" in
     0)
       if [ -n "$_prs_out" ]; then
         printf '%s\n' "$_prs_out" | sed 's/^/PREP-SELECT-ROW: /'
       else
         echo "PREP-SELECT: zero rows selected -- every map row is covered, completed, or out of scope (a normal result)."
       fi
       ;;
     2)
       echo "✗ step 3: prep-row-select.sh reported a bad invocation (rc=2)"
       exit 2
       ;;
     *)
       echo "✗ step 3: prep-row-select.sh did not run (rc=$_prc) -- the selection did not run, not"
       echo "  'ran and found nothing'; do not treat this as an empty result."
       exit 3
       ;;
   esac
FENCE_BASH
   ```

   **For each `PREP-SELECT-ROW:` line above, invoke `Skill(skill="spec-from-issue", args="<issue#>
   --slug <slug>")`.** A thin or vague issue is SKIPPED (marked `[~]` in PROJECT.md with a
   `needs-human` note), never fabricated — unchanged behaviour.

   **This loop is an instruction, not an enforcement (ADR-0134 §D10).** Nothing stops a model from
   issuing a `Skill()` call for a row the fence did not print, or from skipping one it did print.
   What changed is that the list is now computed by code with a stated contract instead of derived
   ad hoc from a glob — the failure shape moves from a silently wrong list to a list on screen that
   a reader can compare against what was actually generated.

4. **Prep branch — commit Phase P's outputs and make them the fork point (issue #364, ADR-0127
   §D4).** Everything above is written into the WORKING TREE, so without this step those files exist
   only wherever the first feature happens to commit them, and every later feature forked from a
   clean base finds no SPEC of its own. That is not hypothetical: it is `VCS-003` in this
   repository's own ledger, observed on 2026-08-04 with five SPECs stranded on one feature branch.

   Create `autopilot/prep-<YYYY-MM-DD>` from the default branch, commit `PROJECT.md`,
   `docs/specs/*.spec.md`, `docs/specs/_issue-map.tsv` and `.claude/test-cmd` onto it, and push it.
   Use the `commit` skill with `--branch` and `--include` — never hand-rolled git, for the reason
   Gate 4.0 gives: one commit path in the system.

   **Record the ref as `$_prep_ref`.** §3.3 hands it to `project-conductor`, which forks every
   feature branch from it. The feature PRs still target `main`.

   Opening a PR for the prep branch itself is OPTIONAL and belongs to the human's morning: it is
   documentation only, and merging it first is what stops each feature PR from carrying the prep
   commit. The run does not depend on it being merged.

   **Skip-if-present, like every step above:** if `autopilot/prep-<today>` already exists, reuse it
   rather than creating a second one. A resumed run must fork from the same base as the run it
   resumes, or half the features sit on a base the other half cannot see.

Record for the report (schema v2.1 `prep` block): `features_generated`, `features_skipped_thin`,
`test_cmd_created`, and `prep_ref`. Then fall into Phase 0. Phase 0 still enforces the TOFU-trust
and gh-auth wall; Phase P grants neither.

**External-dependency check (G13, ADR-0060) is NOT a Phase P step.** It runs later, per feature,
at that feature's own Gate 2c inside the per-feature chain §3.3 drives — a plan's declared
dependencies do not exist until that feature's architect has run, which is after this phase. It is
named here because a BLOCK there reuses this section's skip vocabulary (mark `[~]`, append a
reason) via the same per-feature `skipped-features` note §3.3 describes, never the run-level
`needs-human` marker.

---

## 2. Phase 0 — Hard pre-flight (read-only, script-level)

Any failure writes an `aborted` report and stops. No dispatch, no push. Emit one line per check.

**The permission posture is not one of the checks in this section, and must not be added as one.**
It is checked in Phase M, above Phase P, because Phase P writes files and a blocking mode would
stall it before this section ran at all (ADR-0110). Adding a copy here would be a second answer to
"may this run start" — see `permission-mode-state.sh`'s header for why there is exactly one.

1. **Scope guard (first):** resolve `$PWD`. Every downstream action is scoped to it. If a later
   manifest names a `project_root` outside `$PWD`, abort (same rule as autopilot-build check 1).
2. **Git repo:** `git rev-parse --git-dir` succeeds.
3. **Opt-in marker:** `.claude/autopilot.yml` exists and sets `publish: true`. Absent or
   `false` → abort with "publish not opted-in for this repo; run stops at local commit, use
   autopilot-build instead."
   **A repo still carrying the pre-ADR-0127 name is DETECTED, never read (§D2.3).** Falling back to
   the old filename would let two files disagree about whether this repository has authorised
   unattended `git push`, and that disagreement is silent in the permissive direction.
   <!-- fence-contract: autopilot-optin -->
   ```bash
   # ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
   # the host shell. No `export` prologue — this body has no free variables. The terminator sits at
   # COLUMN 0 even though this fence is indented inside a numbered list item: an indented terminator
   # is swallowed into the here-document and destroys this fence's exit code silently. It is not a
   # formatting slip — do not tidy it.
   bash <<'FENCE_BASH'
   m="$PWD/.claude/autopilot.yml"
   legacy="$PWD/.claude/nightly-autopilot.yml"
   if [ ! -f "$m" ] && [ -f "$legacy" ]; then
     echo "✗ opt-in: found $legacy — this repo predates the ADR-0127 rename."
     echo "  The old name is not read as a fallback. Migrate, review the result, and commit it:"
     echo "    bash ~/.claude/hooks/autopilot-migrate.sh --root \"$PWD\""
     exit 1
   fi
   test -f "$m" || { echo "✗ opt-in: $m missing"; exit 1; }
   grep -qE '^[[:space:]]*publish:[[:space:]]*true[[:space:]]*$' "$m" || { echo "✗ opt-in: publish not true"; exit 1; }
FENCE_BASH
   ```
4. **PROJECT.md present:** `test -f PROJECT.md`. Phase P generates it from issues; if it is still
   absent (no prep source and none pre-existing) → abort ("no roadmap; add a `prep.issues_label` to
   the opt-in marker or create PROJECT.md").
5. **TOFU test-cmd trusted:** `.claude/test-cmd` is not `NONE`/placeholder and its SHA-pinned
   `(hash, normalized-root)` pair is in `~/.claude/state/stop-gate/trust` (same check as
   autopilot-build check 6). Never auto-grant. Phase P may have written the `.claude/test-cmd`
   file, but trust is still human: if untrusted, abort with the exact one-liner,
   "test-cmd not trusted — review `.claude/test-cmd` then run once:
   `bash ~/.claude/hooks/approve-test-cmd.sh \"$PWD\"`".
6. **hook_verified known (roadmap-wide, pre-flight):**
   <!-- fence-contract: autopilot-check-6 -->
   ```bash
   # ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
   # the host shell. Two measured divergences live in this body: the unmatched-glob `ls` below, which
   # zsh's `nomatch` declines to run at all, and `for _m in $_manifests`, which needs the word split
   # only bash performs on an unquoted expansion. `export` forwards this body's caller-bound free
   # variables. The terminator sits at COLUMN 0 even though this fence is indented inside a numbered
   # list item: an indented terminator is swallowed into the here-document and destroys this fence's
   # exit code silently. It is not a formatting slip — do not tidy it.
   export CLAUDE_PLUGIN_ROOT
   bash <<'FENCE_BASH'
   _manifests=$(ls "$PWD"/docs/manifests/*.manifest.yml 2>/dev/null)
   if [ -z "$_manifests" ]; then
     echo "note: no manifests exist yet (Phase P has not created any feature manifest). Each"
     echo "feature's manifest defaults hook_verified: false (safe Agent-tool fallback dispatch,"
     echo "ADR-0016) at manifest-init.sh creation time, so there is nothing to validate yet and"
     echo "this is not an abort condition. No global cross-run smoke-test record exists"
     echo "(ADR-0029 Section 1, 'Gap flagged for issue #34') -- hook-verify-workflow.sh is"
     echo "deliberately read-only and stateless; this check does not depend on one existing."
   else
     # The field-state helper. Two-tier resolution, same order project-conductor and commit use.
     # If NEITHER resolves the pre-flight aborts: this is a gate, and an infrastructure gap must
     # fail closed and loudly, never quietly fall back to a second copy of the logic (issue #195).
     if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/manifest-field-state.sh" ]; then
       _mfs="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/manifest-field-state.sh"
     elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/manifest-field-state.sh" ]; then
       _mfs="$HOME/.claude/skills/concept-to-code/scripts/manifest-field-state.sh"
     else
       echo "✗ hook_verified: manifest-field-state.sh not found in either location."
       echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
       exit 1
     fi
     _bad=0
     for _m in $_manifests; do
       # Four states, not two (issue #123, ADR-0075). `m.get('hook_verified')` returned None for a
       # field that is ABSENT and for one explicitly set to null, and an empty string when the file
       # could not be parsed at all — so a manifest older than the field was reported as corrupted,
       # and a manifest the check never read was reported as having a bad value.
       #
       # The helper REPORTS the state; the policy below is this call site's own and stays visible
       # here. autopilot-build check 7 reads the same field through the same helper and treats
       # ABSENT as an abort — opposite to the branch below, and both are right (ADR-0076 §D2).
       # Do not "reconcile" the two.
       _st=$(bash "$_mfs" "$_m" hook_verified 2>/dev/null)
       _rc=$?
       [ "$_rc" -eq 0 ] || _st="UNREADABLE"     # exit 2/3: it did not run, same operator action
       case "$_st" in
         'PRESENT|True'|'PRESENT|False')
           : ;;                                     # the two valid values
         'ABSENT|completed')
           echo "note: $_m has no hook_verified field and is completed — it predates the field"
           echo "  (ADR-0016 added it to manifest-init.sh afterwards). A completed chain's dispatch"
           echo "  mode cannot affect this run, so the documented default (false) applies. Not an abort."
           ;;
         'ABSENT|'*)
           echo "✗ hook_verified: $_m has no hook_verified field and is NOT completed"
           echo "  (current_step=${_st#ABSENT|}) — a chain still in flight whose dispatch mode is unknown."
           echo "  This is not the pre-schema case; re-init the manifest or set the field explicitly."
           _bad=1
           ;;
         'UNREADABLE'|'')
           echo "✗ hook_verified: $_m could not be read — the check DID NOT RUN on it."
           echo "  Either the YAML is unparseable or python3/PyYAML is unavailable. This is not the"
           echo "  same as finding a bad value; fix the file or the interpreter and re-run."
           _bad=1
           ;;
         *)
           echo "✗ hook_verified: $_m has hook_verified=${_st#PRESENT|} (must be true/false)."
           echo "  A value is present and is neither — the manifest is corrupted or was hand-edited."
           _bad=1
           ;;
       esac
     done
     [ "$_bad" -eq 0 ] || exit 1
   fi
FENCE_BASH
   ```
   (drives Workflow vs Agent-tool dispatch downstream, per manifest, exactly as before.)

   **Scope stays roadmap-wide, deliberately (ADR-0075 §D3).** Issue #123 raised narrowing the loop
   to the manifests of pending roadmap features. Rejected: that needs the PROJECT.md-feature →
   manifest mapping ADR-0030 already had to fix twice for suffix collisions, and a wrong mapping
   silently skips a manifest that matters. The absent-on-completed default removes the landmine
   without a lookup that can be wrong.
7. **`gh` authenticated:** `gh auth status` succeeds (needed to push and open PRs).
8. **CI + branch protection:** if `.github/workflows/ci.yml` is absent, drop the template
   (`~/.claude/templates/ci.yml` at runtime; source `staging/project-templates/ci/ci.yml`),
   substituting `__TEST_CMD__` with the trusted `.claude/test-cmd`, then run
   `~/.claude/hooks/set-branch-protection.sh`.

   **Then audit the WHOLE required set, not the `ci` context alone (issue #322, ADR-0114).** This
   step used to end *"verify the `ci` check is required on `main`"*, which was prose with no
   mechanism and named one context out of however many the branch requires — this repository's own
   `main` requires three, because `set-branch-protection.sh` unions exactly ONE into whatever is
   already there. A pre-flight that knows a third of the merge gate can pass while a PR the run
   opens is unmergeable.

   The authority is the **live** required set, derived, never a list declared in the opt-in marker:
   a declaration cannot lower what GitHub enforces, so one that disagrees is stale rather than
   lighter. A silently-added required check is caught by SATISFIABILITY instead — nothing produces
   it, so the audit aborts.

   <!-- fence-contract: autopilot-check-8 -->
   ```bash
   # ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
   # the host shell. No `export` prologue — this body has no free variables beyond `HOME`/`PWD`,
   # which every shell exports already. The terminator sits at COLUMN 0 even though this fence is
   # indented inside a numbered list item: an indented terminator is swallowed into the
   # here-document and destroys this fence's exit code silently. Do not tidy it.
   bash <<'FENCE_BASH'
   _rca="$HOME/.claude/hooks/required-checks-audit.sh"
   if [ ! -f "$_rca" ]; then
     echo "✗ check 8: required-checks-audit.sh not found at $_rca — the check DID NOT RUN."
     echo "  Run: bash staging/sync-to-claude.sh --apply"
     exit 1
   fi
   _out=$(bash "$_rca" --root "$PWD" 2>&1); _rc=$?
   printf '%s\n' "$_out"
   case "$_rc" in
     0) echo "✓ check 8: every required status check has a producer" ;;
     1) echo "✗ check 8: a required status check has no producer — a PR opened tonight would sit"
        echo "  pending forever and could not be merged in the morning."
        exit 1 ;;
     *) echo "✗ check 8: the audit DID NOT RUN (rc=$_rc). A roadmap does not start on an unknown"
        echo "  merge gate — an unread gate is not a clean gate."
        exit 1 ;;
   esac
FENCE_BASH
   ```

   **`rc=3` aborts, and that is deliberate.** The audit reports "could not look" separately from
   "found nothing wrong" precisely so this branch can exist; treating them alike is the defect this
   check was rewritten to close. **`PASS` means every required context has a PRODUCER, never that
   it will be green** — nothing at launch time can know whether tomorrow's markdown lints. That
   half is the morning report's per-context reconciliation in §4.

9. **Run scope resolves (issue #365, ADR-0129 §D7 fence 2):**

   **This is not the permission posture, and it is not the second check the header sentence above
   forbids.** That sentence stops a SECOND answer to "may this run start" from being added to this
   section; it does not cap the section at eight items. A ninth check answering a different question
   — which roadmap rows this run may touch — is exactly what the reworded sentence still allows.

   It resolves `--only`'s tokens against the `PROJECT.md` check 4, immediately above, has just
   asserted exists — a genuine dependency on check 4 having already run, not a repeated existence
   probe. A token that resolves to no row, or to more than one, aborts here, before any feature
   starts, naming the token: the same "fail fast and loudly" direction every check in this section
   already takes.

   <!-- fence-contract: autopilot-scope-resolve -->
   ```bash
   # ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
   # the host shell. `for _tok in $_toks` below needs the word split only bash performs on an
   # unquoted expansion — under zsh the comma-separated token list arrived as one word and a
   # multi-token `--only` resolved nothing. `export` forwards the six free variables Phase S hands
   # over; a plain shell variable does not survive the new process boundary. The terminator sits at
   # COLUMN 0 even though this fence is indented inside a numbered list item: an indented terminator
   # is swallowed into the here-document and destroys this fence's exit code silently. Do not tidy
   # either line.
   export _root _scope_source _scope_features _scope_only _dry_run _scope_preserved
   bash <<'FENCE_BASH'
   # Free variables: _root ($PWD), and _scope_source/_scope_features/_scope_only/_dry_run/
   # _scope_preserved from Phase S's SCOPE-PARSE line (source/features/only/dry_run/
   # scope_preserved -- ADR-0167 §D3/§D6, the last carrying scope-file-read.sh's own state token:
   # ABSENT/REUSABLE/SPENT/NOT-REUSABLE/MALFORMED/UNREADABLE). CHECKER: the caller branches on the
   # exit code, the opposite idiom from a REPORTER, which always exits 0 and signals through stdout
   # alone (ADR-0047 §D8 — this file names no fourth call site for that mechanism, so the contrast
   # is stated generically here, as Phase S's fence already does).
   if [ ! -f "$_root/PROJECT.md" ]; then
     echo "✗ scope: $_root/PROJECT.md not found -- the check DID-NOT-RUN"
     exit 3
   fi
   if [ ! -r "$_root/PROJECT.md" ]; then
     echo "✗ scope: $_root/PROJECT.md exists but is not readable -- the check DID-NOT-RUN"
     exit 3
   fi

   _sf="$_root/.claude/autopilot-state/scope"

   # REUSE branch (ADR-0167 §D3 point 2, §D6 REUSABLE, R-01). Phase S already decided this is a
   # reuse -- source=preserved only ever comes from a REUSABLE probe. Do not feed $_scope_only
   # through the token-resolution loop below: the file's own only= lines are exact roadmap-row
   # TEXT (ADR-0129 §D2), not comma-separated tokens, and re-resolving them matches nothing and
   # aborts the launch. Do not rewrite $_sf. published stays untouched -- ADR-0167 §D4 resets it
   # only when a FRESH scope is written, and this is not one.
   if [ "$_scope_source" = "preserved" ]; then
     _preserved_features=$(grep '^features=' "$_sf" 2>/dev/null | head -1 | sed 's/^features=//')
     _preserved_only=$(grep '^only=' "$_sf" 2>/dev/null | sed 's/^only=//')
     echo "SCOPE-RESOLVE: OK source=preserved (reusing $_sf, not re-resolved, not rewritten) features=$_preserved_features"
     if [ -n "$_preserved_only" ]; then
       printf '%s\n' "$_preserved_only" | sed 's/^/  only: /'
     else
       echo "  (preserved bound has no --only rows -- every roadmap row is in scope)"
     fi
     exit 0
   fi

   # STALE-FILE branch (ADR-0167 §D7, R-06). Phase S already probed this file and could not trust
   # it either; a file conductor-scope-gate cannot read would exit 3 -> needs-human on the first
   # candidate, so it is removed HERE, before the guard is armed. rm -f succeeds on a mode-000
   # file because removal needs write permission on the DIRECTORY, not the file -- this also fixes
   # the latent bug where the `>` redirect below silently fails on a mode-000 existing file.
   case "$_scope_preserved" in
     MALFORMED|UNREADABLE)
       if [ -e "$_sf" ]; then
         if rm -f "$_sf" 2>/dev/null; then
           echo "⚠ scope: preserved file $_sf was $_scope_preserved -- removed, falling back to normal resolution"
         else
           echo "✗ scope: preserved file $_sf was $_scope_preserved and could not be removed -- DID-NOT-RUN"
           echo "  Run: fix the permissions on $(dirname "$_sf") (or remove $_sf by hand), then relaunch"
           exit 3
         fi
       fi
       ;;
   esac

   _resolved=""

   # Zero --only tokens means EVERY roadmap row is in scope, never none (ADR-0129 §D1): the fence
   # branches on the list being empty rather than writing an empty only= line, because the two
   # readings of "empty" are the difference between an unscoped run and a run that does nothing.
   if [ -n "$_scope_only" ]; then
     _toks=$(printf '%s' "$_scope_only" | tr ',' ' ')
     for _tok in $_toks; do
       [ -n "$_tok" ] || continue

       # 1. Issue number first (ADR-0129 §D3). The needle carries the CLOSING PARENTHESIS: "(issue
       #    #29)" is not a substring of "(issue #293)" -- the literal ')' immediately after the
       #    digits is what stops the token "29" resolving to the "293" row.
       _matches=$(grep -F "(issue #$_tok)" "$_root/PROJECT.md" 2>/dev/null)

       if [ -z "$_matches" ]; then
         # 2. Full topic-slug, MATCH-ONLY (ADR-0129 §D3/A7). This is a second derivation of a value
         #    project-conductor's own prose also derives, and the two derivations can disagree -- but
         #    what is STORED below is the roadmap line's EXACT TEXT (§D2), never this slug, so a
         #    disagreement here can only fail to resolve a token. It can never select the wrong
         #    feature.
         _slug_hits=""
         while IFS= read -r _line; do
           [ -n "$_line" ] || continue
           # ROADMAP ROWS ONLY (issue #462). Without this guard the loop normalised EVERY line of
           # PROJECT.md, prose and markdown tables included, and `cut -c1-40` then made a table row
           # collide with the roadmap row it documents: a feature whose slug is exactly 40
           # characters ("kindle-login-with-persistent-web-session") truncates to the same slug as
           # a "| Feature | Spec | ADR |" row describing it, so the token resolved to two lines and
           # this check aborted as ambiguous. Observed on a live autopilot run, 2026-08-17.
           # The refusal was right and the population was wrong — CLAUDE.md rule 18: a scan is
           # satisfied by the whole population it searches, not by the part it meant. Only a
           # "- [ ]"/"- [x]"/"- [~]" line is a roadmap row, so nothing else belongs in the
           # comparison. The `sed` below strips that prefix when present and passes anything else
           # through unchanged, which is precisely why every other line reached the cut.
           case "$_line" in
             '- ['*) : ;;
             *) continue ;;
           esac
           _title=$(printf '%s' "$_line" | sed -E 's/^- \[[ xX~]\][[:space:]]*//')
           _cslug=$(printf '%s' "$_title" | tr '[:upper:]' '[:lower:]' \
             | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40 | sed -E 's/-+$//')
           if [ "$_cslug" = "$_tok" ]; then
             if [ -z "$_slug_hits" ]; then _slug_hits="$_line"; else _slug_hits="$_slug_hits"$'\n'"$_line"; fi
           fi
         done < "$_root/PROJECT.md"
         _matches="$_slug_hits"
       fi

       if [ -z "$_matches" ]; then _n=0; else _n=$(printf '%s\n' "$_matches" | wc -l | tr -d ' '); fi
       case "$_n" in
         0)
           echo "✗ scope: --only token '$_tok' resolves to no roadmap row (matched neither an issue number nor a topic-slug)"
           exit 1
           ;;
         1)
           _title=$(printf '%s' "$_matches" | sed -E 's/^- \[[ xX~]\][[:space:]]*//')
           if [ -z "$_resolved" ]; then _resolved="$_title"; else _resolved="$_resolved"$'\n'"$_title"; fi
           ;;
         *)
           echo "✗ scope: --only token '$_tok' matches more than one roadmap row -- ambiguous, refusing to guess:"
           printf '%s\n' "$_matches" | sed -E 's/^- \[[ xX~]\][[:space:]]*/    /'
           exit 1
           ;;
       esac
     done
   fi

   if [ -n "$_resolved" ]; then
     _rn=$(printf '%s\n' "$_resolved" | wc -l | tr -d ' ')
   else
     _rn=0
   fi

   echo "SCOPE-RESOLVE: OK source=$_scope_source features=$_scope_features resolved=$_rn"
   if [ -n "$_resolved" ]; then
     printf '%s\n' "$_resolved" | sed 's/^/  only: /'
   else
     echo "  (no --only tokens -- every roadmap row is in scope)"
   fi

   if [ "$_dry_run" = "true" ]; then
     echo "scope: --dry-run -- resolution printed above, no scope file written"
     exit 0
   fi

   mkdir -p "$_root/.claude/autopilot-state"
   {
     echo "source=$_scope_source"
     echo "features=$_scope_features"
     if [ -n "$_resolved" ]; then
       printf '%s\n' "$_resolved" | sed 's/^/only=/'
     fi
   } > "$_sf"
   echo "scope: wrote $_sf"

   # published reset (ADR-0167 §D4): remove it exactly when a FRESH scope is written here -- never
   # on --dry-run (short-circuited above) and never on REUSE (already exited above).
   rm -f "$_root/.claude/autopilot-state/published" 2>/dev/null
   exit 0
FENCE_BASH
   ```

   On exit 0, the scope file at `<root>/.claude/autopilot-state/scope` is written and `published` is
   removed with it — or, under `--dry-run`, only printed, matching Phase S's routing paragraph — or,
   under a REUSE (`source=preserved`), neither is touched at all: the preserved bound is announced
   as-is (ADR-0167 §D3/§D4). On exit 1 the message names the token(s) that did not resolve or
   resolved ambiguously, and no scope file is written. On exit 3 the check DID NOT RUN: either no
   readable `PROJECT.md` (distinct from exit 1's "read it, found nothing"), or a `MALFORMED`/
   `UNREADABLE` preserved file that could not be removed before a fresh write (ADR-0167 §D7).

On all checks passing:
```
autopilot · pre-flight PASSED · arming guard, starting roadmap...
```

No `AskUserQuestion` is called after this point.

**Permission posture (ADR-0020 CC 2.1.186 note).** An unattended dispatch is only safe when the
Step-5 allowlist covers every tool the subagents use; an out-of-allowlist tool raises a prompt that
stalls the run. Keep hooks enabled or `/goal` cannot evaluate and the guard cannot fire.

---

## 3. Phase 1 — Arm and drive the roadmap

### 3.1 Arm the autopilot state

The marker **records who armed it and when** (issue #321, ADR-0112). Its *presence* is still what
activates the guard — contents change nothing about that — but a marker that names its owner is the
difference between a stale one being diagnosable and being a mystery.

```bash
mkdir -p "$PWD/.claude/autopilot-state"
# activates autopilot-guard for this repo, and records the owner so a stale marker is identifiable
printf 'session_id=%s\nstarted_at=%s\n' \
  "${CLAUDE_CODE_SESSION_ID:-}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$PWD/.claude/autopilot-state/active"
: > "$PWD/.claude/autopilot-state/build-status"      # cleared; set GREEN/RED after each test run
```

`started_at` for the morning report is read back from that marker. **Do not invent a separate file
for it.** Before ADR-0112 this step said only *"record `started_at`"* without naming a location, and
an orchestrator improvised `.claude/autopilot-state/started-at` — a real file, in this repository right
now, written by nothing in the codebase and read by nothing either. A value with no specified home
gets one anyway, chosen by whoever runs the step.

**This marker outlives a run that dies.** Phase 2 is the only place that removes it, and a session
killed by context exhaustion, a crash, or the human pressing stop never reaches Phase 2 — so the
guard stays armed in the human's own later sessions. That is not a defect in the guard, which is
right to fail closed; the exit is `autopilot-disarm.sh`, documented in the RUNBOOK under
*"The guard is still armed and I cannot push"*.

### 3.2 Print the `/goal` template

Print this for the human to paste (it keys off the status line the publish step prints, since the
`/goal` evaluator cannot call tools):

```
/goal "Every feature in PROJECT.md is [x], committed on feat/*, pushed, and a PR is open,
as shown by a AUTOPILOT-PUBLISH line for each feature and no AUTOPILOT-GUARD HALT line.
Or stop after <N> turns."
```

### 3.3 Drive project-conductor in roadmap-autopilot

Invoke `Skill(skill="project-conductor", args="autopilot --fork-from <$_prep_ref>")`, passing the
prep ref Phase P step 4 recorded. **Every feature branch forks from that ref, and every feature PR
still targets `main` (issue #364, ADR-0127 §D4).** The two are different questions and were being
answered by one value: forking from `main` leaves each feature without the SPECs Phase P wrote, and
forking from the previous feature's tip stacks PR *N* on features 1..*N*.

The conductor (roadmap-autopilot mode) pre-authorizes
every pending feature, skips the per-feature Step 3 gate, and for each feature:
architecture (Gate 2, including Gate 2c's G13 external-dependency check — ADR-0060, resolved via
`~/.claude/hooks/external-dependency-check.sh`, the same script `concept-to-code/SKILL.md` Gate 2c
calls) → implement → review-triage-fix → local commit → `publish-feature.sh` (guard fires) → print
the `AUTOPILOT-PUBLISH` status line → advance to the next `[ ]`.

**Marker contract (read by `autopilot-guard`) — two markers, two different scopes, since ADR-0060
§D3 fixed a pre-existing latent defect (issue #114):**

- **Run-level `needs-human`** (`<root>/.claude/needs-human`): something is wrong with the *run*.
  On a feature that fails to reach `completed` for an unknown-state reason — a coder crash, an
  anti-test-weakening halt (ADR-0047 §D5, below) — the conductor writes this marker, and
  `autopilot-guard` blocks that publish and **every subsequent one**. `rtf-blocker` is the other
  run-level halt and behaves the same way: once either marker is set, the guard blocks every
  subsequent publish, so a HALT stops the whole roadmap rather than skipping one feature. A halted
  feature keeps its local commit but has no ready PR. (`token-budget` was a third run-level halt;
  it is removed — see below.)

  **`rtf-blocker` is deliberately unproduced, and the reason is measured, not a deferral**
  (issue #365, ADR-0129 §D6): `concept-to-code` Gate 5's autopilot default is "Skip review", and
  `project-conductor` invokes `concept-to-code` for every feature on both branches — the
  `_autopilot=true` path and the `_autopilot=false` path — never `autopilot-build`. So no review
  cycle runs during an unattended roadmap run, and a producer inside `review-triage-fix` could
  never fire on the one path where the guard that reads this file exists.

  **`token-budget`'s verdict is deliberately not transferred to `rtf-blocker`, and this paragraph
  exists so a future reader does not "tidy" the second away for consistency with the first.** The
  two cases differ in kind: `token-budget`'s halt was **structurally unable to work** — evaluated
  after the only thing it could have stopped — whereas `rtf-blocker`'s halt **would work correctly
  the moment something wrote it**. Removing a mechanism that cannot work is a correction; removing
  one that works and is merely unreached is deleting a safeguard because the path it guards is
  currently unused. `VCS-010` in `TODO.md` and PROJECT.md Phase 11 Wave 1 both asked for "a
  producer or its honest removal"; the honest answer is the third one — the mechanism is sound,
  the reason it is unreached is a larger finding about unattended review (see ADR-0129's *Findings
  recorded, not fixed*), and this file now says so.
- **Per-feature `skipped-features`** (`<root>/.claude/autopilot-state/skipped-features`,
  append-only): this *one* feature cannot proceed for a known, contained reason, and the roadmap
  continues to the next `[ ]`. **Five writers**, the last two added by ADR-0111 (issue #324):
  `spec-from-issue`'s thin-issue skip (Step 2), `spec-from-issue`'s injection-suspect skip
  (Step 1.5, ADR-0059), Gate 2c's G13 unprovisioned-dependency skip (ADR-0060 §D2 — see the
  "Marker" prose in `concept-to-code/SKILL.md`'s Gate 2c Autopilot-default block; it fires at each
  feature's own Gate 2c inside the per-feature chain this section drives, not literally inside §1.5
  Phase P, since dependencies are not declared until that feature's architect has run — noted here
  because it is this phase's skip mechanism being reused), `project-conductor` Step 4's
  **no-generated-SPEC skip**, and `project-conductor` Step 5 branch C's **`TERMINAL` entry-state
  skip**. `autopilot-guard.sh` never reads this file: its presence has no effect on `--check`, by
  design (see the script's own v1.3 header comment). Every writer also marks the feature `[~]` in
  PROJECT.md with the same reason. The morning report lists these under `features_skipped[]`
  (schema v2.2, §4), separate from `guard_halts[]`.

  **Branch C is a split, not a downgrade** (ADR-0111): only a `TERMINAL` entry state — a chain that
  reached a *decided* end, its reason recorded in the manifest — takes the skip path. Every other
  state a feature can be left in is still a run-level `needs-human` halt, including the
  anti-test-weakening halt described below, which never transitions and so is never `TERMINAL`.

Before this ADR (issue #114), both writer classes above shared the run-level `needs-human` file, so
one thin issue silently halted every other feature in the roadmap — a latent defect, not a design
choice. If you find prose or a manifest describing a single shared marker, it predates this fix.

A Step 5 anti-test-weakening halt (ADR-0047 §D5) means the feature never reaches `completed` for an
unknown-state reason — the fix cycle touched something and the outcome cannot be trusted — so it
stays a **run-level** halt: the conductor writes `needs-human` exactly as it does for any other
feature that fails to complete, and the guard blocks that publish and every subsequent one. The
reason is recorded in `guard_halts[]` in the morning report. This skill runs no scan of its own —
detection happens once, inside `concept-to-code` Step 5, and this skill only surfaces the resulting
halt.

---

## 4. Phase 2 — Morning report and disarm

On every exit path, write `<project_root>/.claude/autopilot-report.json` (schema v2.2: v2.1 fields
plus `features_skipped[]`, ADR-0060) with per-feature
`status`, `branch`, `commit_sha`, `pr_url`, `ci_status`, `guard_halt`, the `guard_halts[]` roll-up,
`features_skipped[]` (read from `<project_root>/.claude/autopilot-state/skipped-features`, one entry
per line, `{feature, reason}` — additive and distinct from `guard_halts[]`: a skip did not stop the
roadmap, a halt did — §3.3 "Marker contract"), and `spend` (from the `/goal` overlay). Set
`ended_at` via `date -u`.

Also, per feature, `test_count_delta`, `deleted_lines`, `iteration_count`, `elapsed_wall_seconds`
(ADR-0064, issue #118) — additive, conditional-if-present, no schema bump: summed from that
feature's own `task_metrics` array in its `step5-report.json`, when present. These are METRICS,
not findings (ADR-0064 §D2): nothing in this Phase branches on them, they are never surfaced as
requiring action, and a feature whose `step5-report.json` carries no `task_metrics` leaves all
four fields absent on that feature entry — never `0` (ADR-0064 §D3).

The report also carries an additive `scope` object (issue #365, ADR-0129 §D10 — schema v2.2, no
version bump, the block is additive):

```json
"scope": {
  "source": "arguments",
  "requested": { "features": 2, "only": ["…", "…"] },
  "delivered": 2,
  "remaining_in_roadmap": 29,
  "turns_per_feature": [ { "feature": "…", "turns": 48 } ]
}
```

`delivered` is read from `published` (a count of its lines) and `source`/`requested` from `scope`
— **both before the disarm**, which deletes both. This section already runs prior to the disarm
call below; stating the dependency here matters because two files whose reader sits a few lines
above their deleter is exactly the ordering that gets "tidied" by a later edit.

This field is mechanical: the count of `- [ ]` rows in `PROJECT.md`, taken **at report time**, not
at run start.

**`turns_per_feature` is an orchestrator self-report, and is labelled as one.** No per-turn counter
is exposed to a skill; it is derived by the orchestrator counting its own turns between the
`AUTOPILOT-PUBLISH` lines Phase 1 already prints. ADR-0047 §A3's rule against trusting a
self-report does not apply here (ADR-0073's reasoning): that rule is about a self-report a **gate**
acts on, and this figure feeds a human re-deriving a turn budget — a disclosure feeding a human
decision can only add information, never remove a check. `turns_per_feature` is **never read by a
gate**.

Disarm the guard. This clears the whole transient set, not just the marker (ADR-0112): a
`build-status` left reading `RED` halts the in-script `--check` gate **regardless of the marker**,
and a `needs-human` left behind halts every publish — so removing only `active` leaves the next
session blocked by a file the disarm appeared to have handled.

```bash
bash ~/.claude/hooks/autopilot-disarm.sh --completing "$PWD"
```

**`--completing` is not decoration, and this step used to be impossible without it.** The bare form
is the RECOVERY path: it refuses the session that armed the marker, because a session cannot prove
a run it does not own is over. This is that session. So Phase 2 was refused on every completed run,
and the refusal it got said *"finish the run, Phase 2 clears the marker"* while Phase 2 cleared the
marker by calling this very script. The marker outlived every run through the primary path rather
than through a crash — the failure `autopilot-disarm.sh` exists to remove, reintroduced at the one
place that was assumed to be safe.

`--completing` is the exact mirror: the owner is the permitted caller and a *foreign* session is
the one refused, because a session that did not arm the marker has no standing to declare the run
finished. So a refusal (exit 1) on this path means the marker was rewritten mid-run **by a
different session** — worth reporting rather than working around. Exit 3 means the disarm did not
run: report it, and do not treat the guard as cleared.

**Do not replace this with `rm -f`.** The plain remove is what this step used to be, and it is how a
`RED` build-status from a finished run reaches the next morning still halting things.

Emit one terminal line:
```
autopilot · <status> · report: <project_root>/.claude/autopilot-report.json
```

Reconcile CI where possible: for each open PR, `gh pr checks <url>` maps **every required context**
to `green|red|pending`.

**`ci_status` is the AGGREGATE over the required set, not one check's colour (issue #322,
ADR-0114).** `red` if any required context is red, `pending` if any is pending, `green` only when
all are green, `unknown` when CI could not be queried. On a repo requiring a single check this is
byte-identical to what it has always been; on one requiring three it is the difference between a
correct value and a misleading one. This repository requires `markdownlint`, `links` and `ci`, and
before this a red `markdownlint` — real, PR #317 — reported as `green` and surfaced only when the
human tried to merge.

The per-context detail goes in an additive sibling, `required_checks`, so nothing that reads
`ci_status` has to change:

```json
"ci_status": "red",
"required_checks": { "ci": "green", "markdownlint": "red", "links": "green" }
```

The required set is the same live list pre-flight check 8 audited — read it with
`bash ~/.claude/hooks/required-checks-audit.sh --root "$PWD"`, whose `required:` lines carry it.
Do not re-derive it from `gh pr checks` output: that reports every check that ran, required or
not, and aggregating over those would let a non-blocking red check report the PR as unmergeable
when it is not.

---

## 5. Safety invariants

- **No merge, ever.** No code path calls `gh pr merge`, `--merge`, or enables auto-merge.
- **No force-push, no main.** Publish targets `feat/<slug>` only; the settings deny list blocks
  force-push; `publish-feature.sh` refuses a slug that resolves to `main`/`master`.
- **Why "no merge" is load-bearing, not a convenience (ADR-0059 §D2).** Phase P (§1.5) can turn a
  GitHub issue body into this run's design input, and an issue body is attacker-controllable text.
  Prompt fencing and the injection scan (ADR-0059 §D1/§D3) are a mitigation, not a boundary — the
  mechanism reading that text is the same mechanism an attacker is trying to redirect. The actual
  boundary is that this path cannot merge, force-push, or write `main`; a pushed branch and an open
  PR are reversible, and the human reviews before either stops being true. **Granting merge
  authority to this path would turn every issue body into a remote code execution vector**: a
  malicious issue could get its own code merged to `main` overnight with no human in the loop,
  using this skill's own commit-and-push privileges to do it. Do not add merge authority here
  without addressing that first.
- **Opt-in per repo.** Absent or `publish: false` marker → the skill never pushes; use
  `autopilot-build` for a local-commit-only run.
- **Guard fails safe.** On any halt condition or internal guard error, the publish is blocked and the
  PR is left not-ready. Nothing broken looks mergeable.
- **Hooks stay active.** `stop-gate.sh`, `pre-flight-pattern-enforce.sh`, `protect-files.sh`,
  `db-backup-guardrail.sh`, and `autopilot-guard.sh` all fire. Autopilot suppresses human prompts, not
  safety mechanisms.
- **TOFU never auto-granted.** Pre-flight reads the trust file; it never writes it.

---

## 6. Out of scope (v1)

- Auto-merge on green — rejected in ADR-0022 (Alt A); the morning merge is the human checkpoint.
- Cron scheduling (`CronCreate`) — wrap once the Phase 4 smoke test passes.
- CI reconciliation beyond a single `gh pr checks` pass — a watcher that waits for CI to finish is
  deferred; the report records `pending` if CI has not settled.
