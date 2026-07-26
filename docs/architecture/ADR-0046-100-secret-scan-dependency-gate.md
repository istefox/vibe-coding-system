# ADR-0046 — Secret content scan, dependency gate, CI steps

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #100 (first feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/100-secrets-and-dependency-gate-content-scan.spec.md`
- **Supersedes:** nothing. **Amends:** nothing. `protect-files.sh` and every `commit` invariant
  guardrail are untouched by design.

> **This document is inside the corpus it describes.** `secret-scan.sh` will be run over this
> repository's own tracked files by its own test harness, and this ADR is one of them. No literal in
> it may match a detection rule, so every rule below is written in its regex form and never as a
> sample value. The same constraint binds the plan and the test file (§D3, §A5).

> **Filename note — read before creating any file for this feature.** This ADR was first written to
> `ADR-0046-100-secrets-dependency-gate.md` and the deployed `protect-files.sh` denied the write:
> the path contains `secrets`, one of its `PROTECTED` substrings. The SPEC's own named artifacts hit
> the same wall. Every filename in this feature therefore uses the singular `secret`. See §D13 — it
> is not a cosmetic detail, it is a hard blocker on three paths the SPEC names literally.

## Context

Three gaps, all from the agentic-spec integration report:

1. **Secrets are caught by filename only.** `protect-files.sh` blocks a *write* whose path
   contains `.env`, `secrets`, `.pem`, `.key`, `credentials`. `commit/SKILL.md:70` re-applies four
   patterns to the union `staged ∪ tracked_modified ∪ untracked` before a commit. Neither looks
   inside a file. A key pasted into `src/config.py` passes both.
2. **A new dependency is invisible.** Nothing compares the dependency manifests in a diff against
   what the plan or the ADR authorised. An agent can `npm install` its way out of a hard problem and
   the only record is a lockfile nobody reads at the gate.
3. **Neither check exists in a generated project's own CI.** Every guard in this system lives in a
   hook or in a skill's prose, which means it exists only while an agent is driving. A human pushing
   by hand gets nothing.

Two constraints shape everything below.

**The false-positive corpus is not hypothetical.** This repository already contains high-entropy
strings that must never be flagged. Measured, not assumed: seven GitHub Actions SHA pins (40 hex
characters each) across the two workflow files, a 60-hex fake trust hash in `run-hook-tests.sh` and
again in a 2026-05-20 plan, and — the finding that decided the rule design — a naive
`[A-Za-z0-9+/]{32,}` "looks like base64" pattern matches ordinary prose, because absolute paths and
URLs put `/` inside the character class. `ADR-0018…:349` matched on the string
`/Users/stefanoferri/Developer/vibe-coding-system/SPEC.md`. An entropy-only detector is not merely
noisy here, it is useless.

**Three later features build directly on this one.** #101 adds a second reporter call site beside
these in `commit` Step 1, #105 adds `SUSPECT` detectors to `weakening-scan.sh`, and #108 turns all
of them into a fail-closed `checks` job in the target project's CI. So the scripts must be plain
shell tools driven by a file list or a diff, with no Claude Code hook payload anywhere in the input
path, and the commit-gate rendering must be a list a fourth finding type can join without a rewrite.

## Decision

### D1 — Two standalone reporters, `weakening-scan.sh`'s contract

`staging/plugin/scripts/secret-scan.sh` and `staging/plugin/scripts/dependency-scan.sh`. Bash 3.2 +
awk + grep, no external tool beyond POSIX, and no `git` invocation inside either script — the caller
supplies the input. Findings are TAB-separated lines on stdout:

```
SECRET<TAB><file>:<line><TAB><rule>
NEWDEP<TAB><package><TAB><manifest>
```

Empty stdout means no findings. The caller decides whether a finding blocks. This is deliberately
the same division of labour as `weakening-scan.sh`: the detector never knows the policy, which is
what lets #108 run the identical script fail-closed in CI while the commit path stays advisory for
`NEWDEP`, with no flag and no second copy.

### D2 — Exit codes: 0 for any completed scan, non-zero only for "did not run"

