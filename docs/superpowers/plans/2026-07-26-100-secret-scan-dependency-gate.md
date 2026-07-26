# Plan — Secret content scan, dependency gate, CI steps (issue #100)

- **ADR:** `docs/architecture/ADR-0046-100-secret-scan-dependency-gate.md`
- **SPEC:** `SPEC.md` / `docs/specs/100-secrets-and-dependency-gate-content-scan.spec.md`
- **Test command:** `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
- **Tasks:** 9, ordered by dependency. Every task states its RED before its GREEN.

---

## Pre-flight constraints — read all of these before Task 1

**PF1 — Filenames. Three paths the SPEC names literally cannot be created on this machine.**
`protect-files.sh` is a `PreToolUse` hook on `Write|Edit|MultiEdit` whose `PROTECTED` list contains
the substrings `secrets`, `.env`, `.pem`, `.key`, `credentials`, `/.git/`, `package-lock.json`. Any
`Write` to a path containing one of them is denied with exit 2. This was hit for real while writing
the ADR. Use the singular `secret` everywhere:

| SPEC / brief says | create this instead |
|---|---|
| `…/tests/secrets-dep-gate.test.sh` | `staging/plugin/scripts/tests/secret-dep-gate.test.sh` |
| `ADR-0046-100-secrets-dependency-gate.md` | already created as `ADR-0046-100-secret-scan-dependency-gate.md` |

**Do not route around the hook** — no `cat > file` through `Bash`, no `python3 -c` file write. That
is the exact bypass ADR-0041 and ADR-0045 exist to prevent. The rename is the sanctioned path.

**PF2 — Fixture files are created at run time, never with the `Write` tool.** The dependency-scan
fixtures need names like `package-lock.json`, which PF1 also forbids. Every fixture in this feature
is written by `printf` into a `mktemp -d` directory from inside the harness, which is how every
existing harness in `staging/plugin/scripts/tests/` already works. No repository file is ever named
after a protected pattern.

**PF3 — Bash 3.2 (macOS). No associative arrays, no `mapfile`, no `${v^^}`, no process substitution
`<(…)`, no `<<<`.** Heredocs and pipes only. awk arrays are fine (awk is not bash).

**PF4 — No literal in any file this plan creates may match a detection rule.** The harness runs the
scanner over this repository's own tracked files (Task 3) and fails if a content rule fires. This
plan, the ADR and the harness are all in that corpus. Write every pattern in regex form. Build every
key-shaped string by concatenation at run time, never as one literal token in the file.

> This was verified, not assumed. Every rule in ADR §D3 was run against the ADR and this plan before
> either was handed over. The first draft of Task 2 step 2 below carried a literal 20-character
> access-key-shaped probe string and **matched `aws-access-key-id` in its own plan** — it is now a
> concatenation. The three placeholder examples in section B7 still match the raw `assigned-secret`
> pattern and are deliberately left in place: they are cleared by the placeholder exclusion, so their
> presence in the corpus is evidence the exclusion list does its job.

**PF5 — `awk` interval support was verified live on this machine** (`awk version 20200816`; both
`/AKIA[0-9A-Z]{16}/` and `match($0, /…{16}/)` work). It is not portable to every awk, which is why
ADR §D4 mandates a start-up probe. Do not skip the probe on the grounds that it passes here.

**PF6 — Reporter contract.** Exit 0 whenever a scan completes, findings or not. Exit 2 only on
invalid invocation, exit 3 only when the awk probe fails. Never exit non-zero because something was
found.

**PF7 — `xargs` with an empty input list runs the utility once with no arguments on BSD**, which
makes `grep` read stdin and hang. Any batch invocation must either guard on a non-empty list or pass
`/dev/null` as a fixed first file argument.

---

## Anchor invariants — must be true after every task

- **A1** `staging/plugin/scripts/protect-files.sh` is byte-identical to its state at Task 0.
- **A2** Every bullet under `## Invariant guardrails` in `staging/plugin/skills/commit/SKILL.md` is
  unchanged, in particular the one forbidding a commit of `.env`, secrets and API keys. Text may be
  added elsewhere in the file; no guardrail bullet may be edited or removed.
