# ADR-0133 — A bash fence executes under bash, not under the host shell (issue #394)

- **Status:** Accepted
- **Date:** 2026-08-09
- **Issue:** #394
- **SPEC:** `docs/specs/394-skill-fences-rely-on-word-splitting.spec.md`
- **Supersedes:** nothing. **Amends:** ADR-0083's fence contract, by adding an execution-shell
  clause to it. **Related:** ADR-0132 (the other half of "a fence is just text"), ADR-0129
  (the bound this defect discarded), ADR-0061 (the H4 gate this defect inverts).

---

## Context

A bash fence in a `SKILL.md` is executed by whatever shell the `Bash` tool call runs under. On this
machine that shell is **zsh 5.9**, and the fence was written and tested for **bash**.

zsh does not word-split unquoted parameter expansions. So `bash "$_sap" $_args` — the line
`autopilot` Phase S uses to hand `--features 1 --only 293` to its parser — passes **one** argument
where bash passes four. The parser's skip-anything arm discards the single unrecognised token in
silence, `scope-args-parse.sh` reports no bound, and the run proceeds over **every** pending roadmap
row. The fence's own comment says the line is *"UNQUOTED on purpose: this reproduces the word split
the moved `set --` performed"*. It reproduces nothing of the sort under zsh.

**This is ADR-0132's failure shape reached by a different route.** There, the renderer rewrote the
fence before the model saw it: the text was not the text. Here the text is intact and **the
interpreter is not the interpreter**. Both defeat ADR-0083's whole mechanism, which rests on the
assumption that what a test executes is what the run executes.

**The harness executes extracted fences under `bash`** (`run_fence` ends `bash "$_s"`). That is
exactly why every fence test is green while the live path is broken, and why no test that *reads* a
file could ever have caught it. A guard cannot observe an interpreter it does not invoke.

**The defect predates #385.** The pre-ADR-0132 form was `set -- $_args`, which fails identically
under zsh (measured: `argc=1`). ADR-0129's `--features` bound has therefore **never been applied on
this machine**, from its first run onward. Any prior claim that an `autopilot` run was bounded by
`--features` is a claim about a mechanism that was not running. (R-11.)

---

## Measured facts

Everything in this section was produced by **execution**, on 2026-08-09, on this machine:
zsh 5.9 (arm64-apple-darwin25.0), GNU bash 3.2.57(1)-release, macOS, CC 2.1.226. It is
host- and build-stamped and must be re-measured, never re-cited, after a major bump.

### The divergence classes, confirmed differentially

The same script run under both shells:

| Class | Construct | bash 3.2 | zsh 5.9 |
|---|---|---|---|
| **C1a** word splitting, argument | `bash -c 'echo $#' _ $_args` | `argc=4` | `argc=1` |
| **C1b** word splitting, `for` | `for t in $_args` over four words | 4 iterations | 1 iteration |
| **C1c** word splitting, `${v:+…}` | `cmd ${_troot:+--tests-root "$_troot"}` | `argc=2` | `argc=1` |
| **C2** unmatched glob | `ls /nonexistent/*.yml` | pattern passed to `ls` | `no matches found`, **command never runs** |
| **C3** `echo` escapes | `echo 'a\tb'` | literal `a\tb` | a TAB |

C3 appears in no fence today and is listed because it is a member of the class, not because it is a
site. The class is open-ended: `MULTIOS`, `KSH_ARRAYS`, `$0`, `[[ =~ ]]` capture variables,
`printf %q`, `local`/`typeset` scoping and more all differ. **That open-endedness is the argument
for removing the class rather than the instances.**

### The corpus