| code | meaning |
|------|---------|
| 0 | the scan ran; findings may or may not be on stdout |
| 2 | invalid invocation (unknown flag, missing argument, unreadable list file) |
| 3 | the environment cannot support the rules (§D4 awk probe failed) |

Exit 0 with findings is the reporter contract and is pinned by a test. Codes 2 and 3 never mean
"found something", they mean "believe nothing about this run". #108 can therefore treat non-zero as
a hard CI failure and non-empty stdout as a policy failure, without conflating the two.

### D3 — Detection is anchored on a distinctive prefix or on a keyword, never on entropy

Eleven rules. Ten are anchored on a vendor-specific prefix or a structural marker; one is
keyword-anchored. Not one of them scores entropy.

| rule id | anchor (ERE) |
|---|---|
| `filename-pattern` | path matches `.env`, `.env.*`, `*secret*`, `*credential*`, `*.pem` (case-insensitive) |
| `aws-access-key-id` | `(AKIA\|ASIA)[0-9A-Z]{16}` at non-alphanumeric boundaries |
| `aws-secret-access-key` | `aws[_-]?secret[_-]?access[_-]?key` then `[:=]` then an optionally quoted `[A-Za-z0-9/+=]{40}` |
| `private-key-block` | `-----BEGIN [A-Z ]*PRIVATE KEY-----` |
| `github-token` | `gh[pousr]_[A-Za-z0-9]{36}` or `github_pat_[A-Za-z0-9_]{30,}` |
| `google-api-key` | `AIza[0-9A-Za-z_-]{35}` |
| `slack-token` | `xox[abprse]-[0-9A-Za-z-]{10,}` |
| `stripe-secret-key` | `(sk\|rk)_live_[0-9A-Za-z]{16,}` |
| `openai-api-key` | `sk-(proj-)?[A-Za-z0-9_-]{32,}` |
| `jwt` | `eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}` |
| `assigned-secret` | a secret-ish keyword, then `[:=]`, then an optionally quoted `[A-Za-z0-9+/_=.~-]{16,}` value |

Two details carry most of the false-positive protection.

**`jwt` requires the second segment to start with `eyJ` as well.** A real JWT's payload is a JSON
object, so its base64 begins with the same three characters. Requiring both segments turns a rule
that would fire on any dotted base64-ish string into one that fires on a JWT.

**`assigned-secret` is the only heuristic rule, and it carries four exclusions** applied to the
matched line before anything is reported:

- the value is a placeholder — `x{8,}`, `changeme`, `your[-_]…`, `example`, `sample`, `dummy`,
  `fake`, `placeholder`, `redacted`, `todo`, `none`, `null` (case-insensitive, prefix match);
- the value is a pure hex run of exactly 32, 40, 64 or 128 characters, i.e. an MD5, SHA-1, SHA-256
  or SHA-512 digest. This is the corpus rule that keeps the Actions SHA pins and the fake trust hash
  quiet;
- the line reads an environment variable rather than defining a value — `process.env`, `os.environ`,
  `getenv`, `ENV[`, or a value beginning with `$`. The last one is free: `$`, `{` and `}` are not in
  the value character class, so the `Bearer ${…}` header in `staging/plugin/.mcp.json:11` cannot
  reach the 16-character minimum;
- the value is empty, or the assignment has no right-hand side.

The prefix-anchored rules get **no** placeholder exclusion. A vendor's own documentation example
that happens to be a syntactically valid access key ID is reported, because "the value ends in
`EXAMPLE`" is a string an agent can write on purpose. Reporting it costs a human one glance;
excluding it opens a hole shaped exactly like the thing this ADR exists to close.

### D4 — A startup capability probe, because a silently inert rule is the worst outcome

Every rule uses ERE interval syntax (`{16}`). The one-true-awk shipped by macOS only gained interval
support around 2019; the version on the development machine is `20200816` and supports intervals in
both `/…/` literals and `match()` — verified live before this ADR was written, not assumed. An older
awk does not error on `{16}`; it treats the braces as literal characters, and every rule silently
matches nothing.

