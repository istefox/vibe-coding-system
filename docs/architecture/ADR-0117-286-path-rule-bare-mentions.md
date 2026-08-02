# ADR-0117 — concept-to-code PATH RULE: the bare-mention population, re-derived and guarded

**Status:** Accepted
**Date:** 2026-08-02
**Author:** istefox
**Supersedes:** none
**Superseded by:** none
**Amends:** ADR-0028 §2.4 / §3.6 (the deliberately-deferred sixth mention) — in part, for that one
deferral only. ADR-0028's other four findings stand untouched.
**Related:**
- SPEC: `SPEC.md` at repo root (GitHub issue #286), Phase 10 Wave 1
- ADR-0028 (`32-manifest-helpers-guards`) — the source: fixed five PATH-RULE call sites, disclosed a
  sixth at the then-current `SKILL.md:569` and deferred it by name
- ADR-0082 (`207-210-cross-reference-form`) — a cross-reference names a distinctive anchor, never a
  line number; and the extractor must SKIP the waiver's own declaration line
- ADR-0086 (`derived-guard-pattern-not-extracted`) — the criterion for whether a derived guard
  shares a helper or stays a deliberate copy
- ADR-0085 (`208-derived-guard-boundaries`) — count-guard the DENOMINATOR, not the matches
- ADR-0108 (`284-plant-registry`) — rule 12 and the declared-plant mechanism
- ADR-0043 (`93-pairs-completeness`) — the direction lesson: a check blind by construction to what
  it omits
- Implementation plan: `docs/superpowers/plans/2026-08-02-the-sixth-bare-manifest-set-flag-sh-ment.md`

---

## 1. Context

`staging/plugin/skills/concept-to-code/SKILL.md` states its own PATH RULE, in a blockquote directly
above the helper inventory:

> **PATH RULE — all scripts use the absolute prefix `~/.claude/skills/concept-to-code/scripts/`.
> NEVER derive the path from the manifest location (`<manifest-dir>/scripts/` does NOT exist).
> Every bash call below must use the full absolute path.**

ADR-0028 (issue #32) enforced it at five named `manifest-set-flag.sh` call sites, found a sixth
during its own research, and deferred it with reasons (§3.6): both the SPEC and the orchestrator
brief presented the count as a closed, counted list, and the sixth was grammatically distinct — a
`via `X`` clause inside a longer conditional sentence, not a standalone bullet. The deferral was
correct discipline for its moment. Issue #286 is the follow-up it explicitly left open.

### 1.1 The re-derivation, because the number was never the point

The SPEC directs re-derivation rather than confirmation of ADR-0028's "five plus one deferred". That
instruction is load-bearing: **the population is 62 occurrences, of which 16 are findings today, and
ten of those sixteen are call sites.** Not one plus five.

Measured on 2026-08-02 against the current staged file (62 occurrences of the seven manifest-helper
basenames; the seven derived from `staging/plugin/skills/concept-to-code/scripts/manifest-*.sh`):

| bucket | count |
|---|---|
| carries the absolute prefix (`~/.claude/…/scripts/`, `$HOME/…/scripts/`, `$_c2c/`) | 33 |
| on a comment line inside a fence (never executed) | 3 |
| canonical prose: a bare code span, no arguments, no invocation verb before it | 10 |
| **findings** | **16** |
| — of which: relative `scripts/<helper>.sh` path in an instruction | 3 |
| — of which: a bare name in an instruction followed by arguments | 7 |
| — of which: an unquoted name in running text | 3 |
| — of which: a bare code span preceded by an invocation verb | 3 |

Of the 16 findings, **10 are call sites** (an instruction the orchestrator is meant to execute) and
**6 are prose** (a description that names the helper in an executable-looking shape). ADR-0028's
deferred sixth is one of the ten. The other nine were never counted by anything: five of them
(`manifest-set-gate.sh <manifest-path> N approved …`) were **created after** ADR-0028, by ADR-0099
(issue #238), which had no reason to know the rule existed. That is the mechanism by which this
population grows: the rule lives in one blockquote, and nothing has ever read it.

### 1.2 Why a bare mention is a defect and not a style preference

The staged copy and the deployed copy can differ, and everything in this repository is staged first
and deployed later by hand (`sync-to-claude.sh`). A relative or bare invocation resolves against
whatever the session's working directory happens to be — never reliably against
`~/.claude/skills/concept-to-code/scripts/`. The failure is silent on the happy path and wrong on
every other, which is precisely why it has survived two ADRs.

### 1.3 The hard part: form does not separate an instruction from prose

The SPEC's own edge case names it. Two lines in the same file:

- `- **exit 3 (INCONCLUSIVE)** → record NOTHING, do not call `manifest-set-flag.sh`.` — prose.
- `… otherwise record `hook_verified = false` via `manifest-set-flag.sh` and take the Agent-tool
  fallback.` — a call site. **ADR-0028's deferred sixth.**

They are the same shape: a bare code span with no arguments. No formal rule over the text separates
them, and this is the reason a guard for this class had never been written. It is also the reason a
"prose is a bare code span, everything else is a call site" rule — the first design tried here — is
**unusable**: it classifies the issue's own subject as compliant, and a guard that cannot catch the
defect it was written for is not a guard.

The distinguisher that does work was measured rather than invented. Extracting the word immediately
preceding every bare occurrence over the real corpus gives a clean distribution: the ten
canonical-prose occurrences are preceded by `—`, `(`, `in`, `the`, `to`, `it.**`, or nothing
(start of line). The three that need catching are preceded by `via`, `call`, `via`. **An invocation
verb immediately before the name is the signal**, and on this corpus it produces exactly three false
positives — `NOT via `X``, `do not call `X``, `NOT via X which is boolean-only` — which are the
negated-prose class the SPEC's edge case names by name.

### 1.4 The instance number is already colliding

`# DERIVED-GUARD PATTERN — instance N (ADR-0086)` markers were derived from the harness at design
time rather than taken from the brief. Declared today: 1, 2, 3, 4, 5, 6, 8, 9, and **10 twice** —
`conductor-entry-failure-split.test.sh:35` and, in prose, `concept-to-code-bsd-autopilot-gates.test.sh:304`.
Instance 7 (ADR-0087) carries no marker at all. So this feature is **instance 11**, and the brief's
"instance 10 or so" would have produced a third collision. Recorded, not fixed: renumbering nine
headers is not in this SPEC's scope.

## 2. Decision

Three parts: convert the ten call sites, declare the six prose occurrences, and ship a derived
checker that fails on the next one.

### 2.1 A checker script with an exit-code contract, not assertions alone (R-02)

`staging/plugin/scripts/tests/path-rule-check.sh`, invoked as
`path-rule-check.sh <skill-md> <helper-scripts-dir>`.

- **Exit 0** — no findings. Stdout **empty**.
- **Exit 1** — one or more findings, one per line on stdout.
- **Exit 2** — bad invocation (wrong argument count, unreadable skill file, missing helper dir).
- **Exit 3** — the check DID NOT RUN: the helper derivation produced zero basenames.
- A one-line summary goes to **stderr on every run**:
  `path-rule-check: helpers=<n> occurrences=<n> compliant=<n> waived=<n> findings=<n>`.

It is a **CHECKER** — the caller branches on the exit code. It prints no `CLEAN` sentinel and must
never grow one: `weakening-scan.sh` is a reporter that always exits 0 and signals on stdout, and the
two idioms have already been confused once in this repository at a single call site (ADR-0048 §"two
adjacent gates, two opposite caller idioms"). The header says so, and an assertion pins that stdout
is empty on success.

Exit 3 exists because a derivation that stops resolving prints nothing and exits 0 — indistinguishable
from a clean file, which is this feature's own defect one level down.

**It lives under `staging/plugin/scripts/tests/`, deliberately.** That directory is outside
`pairs-completeness.test.sh`'s `plugin/scripts/*.sh` population (non-recursive, verified) and outside
its `*.test.sh` CI list, so the script needs no `PAIRS` entry, is not deployed, and creates **no
"inert until sync" dependency** — the class that has bitten six recent ADRs. `plant-check.sh` and
`run-hook-tests.sh` are the precedent. The name deliberately does not end in `.test.sh`, so
`.claude/test-cmd`'s glob does not execute it as a harness.

### 2.2 The predicate, in the order it is applied

For each occurrence of a derived helper basename on a line, after the line has been **truncated at
the first `<!-- path-rule-exempt:`** (see §2.4):

1. **COMPLIANT — absolute.** The text immediately preceding the basename is
   `~/.claude/skills/concept-to-code/scripts/`, `$HOME/.claude/skills/concept-to-code/scripts/`, or
   `$_c2c/` (the variable bound to that path two lines above its three uses).
2. **COMPLIANT — comment line.** The line's first non-blank character is `#`. A comment is never
   executed. This covers the three fenced-block comments that describe helper behaviour.
3. **FINDING — invocation-shaped**, if any of:
   - the preceding text ends with `scripts/` (a relative path is never prose);
   - the character immediately before is not a backtick (an unquoted name in running text);
   - the character immediately after is not a backtick (arguments follow inside the span);
   - the last word before the opening backtick, normalised, is an **invocation verb**.
4. **COMPLIANT — canonical prose** otherwise: `` `<helper>.sh` `` with nothing after it in the span
   and no invocation verb before it.

Word normalisation: strip a trailing backtick from the preceding text, take the last
whitespace-separated field, strip leading `(` and `*`, strip trailing `.,:*`, lowercase.

**Verb set:** `via call calls calling invoke invokes invoking run runs running use uses using
execute executes`. Only `via` and `call` occur in the corpus. The set is wider on measured grounds,
not on taste: running the wider set over the real file adds **zero** false positives (no
canonical-prose occurrence is preceded by any of them), so the extra entries cost nothing today and
cover the shapes a future author will plausibly write. `bash` is deliberately absent — `bash
manifest-set-flag.sh …` is already caught by the unquoted-name rule, and listing it would suggest
the verb set is the mechanism for that case when it is not.

**Scanning is by literal `index()`, never a built regex.** The helper set is derived at run time,
and building an alternation from derived names is how ADR-0093 shipped a rule that silently matched
nothing: BSD `grep` rejects an empty ERE alternative and the whole sweep then reads as clean.
Literal matching has no escaping surface and no empty-alternative failure mode (the ADR-0032
reasoning, applied to a different tool).

### 2.3 The ten call sites are converted by prefix substitution only (R-01)

Each of the ten gets `~/.claude/skills/concept-to-code/scripts/` inserted before the basename, with
the surrounding sentence otherwise byte-identical. **No arguments are invented and no sentence is
rewritten** — ADR-0028 §2.4's own rule ("this is a path-prefix substitution, not a rewrite"), reused
because it is what keeps a mechanical fix mechanical. Two of the ten additionally gain the backticks
their neighbours already have, because the substitution puts a path into running text.

The five `manifest-set-gate.sh <manifest-path> N approved …` shorthands created by ADR-0099 are
converted rather than waived. They are instructions with arguments; if an orchestrator copies one it
resolves against the wrong tree, which is the defect. Waiving them instead would leave a declared
hole in exactly the shape the checker exists to catch.

### 2.4 Six prose occupancies get a declared waiver (R-01, R-02)

`<!-- path-rule-exempt: <reason ≥ 40 chars> -->`, on the **same line** as the occurrence it excuses.
Five lines, six occurrences. One line carries two.

- Same line, not the line above: an HTML comment on its own line **breaks the surrounding markdown
  paragraph**, and every one of the five sits mid-paragraph. Same-line also makes the marker
  self-locating, with no rule about how far it reaches.
- One line, ≥ 40 characters, exactly as ADR-0077/0082/0083/0084 require, and for the reason ADR-0082
  §U3 earned: a reason that wraps is a prose assertion that depends on where the text breaks.
- **The scanner truncates the line at the marker before scanning it** — ADR-0082's rule, which is
  load-bearing for the same reason there. A reason will name the helper it is excusing; without the
  truncation that mention is an occurrence, waived by the marker that introduced it, and a marker
  could satisfy itself on a line with no real subject (rule 12).
- **A marker producing zero waived occurrences is a `STALE-WAIVER` finding**, and a reason under 40
  characters is a `SHORT-REASON` finding. ADR-0081 §ZA4's direction: a stale waiver reads exactly
  like clean coverage.

### 2.5 The rule is written into SKILL.md, and written so it cannot count itself (R-01)

The PATH RULE blockquote gains a paragraph stating the prose form, the four invocation-shaped forms,
and the waiver. **It uses `<helper>.sh` placeholders and never spells a real basename in a violating
shape, and it names the marker as `path-rule-exempt` without its `<!--` delimiters.** Both are rule
12: the first would make the documentation a finding, the second would make it a malformed waiver.
The literal marker opening therefore appears in SKILL.md only where it is a live waiver — an
invariant the STALE-WAIVER check already enforces.

### 2.6 The guard's assertions extend the existing harness (R-02, R-03)

Section F is added to `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh`
— ADR-0028's own file, whose Section D is this guard's instance-level ancestor. Sections A–E are
byte-untouched, D1–D5 included: they pin five specific sentences and the class guard does not
subsume that.

The file is already in `docs-ci.yml`'s named `shell-tests` list, so **no CI append is needed and the
CI-dark class ADR-0113 closed cannot reopen here.** That is the deciding practical argument for
extending rather than creating a new file; the SPEC offers both and names this one first.

Both directions per contract (ADR-0039): the real file must be clean, and fixtures must make the
checker exit 1, 2 and 3 for the right stated reason. Count guards ride on the stderr summary:
`helpers >= 7`, `occurrences >= 50`, `waived >= 1` — the DENOMINATOR, per ADR-0085. A waiver
population of zero would make every waiver assertion vacuous (ADR-0084 §S2).

The header note is `# DERIVED-GUARD PATTERN — instance 11 (ADR-0086). Derives: helper basenames from
a scripts directory, occurrences inside one file. Waiver: `<!-- path-rule-exempt: <reason> -->`,
same-line, which the scanner must TRUNCATE at.` Not extracted into a shared helper, per §3.4.

## 3. Alternatives considered

### 3.1 Population: trust ADR-0028's "five plus one deferred" and fix one line

**Rejected**, and the SPEC forbids it in terms. The count was accurate on 2026-07-11 and is wrong
now: five of today's ten call sites were written by ADR-0099 three weeks later. Fixing the one named
line would have closed the issue's literal text, left nine live defects, and — worse — produced a
green result that reads as "the convention is enforced". This is the same shape as ADR-0091's
by-name archive check, which would have missed 38 of 41 subjects while looking correct.

### 3.2 Predicate: form only — prose is a bare code span, everything else is a call site

**Rejected on evidence, and it was the first design tried.** It classifies
``via `manifest-set-flag.sh` `` — the issue's own subject, ADR-0028's deferred sixth — as compliant,
because it is byte-for-byte the same shape as the prose ``do not call `manifest-set-flag.sh` ``. It
would have shipped a guard that goes green against the defect it was commissioned for, with a clean
count and a plausible design story. The verb rule costs a word list and three declared waivers and
catches it.

### 3.3 Predicate: require a declared waiver on every bare mention, no verb rule

**Rejected on cost, having been measured.** It is the strictest option and it is defensible; it
would need **19 markers on 18 lines** of a 4012-line instruction file the model reads on every chain
run, and it would tax every future edit that names a helper in passing with a 40-character
justification. The verb rule reduces that to five markers whose false-positive class is exactly the
one the SPEC names, at the price of a residual blind spot (§4 Negative). A guard that makes its own
file unpleasant to edit gets weakened by the next author, which is worse than a disclosed hole.

### 3.4 Extract the derived-guard scaffolding into a shared helper

**Rejected — ADR-0086's criterion, applied rather than cited.** Extract only when two copies giving
different answers would be a defect. This guard asks its own question about its own population
(occurrences of a derived basename inside one markdown file) with its own waiver payload and its own
count-guard thresholds. `>= 7`, `>= 50` and `>= 1` are legitimately different numbers from every
other instance's, and the marker's syntax follows the file's language. A defect in a shared source
would disable eleven guards at once, in the stay-green way this repository has already watched three
times. Instance 11 stays a deliberate copy, with the rule recorded in its header as the other ten do.

### 3.5 Home: a new hermetic test file, one-per-issue

**Rejected, narrowly.** It is the dominant convention and it would be correct; it costs a manual
append to `docs-ci.yml`'s explicit list, the exact step that left four harnesses CI-dark until
ADR-0113. That risk is now caught (`pairs-completeness.test.sh` CI1), so this is a preference rather
than a hazard — but the SPEC names `concept-to-code-manifest-helpers-guards.test.sh` first, its
Section D is this class's instance-level ancestor, and keeping the instance pins beside the class
guard makes the relationship legible to the next reader. Zero CI wiring beats caught CI wiring.

### 3.6 Home for the checker: `staging/plugin/scripts/` with a `PAIRS` entry

**Rejected.** A `PAIRS` entry deploys the script to `~/.claude/hooks/`, where nothing calls it, and
creates a sync dependency for a check that only ever runs from the repository. `plugin/scripts/`
would also put it inside `pairs-completeness.test.sh`'s population, forcing either a pointless
deployment or a declared exemption in a list documented as probe-only tooling. `tests/` needs
neither.

### 3.7 The five `manifest-set-gate.sh` shorthands: drop the command, keep the pointer

Considered seriously. Each of the five reads "see *Gate approval recording* in §5:
`manifest-set-gate.sh <manifest-path> N approved …`", and ADR-0099 wrote the canonical block
precisely so the command is named once. Deleting the shorthand and keeping only the pointer would
honour that intent and remove five occurrences outright. **Rejected**: it changes five gate blocks'
text materially, loses the at-a-glance argument shape at the point of use, and is an interpretive
edit where a mechanical one is available. Prefix substitution is the smaller and more reversible
change, and matches what ADR-0028 did to its own five.

### 3.8 Reword the six prose occurrences into the canonical form instead of waiving them

**Rejected as a principle, not a preference.** Two of the six could be backticked into compliance in
one keystroke. Rewording prose so a checker stops complaining is how prose gets worse, and it would
establish that the guard outranks the sentence. A line is either a call site — converted — or prose
— declared. There is no third move.

### 3.9 Widen the scan to every skill that calls these helpers

Measured while deriving: `autopilot-build` has 9 bare occurrences of 15, `project-conductor` 8 of 8,
`nightly-autopilot` 5 of 7, `commit` and `deep-refactor` 1 each. **Out of scope by the SPEC**, and
correctly so — the PATH RULE is `concept-to-code`'s own stated rule, and whether it binds a
neighbouring skill's prose is a decision, not a cleanup. The checker takes the file as an argument
specifically so a later issue can point it elsewhere without editing it. Disclosed, not half-done.

## 4. Consequences

### Positive

- The PATH RULE is enforced by something for the first time since it was written. Its ten live
  violations are closed, including the one ADR-0028 named and the five ADR-0099 created without
  knowing the rule existed.
- The population is now **measured, not asserted**: 62 occurrences, 46 compliant, 16 findings, with
  the derivation itself count-guarded so it cannot silently stop resolving.
- The next bare call site fails at the moment it is written, in a harness already wired into CI, with
  no deployment step between the fix and the guard.
- The checker introduces **no sync dependency**. It lives outside every deployment path, so it cannot
  be "inert until sync" or — the worse variant this repository has hit repeatedly — abort a live gate
  because a machine has not synced.
- The instance-numbering collision at 10 was found by deriving the number instead of trusting the
  brief, and is on record before a third file claims it.
- `manifest-field-state.sh` is inside the derived helper set although ADR-0016-era prose never listed
  it in the inventory: deriving from the directory rather than from a hardcoded list means a helper
  added tomorrow is in scope without anyone remembering to add it.

### Negative

- **The residual blind spot is real and is the price of §3.3.** A future call site written as
  ``record X using an invocation verb outside the set, then `<helper>.sh` `` is invisible to the
  checker. The verb set is a list, and a list is a judgement encoded as data. It is stated in the
  script header, and the honest reading of a green run is "no *recognised* invocation shape is bare",
  not "no bare call site exists".
- **The comment-line exemption is broader than fenced code.** Any line whose first non-blank
  character is `#` is skipped, which includes markdown headings. Harmless today (no heading names a
  helper) and a hole if one ever does.
- Five HTML comments enter a 4012-line instruction file the model reads on every chain run —
  ~120 tokens, accepted on ADR-0083/0084's terms, and the first time this particular file pays it.
- Five gate-recording lines get ~48 characters longer (§3.7). A reviewer scanning the diff will see
  five near-identical long lines change for what looks like no behavioural reason.
- The guard reads `concept-to-code/SKILL.md` only. `autopilot-build`, `project-conductor`,
  `nightly-autopilot`, `commit` and `deep-refactor` carry 24 bare occurrences between them and are
  outside the population by design (§3.9). A green run says nothing about them.
- The checker verifies a **shape**, never that an instruction is correct. An absolute path pointing
  at a helper that does not exist passes.

### Neutral

- Sections A–E of `concept-to-code-manifest-helpers-guards.test.sh` are byte-untouched, D1–D5
  included. The class guard subsumes their intent but not their anchors: they pin five specific
  sentences, and one has already been updated once for a legitimate reword (ADR-0040's `step 8b` →
  `step 8c`).
- No `docs-ci.yml` change, no `sync-to-claude.sh` `PAIRS` change, no `.claude/test-cmd` change, no
  manifest schema change, no deployed file changed. The smallest blast radius available for the
  finding count.
- Instance 11 of the derived-guard pattern, deliberately not extracted (§3.4), with the rule recorded
  in the section header exactly as instances 1–6 record it.
- The three `$_c2c/` occurrences are treated as compliant. The variable is bound to
  `$HOME/.claude/skills/concept-to-code/scripts` two lines above its first use, inside the same
  fence — a fully-qualified deployed path by construction, and the fence is already an ADR-0083
  declared contract executed by a test.
- ADR-0028's body is not edited. Its §2.4 deferral was accurate for its moment (ADR-0034 precedent);
  the amendment is recorded here and in the living `CLAUDE.md` summary.

## 5. References

- `SPEC.md` (repo root) — issue #286
- `staging/plugin/skills/concept-to-code/SKILL.md` — the file carrying the population and the rule
- `staging/plugin/skills/concept-to-code/scripts/manifest-*.sh` — the seven helpers the population is
  derived from
- `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` — ADR-0028's harness,
  gaining Section F
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry (ADR-0108)
- `staging/plugin/scripts/tests/pairs-completeness.test.sh` — the `plugin/scripts/*.sh` population
  this checker deliberately sits outside, and the CI-list guard added by ADR-0113
- `docs/architecture/ADR-0028-32-manifest-helpers-guards.md` — the source and the deferral
- `docs/architecture/ADR-0099-238-hitl-gate-audit-trail.md` — author of five of the ten call sites
- `docs/architecture/ADR-0082-207-210-cross-reference-form.md` — distinctive anchors; the extractor
  must skip its own declaration line
- `docs/architecture/ADR-0086-derived-guard-pattern-not-extracted.md` — the extraction criterion
- `docs/architecture/ADR-0085-208-derived-guard-boundaries.md` — count-guard the denominator
- `docs/architecture/ADR-0093-232-macos-detection-false-positives.md` — the built-alternation failure
  this checker avoids by literal matching
- Implementation plan: `docs/superpowers/plans/2026-08-02-the-sixth-bare-manifest-set-flag-sh-ment.md`