| Quantity | Measured 2026-08-09 | Previously recorded |
|---|---|---|
| staged `SKILL.md` files | **30** | 30 (ADR-0132) |
| bash fences in them | **162** | 162 (ADR-0132); 138 (ADR-0107, for #206) |
| `fence-contract` declarations | **32** | 18 (ADR-0107) |
| `fence-illustration` declarations | **1** | 1 |
| unmarked fences | **129** | — |

ADR-0107's 18 is not wrong; it is a snapshot of its moment. **Re-derive, never cite.**

### The divergent sites — 15 genuine records across 14 fences, from a committed instrument

The design-time table was produced by hand and reported **14 findings across 13 fences with 2 false
positives**. It has been re-derived by driving `fence-shell-divergence-scan.sh` over all 162 fence
bodies, with `fence-contract-coverage.test.sh`'s `enumerate_fences`/`fence_body` pair as the single
enumerator. **The count moved; the population did not** — every record the drive added falls inside
a fence that was already in the population or already outside it, so 32 ∪ 9 = 41 is unchanged.

| | design-time (by hand) | committed scanner |
|---|---|---|
| records emitted | 14 | **24** |
| distinct fences with ≥ 1 record | 13 | **17** |
| genuine records | 14 | **15** |
| genuine fences | 13 | **14** |
| false-positive records | not counted per record | **9** |
| fences carrying **only** false-positive records | 2 | **3** |

**All fourteen design-time rows reproduce**, byte-for-byte, at the same body line. Genuine records,
five per class:

| Class | Scanner | Skill | Fence | Marker | Line |
|---|---|---|---|---|---|
| C1a | `W-arg` | `autopilot` | @111 +27 | `autopilot-scope-args` | `_sap_out=$(bash "$_sap" $_args)` |
| C1a | `W-arg` | `project-conductor` | @52 +21 | `conductor-step0-args` | `_ca_out=$(bash "$_ca" $_args)` |
| C1a | `W-arg` | `claude-md-slim` | @169 +11 | *(unmarked)* | `$DUP_ARGS \` |
| C1c | `W-arg` | `concept-to-code` | @1865 +6 | *(unmarked)* | `${_troot:+--tests-root "$_troot"}` |
| C1c | `W-arg` | `concept-to-code` | @1887 +6 | *(unmarked)* | `${_troot:+--tests-root "$_troot"}` |
| C1b | `W-for` | `autopilot` | @444 +23 | `autopilot-check-6` | `for _m in $_manifests` |
| C1b | `W-for` | `autopilot` | @576 +22 | `autopilot-scope-resolve` | `for _tok in $_toks` |
| C1b | `W-for` | `commit` | @100 +4 | *(unmarked)* | `for _inc in $include_paths` |
| C1b | `W-for` | `commit` | @228 +9 | *(unmarked)* | `for _f in $staged $tracked_modified $untracked` |
| C1b | `W-for` | `commit` | @479 +10 | *(unmarked)* | `for _inc in $include_paths` |
| C2 | `G-glob` | `autopilot` | @444 +1 | `autopilot-check-6` | `ls "$PWD"/docs/manifests/*.manifest.yml` |
| C2 | `G-glob` | `project-conductor` | @97 +6 | *(unmarked)* | `ls -t …/????-??-??-"$_slug".manifest.yml` |
| C2 | `G-glob` | `project-conductor` | @324 +6 | *(unmarked)* | *(same lookup, second copy)* |
| C2 | `G-glob` | `project-conductor` | @558 +6 | *(unmarked)* | *(same lookup, third copy)* |
| C2 | `G-glob` | `project-conductor` | @444 +10 | `conductor-step4-nospec-skip` | `ls "$_root"/docs/specs/"$_issue"-*.spec.md` |

**The fifteenth row is new, and it is a genuine site the hand pass missed** —
`conductor-step4-nospec-skip`, a **fourth** copy of the same unmatched-glob lookup, inside a declared
contract. It changed no count because that fence was already in the population as a declaration;
had it been unmarked it would have been the tenth population entrant. The hand pass found the three
copies that share a variable name (`_cand`) and missed the one that does not (`_spec`) — which is
the argument for a committed instrument rather than a careful reading, stated as a receipt rather
than as a principle.

**Classes with zero records across all 162 fences:** `W-set`, `E-echo`, `B-builtin`, `B-var`,
`B-declare`, `A-array`. C3 and the four cheap bash-only probes are class members with no site today.
`W-set` returning zero is the expected post-ADR-0132 state: that idiom was the pre-#385 form.

**Four sites the issue's own scanner could not see**, because it matched `for X in $VAR` and
`set -- $VAR` only: `conductor-step0-args` (the same fail-open shape as Phase S, in a second skill),
`claude-md-slim` (`$DUP_ARGS` must split into four words or `content-union-check.sh` reads the whole
string as its `<original>` positional — ADR-0044's usage error, produced by the shell), and the two
`concept-to-code` `${_troot:+…}` sites, which feed ADR-0048's **merge-blocking** requirement-coverage
gate an unrecognised single argument.

**Failure directions differ, and only one of them is quiet.** The Phase S site fails **open**. The
`commit` sites fail **closed and wrongly**: `commit/SKILL.md`'s H4 test-diff gate (ADR-0061 §D1)
receives one blob under zsh and classifies **every** changed file as a test file — observed live on
2026-08-08 and initially misattributed to an orchestrator scripting error. The **four**
`project-conductor` C2 sites are **divergent in mechanism and equivalent in outcome today**. Probed
under both shells rather than argued: bash runs `ls` against the literal pattern, zsh's `nomatch`
declines to run it, and in both the variable ends empty, the script continues, and the exit code is
preserved. **One clause of the earlier phrasing was wrong and is corrected here: `2>/dev/null` does
not suppress zsh's diagnostic.** The redirection belongs to the `ls` that never runs, so
`no matches found: …` reaches the script's stderr unredirected — a visible difference on a path
whose outcome is identical. They are in the population because the class is present, not because a
symptom is.

**Nine false-positive records across five fences**, every one an instance of a declared blind spot
except the last, which is a blind spot nobody had declared:

| Records | Fence | Cause |
|---|---|---|
| 1 (`W-arg` +5) | `autopilot-build-check-3` | a python comprehension inside a `python3 -c "…"` string spanning several lines — the multi-line-quoted-string blind spot. Design-time false positive 1 of 2. |
| 4 (`W-arg` +13/+14/+18/+24) | `concept-to-code` merge-back @1394 | the single declared **illustration**, whose `<base-fork halt: …>` pseudo-code does not parse as bash. Design-time false positive 2 of 2. Outside the population by §D3. |
| 1 (`G-glob` +71) | `autopilot-scope-args` @111 | an interior line of a multi-line single-quoted `awk` program (`/^scope:[[:space:]]*$/ { … }`) — same blind spot, in a fence that also carries a genuine record. |
| 2 (`W-arg` +12/+31) | `commit` @228 | continuation lines of `test_files="$test_files⏎$_f"` — same blind spot, same fence-with-a-genuine-record shape. |
| 1 (`G-glob` +14) | `autopilot-build-check-1` | **a blind spot not previously declared.** `"$cwd_n"/*)` is a real `case` arm, and `is_case_arm` disqualifies any prefix containing whitespace, `=`, `$`, `(`, `)`, `;`, `&` or a backtick — `$` is the one that fires here, so a case pattern built from a **variable** is not recognised as one and its `*` reads as a command-word glob. This is the *reverse* of the declared case-arm blind spot, which says a genuine glob shaped like a case arm is missed. Probed under both shells: `case` pattern matching is not filename globbing, `nomatch` does not apply, and the three-way fixture gives identical results. |

The fifth entry is a **new measured limit of the instrument**, recorded here rather than folded into
§Consequences/Negative, because the scanner's header quotes that paragraph verbatim and a silent
edit would leave a quote disagreeing with its source — the ADR-0042 shape. The header must absorb
this sentence the next time `staging/` is edited; until then its blind-spot list is a floor.

### The population and the R-12 boundary, counted rather than asserted

Both numbers come from the same drive, printed as a subtraction over two independently counted
quantities rather than stated:

| Quantity | Measured |
|---|---|
| bash fences in staged `SKILL.md` | **162** |
| `fence-contract` declarations | **32** |
| `fence-illustration` declarations | **1** |
| unmarked fences | **129** |
| divergent **declared** fences | 7 |
| divergent **unmarked** fences | **9** |
| divergent **illustration** fences | 1 *(excluded by §D3)* |
| **population** = 32 declarations ∪ 9 unmarked-divergent | **41** |
| **outside the population (R-12)** = 162 − 41 | **121** |

The nine unmarked entrants, in full: `claude-md-slim` @169; `commit` @100, @228, @479;
`concept-to-code` @1865, @1887; `project-conductor` @97, @324, @558. Three of the nine are the
`commit` fences R-03 gives markers to, so after Task 5 the split reads 35 declarations ∪ 6 unmarked
and the population total is unchanged.

### The outbound direction — what a wrapped fence stops being able to hand on

The design-time analysis measured only the **inbound** direction (a fence's own free variables,
which D1 rule 3 forwards with `export`). A wrapped body also runs in a subprocess, so a variable it
*binds* dies at the closing terminator. That direction was measured the same way: for each of the 41
population fences, every variable it binds, matched against every later reference in the same
`SKILL.md` that the consuming context does not itself rebind. 42 raw hits, of which 21 are a local
scratch name (`_rc`, `_out`, `_cand`, `_mfs`, `_mes`) that the consuming fence rebinds independently
and which therefore never crosses a boundary at all.

**The consumer is often prose, not a later fence**, and a fence-pair sweep is structurally blind to
that half. Both are listed:

| Skill | Binder | Consumer | Variable(s) | Consumer kind |
|---|---|---|---|---|
| `autopilot-build` | @58 check 1 | @207 check 6 | `project_root` | fence |
| `autopilot-build` | @179 check 4 | @191 check 5 | `plan` | fence |
| `commit` | @100 Step 1 | @479 staging | `include_paths` | fence |
| `concept-to-code` | @1865 | @1887 | `_troot`, `_out`, `_rc` | fence |
| `concept-to-code` | @1173 | batch-dispatch policy | `openers`, `tasks`, `orc` | **prose, 925 lines later** |
| `project-conductor` | @52 Step 0 | @212, @286, @389, @594 | `_autopilot`, `_fork_from`, `_scripts` | fence + prose |
| `project-conductor` | @97, @324, @558 | the next prose line | `_manifest` | **prose, adjacent** |

Three of these are worth naming individually.

- **`concept-to-code` @1865 → @1887 is the tightest**, and both halves are unmarked population
  entrants Task 7 wraps: the gate binds `_troot`, `_out` and `_rc`, and the auto-repair retry reads
  all three. Wrapping the two independently severs all three at once, inside ADR-0048's
  merge-blocking gate.
- **`project-conductor` @97 / @324 / @558 bind `_manifest` and print nothing.** The consumer is the
  instruction on the line immediately after the closing fence — *"Read `current_step` from
  `$_manifest`"* — in all three copies. These are the three unmarked C2 sites Task 7 wraps, so the
  rewrite and the wrapper land in the same task by construction.
- **`project-conductor` @52 declares a handoff it provides no channel for.** It binds `_autopilot`,
  `_fork_from` and `_scripts` and its only `echo`s are `DID-NOT-RUN` messages, so there is no success
  token. The consuming fences @212/@286/@389 declare `_autopilot`/`_fork_from` as *"bound by the
  orchestrator"*, which is the right contract with nothing implementing it; `_scripts` at @594 is not
  declared anywhere. Today this works because the fences share a shell. Under the wrapper it does
  not, and the declaration will read as if it always did.

**Already mediated, and the model the rest should copy: `autopilot` Phase S.** It binds
`_source`/`_features`/`_only`/`_dry_run` and prints `SCOPE-PARSE: OK source=… features=… dry_run=…`,
with the prose directly below saying the line is authoritative and naming each field the orchestrator
carries. `autopilot-scope-resolve` @576 then declares those four as free variables *"from Phase S's
SCOPE-PARSE line"*. Producer prints, contract names the fields, consumer declares where they come
from — that is D4 satisfied, in the file, before this ADR asked for it.

**Excluded as mediated:** `concept-to-code` @82 → @200 (`_man`, `_root` — the consumer declares both
orchestrator-bound and the binder derives them from the `<project-root>`/`<topic-slug>` placeholders
the orchestrator substitutes) and `project-conductor` @97/@324 → @286/@505/@711 (`_slug`, the same
placeholder). `project-conductor` @52 → @97 (`_root`) is `$PWD`, re-derivable anywhere, though @97
carries no free-variable declaration saying so.

**The sweep's own limit, found by tripping over it.** A 25-line window after each fence reported the
paragraph *explaining* `$tasks` and `$openers` and missed the paragraph *using* them, 925 lines
away — rule 12 inside the measurement rather than inside an assertion. The table above comes from a
whole-file sweep for that reason. It still stops at the file boundary: a variable a fence binds and
a *different* skill consumes would not appear, and nothing here rules that out.

### Two harness properties measured, both load-bearing

- **`bash -n` is blind to a wrapped body.** A heredoc body is data to the outer parse. Measured:
  `bash -n` accepts a wrapper whose body contains `if [ ; then`. So `F7` — *a declared contract must
  at minimum parse as bash* — goes **vacuous the moment the wrapper lands**, on the same day it
  becomes most needed. This is not a side note; it is a check silently ceasing to check.
- **`fence_body`'s dedent corrupts a column-0 line inside an indented fence.** It prints
  `substr($0, ind + 1)`, so for a 3-space-indented fence the line `FENCE_BASH` extracts as
  `CE_BASH`. A pre-existing latent defect with no consequence until this feature puts a column-0
  line inside nine indented fences.

---

## Decision

### D1 — The wrapper form

Every fence in the population executes its body under bash through a **quoted here-document fed to
`bash`**, with an optional inbound-environment prologue:

```text
export _root _scope_only            <- only when the body has free variables
bash <<'FENCE_BASH'
…body, verbatim…
FENCE_BASH
```

Four rules, each earned by a measurement:

1. **The delimiter is the literal `FENCE_BASH`, quoted at the opener.** Quoting is what stops the
   host shell expanding anything in the body — without it zsh would perform command substitution on
   the body's `$(…)` before bash ever saw it, which is strictly worse than the defect. Measured: the
   only here-document delimiter inside any declared fence today is `DIRTY_EOF`, and no `SKILL.md`
   contains a column-0 line reading `FENCE_BASH`. Nested here-documents work (verified with
   `python3 - <<'PY'`).
2. **The terminator sits at column 0, even when the fence is indented.** Measured: with the
   terminator indented to match its fence, the here-document runs to EOF, the terminator line is
   swallowed into the body, **and the exit code is destroyed** — the probe printed `body-ran` and
   never reached its `rc=` line. With the terminator at column 0 and the body indented, everything
   works and `rc=4` survives. Nine of the 32 declared fences are indented, so this is not a corner.
3. **`export <names>` precedes the wrapper when the body has free variables.** The body now runs in
   a separate process, so a variable the caller bound as a plain shell variable no longer reaches
   it. `export NAME` promotes an already-bound variable in both shells, is a no-op on an unset one,
   and costs one line. Measured: with it, a caller-bound `manifest` is visible inside and the exit
   code is preserved; without it the body reads `UNSET`. **24 of the 32 declared fences have at
   least one free variable**, so this line is not optional decoration.
4. **No positional-parameter token is introduced** (ADR-0132 §THE RULE). `bash <<'FENCE_BASH'`
   contains none, and `skill-fence-positional-tokens.test.sh` stays green.

Verified by execution under **both** shells, on the same script: identical stdout, stderr passed
through unchanged, exit codes 1/2/3/4 preserved exactly, all three divergence classes neutralised.

### D2 — The wrapper carries no declaration marker of its own

**Its presence in the body is its own evidence, and the guard reads the body.** A
`<!-- fence-wrapped -->` marker would be a second source of truth that can disagree with the
mechanism it describes, with nothing to say which is authoritative — the ADR-0042 shape, and the
shape ADR-0043's direction lesson is about. A marker is a claim; an executable line is not.

State this at the guard, because the next reader meeting an unmarked convention in a repository
full of markers will otherwise "fix" the omission.

### D3 — The population is declared contracts ∪ audit-divergent fences

**41 fences: the 32 declarations plus the 9 divergent fences that carry no marker.** (Of the 17
fences the scanner flags, 7 are already declared and 1 is the illustration, so the union is 32 + 9.
The design-time hand pass counted 13 and 4 and reached the same 9 — a smaller measurement of the
same set, not a different answer.) Derived at run time — the declarations from the marker parse, the
divergent set from the scanner — never from a list.

**Membership does not require a marker.** Only the three `commit` fences gain `fence-contract`
markers, because R-03 names them: they are the two ADR-0061/H4 sites plus the third copy of the
same include-path loop, they are the ones whose wrong behaviour was observed live, and leaving the
system's most-invoked gate outside every declared population after repairing it is how the same
defect returns unwitnessed. The other six enter the population through the scanner alone. None of
the nine is abort-capable (`F3` is green today, which is the proof), so no existing declaration
obligation is being dodged.

**The boundary, stated rather than left implicit (R-12): 121 of the 162 fences stay unwrapped.**
A fence that is neither declared nor detected as divergent is untouched, and a shell-agnostic fence
is left exactly as it is. That is the settled perimeter, and it means a green guard says *every
fence in the population is wrapped* — never *no fence can diverge*.

### D4 — A wrapped fence communicates through stdout tokens and its exit code only

Already true of most declared contracts; the wrapper makes it structural in the outbound direction,
because a variable bound inside the body dies with the subprocess. Any block currently binding a
variable read later in its step is rewritten to print it, and the consumer receives it the way
`<manifest-path>` is already received — as a value the orchestrator carries. **The inbound direction
keeps working, through D1 rule 3**, so this ADR does not convert 24 fences to placeholders; that
would be a different feature with a different blast radius.

**The blocks this applies to are measured, not left for the implementer to find** — the table in
§Measured facts / *The outbound direction* is the work order, and `autopilot` Phase S's
`SCOPE-PARSE:` line is the worked example, because it already does exactly this. Note that the
consumer is prose rather than a later fence in two of the seven rows, including all three
`project-conductor` `_manifest` sites: a rewrite that only looks at fence-to-fence handoffs would
wrap those three and leave the instruction below them reading a variable that no longer exists.

### D5 — The guard is structural, lives in `fence-contract-coverage.test.sh`, and is paired with an executed proof

**Structural, not an idiom scan.** If the wrapper is present the interpreter is bash and the
question is closed regardless of the construct inside. An idiom guard would inherit the blind spots
of whoever enumerated the idioms — and the enumeration in the issue itself missed `cmd $VAR`, which
is the shape of #394.

**In `fence-contract-coverage.test.sh`, not a new file**, for one reason: that file already owns
`enumerate_fences` and `fence_body`. A second copy would be two answers to *what is a fence and what
is its body* — the exact case ADR-0086 §D1 says to extract rather than duplicate, and ADR-0069's
receipt. It is already named in `docs-ci.yml`, so R-06 needs no list edit for the harness.

**The scanner is a separate, non-deployed script** (`fence-shell-divergence-scan.sh`, no `.test.sh`
suffix, under `staging/plugin/scripts/tests/`). It is outside `.claude/test-cmd`'s glob, outside
`docs-ci.yml`'s named list and outside `pairs-completeness.test.sh`'s non-recursive
`plugin/scripts/*.sh` population — so it needs no `PAIRS` entry and **this feature introduces no
inert-until-sync failure mode** (R-13). Precedents: `path-rule-check.sh` (ADR-0117),
`transition-pair-count.sh` (ADR-0120), `mode-binding-check.sh` (ADR-0131). It **classifies a body
handed to it on stdin and enumerates nothing**, so the single enumerator stays single.

It is a **reporter**: always exit 0 with findings on stdout, `exit 3` when awk cannot express the
rules (every rule uses `{n}` interval syntax, and a pre-2019 awk treats the braces literally, making
every rule silently inert — ADR-0046's receipt). The **guard** that consumes it is a checker.

**Paired with an executed proof, because a structural check proves a shape and not a behaviour.**
One wrapped fence is run under zsh and its stdout token and exit code compared against bash's.
`zsh` is installed in the `shell-tests` CI job so the assertion is not CI-dark (the class ADR-0032
named), **and** its absence is reported as an explicit `ZSH-ABSENT` outcome rather than a silent
skip — a check that did not run must never read as a check that found nothing.

### D6 — `F7` is repaired in the same change, because the wrapper is what breaks it

A new assertion parses the **inner** body of every wrapped population fence. Without it, the day the
wrapper lands is the day `F7` starts passing every fence unconditionally while looking unchanged.
`fence_body`'s dedent is fixed in the same change — strip *at most* the opener's indentation in
leading blanks, never `substr` past the start of a shorter line — because the column-0 terminator is
unextractable without it.

---

## Alternatives considered

**A1 — `setopt shwordsplit nonomatch` (or `emulate sh`) when `$ZSH_VERSION` is set.** One line, no
subprocess, every inbound and outbound variable preserved, zero contract change. **Rejected:** it
leaves zsh as the interpreter and fixes only the options someone thought to name. `emulate sh`
emulates *sh*, not bash — `[[ ]]`, `local`, `+=` and `printf %q` are then governed by a third
compatibility surface nobody has measured. It converts an open-ended class into an enumerated list,
which is the per-idiom approach this feature exists to avoid, moved up one level of abstraction.
The interview settled execution under bash; this would have re-opened it.

**A2 — Quote every unquoted expansion and pass argument lists as arrays.** The narrowest possible
diff, no process boundary, no contract change. **Rejected:** it fixes 14 measured sites and nothing
else, and the measurement above says the scanner is a floor — `cmd $VAR` was invisible to the
issue's own sweep, and C3 is a class member with zero sites *today*. It also cannot express
`--features 1 --only 293` as a bash-3.2-portable array inside a fence without positional
parameters, which ADR-0132 forbids outright.

**A3 — Move every fence body into a `skills/<name>/scripts/` file.** A file carries a bash shebang
and is never subject to the host shell; ADR-0132 relies on exactly that property, and it would kill
this defect and the render-substitution defect together, permanently. **Rejected:** the fences most
affected are the ones a human reads at the point of decision — the permission posture, the opt-in
marker, the scope bound, the H4 test-diff gate. ADR-0132 §D2 already made this call deliberately
("everything below deliberately stays here, where a human approving an overnight launch reads the
mechanism"). Emptying 41 fences into files reverses an Accepted decision for a reason that has a
cheaper answer, and the SPEC puts `scripts/*.sh` out of scope.

**A4 — `bash -c '<body>'` instead of a here-document.** No terminator, so no column-0 rule and no
indentation hazard. **Rejected on measurement:** fence bodies contain single quotes everywhere
(`sed 's/^…//'`, `grep '^current_step:'`, `python3 -c "…"`), and there is no way to embed a single
quote inside a single-quoted argument without breaking the body out of its own quoting. It also
requires escaping decisions per fence, which is a per-fence form and defeats a structural guard.

**A5 — Change the host shell.** `chsh` to bash, or force the `Bash` tool to use bash.
**Rejected:** the shell comes from the user's profile, zsh is the macOS default since Catalina, and
the fix would work on this machine while leaving every other machine — and CI, and any future
operator — exposed. It also fixes nothing for a `SKILL.md` deployed to someone else. The SPEC puts
it out of scope and the reasoning is sound.

**A6 — Wrap all 162 fences.** No population question, no scanner, no boundary to state.
**Rejected:** the interview settled the population as declarations ∪ divergent, and the cost is not
symmetric — every wrapped fence acquires a process boundary, an `export` contract for its free
variables, and a `bash -n` blind spot that `WS` must then cover. 121 of those fences are prose
illustrations, one-line examples and blocks nothing executes. A guard whose population is "all" is
cheaper to state and far more expensive to keep true.

**A7 — Put the guard in a new `*.test.sh` file.** Cleaner separation of concerns; the wrapper
question is not the coverage question. **Rejected:** it needs a second copy of `enumerate_fences`
and `fence_body`, which is ADR-0086's criterion answered in the affirmative — two copies giving
different answers about what a fence body is would be a defect, not a preference. It would also
require a hand edit to `docs-ci.yml`'s named list, the CI-dark class ADR-0113 measured at four
harnesses.

**A8 — A `<!-- fence-wrapped -->` declaration marker.** Symmetric with `fence-contract` and
`fence-illustration`, greppable, cheap. **Rejected:** see D2. Every existing marker declares
something the file cannot otherwise show (an id, an exemption, a reason). The wrapper shows itself.

---

## Consequences

### Positive

- The executed shell becomes the tested shell for every fence in the population. Word splitting,
  `nomatch`, `echo` escapes and **every future divergence** stop applying together, which is the
  whole reason to remove a class rather than its members.
- `autopilot --features N` bounds a run for the first time since ADR-0129 shipped. So does
  `--only`. `project-conductor`'s Step 0 argument parse — the same shape, in a second skill, that
  nobody had found — is fixed in the same change.
- `commit`'s H4 test-diff gate (ADR-0061 §D1) stops classifying every changed file as a test file,
  and `claude-md-slim`'s `--global` path stops handing `content-union-check.sh` a four-flag string
  as one positional. Both were failing closed for reasons that read as defects elsewhere.
- ADR-0048's requirement-coverage gate receives `--tests-root <path>` as two arguments again, so a
  merge-blocking gate stops being fed an unrecognised token.
- The inbound cross-fence dependency, previously implicit and documented only in prose comments on
  two fences, becomes an explicit `export` line the guard can read.
- Two latent harness defects are closed as a by-product: `F7`'s impending blindness, and
  `fence_body`'s corruption of a column-0 line inside an indented fence.

### Negative

- **A process boundary appears where there was none.** A wrapped fence can no longer change the
  caller's working directory or environment. The audit found no fence that does, and no fence that
  reads the caller's stdin — but the audit is a floor, and the failure mode of a missed one is a
  behaviour change at runtime rather than a red test.
- **The column-0 terminator is load-bearing and looks like a typo.** Inside a 3-space-indented
  fence it reads as a formatting mistake, and "tidying" it silently destroys the exit code of that
  fence — a failure this ADR's own probe produced on the first attempt. The rule is stated at the
  guard and asserted, which is the only reason it is survivable.
- **The scanner measures a floor and will always measure a floor.** Its declared blind spots:
  a multi-line quoted string is analysed as unquoted on its interior lines (the
  `autopilot-build-check-3` false positive); here-document bodies are skipped as data, so shell code
  fed to a shell through one is invisible; `case` arms are excluded from the glob class by a lexical
  heuristic, so a genuine glob on a line shaped like a case arm is missed; only C1/C2/C3 plus four
  cheap bash-only probes are modelled, against a divergence surface that includes `MULTIOS`,
  `KSH_ARRAYS`, `$0`, `[[ =~ ]]` captures, `printf %q` and `local`/`typeset` scoping; and it reads
  staged `SKILL.md` only. **A green scan means no modelled idiom was found, never that no divergence
  exists.**
- **A fifth blind spot was measured by the corpus drive and is NOT in the paragraph above**, which is
  quoted verbatim by the scanner's own header: a `case` arm whose pattern is built from a variable
  (`"$cwd_n"/*)`) is not recognised as a case arm, so its `*` is reported as a command-word glob.
  Recorded in §Measured facts with its probe rather than edited into the quoted text, because a
  paragraph and its verbatim quote drifting apart is the ADR-0042 shape. The header absorbs it at the
  next `staging/` edit; until then the declared list is a floor, which is what the paragraph above
  already says of itself.
- 121 fences stay unwrapped and stay exposed. That is the settled perimeter (D3), and it is the
  thing most likely to be mis-read from a green run.
- Three `commit` fences acquire `fence-contract` markers and therefore acquire an execution
  obligation (`F4`) that did not exist. That is the cost of R-03 and it is paid once.
- CI gains a `zsh` install step in the `shell-tests` job.

### Neutral

- Per-fence exit codes and stdout tokens are unchanged, so no caller's branching moves (R-09).
  `PREFLIGHT_CLEAN`, `SCOPE-PARSE:`, `COLLAPSED`, `BASELINE_OK` and the rest are untouched, and
  `exit 3` keeps meaning *the check did not run*.
- The wrapper is invisible to every caller; it is an implementation detail of the fence.
- `enumerate_fences`, the marker grammar, `run_fence`'s substitution contract and `plant-check.sh`'s
  sandbox are all unaffected. `bash <<'FENCE_BASH'` contains no ` | `, so it is expressible as a
  plant needle.
- ADR-0083's contract/illustration split is unchanged. The single illustration stays an
  illustration and stays unwrapped.

---

## Verification

The six bullets immediately below are the **design-time** probes, recorded on this machine on
2026-08-09. Everything after them was measured by the **implementation**, on the same machine and
the same day, against the shipped tree — they are appended rather than folded in, because a probe
run against a prototype and a probe run against the merged file are not the same evidence.

- Differential probe of C1a/C1b/C1c/C2/C3 under zsh 5.9 and bash 3.2 — table above.
- Wrapped-fence probe under **both** shells: identical stdout, stderr through, `rc=3` preserved,
  nested `python3 - <<'PY'` intact.
- Indented-fence terminator probe: column-0 terminator → `rc=4` preserved; indented terminator →
  body runs, rest of script swallowed, exit code lost.
- `bash -n` blindness probe: a wrapper containing `if [ ; then` passes.
- `fence_body` dedent probe: `FENCE_BASH` extracts as `CE_BASH` under the current `substr` dedent,
  correctly under a guarded dedent.
- Inbound forwarding probe: `export manifest` before the wrapper makes a caller-bound value visible
  inside; without it the body reads `UNSET`.

### R-07 — the executed proof, run live (`WSA` / `WSB`)

Run on 2026-08-09, zsh 5.9 (arm64-apple-darwin25.0) / GNU bash 3.2.57(1)-release, on the fence
`autopilot-check-6`, against the same two-manifest fixture `WSA`/`WSB` construct for themselves:
`a.manifest.yml` carrying `hook_verified: true` and `b.manifest.yml` carrying none, which is what
exercises that fence's C1b divergence (`for _m in $_manifests`). The fence was chosen for that
divergence and never arbitrarily — a shell-agnostic body would pass under either shell and pin
nothing about the wrapper doing its job. The four transcripts are verbatim, temp paths elided to
`<T>`:

**`WSA` — the WRAPPED body, the same outer script read by each shell.**

```text
--- zsh ---   rc=0
note: <T>/docs/manifests/b.manifest.yml has no hook_verified field and is completed — it predates the field
  (ADR-0016 added it to manifest-init.sh afterwards). A completed chain's dispatch
  mode cannot affect this run, so the documented default (false) applies. Not an abort.

--- bash ---  rc=0
note: <T>/docs/manifests/b.manifest.yml has no hook_verified field and is completed — it predates the field
  (ADR-0016 added it to manifest-init.sh afterwards). A completed chain's dispatch
  mode cannot affect this run, so the documented default (false) applies. Not an abort.
```

**Byte-identical stdout, identical `rc=0`.** A quoted here-document opener is parsed the same way by
both outer shells, so the body reaches a literal `bash` subprocess whichever shell read the wrapper.

**`WSB` — the negative twin: the SAME body UNWRAPPED.**

```text
--- zsh ---   rc=1
✗ hook_verified: <T>/docs/manifests/a.manifest.yml
<T>/docs/manifests/b.manifest.yml could not be read — the check DID NOT RUN on it.
  Either the YAML is unparseable or python3/PyYAML is unavailable. This is not the
  same as finding a bad value; fix the file or the interpreter and re-run.

--- bash ---  rc=0
note: <T>/docs/manifests/b.manifest.yml has no hook_verified field and is completed — it predates the field
  (ADR-0016 added it to manifest-init.sh afterwards). A completed chain's dispatch
  mode cannot affect this run, so the documented default (false) applies. Not an abort.
```

**They diverge, which is what makes `WSA` mean anything** — without this twin `WSA` could not tell a
working wrapper from a fence that never diverged. Note what the zsh row actually says: the unsplit
list arrives as ONE path-looking blob, `python3` cannot read it, and the check reports *the check DID
NOT RUN* — naming a cause that is not the cause. A pre-flight aborting for a reason that is not the
reason is worse than one aborting for the right one, and no reading of the file could have found it.

**`ZSH-ABSENT` was exercised, not assumed.** The harness was re-run on a curated `PATH` carrying
every tool it needs except `zsh` (a directory of symlinks to `/usr/bin`, `/bin`, `/usr/sbin`,
`/sbin`, `/opt/homebrew/bin` with `zsh` withheld), and it reported:

```text
FAIL: WSA: ZSH-ABSENT — zsh is not on PATH, the executed proof could not run (never a silent skip)
FAIL: WSB: ZSH-ABSENT — zsh is not on PATH, the negative twin could not run (never a silent skip)
PASS: Z1: 66 assertions ran (floor 66) — none silently vanished
PASS=65 FAIL=2
```

**The count does not drop — 66 assertions still run, two of them fail by name.** That is the whole
difference between this and a skip, and `Z1` is what makes it observable: a suite reporting 64
assertions instead of 66 would have read as a shorter run rather than a missing proof (ADR-0032's
CI-dark class). CI installs `zsh` in the `shell-tests` job for exactly this reason. **Removing that
step turns the job red rather than quietly dropping the proof** — the correct direction, and it will
read as a regression the first time.

### R-08 — end-to-end acceptance of the original symptom

`autopilot --features 1 --only 293 --dry-run`. **The two Phase S fences were executed directly under
`zsh`, exactly as rendered, rather than through a live `/skill autopilot` invocation** — they are not
the same evidence and the difference is stated rather than glossed. What makes the substitution sound
here specifically: both fence bodies contain **zero** positional-parameter tokens (ADR-0132 §THE
RULE, pinned by `WS6` over all 35 population fences and by `skill-fence-positional-tokens.test.sh`),
so the rendered text is byte-identical to the text on disk, and running the disk text under the host
shell *is* running the rendered text. `SCOPE-PARSE`'s four fields were carried into
`autopilot-scope-resolve` as `_scope_source`/`_scope_features`/`_scope_only`/`_dry_run`, exactly as
the prose between the two fences instructs the orchestrator to carry them.

```text
=== autopilot-scope-args  (host shell: zsh 5.9) ===
SCOPE-PARSE: OK source=arguments features=1 only=293 dry_run=true
autopilot scope: source 'arguments' is in effect (dry_run=true)
rc=0

=== autopilot-scope-resolve  (host shell: zsh) ===
SCOPE-RESOLVE: OK source=arguments features=1 resolved=1
  only: task_num extracts digits only so a lettered task collides with its sibling  (issue #293)
scope: --dry-run -- resolution printed above, no scope file written
rc=0
```

`source=arguments`, `features=1`, **exactly one** roadmap row resolved. No scope file was written
(`--dry-run`), and no guard was armed.

**A green guard is not a substitute for reproducing the defect's absence, so the counterfactual was
run too** — the same `autopilot-scope-args` body with the wrapper stripped, under both shells:

```text
--- unwrapped, under zsh (the host shell — the pre-ADR-0133 live path) ---
SCOPE-PARSE: OK source=none features= dry_run=false
autopilot scope: source 'none' is in effect (dry_run=false)
rc=0

--- unwrapped, under bash (the shell it was written for) ---
SCOPE-PARSE: OK source=arguments features=1 only=293 dry_run=true
rc=0
```

**`source=none`, no bound, `dry_run=false`, and `rc=0`.** Every scoping argument was discarded, the
fence reported success, and a launch asking for one feature would have proceeded — unbounded, over
every pending roadmap row, and *without* the `--dry-run` the operator asked for, so it would have
armed the guard and started publishing. That is the whole issue in one transcript, and it is silent:
nothing in that output says a bound was dropped.

### R-11 — the defect predates #385, and `--features` has never bounded a run on this machine

Both forms measured directly, same day, same two shells:

| Form | Era | bash 3.2 | zsh 5.9 |
|---|---|---|---|
| `set -- $_args` | pre-#385 (before ADR-0132 moved the parse into a script) | `argc=5`, `first=--features` | **`argc=1`**, `first=--features 1 --only 293 --dry-run` |
| `bash "$_sap" $_args` | post-#385, pre-#394 | `argc=5` | **`argc=1`** |

**This is a finding, not a footnote.** ADR-0129 shipped `--features`/`--only` and every run of
`autopilot` on this machine since has executed one of these two forms under zsh, so the bound has
**never once been applied**. Any earlier statement that a run was bounded by `--features` is a
statement about a mechanism that was not running — the roadmap's Phase 11 notes, and ADR-0129's own
consequences, should be read against that. It also means the two eras are not "a defect and its
regression": #385 changed which line carried the unquoted expansion and changed nothing about
whether it split.

### Two findings the implementation measured, recorded here rather than in §Measured facts

**1. `spec-coverage.sh`'s `rc=2` is this gate's FAIL-OPEN branch, so ADR-0048's merge-blocking
requirement-coverage gate has been PASSING whenever a tests-root was supplied.** This is the most
consequential consequence found in the whole feature and the design-time audit stopped one step
short of it: §Measured facts records the two `${_troot:+--tests-root "$_troot"}` sites as feeding
the gate "an unrecognised single argument", which describes the input and not the outcome. Measured
against the real script, on a SPEC declaring one id and a plan citing it:

```text
--- unwrapped, under zsh ---
rc=2
spec-coverage: unknown argument: --tests-root <T>
usage: spec-coverage.sh --spec <file> --plan <file> [--tests-root <dir>] [--list]
--- unwrapped, under bash / wrapped, under either shell ---
rc=0
COVERED<TAB>R-01
spec-coverage: 1 id(s) declared, 1 covered, 0 uncovered, tests-root=<T>, 1 test file(s) discovered
```

(`<TAB>` is the real separator, written out because a literal tab in this file trips `MD010`;
`spec-coverage.sh`'s own usage text, three lines above it in the same transcript, says
"TAB-separated".)

`concept-to-code`'s Step 5 policy for this gate reads, verbatim: *"`_rc = 2`, or `_scov` empty
(script did not resolve): fail-open, visibly. Record `"status": "unavailable"` in
`step5-report.json` and proceed."* That branch is correct for what it was written for — a checker
that could not be resolved must not block a chain — and it is precisely why this was invisible.
`rc=2` means *bad invocation*, and the invocation was being corrupted by the shell rather than by a
caller, so the gate classified its own corruption as its own unavailability and proceeded.

**The scope of the claim, stated rather than left to be inferred.** `_troot` is non-empty exactly
when `test_cmd_placeholder` and `test_cmd_provisional` are both false, so on a machine whose host
shell does not word-split — this one, and every macOS default since Catalina — every such chain run
since ADR-0048 shipped recorded `"status": "unavailable"` and proceeded. On a machine whose host
shell is bash the gate worked as designed throughout. That is not a mitigation: it means the gate's
verdict depended on the operator's login shell, which nothing anywhere records.

**The gate blocks again from this change onward, which means the first chain to run it may report an
uncovered id that has been uncovered for weeks — that is the gate working, not a regression.**

**2. The derived population reads 35, not 41, and that is correct — say so, or the next reader
counts six missing fences.** §D3 states the population as 32 declarations ∪ 9 unmarked-divergent =
41, and `WS0` reports `35: 35 declared, 0 unmarked-divergent`. Neither number is wrong and the
reconciliation is mechanical:

- R-03 gave the three `commit` fences `fence-contract` markers, so 32 declarations became **35** and
  the 9 unmarked-divergent became **6** — §D3's own closing sentence predicts exactly this split.
- `fence-shell-divergence-scan.sh` **skips here-document bodies as data**, a blind spot its header
  declares. A wrapped fence's divergent line now sits inside a here-document, so the scanner stops
  flagging it. An *unmarked* fence therefore LEAVES the derived population the moment it is fixed;
  a *declared* one cannot, because its membership comes from the marker.

So 35 is the post-fix steady state and 41 is the pre-fix work order. **Verified self-restoring**
rather than argued: stripping every `bash <<'FENCE_BASH'` / `FENCE_BASH` pair in an isolated copy of
`staging/` removed **41** wrapper openers and took `WS0` back to `41: 35 declared, 6
unmarked-divergent`, with `WS1` failing and naming all 41 and `WS4` failing with `0 outside the
population`. The real tree was never touched. **A number differing from the one in this ADR's own
prose is not a discrepancy to reconcile away** — it is the guard reporting a population that
legitimately shrinks as the work lands, and `WS0`'s two-part breakdown (`N declared, M
unmarked-divergent`) exists so the shrink is legible rather than mysterious.

### A correction to the plan's free-variable analyser rule

The plan's *Measured facts* item 12 warns that the design-time analyser **missed** assignments not at
line start (`*) OTHER="$OTHER$f " ;;` inside a `case` arm read as a free variable) and prescribes
matching `(^|[;&|(]|[[:space:]])NAME=` before trusting a generated `export` list. That rule is
necessary and it is not sufficient: it has a **second, opposite failure mode**, and the corrected
matcher is what introduces it. A `NAME=` occurring inside a **comment** is read as an assignment, so
the name is classified as bound and **dropped from the `export` list** — a real free variable, gone
silently. Measured instance: the comment `# … _autopilot. Inert unless _autopilot=true.` sits inside
the bodies of `conductor-scope-gate` and `conductor-published-skip`, and cost both fences their
`_autopilot` export in a draft. Both now carry it.

The two failures point opposite ways and only one is safe. Over-listing a name is harmless (`export`
on an unset variable is a no-op in both shells, D1 rule 3). **Omitting one empties a variable inside
the body, at run time, with no test able to see it** — here it would have made two `autopilot`-only
guards read `_autopilot` as empty and take their inert branch, so a scope gate and a re-publish guard
would both have silently stopped guarding. **Strip comments before analysing, and when in doubt
export the name.**

---

## Correction (2026-09-12)

The `bash <<'FENCE_BASH' ... FENCE_BASH` wrapper this ADR prescribes breaks one further construct
not identified at the time: a **quoted heredoc nested inside a command substitution nested inside
double quotes** — `git commit -m "$(cat <<'COMMITMSG' ... COMMITMSG )"` — fails with `unexpected
EOF while looking for matching '` the moment the heredoc body contains an apostrophe. Found live in
`commit/SKILL.md`'s Step 5 fence (issue #406), reproduced three times on ordinary prose ("run's
manifest", "the issue's proposed remedy") across three separate sessions (2026-08-11, -14, -17)
before being traced to this ADR's own wrapper rather than to the fence content.

Repo-wide audit (issue #406 R-03): of the seven `SKILL.md` files using the `FENCE_BASH` wrapper
(`brief-to-app`, `autopilot-build`, `autopilot`, `claude-md-slim`, `commit`, `concept-to-code`,
`project-conductor`), this was the only instance of the nested-heredoc-in-command-substitution
shape. `autopilot-build`'s `bash -c "$(cat $project_root/.claude/test-cmd)"` reads a file's content
into a command substitution but contains no heredoc, so it does not carry this failure mode.

**The fix is not a new escaping rule — it is removing the construct.** `git commit -F <tmpfile>`
takes the message through a file instead of the shell's argument-parsing path entirely: no command
substitution, no nested heredoc, no character class left to break on. Any future fence that needs to
hand a multi-line, human-authored string to a command should prefer writing it to a temp file over
building a `"$(cat <<'X' ... X)"` construct under this wrapper — the wrapper's own free-variable and
column-0-terminator rules (§D1) do not make that specific nesting safe.

Regression pinned as `WSM` in `fence-contract-coverage.test.sh`, plant manually verified RED against
`git commit -F "$_commitmsgfile"` → `git commit -m "$_commitmsgfile"` before trusting it.

---

## References

- Issue #394; SPEC `docs/specs/394-skill-fences-rely-on-word-splitting.spec.md`
- ADR-0132 (skill-argument substitution in fences — the sibling failure shape, and the source of the
  "a file is never rendered" property this ADR declines to lean on)
- ADR-0083 (the fence contract this amends), ADR-0107 (the population lesson)
- ADR-0129 (`--features`/`--only`, the bound this defect discarded)
- ADR-0061 §D1 (the H4 test-diff gate), ADR-0048 (the requirement-coverage gate),
  ADR-0044 (`content-union-check.sh`'s two-flag contract)
- ADR-0086 §D1 (extract only when two copies giving different answers would be a defect)
- ADR-0117 / ADR-0120 / ADR-0131 (checker placed outside every deployment path)
- ADR-0032 (the CI-dark class), ADR-0113 (`docs-ci.yml`'s hand-maintained list)
- ADR-0046 (the `exit 3` "did not run" contract and awk interval syntax)
