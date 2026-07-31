# SPEC — the reason floor is duplicated in seven derived guards and nothing stops one drifting

Source: GitHub issue #304

## Objectives
1. Re-derive the instance count of the derived-guard pattern and the reason floor each instance
   uses, rather than trusting the recorded figures — ADR-0086 says six, ADR-0087 records seven, and
   ADR-0086 itself notes PROJECT.md said four and named the wrong four.
2. Apply ADR-0086's own criterion to the result: extract only when two copies giving different
   answers would be a defect. The criterion is about the *predicate*; the 40-character reason floor
   and the count-guard idiom are a shared convention rather than six different questions.
3. Detect a drift in the shared convention without introducing a shared helper, so each guard file
   stays independently runnable — or, if the honest answer is that no mechanism is worth it, record
   that as a decision with the criterion applied.

## Scope
In: the enumeration of derived-guard instances and the reason floor each one applies; a drift
detector over the shared convention (the floor value, and the count-guard idiom on the derivation);
or, if the criterion says no mechanism is warranted, a recorded decision.

Out: extracting the predicates themselves — ADR-0086's refusal stands, since the six-plus guards ask
different questions about different populations and correlated failure is worse than duplication for
guards specifically. The hermeticity property is a hard constraint, not a preference: each test file
must remain individually runnable (`bash <file>`), as `.claude/test-cmd` and `docs-ci.yml` both
invoke them one at a time. No guard's population, waiver syntax or marker position rules change.

## Stack
Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture
Instances carrying the `DERIVED-GUARD PATTERN — instance N` header today, all under
`staging/plugin/scripts/tests/`:

- `transcript-scan-rule.test.sh` (instance 1) — files filtered by content; waiver
  `# transcript-scan-exempt: <reason>`; floor applied at `T4`.
- `fence-contract-coverage.test.sh` (instance 2) — fenced blocks inside a file; waiver
  `<!-- fence-contract: <id> -->` / `<!-- fence-illustration: … -->`, which is also the extraction
  anchor; floor at `F5`.
- `cross-reference-form.test.sh` (instance 3) — token occurrences inside a file; waiver
  `xref-exempt: <token>|<token> — <reason>`, which the extractor must SKIP; floor at `U3`.
- `skill-coverage-perimeter.test.sh` (instance 4) — directories verified against another tree;
  waiver `<!-- skill-coverage-exempt: <reason> -->`, position-constrained; floor at `S3`.
- `skill-text-corrections.test.sh` (instance 5) — names parsed from one prose line (section F6);
  no waiver.
- `agent-command-scope.test.sh` (instance 6) — names parsed from a `case` arm (section J); no
  waiver.
- `manifest-field-state.test.sh` (instance 8) — the value set on both sides; no waiver, by design
  (a value domain with an exemption is not a domain).

Further instances the re-derivation must reconcile against the headers, which are numbered
inconsistently ("instance N of 6" alongside "instance 8"): `transition-producer.test.sh` (waiver
`# transition-producer-exempt: <target> — <reason, >= 40 chars, ONE line>`, floor at `TP4`) and the
deployed-only registry assertions `DO1`–`DO5` in `pairs-completeness.test.sh` (floor at `DO3`).

Supporting files: `staging/sync-to-claude.sh` (holds the `# deployed-only:` and
`# pairs-zone-anomaly:` declarations two of the guards read),
`docs/architecture/ADR-0086-derived-guard-pattern-not-extracted.md` (the source; the quoted line
numbers will have moved), `docs/architecture/ADR-0087-222-deployed-only-skills.md` (records the
count is already seven), `staging/plugin/scripts/tests/plant-check.sh`,
`.github/workflows/ci.yml` and `.github/workflows/docs-ci.yml`.

## Data model
None in the application sense. The convention under review has two shared elements:
- a reason floor — the minimum character length of a declared waiver's reason, currently 40 at every
  site measured;
- a count guard on the derivation — a minimum candidate count (`>= 8`, `>= 25`, `>= 40`, `>= 100`,
  `>= 2` at different sites) whose *threshold* is legitimately per-population, while the *idiom* is
  shared.

## API / Interfaces
- The one-line waiver markers, one per guard, each in the language of the file it lives in (shell
  comment for hook-facing guards, HTML comment for markdown-facing ones) and each carrying a
  different payload (reason; reason + id; reason + token list) and, in one case, a position
  constraint.
- The per-instance header line `# DERIVED-GUARD PATTERN — instance N …`, which today is the only
  record of membership in the pattern and is itself inconsistent about the total.
- Whatever drift detector this feature adds: it must read the instances as data, not link them into
  a shared runtime dependency.

## UI flows
None.

## Edge cases
- The recorded counts disagree (six in ADR-0086, seven in ADR-0087, seven in the issue, and the
  headers themselves mix "of 6" with "instance 8"), so the count must be re-derived rather than
  taken from any of them.
- An instance that legitimately uses a different threshold for its count guard is not a drift; only
  a divergence in the shared convention is.
- A detector that reads the instance headers is only as complete as the headers: an eighth or ninth
  copy written without the header line is invisible to it — the exact failure ADR-0086 disclosed.
- A shared helper would restore correlated failure: a defect in one source disables every guard at
  once, in the stay-green way this repository has already watched happen.
- A number such as `40` appears in these files for unrelated reasons (a divergence count, a
  line-count guard, a slug truncation length), so a naive scan for the literal counts sites that are
  not the floor — rule 12 applied to the detector itself.
- Recording "no mechanism" is a legitimate outcome under R-02, but only as a decision with the
  criterion applied, not as an eighth repetition of the disclosure.
- Per the repository's standing rules: any new assertion must be seen RED against a declared plant.

## Success criteria
- [ ] R-01 — a drift in the shared convention is detected, without a shared helper that would break
      the hermeticity ADR-0086 protects (each file must stay independently runnable).
- [ ] R-02 — if the honest answer is that no mechanism is worth it, that is recorded as a decision
      with the criterion applied, not left as a disclosure repeated an eighth time.