So the script probes the interval capability at start-up and exits 3 with a loud stderr message if
it fails. It never exits 0 with an empty finding list on an awk that cannot express the rules. This
is the ADR-0043 lesson on a different substrate: a check that reports nothing is indistinguishable
from a check that found nothing, and that ambiguity is what kept issue #93 invisible. `SECRET_SCAN_AWK`
overrides the interpreter so the probe's failure path is testable, mirroring `AGENT_COMMAND_SCOPE_DIR`
in `agent-command-scope.sh`.

### D5 — Findings on stdout, a run summary on stderr

`weakening-scan.sh` prints the sentinel `CLEAN` when it finds nothing. The SPEC specifies "`SECRET`
lines or nothing" for these two, and a truly empty stdout composes better with `wc -l` in #108's
fail-closed job. But an entirely silent success has the failure shape D4 exists to prevent.

Resolution: stdout carries findings only, and **one summary line goes to stderr on every run**:

```
secret-scan: 350 file(s) listed, 348 scanned, 2 skipped, 0 finding(s)
dependency-scan: 1 manifest(s) in diff, 3 added, 1 new package(s)
```

stderr never pollutes the machine-readable channel, a CI log shows the script actually ran, and
"0 files scanned" becomes visible instead of reading like a clean result. `dependency-scan` prints
an explicit `no recognised dependency manifest in the diff — inert` line for the SPEC's inert case,
so that outcome is stated rather than inferred from silence.

### D6 — Two input modes, one shared rule engine

```
secret-scan.sh --files <list-file>   # newline-separated paths, read from the working tree; "-" = stdin
secret-scan.sh --diff                # unified diff on stdin; added lines only
dependency-scan.sh --diff [--allow <file>]
```

Both modes normalise to one intermediate record stream, `path<TAB>lineno<TAB>content`, and a single
rule engine consumes it. `--files` scans whole files (the commit path needs this: an untracked new
file has no diff). `--diff` scans added lines only and derives the new-file line number from the
`@@` hunk headers (the CI path needs this: only new content is in scope). One engine, two front
ends — the alternative, a rule table per mode, is how two detectors drift apart.

No hook payload, no JSON parsing, no `jq`. That is what makes them runnable from a plain shell and
is a hard requirement of #108.

### D7 — `secret-scan.sh` owns the filename rule too, with precedence and one line per file

The filename rule moves into the script as rule id `filename-pattern`, reported with line `0`, using
the four patterns already written in `commit/SKILL.md:70`. It is not narrowed: narrowing it would
weaken an existing invariant guardrail, which this feature is forbidden to do.

On a filename match the script emits exactly one line for that file and **does not scan its
content**. That satisfies the SPEC edge case ("reported once, not twice") in the script rather than
in skill prose, and it stops a real `.env` from producing fifty lines at the gate. Content findings
are deduplicated to **one line per (file, rule)** at the first matching line, so a file with ten
access keys yields one finding, not ten.

Noted while writing this, changed nowhere: the two existing filename rules already disagree.
`protect-files.sh` matches the plural substring `secrets`, `commit/SKILL.md:70` matches the singular
`*secret*`. The script implements the `commit` set, which is the broader of the two. Reconciling
them is a separate decision with its own blast radius; `protect-files.sh` is out of scope per the
SPEC.

### D8 — `dependency-scan.sh` reports `added minus removed`, never `added`

A lockfile reorder produces `+` lines for packages that were already there. A version bump produces
a `+` and a `-` for the same package. Both must be silent. So the script collects package names from
added lines and from removed lines per manifest and reports only the set difference. This single
decision covers two of the five SPEC edge cases.

Three ecosystems in v1, matching the three project templates that exist (`app-fastapi-react`,
`ios-swiftui`, `web-vanilla-wordpress`):

- **npm** — `package.json`, `package-lock.json`, `npm-shrinkwrap.json`, `yarn.lock`, `pnpm-lock.yaml`
- **Python** — `requirements*.txt`, `pyproject.toml`, `Pipfile`, `Pipfile.lock`, `poetry.lock`
- **Swift/iOS** — `Package.swift`, `Package.resolved`, `Podfile`, `Podfile.lock`

