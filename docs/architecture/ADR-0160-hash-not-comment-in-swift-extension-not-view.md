# ADR-0160 — a Swift macro is not a comment, and a `.swift` extension is not a view

- **Topic slug:** `hash-not-comment-in-swift-extension-not-view`
- **Issue:** #472 (`zero-assertion-test` blind to Swift Testing), #478 (Gate 5.05 fires on any Swift
  file)
- **SPEC:** none — bounded correctness fixes to two detectors, no requirement ids
- **Extends:** ADR-0051 (`weakening-scan.sh`'s detector set), ADR-0073 §D4 (the same script's
  documented blind-spot precedent), ADR-0066 (Gate 5.05, the checklist this narrows the trigger
  for), ADR-0093 (`detect-macos.sh`'s "a keyword counts only near its evidence" shape, reused here).
  Supersedes nothing.
- **Narrows:** ADR-0054 §CE (project-ci-checks.test.sh's forward guard against modifying a vendored
  check script) — see D3

## Status

Accepted — 2026-08-19.

## Context

Two field defects, both a check trusting a file's surface shape — an extension, a leading character
— for a question that needs its content.

### #472 — `#` opens a comment in Python; in Swift it opens a macro

`weakening-scan.sh`'s body scan skipped any line whose first non-whitespace character is `#`,
treating it as a comment leader — true in Python, Ruby, shell, YAML. **Every Swift Testing
assertion starts with `#`**: `#expect(...)`, `#require(...)`. So the scan read a passing test's own
assertion as a comment, decided the test body asserted nothing, and reported `zero-assertion-test`.

Reported from the field run: 32 findings against 12 real `#expect` calls in one file, all eleven
repeats landing on the one file that actually had assertions — the shape a systematic misreading
produces, not a one-off.

### #478 — a `.swift` extension is not "this diff touched a view"

Gate 5.05's trigger was a bare extension match, `grep -E '\.(swift|html|css|tsx|jsx|vue)$'`. A
model, a service, a network client, a parser are all `.swift` and none of them is a view. Reported:
a feature with no view and no `import SwiftUI` anywhere in its diff still ran `ui-layout-audit` and
recorded a seven-item accessibility/i18n checklist about UI work that did not exist.

## Decision

### D1 — `#` is a comment leader only where it is one; `#require(` joins `#expect(`

`is_hash_comment_lang(p)` — an **allowlist**, not "every extension except Swift": a denylist naming
one language leaves every other language where `#` is not a comment (Go, Java, C, JS/TS…)
mis-scanned too, just unmeasured. `#` is a comment leader in `.py .rb .sh .bash .zsh .pl .pm .yaml
.yml .toml .tf .cmake .r .jl` — languages checked against the file extension, matching the same
per-extension idiom `is_test()` a few lines above already uses. `.swift` is deliberately absent.

`is_assert_tok()` gains `#require\(` — Swift Testing's second assertion macro. `#expect\(` already
matched via the bare `expect\(` token, which is why the fix is one macro, not two. `require\.` in
the existing pattern needs a dot (`x.should.require.something`, Chai/should-style) and does not
collide with `#require(`.

`//` and `*` (a block-comment continuation line) stay comment leaders in every language this scan
runs against — unaffected by D1; only the `#` leader is narrowed, and only for the file it reads.

### D2 — Gate 5.05 fires on UI-bearing content, not on an extension alone

New script, `ui-file-detect.sh` — a reporter (ADR-0048 §D5's convention: exit 0 always, the
UI-bearing subset on stdout), invoked from Gate 5.05 in place of the bare extension grep. Same shape
as `detect-macos.sh` (ADR-0093): a keyword counts only near what it is evidence of.

- **`.html`/`.css`/`.tsx`/`.jsx`/`.vue` stay extension-only, on purpose.** No measured
  false-positive exists for these — a `.css` file that is not about layout is not a documented or
  observed shape here. Narrowing them without a measurement would be guessing, the opposite of what
  closes #478.
- **`.swift` needs its own content to say so**: an `import SwiftUI|AppKit|UIKit`, or a
  `struct`/`class`/`final class` declaration conforming to `View`, `NSView`, `NSViewController`,
  `UIView` or `UIViewController`. Either is sufficient.
- **A deleted `.swift` file is not UI-bearing** — `[ -f "$f" ]` fails, no content to read, and a
  deleted file cannot be missing a view. The same direction the "no measured false-positive on the
  web extensions" call already favors: stricter never fires where it did not need to.

### D3 — the CE forward guard is narrowed again, the same way it was narrowed once before

`project-ci-checks.test.sh`'s CE section is an ALWAYS-PASS forward guard from ADR-0054 §D1: no
existing vendored check script (`secret-scan.sh`, `dependency-scan.sh`, `weakening-scan.sh`,
`interface-check.sh`) may have an executable-line change, because ADR-0054's actual constraint was
narrower than the guard's literal wording — the CI-wrapping feature must achieve fail-closed by
*wrapping* the scripts, never by baking posture *into* them. As first written, CE could not tell that
constraint apart from an ordinary correctness fix to a script's own detection logic: every executable
diff failed identically. It had already been narrowed once, on 2026-07-29 (ADR-0073 §D4, issue #177),
to admit comment-only changes while keeping executable ones blocked.

D1's fix to `weakening-scan.sh` is an executable-line change, and it is squarely the second class —
a measured false-positive corrected in the script's own logic, with its own ADR and its own test
coverage in `reward-hack-detectors.test.sh` — not CI-posture baked in. Rather than relax CE
unconditionally (which would silently readmit the class it exists to catch) or revert the fix, CE
gains a **declared, content-verified exemption**:

- A small table, `CE_EXEMPT_<script>`, one entry: `CE_EXEMPT_weakening_scan_sh="472"`. Empty for
  the other three scripts — unconditionally frozen, exactly as before.
- An executable diff to an exempted script only passes CE when the diff **itself** cites the
  declared issue number as a standalone `#<n>` token. The exemption is re-verified against the live
  diff on every run; a table entry alone grants nothing. A later, unrelated edit to the same script
  that does not cite `#472` is not covered by this entry and CE fails on it exactly as it would on
  any other script.
- This is not a widened union (the failure mode ADR-0044 refused elsewhere): a per-file, per-issue,
  content-checked entry, matching the same "declared and verified" shape.

The unconditional half of D1's original constraint is untouched: an executable change to any script
that does **not** cite a declared exemption still fails, and the fix is still to revert, never to
relax the assertion further without the same declared, content-verified process.

## Consequences

- A Swift Testing file's real assertions are read as assertions; the 32-false-finding shape observed
  in the field does not reproduce.
- A Swift feature with no view runs no UI audit and records no accessibility checklist it has no
  content to justify.
- `#` and the extension check both stay exactly as strict as before for every language and every web
  extension already covered — D1 and D2 both narrow one specific false-positive, not the detector's
  reach generally.
- CE keeps its unconditional refusal for three of four scripts and for any uncited change to the
  fourth. The exemption table is small, per-issue, and re-verified every run rather than a standing
  grant.
- **Not addressed.** `ui-file-detect.sh`'s declaration regex for `.swift` has a structural
  redundancy already present before this ADR (its second and third `grep` checks overlap on the
  class-declaration case) — noted here because it was seen while implementing D2, not because this
  ADR fixes it; it changes no observable behavior.

## Alternatives considered

**A1 — a denylist of "languages where `#` is NOT a comment" instead of an allowlist.** Rejected:
every language absent from the denylist keeps being mis-scanned, just without measurement — the same
shape D1's own header warns against for the allowlist it chose instead.

**A2 — narrow the `.swift` extension out of Gate 5.05's trigger entirely, require an explicit
opt-in.** Rejected: it would silently stop auditing every genuine SwiftUI/UIKit feature too, trading
a false positive for a false negative with no measurement behind the trade.

**A3 (D3) — revert `weakening-scan.sh`, leave #472 unfixed in this batch.** Considered and declined
by the user: the measured false-positive (32 findings, 0 true) is a real defect with its own
observed field cost, and CE's literal wording was already broader than ADR-0054's own stated intent.

**A4 (D3) — relax CE unconditionally for all four scripts, or drop the guard.** Rejected: it would
readmit exactly the class CE exists to catch — a future feature achieving fail-closed by modifying a
script instead of wrapping it, with no distinguishing mechanism left at all.

## Test and plant obligations

`reward-hack-detectors.test.sh`, Section HI:

- **HI1** — an added Swift Testing `#expect(...)` call is recognised as an assertion, not skipped as
  a comment.
- **HI2** — an added `#require(...)` call is recognised as an assertion token.
- **HI3** (forward guard) — a genuinely empty Swift `@Test` still fires `zero-assertion-test`; the
  fix narrows what counts as a comment, it does not disable the detector for Swift.
- **HI4** (regression guard) — a Python test body containing only a `#` comment still reads as
  `zero-assertion-test`; the Swift fix does not widen what counts as a body line elsewhere.

`accessibility-i18n.test.sh`, Section AIJ:

- **AIJ1** — the Gate 5.05 trigger invokes `ui-file-detect.sh`, anchored on the executable fence
  line, not the adjacent prose mention of the same filename (measured: the first draft's needle
  matched the prose one line above the fence even with the code line reverted — a registry NOFIRE).
- **AIJ2** — `ui-file-detect.sh` exists and is readable at the invoked path. No plant: an existence
  check, the same class `prep.test.sh`'s PT1/PT2 already documented as unplantable — the registry
  mutates text inside a tracked file, never a file's presence. Verified by hand instead.
- **AIJ3** — a `.swift` file with no UI import and no qualifying declaration is not admitted.
- **AIJ4/AIJ5** — a SwiftUI `View` file and a UIKit `UIViewController` subclass are admitted. No
  plant, documented rather than forced, the same precedent as `batch-boundary-precedence.test.sh`'s
  CB2/CB6 and `stop-gate-path-predicate.test.sh`'s SGP25/SGP26: both fixtures satisfy two of
  `is_ui_swift()`'s three independently-sufficient checks at once by realistic construction (a real
  SwiftUI view both imports SwiftUI and declares `: View`), so no single-line mutation isolates
  either check. AIJ3's plant already pins the mechanism gating all three.
  - **AIJ6** (forward guard) — a `.css` file is admitted unconditionally, content unchecked and even
  absent — the extension-only path D2 keeps for the classes it was never wrong about.

`project-ci-checks.test.sh`, Section CE/D2:

- **D2a** (positive) — a diff line citing `#472` as a standalone token matches issue 472's
  exemption.
- **D2b** (negative, per-issue) — a line citing a different issue (`#999`) does not satisfy issue
  472's exemption; the table grants per-issue cover, not blanket cover.
- **D2c** (negative, no citation) — a line with no issue citation at all does not satisfy any
  exemption.
- **D2d** (forward guard) — only `weakening-scan.sh` carries a `CE_EXEMPT_*` entry; the other three
  scripts stay unconditionally frozen.

All new plants — HI1, HI2, AIJ1, AIJ3, AIJ6, D2a, D2b, D2c, D2d — individually plant-verified
`FIRED` against an isolated copy, and again by the full registry: `PASS=511 FAIL=0`, 503 of 503
declarations run. One needle-authoring lesson recorded for later readers: a needle or
replacement must never embed a literal ` | ` (the plant declaration's own field delimiter) — AIJ1's
first draft did, silently mis-parsed into extra fields, and its mutation degenerated into a no-op
until caught by direct inspection, not by the probe reporting an error.

## References

- Issue #472, issue #478
- ADR-0051 — `weakening-scan.sh`'s original detector set
- ADR-0073 §D4 — the first CE narrowing (comment-only changes), the direct precedent for D3
- ADR-0093 — `detect-macos.sh`, the "keyword counts only near its evidence" shape D2 reuses
- ADR-0054 §D1/§CE — the guard D3 narrows, and the constraint that remains unconditional
- ADR-0044 — why a widened union was refused elsewhere, the shape D3's per-issue table avoids
- CLAUDE.md rule 1 (AIJ1's needle-precision fix), rule 3 (decoration-independent matching), rule 6
  (D3's per-file exemption vs. a widened union), rule 9 (a waiver re-verified against live content,
  not a standing grant)