- **A3** The four filename patterns in `commit/SKILL.md` Step 1 (`.env`, `*secret*`, `*credential*`,
  `*.pem`) still appear in Step 1 prose.
- **A4** `staging/project-templates/ci/ci.yml` still contains the `__TEST_CMD__` token and the job
  name `ci` (`nightly-autopilot/tests/run-tests.sh` and `set-branch-protection.sh` both depend on
  these).
- **A5** `staging/plugin/skills/review-triage-fix/` is untouched, `weakening-scan.sh` included.
- **A6** The existing 25 harnesses under `staging/plugin/scripts/tests/` stay green.

---

## Call-sites checked before planning (contract-staleness sweep)

Changing `commit/SKILL.md` Step 1 changes an observable behaviour of a skill three other skills
invoke. Grepped, and listed here so nobody has to rediscover them:

- `staging/plugin/skills/concept-to-code/SKILL.md` — Step 7 invokes `commit`.
- `staging/plugin/skills/project-init/SKILL.md` — invokes `commit`.
- `staging/plugin/skills/autopilot-build/SKILL.md` — invokes `commit --autopilot` (Step 4 is skipped
  there; ADR §D9 defines the unattended policy, and Task 6 must write it into Step 1 explicitly).
- **No existing test asserts on `commit/SKILL.md` content.** There is nothing to update, and that
  absence is itself why Task 6 adds static anchors.
- `staging/project-templates/ci/ci.yml` is asserted on by
  `staging/plugin/skills/nightly-autopilot/tests/run-tests.sh:62` (`__TEST_CMD__` only). That
  harness is **not** in `docs-ci.yml`'s list — run it by hand after Task 7.
- `staging/sync-to-claude.sh` `PAIRS` is asserted on by
  `staging/plugin/scripts/tests/pairs-completeness.test.sh` (every src must exist under `staging/`).
  Add the two entries only after the two scripts exist, or that harness goes red.

**Run the full suite, not just the new file, after Tasks 6, 7 and 8.** A contract change in a shared
skill or in `PAIRS` can turn a harness red in a module nobody touched.

---

## Task checklist

Index of the task sections below, in execution order. The chain's Step 5 pre-dispatch
validation counts unchecked `- [ ]` items here; the authoritative task detail is in the
`## Task N` sections that follow.

- [x] Task 1 — RED: harness skeleton, sections A/B/C for `secret-scan.sh`
- [x] Task 2 — GREEN: implement `staging/plugin/scripts/secret-scan.sh`
- [x] Task 3 — RED then GREEN: section D, the repository as the false-positive corpus
- [x] Task 4 — RED: section E for `dependency-scan.sh`
- [x] Task 5 — GREEN: implement `staging/plugin/scripts/dependency-scan.sh`
- [x] Task 6 — Wire `commit` Step 1, with section F1–F4 seen RED first
- [x] Task 7 — CI template steps, section F5 seen RED first
- [x] Task 8 — Registration in both registries and in `PAIRS`, section G seen RED first
- [x] Task 9 — Close-out

---

## Task 1 — RED: harness skeleton, sections A/B/C for `secret-scan.sh`

**Create** `staging/plugin/scripts/tests/secret-dep-gate.test.sh` (PF1).

Match `agent-command-scope.test.sh` exactly: `#!/bin/bash`, a header comment block explaining what
the file covers and why, `set -u`, `SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)`,
`STAGING=$(cd "$SCRIPTS/../.." && pwd)`, `TMP=$(mktemp -d)`, `trap 'rm -rf "$TMP"' EXIT`,
`PASS=0; FAIL=0`, `ok()`/`bad()` helpers, lettered sections with comments, and
`echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]` at the end.

Header must state: the false-positive corpus is the repository itself; every positive fixture is
built by concatenation (PF4); the file lives under a name that differs from the SPEC's because of
PF1.