A file that is not one of these is not a manifest and contributes nothing. Adding an ecosystem is one
entry in one awk table; the per-type extraction rules are enumerated in the plan.

`--allow <file>` takes one package name per line, `#` comments and blank lines ignored, exact
case-sensitive match. If `--allow` is absent, `.claude/allowed-deps.txt` is used when it exists.
With no allow list at all, **every** newly added package is reported — the conservative direction for
a reporter, and the reason the script never needs to parse an ADR to learn what was authorised.
Output is sorted, so finding order is deterministic and testable.

### D9 — `commit` Step 1 calls the scripts; the invariant prose stays and remains the fallback

Step 1 gains a script-resolution block in the `CLAUDE_PLUGIN_ROOT` → `$HOME/.claude/hooks` order
already used by `project-conductor/SKILL.md:44-47`. If neither resolves, Step 1 says so and applies
the existing filename check exactly as written today. An un-synced machine therefore keeps today's
behaviour precisely, which is the non-regression floor for a skill that `concept-to-code` Step 7,
`project-init` and `autopilot-build` all call.

Policy, when the scripts do resolve:

- **Any `SECRET` finding stops Step 1 and warns**, filename-rule and content-rule alike. That is the
  existing invariant ("NEVER commit `.env`, secrets, API keys — stop and warn") applied
  deterministically instead of by model judgement. Only an explicit human instruction resumes the
  flow, and if it does, every finding is rendered verbatim in the Step 4 gate so it is visible at the
  click.
- **`NEWDEP` findings never stop anything.** They are rendered in the Step 4 gate under a
  `Pre-commit findings` block.
- **In `--autopilot` mode** (Step 4 is skipped there) a `SECRET` finding aborts the commit and prints
  the findings; a `NEWDEP` finding is printed and the commit proceeds. Aborting unattended on a
  secret is the correct fail direction and is consistent with ADR-0020's autonomy boundary.

The `Pre-commit findings` block is a named, extensible list. #101 appends `WEAKENED` lines to it and
adds its call beside these two; no restructuring needed.

### D10 — The CI template gets two advisory steps inside the existing `ci` job

Both steps are guarded on `[ -x .claude/scripts/<script>.sh ]` and print a skip notice when the
scripts are not vendored into the target repo. They are advisory: the scripts always exit 0 on a
completed scan, so a finding is printed and the required `ci` check stays green.

- The secret step uses `--files` over `git ls-files`. Whole-tree, so it needs no base ref, no
  `fetch-depth` change to the template's `actions/checkout`, and behaves identically on `push` and
  `pull_request`.
- The dependency step needs a diff by definition. It resolves `origin/$GITHUB_BASE_REF`, verifies a
  merge base exists, and prints a skip notice when it cannot — never a hard failure on a shallow
  clone.

The `ci` job **name** is unchanged, because `set-branch-protection.sh` requires it, and the
`__TEST_CMD__` token is untouched, because `nightly-autopilot/tests/run-tests.sh` asserts on it. The
fail-closed `checks` job is #108's, by its own SPEC; creating it here would make #108 a merge
conflict instead of a feature.

**Known gap, stated rather than left to be discovered:** nothing yet copies the two scripts into a
target repo's `.claude/scripts/`. The steps are therefore inert in a freshly generated project
until issue #108 — whose fail-closed job has the identical dependency — settles the vendoring.
The skip notice
makes the inertness visible in the CI log rather than silent.

### D11 — No suppression pragma in v1

There is no `allowlist secret` comment, no `.secretsignore`. A repository that genuinely needs a
key-shaped literal splits it across a concatenation or builds it at run time — which is what the new
test file itself does. A suppression marker is one added comment line away from silencing a real
finding, and silencing a detector by editing a comment is precisely the behaviour class that
`weakening-scan.sh` and #105 exist to catch. Rejected on posture, not on effort; revisit only with
evidence from a real project.

