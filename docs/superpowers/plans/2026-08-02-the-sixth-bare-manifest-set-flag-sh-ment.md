# Implementation plan — the bare manifest-helper mentions in concept-to-code/SKILL.md (issue #286)

ADR: `docs/architecture/ADR-0117-286-path-rule-bare-mentions.md`
SPEC: `SPEC.md` (repo root) — declares **R-01, R-02, R-03**
Phase 10, Wave 1 (LOW: single skill file plus one new checker, no live-guardrail behaviour change).

TEST-CMD: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
(already trusted; unchanged by this feature).

---

## The measurement this plan is built on

Re-derived on 2026-08-02 against the current staged `SKILL.md` (4012 lines). **Do not trust
ADR-0028's "five plus one deferred"** — the SPEC forbids it and the number is stale.

| bucket | count |
|---|---|
| total occurrences of the seven `manifest-*.sh` basenames | 62 |
| compliant — absolute prefix (`~/.claude/…`, `$HOME/…`, `$_c2c/`) | 33 |
| compliant — comment line (first non-blank char `#`) | 3 |
| compliant — canonical prose (bare code span, no args, no invocation verb before) | 10 |
| **findings** | **16** — 10 call sites, 6 prose |

**Task 1 re-derives this independently.** If your count differs from 62/33/3/10/16, stop and report
the difference rather than adjusting the plan's numbers to match — the file may have moved under us.

### The ten call sites (R-01), anchored on distinctive strings, never line numbers (ADR-0082)