**Section A — content rules fire (positive).** One fixture file per case in `$TMP`, written with
`printf`, scanned with `--files`. Assert the exact rule id appears in the output:

- A1 `aws-access-key-id` — the four-letter prefix plus 16 uppercase alphanumerics, concatenated at
  run time.
- A2 `aws-secret-access-key` — an `aws_secret_access_key` assignment whose value is a 40-character
  `[A-Za-z0-9/+=]` run built at run time.
- A3 `private-key-block` — the PEM opening line, assembled from three concatenated fragments so the
  literal never appears whole in the harness.
- A4 `github-token` — the four-character prefix plus 36 alphanumerics.
- A5 `jwt` — three dot-separated segments, the first two beginning with the JSON-object prefix.
- A6 `assigned-secret` — an `api_key` assignment with an 18-character non-placeholder value.
- A7 exit code is 0 on a run that produced findings (PF6, the reporter contract).

**Section B — the false-positive corpus (negative).** Each fixture must produce **zero** output:

- B1 a GitHub Actions pin line: `uses: actions/checkout@` followed by 40 hex characters.
- B2 the 60-hex fake trust-hash line in the shape `run-hook-tests.sh:159` uses.
- B3 a 64-hex value assigned to a `checksum` key (SHA-256 digest exclusion).
- B4 a bare 44-character base64 blob on its own line with no keyword.
- B5 an absolute path line ending in `SPEC.md` — the case that killed the entropy design.
- B6 an `Authorization` header whose value is a `Bearer` token read from `${GITHUB_TOKEN}`.
- B7 placeholder values: `api_key = "your-api-key-here"`, `password = "changeme"`,
  `token = "xxxxxxxxxxxxxxxxxx"`.
- B8 `token = os.environ["GITHUB_TOKEN"]` (reads, does not define).

**Section C — structure and modes.**

- C1 `filename-pattern` fires on a path named `.env`, reported with line `0`.
- C2 precedence: a `.env` fixture containing three different key shapes yields **exactly one** output
  line, and its rule is `filename-pattern` (SPEC "once, not twice").
- C3 dedup: a file containing the same key shape on five lines yields exactly one line, at the first
  occurrence.
- C4 a binary fixture (contains a NUL byte) produces no finding and no error.
- C5 a listed path that does not exist is skipped; exit stays 0.
- C6 an empty file list produces no stdout and exit 0 (and must not hang — PF7).
- C7 `--diff` mode: a unified diff adding a key reports the **new-file** line number derived from the
  `@@` header, not the diff-line offset.
- C8 `--diff` mode ignores removed (`-`) lines carrying a key.
- C9 an unknown flag exits 2 with usage on stderr.
- C10 the stderr summary line is present on a clean run and names a non-zero scanned-file count
  (ADR §D5).
- C11 a path containing a colon is skipped with a stderr warning, not mis-parsed.
- C12 `SECRET_SCAN_AWK` pointed at a stub that fails the interval probe makes the script exit 3 with
  a stderr message, and produce no stdout (ADR §D4).

**RED check:** run the harness. `secret-scan.sh` does not exist, so every assertion in A, B and C
must report FAIL and the file must exit non-zero. A section that passes here is a broken assertion —
fix the assertion before Task 2. Record the observed FAIL count in the task checkpoint.

---

## Task 2 — GREEN: implement `staging/plugin/scripts/secret-scan.sh`

Bash 3.2 (PF3) + one awk rule engine. Shape:

1. **Arg parse.** `--files <list-file>` (`-` reads the list from stdin), `--diff`. Neither, both, or
   an unknown flag → usage on stderr, exit 2 (C9).
2. **awk probe (ADR §D4).** Build the probe string by concatenation so this script is not itself a
   corpus violation — `p="AKIA"; p="${p}ABCDEFGHIJKLMNOP"` — then assert
   `printf '%s\n' "$p" | "$AWK" '/AKIA[0-9A-Z]{16}/{print "y"}'` prints `y`. Otherwise print a loud
   stderr line naming the awk version and exit 3. `AWK="${SECRET_SCAN_AWK:-awk}"` so the failure path
   is testable (C12).
