# ADR-0090 — The one unattended pre-flight check that failed open

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #258 (found by a class sweep run off Wave A1's evidence, not by the chain)
- **Related:** ADR-0076 (#195, the rule this call site broke), ADR-0075 (#123, check 7's fix four
  lines below), ADR-0083 (#206/#218, the previous singleton in this same file), ADR-0089 (#239,
  the sweep's origin), ADR-0086 (the extraction criterion applied and declined)

## Context

`autopilot-build`'s pre-flight is eight checks. It runs with no human present, and any check that
passes when it should not lets an unattended run dispatch agents against an unverified state.

Check 6 read one manifest field like this:

```bash
placeholder=$(python3 -c "import yaml; m=yaml.safe_load(open('$manifest')); print(m.get('test_cmd_placeholder', False))" 2>/dev/null)
[ "$placeholder" = "True" ] && { echo "✗ test-cmd: test_cmd_placeholder=true. …"; exit 1; }
```

The `2>/dev/null` turns every failure into an empty string, and an empty string is not `"True"`, so
the check **passes**. Reproduced before any code was written:

| input | `placeholder` | verdict |
|---|---|---|
| unparseable manifest | `` | **passes — fails open** |
| `python3` or PyYAML absent | `` | **passes — fails open** |
| `test_cmd_placeholder: true` | `True` | aborts (correct) |

This is verbatim the pattern ADR-0076 §THE RULE forbids — *"never with a bare `m.get()`"* — and
ADR-0075 had already fixed **check 7**, in the same file, four lines below, for the same reason.

### It is a singleton, which is what makes it worth an ADR

All eight checks were classified rather than just the reported one:

| check | reads state? | on a read failure |
|---|---|---|
| 1 scope guard | no | — |
| 2 manifest state | greps text | its own defect was #218, fixed |
| 3 gates 1-3 approved | yes | `\|\| echo "missing"` → aborts |
| 4 artifacts on disk | yes | empty → `[ -z "$f" ]` → aborts |
| 5 plan has tasks | helper verdict | explicit `rc` check → aborts |
| **6 test-cmd real + trusted** | **yes** | **empty ≠ "True" → PASSES** |
| 7 hook_verified known | yes | asserts the valid values → aborts |
| 8 git repo present | no | — |

Five checks read state; four fail closed by four different correct idioms; one invented a fifth and
got the direction wrong. **Same shape as #218 in the same file** — check 2 invented its own quote
handling while seventeen sites elsewhere used the correct `sed` idiom, and check 1 used a correct
one twenty-five lines above it.

### A correction to the sweep that found it

The sweep first reported *"11 of 12 declared fence contracts have no `exit 3`"*. Right number,
wrong premise — the ADR-0084 lesson, applied to my own measurement. An `exit 3` **code** is only
needed where a caller branches on it; the property that matters is that a did-not-run must not read
as a pass, and eleven of twelve already have it. So this is **one wrong check, not a class
conversion of twelve fences.**

## Decision

### D1 — Read the field through `manifest-field-state.sh`, assert the valid values

`PRESENT|False` proceeds. `PRESENT|True` aborts. `UNREADABLE` and an empty result abort, naming
"the check did not run" as distinct from a bad value. Anything else aborts naming the value.

Asserting the **valid** values rather than enumerating invalid ones is ADR-0075 §D4's rule: the old
form could not grow as the invalid set grew.

### D2 — `ABSENT` PROCEEDS here, which is the opposite of check 7, and the asymmetry is the decision

Check 7 aborts on an absent `hook_verified` because nothing else records the dispatch mode. This
flag has two fallbacks and they sit in the same check:

- The **authoritative** signal is the file itself, `content = NONE`, tested two lines above. The
  flag describes that file; the file is present and readable.
- A real-looking command that was never approved is caught by the **TOFU trust** check below.

So the flag is corroborating, not primary, and its absence removes no coverage. Measured: 40 of 41
corpus manifests carry it; the single `ABSENT` one is `completed` and predates the field.

Both call sites carry the sentence **"Do not reconcile the two"**, the same discipline ADR-0076 §D2
applied to the two `hook_verified` readers with opposite policies.

### D3 — The two-tier resolution is a deliberate second copy, pinned to agree

ADR-0086's criterion says extract when two copies giving different answers would be a defect, and
these must agree. It is still not extracted: a fence that borrowed a variable bound in an **earlier
fence** would stop being independently executable, which is the property ADR-0083's `F4`/`F7` rest
on. `E7f` asserts the two resolution paths stay identical instead — the agreement is enforced
without giving up independent execution.

## What running it found, that reading it would not have

**Redirecting `HOME` in a test hides PyYAML.** Python derives the per-user site-packages directory
from `$HOME`, so the fixture `HOME` that check 6's test uses to fake the TOFU trust registry makes
`import yaml` fail wherever PyYAML was installed with `pip --user` — which is this machine.

The fence then correctly reported "the check DID NOT RUN" and correctly aborted. **The fixture was
wrong, not the fence**, and three assertions went red saying so. `scope-guards.test.sh` never hit
this because its check-7 runner does not redirect `HOME`.

Fixed by resolving `PYTHONPATH` from the module itself
(`os.path.dirname(os.path.dirname(yaml.__file__))`) rather than guessing a layout, so a
system-installed PyYAML on the CI runner is covered by the same line.

Worth keeping as a harness hazard: **adding a Python-dependent helper to a fence whose test
redirects `HOME` breaks that test for a reason that has nothing to do with the change.**

## What the plants found

**The first plant was invalid and its results were nonsense.** It bounded the replaced block on
`esac\n``` `, which matched a `esac` in a **different fence much later in the file**, so the splice
deleted check 6's TOFU section along with everything in between. The suite then reported E7 and E9
failing with empty output, and E7c *passing* — which would have been read as "the assertion does
not pin the bug" if the planted text had not been inspected.

Re-bounded on `# TOFU trust check`, the plant is exact:

| assertion | against the pre-#258 line |
|---|---|
| **E7c** | **FAILS, `rc=0`** — the unreadable manifest passes the pre-flight. #258 reproduced. |
| **E7e** | **FAILS** — `test_cmd_placeholder: maybe` accepted |
| **E7f** | **FAILS** — only one resolution block exists |
| E7, E7b, E7d, E8, E9 | green before and after — labelled forward guards, not evidence |

**E9 was green for the wrong reason for one run.** Adding the helper dependency made the fence abort
on an unresolvable helper, which is also `rc=1`, and E9 asserted only the exit code. It now asserts
the message names TOFU. Rule 8's family: a negative assertion pins nothing when every failure looks
alike.

## Consequences

- **An unattended gate now aborts on inputs it used to pass.** Correct direction, and it is still a
  behaviour change on the path where nobody is watching.
- **Check 6 gains a dependency on a deployed script**, failing closed when it is missing — the same
  terms as check 7 and ADR-0076's rule for a gate.
- The `ABSENT` branch prints a `·` note rather than staying silent, so a tolerated state is visible
  in the unattended log rather than indistinguishable from a normal pass.
- **Nothing else in this file was converted**, deliberately: the other four state-reading checks
  already fail closed, and rewriting them to use the helper would be churn on correct code.
- Inert until sync.