| # | distinctive anchor today | fix |
|---|---|---|
| 1 | ``6. Invoke `scripts/manifest-init.sh` with args:`` | insert absolute prefix |
| 2 | ``1. Invoke `scripts/manifest-validate.sh <manifest-path>`. Non-zero exit`` | insert absolute prefix |
| 3 | ``via `manifest-set-flag.sh` and take the Agent-tool fallback`` — **ADR-0028's deferred sixth** | insert absolute prefix |
| 4 | ``(call manifest-transition.sh now)`` | add backticks **and** absolute prefix |
| 5 | ``via `scripts/manifest-transition.sh`, then immediately transition based on `chain_path``` | insert absolute prefix |
| 6 | ``in §5: `manifest-set-gate.sh <manifest-path> 1 approved`` | insert absolute prefix |
| 7 | ``in §5: `manifest-set-gate.sh <manifest-path> 2 approved`` | insert absolute prefix |
| 8 | ``in §5: `manifest-set-gate.sh <manifest-path> 3 approved`` | insert absolute prefix |
| 9 | ``in §5: `manifest-set-gate.sh <manifest-path> 4 approved`` | insert absolute prefix |
| 10 | ``in §5: `manifest-set-gate.sh <manifest-path> 5 approved`` | insert absolute prefix |

Sites 6–10 were written by ADR-0099 (issue #238), three weeks after ADR-0028 counted the population.

### The five prose lines needing a declared waiver (R-01), six occurrences

| # | distinctive anchor | why it is prose |
|---|---|---|
| a | ``commit and this assertion: `manifest-set-flag.sh <m> autopilot true` and`` (**two** occurrences on this line) | names *which two writes* land there; describes, never instructs |
| b | ``NOT via `manifest-set-flag.sh`, which is boolean-only`` (the `BASELINE_COMMIT` sentence) | negated — says not to use it |
| c | ``record NOTHING, do not call `manifest-set-flag.sh``` | negated |
| d | ``NOT via manifest-set-flag.sh which is boolean-only`` (the `step5_mode` fallback sentence) | negated |
| e | ``(manifest-transition.sh, Bash, Skill, Agent)`` | enumerates tool-call kinds, not a command |

---

## Invariants for every task

- **Anchor on distinctive strings, never line numbers** (ADR-0082). Every anchor above is chosen to
  be unique; verify uniqueness with `grep -c` before editing.
- **Sections A–E of `concept-to-code-manifest-helpers-guards.test.sh` are byte-untouched**, D1–D5
  included. Add Section F only.
- **Bash 3.2 / BSD tools.** No GNU-only `sed`, no `grep -P`, no process substitution.
- **Rule 12 at two levels.** (i) The documentation paragraph added in Task 5 must use `<helper>.sh`
  placeholders and never a real basename in a violating shape. (ii) It must name the waiver as
  `path-rule-exempt` **without** its `<!--` delimiters, or it becomes a malformed waiver on its own
  line.
- **Every new assertion carries a declared plant** (ADR-0108): `# plant: <id> | <path-rel-to-staging>
  | <needle> | <replacement>`, at **column 1** (an indented declaration is silently skipped —
  ADR-0115 §PC4), no ` | ` inside any field, no newline in a replacement. Avoid the gate-3 and
  gate-5 recording lines as plant targets — their notes contain a `|`.
- **Writes are confined to:** `staging/plugin/scripts/tests/path-rule-check.sh` (new),
  `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh`,
  `staging/plugin/skills/concept-to-code/SKILL.md`. Nothing under `~/.claude`, nothing in `docs/`.

### Batch boundaries (ADR-0088 §D5, ADR-0101)

- **Task 1 and Task 2 must not share a batch.** Task 2's assertions execute the script Task 1
  creates; in the same batch they would go red at exit 127 — a red for the wrong reason, which is
  what ADR-0101 rule 1 exists to prevent, and rule 1 outranks rule 2.
- **Task 2 leaves one EXPECTED red**: assertion `F2` (the real `SKILL.md` is clean) fails at the end
  of Task 2 because the file still has 16 findings. **Task 4 greens it.** This is ADR-0101's case 1
  — a declared red with a named task that resolves it, inside the same Step 5. Any *other* red is
  case 3 and stops the run.
- Suggested batching: `[1]` `[2]` `[3, 4]` `[5, 6]` `[7, 8]`.

---

## Task 1 — the derived checker `path-rule-check.sh` (R-02)

*Budget: staging/plugin/scripts/tests/path-rule-check.sh (~160 lines)*

- [ ] Create `staging/plugin/scripts/tests/path-rule-check.sh`. **Not** `.test.sh` — that suffix
      would make `.claude/test-cmd`'s glob execute it as a harness. **Not** under
      `staging/plugin/scripts/` — that is inside `pairs-completeness.test.sh`'s `*.sh` population and
      would force a pointless `PAIRS` entry or an exemption (ADR-0117 §3.6).
- [ ] Usage: `path-rule-check.sh <skill-md> <helper-scripts-dir>`. Taking the file as an argument is
      deliberate — a later issue can point it at `autopilot-build/SKILL.md` without editing it.
- [ ] **Derive** the helper basenames from `<helper-scripts-dir>/manifest-*.sh` at run time. Never a
      hardcoded list: a helper added tomorrow must be in scope without anyone remembering.
- [ ] **Scan by literal `index()` in awk, never a built regex.** Building an alternation from derived
      names is how ADR-0093 shipped a rule that silently matched nothing (BSD `grep` rejects an empty
      ERE alternative and the sweep then reads as clean).
- [ ] Per line, **truncate at the first `<!-- path-rule-exempt:`** before scanning, and remember that
      the line carried a marker. This is ADR-0082's skip-your-own-declaration rule and it is
      load-bearing: a reason will name the helper it excuses, and without the truncation a marker
      could waive the occurrence it introduced (rule 12).
- [ ] Predicate, applied in this order per occurrence:
      1. **compliant/absolute** — preceded by `~/.claude/skills/concept-to-code/scripts/`,
         `$HOME/.claude/skills/concept-to-code/scripts/`, or `$_c2c/`;
      2. **compliant/comment** — line's first non-blank character is `#`;
      3. **finding/invocation-shaped** — preceding text ends `scripts/`, OR the char before is not a
         backtick, OR the char after is not a backtick, OR the normalised preceding word is an
         invocation verb;
      4. **compliant/prose** otherwise.
- [ ] Word normalisation: strip a trailing backtick from the preceding text, take the last
      whitespace-separated field, strip leading `(` and `*`, strip trailing `.,:*`, lowercase.
- [ ] Verb set: `via call calls calling invoke invokes invoking run runs running use uses using
      execute executes`. `bash` is deliberately absent — it is already caught by the
      not-backticked rule, and listing it would misdescribe which rule does the work.
- [ ] Waiver handling: an invocation-shaped occurrence on a marked line is `waived`, not a finding.
      A marked line producing **zero** waived occurrences emits `STALE-WAIVER <line>`; a reason under
      **40 characters** emits `SHORT-REASON <line>`. Both are findings (ADR-0081 §ZA4 — a stale
      waiver reads exactly like clean coverage).