3. **Build the record stream** `path<TAB>lineno<TAB>content`:
   - `--files`: shell `while IFS= read -r p` loop. Skip and count when `[ ! -f "$p" ]` (C5). Skip with
     a stderr warning when the path contains `:` (C11). Apply the filename `case` (ADR §D7) — on a
     match, print the finding immediately and do not add the file to the scan list (C1, C2).
     Otherwise append to the scan list. Batch-filter binaries with a single
     `grep -Il '' /dev/null <files…>` pass (C4; `/dev/null` first satisfies PF7), then one
     `awk '{printf "%s\t%d\t%s\n", FILENAME, FNR, $0}'` over the survivors.
   - `--diff`: one awk over stdin. Track the current path from `^\+\+\+ b/`, the new-file line counter
     from `^@@ .* \+([0-9]+)`, increment on context and `+` lines, emit only `+` lines (C7, C8). Apply
     the filename `case` to each new path as it appears.
4. **Rule engine.** One awk program reading the record stream. Rule table in evaluation order,
   `assigned-secret` last. Suppress every content finding for a path already reported by
   `filename-pattern`. Dedup on `path SUBSEP rule`, keeping the first line number (C3). Print
   `SECRET\t<path>:<line>\t<rule>`.
5. **`assigned-secret` exclusions** exactly as ADR §D3 lists them: placeholder prefix set, pure hex of
   length 32/40/64/128, env-read markers (`process.env`, `os.environ`, `getenv`, `ENV[`), empty value.
6. **stderr summary** (ADR §D5), always, even on zero findings.
7. `exit 0`.

**GREEN check:** every assertion in A, B and C passes. Then run the whole suite (A6).

---

## Task 3 — RED then GREEN: section D, the repository as the false-positive corpus

Two halves, in this order, because a corpus assertion that is green the moment it is written proves
nothing.

- **D0 (teeth — genuine RED before Task 2 lands, re-verified here).** Copy the repository's own
  `git ls-files` output into `$TMP/list`, append one path pointing at a `$TMP` fixture containing a
  concatenated fake access key, run `--files` over that list, and assert the fixture **is** reported.
  This proves the corpus check can fail. Comment it as such.
- **D1 (the real corpus).** Run `--files` over `git ls-files` alone and assert **zero** findings whose
  rule is not `filename-pattern`. Guard against the vacuous pass: if the file list has zero entries,
  `bad` immediately with an explicit message rather than reporting success (the ADR-0043 lesson,
  applied to this harness).
- **D2** print the `filename-pattern` findings that do appear as informational context; do not assert
  on their exact set — it grows with every document named after this feature.

Label D1 in the source as **an always-PASS forward guard once Task 2 is correct** — it is a
regression pin, not evidence that Task 2 works. That evidence is A, B and D0.

If D1 goes red on a file this feature adds, the fix is the file (split the literal), never the
assertion.

---

## Task 4 — RED: section E for `dependency-scan.sh`

All fixtures are diffs written with `printf` into `$TMP` (PF2) and piped into the script.

- E1 npm: a `package.json` diff adding `"left-pad": "^1.3.0"` → `NEWDEP<TAB>left-pad<TAB>package.json`.
- E2 npm lockfile: a diff adding a `"node_modules/left-pad": {` entry → one `NEWDEP` naming `left-pad`.
- E3 reorder: a lockfile diff whose `+` lines and `-` lines carry the same package set → **no output**
  (SPEC edge case, ADR §D8).
- E4 version bump: a `-` line and a `+` line for the same package at different versions → no output.
- E5 removal only: a `-` line with no matching `+` → no output.
- E6 Python: `+requests==2.31.0` in `requirements.txt` → `NEWDEP` naming `requests`.
- E7 Swift: a `Package.resolved` diff adding an `"identity"` line → `NEWDEP` naming that package.
- E8 `--allow` suppression: E1's diff with an allow file listing `left-pad` → no output. Comment
  lines (`#`) and blank lines in the allow file are ignored.
