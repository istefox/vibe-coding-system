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

### The divergent sites — 14 findings across 13 distinct fences

| Class | Skill | Fence | Marker | Line |
|---|---|---|---|---|
| C1a | `autopilot` | @111 +27 | `autopilot-scope-args` | `_sap_out=$(bash "$_sap" $_args)` |
| C1a | `project-conductor` | @52 +21 | `conductor-step0-args` | `_ca_out=$(bash "$_ca" $_args)` |
| C1a | `claude-md-slim` | @169 +11 | *(unmarked)* | `$DUP_ARGS \` |
| C1c | `concept-to-code` | @1865 +6 | *(unmarked)* | `${_troot:+--tests-root "$_troot"}` |
| C1c | `concept-to-code` | @1887 +6 | *(unmarked)* | `${_troot:+--tests-root "$_troot"}` |
| C1b | `autopilot` | @444 +23 | `autopilot-check-6` | `for _m in $_manifests` |
| C1b | `autopilot` | @576 +22 | `autopilot-scope-resolve` | `for _tok in $_toks` |
| C1b | `commit` | @100 +4 | *(unmarked)* | `for _inc in $include_paths` |
| C1b | `commit` | @228 +9 | *(unmarked)* | `for _f in $staged $tracked_modified $untracked` |
| C1b | `commit` | @479 +10 | *(unmarked)* | `for _inc in $include_paths` |
| C2 | `autopilot` | @444 +1 | `autopilot-check-6` | `ls "$PWD"/docs/manifests/*.manifest.yml` |
| C2 | `project-conductor` | @97 +6 | *(unmarked)* | `ls -t …/????-??-??-"$_slug".manifest.yml` |
| C2 | `project-conductor` | @324 +6 | *(unmarked)* | *(same lookup, second copy)* |
| C2 | `project-conductor` | @558 +6 | *(unmarked)* | *(same lookup, third copy)* |

**Four sites the issue's own scanner could not see**, because it matched `for X in $VAR` and
`set -- $VAR` only: `conductor-step0-args` (the same fail-open shape as Phase S, in a second skill),
`claude-md-slim` (`$DUP_ARGS` must split into four words or `content-union-check.sh` reads the whole
string as its `<original>` positional — ADR-0044's usage error, produced by the shell), and the two
`concept-to-code` `${_troot:+…}` sites, which feed ADR-0048's **merge-blocking** requirement-coverage
gate an unrecognised single argument.

**Failure directions differ, and only one of them is quiet.** The Phase S site fails **open**. The
`commit` sites fail **closed and wrongly**: `commit/SKILL.md:237` is ADR-0061's H4 test-diff gate,
whose predicate under zsh receives one blob and classifies **every** changed file as a test file —
observed live on 2026-08-08 and initially misattributed to an orchestrator scripting error. The three
`project-conductor` C2 sites are **divergent in mechanism and equivalent in outcome today**: zsh
declines to run `ls` where bash runs it against a literal pattern, and both leave `_cand` empty
behind `2>/dev/null`. They are in the population because the class is present, not because a
symptom is.

**Two false positives**, both instructive and both declared as scanner blind spots below:
`autopilot-build-check-3` (a python comprehension inside a `python3 -c "…"` string spanning several
lines — a line-oriented scanner sees the interior lines as unquoted shell) and the `concept-to-code`
merge-back fence (the single declared **illustration**, which does not parse as bash at all).

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

**41 fences: the 32 declarations plus the 9 divergent fences that carry no marker.** (Four of the 13
divergent fences are already declared, so the union is 32 + 9.) Derived at run time — the
declarations from the marker parse, the divergent set from the scanner — never from a list.

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

Recorded at design time, on this machine, 2026-08-09. The implementation re-runs all of it and
appends the audit's own committed output plus the end-to-end acceptance below.

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

**R-07** is completed by the implementation: one wrapped fence executed live under zsh, with its
stdout token and exit code compared against the bash run, recorded here.

**R-08** is completed by the implementation: `autopilot --features 1 --only 293 --dry-run` resolving
`source=arguments`, `features=1` and exactly one roadmap row, recorded here.

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