- [ ] Exit contract, stated in the header: **0** no findings (stdout **empty**) · **1** findings, one
      per line on stdout · **2** bad invocation (wrong arg count, unreadable skill file, missing
      helper dir) · **3** DID NOT RUN (zero helper basenames derived).
- [ ] Header must state, in words: *this is a CHECKER — the caller branches on the exit code. It
      prints no `CLEAN` sentinel and must never grow one; `weakening-scan.sh` is a REPORTER and the
      two idioms have already been confused once at a single call site (ADR-0048).*
- [ ] Always print to **stderr**:
      `path-rule-check: helpers=<n> occurrences=<n> compliant=<n> waived=<n> findings=<n>`.
- [ ] **Checkpoint (RED evidence, live rather than synthetic — ADR-0087's inverted order).** Run it
      against the unfixed `SKILL.md`. Expect exit **1**, `helpers=7 occurrences=62 compliant=46
      waived=0 findings=16`, and the 16 finding lines to match the ten call sites and six prose
      occurrences tabled above. **Record the output verbatim in the task report.** A different count
      means stop and report, not adjust.

## Task 2 — Section F assertions and fixtures (R-02, R-03)

*Budget: staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh (~190 lines)*

- [ ] Append Section F to `concept-to-code-manifest-helpers-guards.test.sh`. Sections A–E byte-
      untouched. No new test file, so **no `.github/workflows/docs-ci.yml` edit** — this harness is
      already in the named `shell-tests` list, which is the deciding practical reason for extending
      it (ADR-0117 §2.6).
- [ ] Section header comment: `# DERIVED-GUARD PATTERN — instance 11 (ADR-0086). Derives: helper
      basenames from a scripts directory, occurrences inside one file. Waiver: a same-line
      path-rule-exempt HTML comment, which the scanner must TRUNCATE at.` **Instance 11, not 10** —
      10 is already claimed twice (`conductor-entry-failure-split.test.sh` and, in prose,
      `concept-to-code-bsd-autopilot-gates.test.sh`). Verify by deriving the numbers again before
      writing.
- [ ] Assertions (both directions per ADR-0039 — a good input and the bad one the check exists to
      catch):
      - `F1` — the checker exists and is invocable by `bash`.
      - `F2` — **the real `SKILL.md` is clean**: exit 0 and **stdout empty**. *Expected RED until
        Task 4.*
      - `F3` — a fixture copy with one planted bare mention: exit **1**, and the finding line names
        the planted line.
      - `F4` — count guard on the **denominator**: `helpers >= 7` from the stderr summary. Guard the
        derivation, not the matches (ADR-0085) — an empty derivation reads as full coverage.
      - `F5` — count guard: `occurrences >= 50`.
      - `F6` — count guard: `waived >= 1`. Zero waivers would make F7/F8/F9 vacuous (ADR-0084 §S2).
      - `F7` — fixture: a marked line with **no** invocation-shaped occurrence reports
        `STALE-WAIVER` and exits 1 (the reverse direction — ADR-0081 §ZA4).
      - `F8` — fixture: a reason that **names a helper** and a line with no other occurrence must not
        self-waive; the marker's own text contributes nothing to `occurrences` (rule 12).
      - `F9` — fixture: a reason shorter than 40 characters reports `SHORT-REASON` and exits 1.
      - `F10` — fixture: an empty helper directory → exit **3**, and the message says the check did
        not run. Distinct from exit 0.
      - `F11` — bad invocation (no arguments) → exit **2**.
      - `F12` — the checker is a CHECKER: its source contains no `CLEAN` sentinel emission, and F2's
        stdout is empty on success. Guards against a future author bolting on a reporter idiom.
- [ ] **Checkpoint.** Run the harness. Expect **F2 RED** (findings=16) and **F1, F3–F12 GREEN**. Any
      other red stops the run (ADR-0101 case 3). Record the exact pass/fail line.

## Task 3 — convert the ten call sites (R-01)

*Budget: staging/plugin/skills/concept-to-code/SKILL.md (~12 lines)*

- [ ] Insert `~/.claude/skills/concept-to-code/scripts/` before the basename at each of the ten
      anchors tabled above. **Prefix substitution only** — no argument invention, no sentence
      rewrite (ADR-0028 §2.4's own rule, reused because it is what keeps a mechanical fix
      mechanical).
- [ ] Site 4 additionally gains the backticks its neighbours have: `(call
      `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh` now)`.
- [ ] Do **not** touch D1–D5's five sites (already absolute) and do not reword any prose.
- [ ] **Checkpoint.** `path-rule-check.sh` against `SKILL.md`: findings **16 → 6**, all six on the
      five prose lines tabled above. Exit still 1.

## Task 4 — declare the six prose occurrences (R-01, R-02)

*Budget: staging/plugin/skills/concept-to-code/SKILL.md (~5 lines)*

- [ ] Append `<!-- path-rule-exempt: <reason> -->` to the **end of each of the five prose lines**
      (a–e above). Same line, not the line above: an HTML comment on its own line breaks the
      surrounding markdown paragraph, and all five sit mid-paragraph.
- [ ] Each reason is **one line and ≥ 40 characters**, and says why the line is a description rather
      than an instruction. A reason that wraps is a prose assertion depending on where the text
      breaks (ADR-0082 §U3).
- [ ] Line (a) carries **two** occurrences and one marker covers the line — say so in its reason.
- [ ] Do not reword any of the five (ADR-0117 §3.8): a line is a call site — converted — or prose —
      declared. Rewording prose so a checker stops complaining is how prose gets worse.
- [ ] **Checkpoint.** `path-rule-check.sh`: exit **0**, stdout empty, stderr
      `helpers=7 occurrences=62 compliant=56 waived=6 findings=0`. Re-run the harness: **F2 now
      GREEN**, whole file green.

## Task 5 — write the convention into SKILL.md's PATH RULE block (R-01)

*Budget: staging/plugin/skills/concept-to-code/SKILL.md (~6 lines), concept-to-code-manifest-helpers-guards.test.sh (~14 lines)*

- [ ] Extend the existing `> **PATH RULE — …**` blockquote with one paragraph stating: prose may name
      a helper as a bare code span with no arguments and no path prefix; a relative
      `scripts/<helper>.sh` path, an unquoted name in running text, a name followed by arguments, or
      a name preceded by an invocation verb is read as a call site and must carry the absolute
      prefix; a line that is genuinely prose in one of those shapes declares a `path-rule-exempt`
      HTML comment on that same line, whose exact form is stated in `path-rule-check.sh`'s header.
- [ ] **Rule 12, both levels.** Use `<helper>.sh` placeholders — a real basename in a violating shape
      would make the documentation a finding. Name the marker as `path-rule-exempt` **without** the
      `<!--` opening — spelling the literal would make the paragraph a malformed waiver. After this
      task the literal marker opening appears in `SKILL.md` only where it is a live waiver, which the
      STALE-WAIVER check already enforces.
- [ ] Add assertion `F13`: the paragraph is present. Match against a **flattened, undecorated,
      case-insensitive** copy of the file — collapse line breaks, strip backticks and asterisks. A
      prose assertion must not depend on where the text wraps or how a word is decorated
      (ADR-0073 / 0076 / 0080 / 0098 / 0101, seven instances and counting).
- [ ] **Checkpoint.** `path-rule-check.sh` still exits 0 with the same summary. Harness green.

## Task 6 — plant every new assertion (R-03)

*Budget: staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh (~15 lines)*

- [ ] One `# plant:` declaration per new assertion `F1`–`F13`, at **column 1**, beside the assertion
      it proves. Where an assertion cannot be planted, say why in a comment at that site rather than
      leaving it silently unplanted (ADR-0113 §CI1's precedent).
- [ ] `F2`'s plant is **R-03 itself**: revert one converted call site to its bare form and require F2
      to go RED. Prefer the ADR-0028 sixth (``via `…/manifest-set-flag.sh` and take the Agent-tool
      fallback``) or a gate-1/2/4 recording line. **Avoid the gate-3 and gate-5 lines** — their notes
      contain a `|`.
- [ ] Plants for the count guards mutate the **checker**, not the file: break the `manifest-*.sh`
      glob (F4) or the literal-scan token (F5), and require the assertion to redden.
- [ ] Run `bash staging/plugin/scripts/tests/plant-check.sh`. **Inspect what each plant actually
      produced** before believing that it fired (ADR-0090 — a plant aimed one line off, or silently
      truncated by the ` | ` separator, reports as fired from a mutation that is not the one it
      describes).
- [ ] A plant that does **not** fire is evidence about the assertion, not a formality to get past
      (ADR-0089). If two guards cover one assertion so neither is isolated, split the fixture
      (ADR-0104, ADR-0111 §B9).
- [ ] **Checkpoint.** `plant-check.sh` green, every new plant firing, `PC0`/`PC4` unaffected.

## Task 7 — verify the boundaries by running them, not by reading (R-02)

*No file changes expected.*

- [ ] Run `bash staging/plugin/scripts/tests/pairs-completeness.test.sh`. It must stay green:
      `path-rule-check.sh` sits under `tests/`, outside the non-recursive `plugin/scripts/*.sh`
      population and outside the `*.test.sh` CI list. **Verify by running it** — the claim is derived
      from `plant-check.sh`'s precedent, not from a guarantee (ADR-0081: a fix is executed, not just
      written).
- [ ] Run the full suite: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1;
      done`. A contract change in a shared instruction file can redden a harness in an unrelated
      module; the full run is not optional.
- [ ] Confirm `.github/workflows/docs-ci.yml`, `.claude/test-cmd` and `staging/sync-to-claude.sh` are
      **unmodified** (`git status`). If any of the three needs a change, stop and report — it means
      the design assumption in ADR-0117 §2.1/§2.6 was wrong.
- [ ] Confirm nothing under `~/.claude` was written.

## Task 8 — record the amendment and the disclosures (R-02)

*Budget: staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh (~6 lines)*

- [ ] In Section F's header, record in one or two lines: the residual blind spot (an invocation verb
      outside the set), the comment-line exemption's breadth (any line starting `#`, markdown
      headings included), and that the population stops at `concept-to-code/SKILL.md` while
      `autopilot-build` (9 bare of 15), `project-conductor` (8 of 8), `nightly-autopilot` (5 of 7),
      `commit` (1) and `deep-refactor` (1) are outside it by design. A green run must not read as a
      claim about them.