### D12 — Deployment and registration

- `sync-to-claude.sh` `PAIRS` gains `plugin/scripts/secret-scan.sh|hooks/secret-scan.sh` and
  `plugin/scripts/dependency-scan.sh|hooks/dependency-scan.sh`, additive, one entry per file per
  ADR-0024. Neither is a hook: no `settings.json` wiring, no manual step, sync alone deploys them.
- The test file gets **no** `PAIRS` entry, matching every harness added since ADR-0041. It validates
  `staging/` and runs in this repository's CI.
- The harness is registered in **both** registries: `.github/workflows/ci.yml` picks it up by glob,
  `.github/workflows/docs-ci.yml` needs an explicit append to its named list. That second one has
  been missed before, so the test asserts on its own registration and cannot pass unregistered.

### D13 — Every filename in this feature uses the singular `secret`

`protect-files.sh`'s `PROTECTED` list contains the substring `secrets`, and it is a `PreToolUse` hook
on `Write|Edit|MultiEdit`. Any path containing `secrets` is therefore unwritable by any agent on this
machine, this ADR's first filename included — the write was denied, which is how the constraint was
found rather than assumed.

Consequences for the three paths the SPEC and the dispatch brief name literally:

| named as | actually created as |
|---|---|
| `docs/architecture/ADR-0046-100-secrets-dependency-gate.md` | `docs/architecture/ADR-0046-100-secret-scan-dependency-gate.md` |
| `docs/superpowers/plans/2026-07-26-100-secrets-dependency-gate.md` | `docs/superpowers/plans/2026-07-26-100-secret-scan-dependency-gate.md` |
| `staging/plugin/scripts/tests/secrets-dep-gate.test.sh` | `staging/plugin/scripts/tests/secret-dep-gate.test.sh` |

The rename is the accommodation, not a workaround: writing those paths through `Bash` to dodge a
`PreToolUse` hook is the routing-around that ADR-0045 and ADR-0041 exist to prevent, and nobody on
this feature may do it. The registry entry in `docs-ci.yml` must use the singular name, or CI fails
on a missing file.

Two more filename traps for the implementer, from the same `PROTECTED` list: `package-lock.json` and
anything containing `.key` are equally unwritable. The dependency-scan fixtures therefore exist only
inside `mktemp -d` directories created by `printf` from within the harness at run time, never as
repository files authored with the `Write` tool. That is the normal shape of every harness in
`staging/plugin/scripts/tests/` anyway, so it costs nothing — but it has to be known in advance,
because discovering it mid-task looks like a broken tool rather than a working guardrail.

## Alternatives considered

**A1 — Entropy scoring (Shannon entropy over tokens), as gitleaks and truffleHog use.** Rejected on
measurement, not on taste. Run against this repository, the cheap approximation of it
(`[A-Za-z0-9+/]{32,}`) matches ordinary prose, because `/` is inside the base64 alphabet and every
absolute path in every ADR qualifies. A real entropy scorer would also have to clear seven Actions
SHA pins and a 60-hex fixture, which forces a hex-digest exclusion — at which point the exclusion is
doing the work and the entropy score is decoration. Anchored rules give a better false-positive
profile for a fraction of the code, and their misses (a bare high-entropy password with no keyword)
are misses a human at the commit gate can still catch.

**A2 — Shell out to `gitleaks`, `detect-secrets` or `trufflehog`.** Rejected: the SPEC puts a hosted
or paid scanner out of scope, and the free ones are still a binary that has to exist on the
developer's machine *and* on the CI runner *and* inside whatever container a generated project uses.
ADR-0039 already worked this through for linters and landed in the same place — a check whose verdict
depends on which tools happen to be installed is not deterministic, and the divergence surfaces as a
red CI on one machine and green on another. Every other script in `staging/plugin/scripts/` is
POSIX-only for exactly this reason.