- E9 default allow path: with no `--allow`, a `.claude/allowed-deps.txt` in the current directory is
  read; assert by running the script from a `$TMP` cwd that contains one.
- E10 inert: a diff touching only `README.md` → no stdout, and a stderr line containing `inert`.
- E11 exit 0 on a run with findings (PF6); exit 2 on an unknown flag.
- E12 output is sorted and stable across two runs of the same input (ADR §D8).

**RED check:** the script does not exist; all of E must FAIL.

---

## Task 5 — GREEN: implement `staging/plugin/scripts/dependency-scan.sh`

One awk program over the diff on stdin, plus a small bash wrapper for arg parsing and the allow file.

Manifest recognition by basename, and the per-type extraction from a line whose leading `+`/`-` has
been stripped:

| type | files | package-name extraction |
|---|---|---|
| npm-manifest | `package.json` | `"<name>": "<version-ish>"` where the value starts with `[~^><=*0-9]` or with `git`/`http`/`file`/`npm`/`workspace` |
| npm-lock | `package-lock.json`, `npm-shrinkwrap.json` | the segment after the last `node_modules/` in a `"node_modules/…": {` key |
| yarn | `yarn.lock` | the text before the last `@` on a line ending in `:` |
| pnpm | `pnpm-lock.yaml` | between the leading `/` and the last `/`, or before `@` in a `<name>@<version>:` key |
| pip | `requirements*.txt` | the text before the first of `=<>~![ ;#` |
| pyproject | `pyproject.toml` | a bare `<name> = "<version>"` key, or the name inside a quoted `"<name><op><version>"` array element |
| pipfile | `Pipfile`, `Pipfile.lock` | a `<name> = ` key, or a `"<name>": {` key |
| poetry | `poetry.lock` | the value of a `name = "<name>"` line |
| swiftpm | `Package.swift` | the last path component of a `.package(url: "…")` URL, `.git` stripped |
| swiftpm-lock | `Package.resolved` | the value of an `"identity" : "<name>"` line |
| cocoapods | `Podfile` | the quoted name after `pod` |
| cocoapods-lock | `Podfile.lock` | the name in a `  - <name> (<version>)` line |

Collect into `added[type SUBSEP name]` and `removed[type SUBSEP name]`. In `END`, emit
`NEWDEP\t<name>\t<manifest-basename>` for each added name absent from `removed` and absent from the
allow set. Pipe stdout through `LC_ALL=C sort -u` (E12). Print the ADR §D5 summary to stderr,
including the `inert` line when no recognised manifest appeared (E10).

Allow set: `--allow <file>` wins; otherwise `.claude/allowed-deps.txt` if it exists; otherwise empty.
Strip `#` comments and blank lines. Pass the file into awk with `-v allowfile=…` and read it with a
`getline` loop.

**GREEN check:** all of E passes, then the full suite (A6).

---

## Task 6 — Wire `commit` Step 1, with section F1–F4 seen RED first

Write the F assertions **before** editing the skill, and confirm they fail.

- F1 `commit/SKILL.md` Step 1 references `secret-scan.sh` and `dependency-scan.sh`.
- F2 Step 1 contains the `CLAUDE_PLUGIN_ROOT` → `$HOME/.claude/hooks` resolution order and a
  documented fallback for when neither resolves.
- F3 Step 1 states the autopilot policy: a `SECRET` finding aborts, a `NEWDEP` finding does not.
- F4 **anti-weakening pin (always-PASS forward guard):** the `## Invariant guardrails` bullet
  forbidding a commit of `.env`, secrets and API keys is present verbatim, and the four filename
  patterns still appear in Step 1 (A2, A3). This passes before and after — it is a guard, not fix
  evidence. Label it as such in the source.

Then edit `staging/plugin/skills/commit/SKILL.md` per ADR §D9:

- Extend the Step 1 bullet at `:70`. Keep the existing sentence; add the script call over the same
  union set, the resolution block, and the fallback sentence stating that with no script the existing
  filename check applies unchanged.
- Add a named **`Pre-commit findings`** block to the Step 4 gate question, rendering `SECRET` and
  `NEWDEP` lines. State in a comment that #101 appends `WEAKENED` lines to this same block.
- Add the autopilot sentence.
- **Touch no guardrail bullet.**

Full suite after this task, not just the new file.

---

## Task 7 — CI template steps, section F5 seen RED first

- F5 `staging/project-templates/ci/ci.yml` contains both step names and the
  `[ -x .claude/scripts/… ]` guard for each.
- F6 always-PASS forward guard: the template still contains `__TEST_CMD__` and the job name `ci` (A4).

Then add the two advisory steps to the existing `ci` job per ADR §D10: the secret step over
`git ls-files` in `--files` mode; the dependency step resolving `origin/$GITHUB_BASE_REF` with a
merge-base check and a skip notice when it cannot resolve. Add a comment naming #108 as the owner of
the fail-closed `checks` job, and naming the vendoring gap (nothing yet copies the scripts into a
target repo's `.claude/scripts/`).

Then run `bash staging/plugin/skills/nightly-autopilot/tests/run-tests.sh` by hand — it asserts on
this file and is **not** in either CI registry.

---

## Task 8 — Registration in both registries and in `PAIRS`, section G seen RED first

- G1 `.github/workflows/docs-ci.yml`'s `shell-tests` loop list contains `secret-dep-gate`. This
  assertion lives inside the harness it registers, so it cannot pass until the append is made — that
  is the point (this registry has been missed before).
- G2 `staging/sync-to-claude.sh` `PAIRS` contains `plugin/scripts/secret-scan.sh|hooks/secret-scan.sh`
  and `plugin/scripts/dependency-scan.sh|hooks/dependency-scan.sh`.
- G3 no `PAIRS` entry is added for the harness (ADR §D12) — assert its absence, so a future
  well-meaning addition has to justify itself.

Then: append `secret-dep-gate` to the `docs-ci.yml` list (singular name — PF1), and add the two
`PAIRS` entries. `.github/workflows/ci.yml` needs no edit; its glob picks the file up.

Run `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` explicitly, then the full suite.

---

## Task 9 — Close-out

1. Full suite green: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`.
2. Confirm A1–A6 by inspection; `git diff --stat` must show no change to `protect-files.sh` or to
   `review-triage-fix/`.
3. Add a `## Decisions from the secret-scan and dependency gate (ADR-0046)` section to `CLAUDE.md`,
   in the established style: the four things a future session must not rediscover — the
   anchored-not-entropy rule design, the awk-probe exit 3, the ADR §D13 filename collision, and the
   fact that the corpus test is the repository itself.
4. Add a dated entry to the top cluster of `docs/vibe-coding-system.md`'s
   "Changes from previous versions" section, after the current most-recent top-block entry.
5. Tick issue #100 in `PROJECT.md` Phase 2 at chain close-out, not here.
6. **Do not sync.** `sync-to-claude.sh --apply` is a human action at a HITL gate. Report that the
   deployed `~/.claude` copy lacks both scripts until it runs, so the deployed `commit` skill takes
   the ADR §D9 fallback path in the meantime.

---

## Checkpoints the implementer must halt on

- **Task 1 RED count is zero or near-zero.** Means the assertions are not testing what they claim.
  Stop and fix the harness before writing any script.
- **Task 3 D1 is red on a file this feature added.** Fix the file (split the literal), never the
  assertion, never the rule.
- **Task 3 D0 passes before Task 2 exists.** Impossible unless the assertion is inverted. Stop.
- **The awk probe fails on this machine.** PF5 says it should not. If it does, the awk on `PATH` is
  not the one that was measured — report it, do not delete the probe.
- **Any harness outside this feature turns red.** A `PAIRS` or `commit/SKILL.md` change reached
  further than intended. Report before continuing.