- [ ] Report — do not fix — the derived-guard instance-number collision at 10, and that instance 7
      carries no marker at all.
- [ ] Report for the durable record: five of the ten call sites were created by ADR-0099 three weeks
      after ADR-0028 counted the population. That, not the deferred sixth, is why re-derivation was
      the SPEC's instruction.
- [ ] **Final checkpoint.** Full suite green, `plant-check.sh` green, `path-rule-check.sh` exit 0.

---

## Requirement coverage

| ID | tasks |
|---|---|
| R-01 — every call site uses the PATH-RULE form | 3, 4, 5 |
| R-02 — a derived guard fails on a new bare mention, count-guarded | 1, 2, 7, 8 |
| R-03 — the guard is seen RED against a planted bare mention | 2, 6 |

## Observable-contract note

No HTTP status, function signature, output format or DB schema changes. The one new observable
contract is `path-rule-check.sh`'s exit codes, which has no pre-existing call site to update: a grep
for `path-rule-check` across the repository returns nothing before Task 1. The five `manifest-set-gate.sh`
shorthand lines change text but not behaviour; `grep -rn "manifest-set-gate.sh <manifest-path>"`
across `staging/` and `.github/` before Task 3 confirms the only readers are the five sites
themselves and no test asserts their current bare form (Sections A–E anchor on `manifest-set-flag.sh`
sites only). Run the **full** suite at Task 7 regardless.

## Risks

- **The verb set is a judgement encoded as data.** A call site written with a verb outside it passes.
  Stated in the header; a green run means "no recognised invocation shape is bare".
- **A plant that reports as fired may have mutated the wrong thing** — the ` | ` separator silently
  truncates a field, and a needle can land one line off. Inspect the produced diff (ADR-0090).
- **F2 is red between Task 2 and Task 4 by design.** Declared here so an unattended breaker reading
  a mid-Step-5 checkpoint does not treat it as case 3.
- **Anchors can move.** Every anchor in this plan is a distinctive string, and Task 1's checkpoint
  re-derives the whole population before any edit. If the counts differ, the file moved — report,
  do not adapt.

TEST-CMD CANDIDATE: none
TEST-CMD MODE: brownfield