**A3 — A `PreToolUse` hook on `Bash(git commit*)` instead of skill prose.** Rejected: it would only
cover a commit driven through the `Bash` tool by an agent, which is the one path already covered by
`commit/SKILL.md`, and it would do nothing for a human running `git commit` in a terminal or for CI.
The SPEC's third objective is explicitly "runnable in a target project's CI with no agent present",
and a hook is the one form that cannot satisfy it. A hook is also fail-open by house convention,
which is the wrong default for the CI copy.

**A4 — Fold the checks into `protect-files.sh`.** Rejected: it is a `PreToolUse` write blocker that
consumes hook-payload JSON on stdin, i.e. the exact input dependency #108 forbids, and it fires per
`Write` on a single path — it can never see a diff or a dependency set. The SPEC puts it out of scope
and this ADR leaves it byte-identical.

**A5 — Narrow the `*secret*` filename pattern to exclude Markdown, to cut noise.** Rejected as a
weakening of an existing invariant guardrail, which this feature is forbidden to do. The cost is
concrete and immediate: this feature's own artifacts all carry `secret` in their filenames, so the
commit that lands them trips `filename-pattern` several times and requires an explicit human
"proceed". That is the existing rule behaving as written, made deterministic. Recorded here so it
reads as a designed consequence rather than as a bug report at the gate. D13 is the related, harder
version of the same collision, and it was not softened either.

**A6 — Create the fail-closed `checks` job now instead of two advisory steps.** Rejected on roadmap
grounds: #108's SPEC names that job as its own deliverable and adds the weakening/`SUSPECT`
detectors to it in the same breath. Building it here would leave #108 with nothing to do but resolve
a conflict, and would decide the vendoring question (D10) with none of #108's context.

**A7 — Emit `CLEAN` on no findings, as `weakening-scan.sh` does.** Rejected in favour of D5's
stdout/stderr split. The SPEC specifies "lines or nothing" for stdout, and a sentinel there would
have to be filtered out by every caller including #108's `wc -l`. The legitimate need behind `CLEAN`
— telling "ran and found nothing" apart from "did not run" — is met by the stderr summary plus the
exit-code table in D2, which carries strictly more information than a sentinel.

**A8 — Parse the ADR or the plan to derive the authorised package list automatically.** Rejected as
non-deterministic: it needs prose comprehension, the one thing these scripts must not require.
`--allow` with a plain file, plus "no allow list means report everything", gives the same protection
with a deterministic rule, and hands the caller — an agent that *has* read the plan — the job of
writing the list when it wants a quieter gate.

**A9 — One `grep -nE` per rule per file, instead of a single awk rule engine.** Rejected on cost and
on parseability: eleven rules over 350 files is ~3,850 process spawns, and `grep -n -H` output is
`file:line:content`, which cannot be unambiguously re-split when a path contains a colon. The awk
engine reads a normalised TAB-separated record stream and has neither problem. Colon-bearing paths
are still refused explicitly (Consequences), because refusing loudly beats mis-parsing quietly.

## Consequences

### Positive

- A key pasted into an ordinary source file is caught before the commit gate for the first time. The
  filename rule and the content rules are applied by one deterministic script rather than by model
  judgement over a prose sentence.
- The commit gate becomes the single place a human sees secrets, new dependencies and (after #101)
  test weakening, in one `Pre-commit findings` block.
- Both scripts are ordinary shell tools. #108 gets its CI job by writing YAML, not by modifying
  detection code, and #105 gets a proven reporter shape to copy.
- The false-positive corpus is executable: the harness runs the scanner over this repository's own
  tracked files and fails if any content rule fires. A future commit that introduces a real key turns
  CI red on a file nobody thought to check.
- Exit codes 2 and 3 mean a broken or unsupported run can never be read as a clean one — the failure
  mode that hid issue #93 cannot recur here.
- `protect-files.sh`, every `commit` invariant bullet, the `ci` job name and the `__TEST_CMD__` token
  are all unchanged, so nothing downstream re-verifies.

### Negative

- **The filename rule now fires deterministically on documentation about secrets**, starting with
  this feature's own files. Previously the model decided whether `*secret*` in a doc filename was
  worth stopping for; now it always stops and warns. This is more correct and more annoying, and A5
  records why it was not softened.
- **Three filenames the SPEC names literally cannot exist on this machine** (D13). The rename keeps
  the feature buildable, but anyone reading the SPEC and the tree side by side will find they
  disagree, and the `docs-ci.yml` registry entry has to use the new name or CI fails on a missing
  file.
- **A file caught by the filename rule is never content-scanned** (D7 precedence). A real key inside
  a `*secret*`-named document is reported as a filename match, not as an `aws-access-key-id`. The
  file is blocked either way; the finding is less specific.
- **A bare high-entropy secret with no keyword and no vendor prefix is missed.** A password assigned
  to a variable named `p` is invisible to every rule. This is the deliberate cost of A1, and it is why
  the commit HITL gate remains the real gate.
- **`assigned-secret` will produce occasional false positives** in target projects — a 20-character
  non-placeholder default assigned to a variable named `…_token` is indistinguishable from a real one
  by any rule that does not know the project. With D11 there is no per-line escape hatch; the
  workaround is to split the literal or move it out of the source.
- **The CI template steps are inert until the vendoring question is settled** (D10). The skip notice
  makes that visible, but a reader of the template could reasonably expect the checks to run.
- **Paths containing a colon are skipped with a stderr warning.** Rare in practice, and refused
  loudly rather than mis-parsed (A9).
- The whole-tree `--files` scan is O(files) shell iterations plus one awk pass. Fine at this
  repository's 350 files and at commit-time file lists; a 50k-file monorepo would want the diff mode.

### Neutral

- Two more scripts in `staging/plugin/scripts/`, two more `PAIRS` entries, one more harness in both
  CI registries. No new hook, no `settings.json` change, no manual sync step.
- `.claude/allowed-deps.txt` is a new optional convention. Absent in every existing project, which
  simply means every added package is reported.
- The `weakening-scan.sh` `CLEAN` sentinel and these scripts' silent-stdout contract now differ.
  Documented in D5; #101, which calls all three, must not assume one convention.
- Eleven rules is a starting set, not a claim of coverage. Adding a twelfth is one table row plus one
  positive and one negative fixture.
- The plural/singular divergence between `protect-files.sh` and `commit/SKILL.md` is recorded (D7)
  and left alone. It predates this feature.

## References

- SPEC: `/Users/stefer/Developer/vibe-coding-system/SPEC.md`, and
  `docs/specs/100-secrets-and-dependency-gate-content-scan.spec.md`
- Plan: `docs/superpowers/plans/2026-07-26-100-secret-scan-dependency-gate.md`
- Downstream specs read for forward compatibility: `docs/specs/101-wire-the-anti-test-weakening-detector-in.spec.md`,
  `docs/specs/105-reward-hacking-detectors-literal-asserti.spec.md`,
  `docs/specs/108-run-the-deterministic-checks-in-the-targ.spec.md`,
  `docs/specs/119-licence-and-provenance-scanning.spec.md`
- Reporter contract precedent: `staging/plugin/skills/review-triage-fix/scripts/weakening-scan.sh`
- Untouched by design: `staging/plugin/scripts/protect-files.sh`,
  `staging/plugin/skills/commit/SKILL.md` "Invariant guardrails"
- Script-resolution precedent: `staging/plugin/skills/project-conductor/SKILL.md:44-47`
- Testability-override precedent: `staging/plugin/scripts/agent-command-scope.sh`
- Silent-empty-result lesson: `docs/architecture/ADR-0043-93-pairs-completeness.md`
- Tool-dependent verdicts rejected before, for the same reason:
  `docs/architecture/ADR-0039-early-coder-feedback.md`
- `PAIRS` granularity and additive-only rule: `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md`
- Unattended autonomy boundary: `docs/architecture/ADR-0020-autopilot-build-skill.md`,
  `docs/architecture/ADR-0022-nightly-autopilot-goal.md`
- No routing around a `PreToolUse` hook: `docs/architecture/ADR-0045-58-interpreter-wrapper-bypass.md`,
  `docs/architecture/ADR-0041-58-agent-write-scope.md`
