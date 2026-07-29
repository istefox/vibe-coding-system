#!/bin/bash
# review-triage-fix: anti-test-weakening detector (heuristic, report-only).
# Input: a unified diff on stdin. Output: "CLEAN" or one or more
#   WEAKENED<TAB><file><TAB><reason>
#   SUSPECT<TAB><file><TAB><detector><TAB><line>
#   AWKGUARD<TAB><detector><TAB><reason>
# Heuristic on purpose (design §7-B / ADR-0051). No auto-revert. Always exits 0 (§D4).
#
# SUSPECT (issue #105 / ADR-0051) is a SEPARATE sentinel from WEAKENED and deliberately does
# NOT match `^WEAKENED` — every caller wired by ADR-0047 greps `^WEAKENED` to decide whether to
# halt an unattended run, and a SUSPECT finding is a heuristic over a diff with no type
# information and no test execution (ADR-0051 §D2). Promoting it into that grep is the most
# likely future "fix" and it is exactly the wrong one.
#
# literal-assertion-added SHIPS DISABLED BY DEFAULT (ADR-0051 §D5, Task 4 measurement recorded in
# the ADR and the feature report). It requires both halves of the condition (an implementation
# file AND a test file change in the same diff) and a literal comparison introduced in the test —
# exactly the shape of adding a test for any new constant, so on a synthetic 5-diff legitimate-
# vs-malicious sample it fired on 4/5, three of them ordinary legitimate co-changes. Real-history
# measurement against this repo's own last 153 commits produced zero firings either way (this
# repo's bash test idiom does not use assert-style tokens at all), so the repo's own history gave
# no evidence either for or against — the synthetic sample is what settled it. The code stays
# wired and tested; set WEAKENING_SCAN_LITERAL_ASSERTION=1 to opt in.
#
# AWKGUARD (ADR-0051 Task 2, mirroring ADR-0046 §D4's secret-scan.sh probe): when opted in, the
# literal-assertion-added detector requires ERE interval syntax ({2,}) to require a literal of at
# least two characters (filtering the extremely common trivial `== 0`/`== ""` comparisons that
# would otherwise dominate its output even further). An awk without interval support does not
# error on {2,} — it treats the braces as literal characters and the rule silently matches
# nothing. A check that reports nothing must be distinguishable from a check that finds nothing,
# so this is probed at start-up, but ONLY when the detector is enabled — probing a disabled
# detector's requirements has nothing to report. On failure, literal-assertion-added alone is
# skipped (every other detector, WEAKENED or SUSPECT, uses only +/*/?/alternation and needs no
# interval support) and an AWKGUARD line is emitted instead of a possibly-false CLEAN.
# WEAKENING_SCAN_AWK overrides the interpreter so this path is testable.
set -u

AWK="${WEAKENING_SCAN_AWK:-awk}"
LIT_ENABLED="${WEAKENING_SCAN_LITERAL_ASSERTION:-0}"

# --- the interval probe. Same construction discipline as secret-scan.sh: built by concatenation
# so this file is not itself a corpus violation for any future secret-content scan. Only run when
# the detector it guards is actually enabled. ---
AWKGUARD_LITERAL=0
if [ "$LIT_ENABLED" = "1" ]; then
  _probe="aa"; _probe="${_probe}a"
  _probe_out=$(printf '%s\n' "$_probe" \
    | "$AWK" '$0 ~ /^a{2,}$/ { print "y" }' 2>/dev/null)
  if [ "$_probe_out" != "y" ]; then
    AWKGUARD_LITERAL=1
    printf 'weakening-scan: WARNING — the awk in use does not support ERE interval syntax ({2,}).\n' >&2
    printf 'weakening-scan: literal-assertion-added is disabled for this run (see AWKGUARD line).\n' >&2
    printf 'weakening-scan: awk = %s ; version = %s\n' "$AWK" \
      "$("$AWK" --version 2>&1 | head -1 || echo unknown)" >&2
  fi
fi

TMPD=$(mktemp -d) || { printf 'weakening-scan: cannot create a temp directory\n' >&2; exit 0; }
trap 'rm -rf "$TMPD"' EXIT

cat >"$TMPD/scan.awk" <<'AWKEOF'
function is_test(p){ return (p ~ /(^|\/)tests?\//) || (p ~ /(^|\/)spec\//) \
  || (p ~ /test_[^\/]*\.[a-zA-Z]+$/) || (p ~ /_test\.[a-zA-Z]+$/) \
  || (p ~ /\.test\.[a-zA-Z]+$/) || (p ~ /\.spec\.[a-zA-Z]+$/) \
  || (p ~ /Tests?\.[a-zA-Z]+$/) }

# ==================================================================================================
# WHAT `CLEAN` DOES NOT MEAN (ADR-0073 §D4, issue #177). READ THIS BEFORE TRUSTING A CLEAN LINE.
#
# `assert-removed` is a COUNT COMPARISON: asrt_rm > asrt_add. Editing an assertion IN PLACE removes
# one assert-bearing line and adds one, so the counts are equal and the rule cannot fire. Changing
#
#     assert result.tension_ok is True   ->   assert result.tension_ok is False
#
# to match whatever the implementation happens to produce is the textbook weakening move, and it is
# invisible to EVERY detector here: the file still exists, no skip marker appears, the counts match,
# the `def` count is unchanged, and the test still has an assertion.
#
# NO DETECTOR WAS ADDED, and the reason is measured rather than assumed:
#   - The diff shape is genuinely ambiguous. Correcting a wrong test and relaxing a right one
#     produce byte-identical diffs. No rule over a diff can separate them, so any detector here
#     reports "an assertion changed", which is ordinary test maintenance.
#   - Measured over this repository's last 354 commits (89 of which touch a test file): a rule on
#     `asrt_rm == asrt_add > 0` fires twice. BOTH hits are PROSE — a comment containing the word
#     "assertion" and an `ok "…"` message containing "asserts". Precision on the observed sample:
#     0 of 2. A signal that is always wrong is one its readers learn to dismiss, which is how a
#     detector makes the CLEAN line here mean LESS rather than more (ADR-0048 §D7).
#   - ADR-0051 §D5 reached the same wall on this same script and shipped `literal-assertion-added`
#     disabled by default for it. This is that precedent applied one step earlier: not shipped.
#
# So the blind spot is real, permanent for now, and written down instead of papered over. A CLEAN
# line from this script means "none of the detectors below fired", never "no weakening occurred".
# ==================================================================================================
function is_assert_tok(s){ return s ~ /assert|expect\(|XCTAssert|EXPECT_|ASSERT_|require\.|should|t\.Error|t\.Fatal/ }
function is_test_def(s){ return s ~ /(def|func|fn)[ \t]+[Tt]est|[ \t]it\(|[ \t]test\(|@Test/ }
# `xit\(` and `\.skip\(` are token-boundary anchored, not bare substrings (live-defect fix):
# unanchored, `xit\(` matches the tail of `sys.exit(`/`process.exit(` and `\.skip\(`
# matches RxJS's `Observable.skip(n)` operator (e.g. `source$.skip(2)`), both ordinary
# host-language code with no relation to a disabled test. `(^|[^A-Za-z])xit\(` requires the
# character before "xit(" to not be a letter, which a real xit() call satisfies (preceded by
# whitespace/punctuation/start-of-line) and "exit(" never does (always preceded by the letter
# "e"). `(^|[^A-Za-z0-9_$])(test|it)\.skip\(` requires the identifier immediately before
# ".skip(" to be exactly "test" or "it" (Jest/Jasmine's disabled-test idiom), which excludes an
# arbitrary longer identifier like "source$" ending in a non-"test"/"it" token. Do not simplify
# this back to a bare substring match.
function is_skip_add(s){ return s ~ /@pytest\.mark\.(skip|xfail)|(^|[^A-Za-z0-9_$])(test|it)\.skip\(|\.only\(|(^|[^A-Za-z])xit\(|xdescribe\(|t\.Skip\(|@Disabled|@Ignore|@unittest\.skip/ }

# deleted-public-symbol: an exported function/route/public class signature. pub_name() returns
# the identifying key (the symbol NAME, not the full line) so a body-only edit — old and new
# lines both name the same symbol but differ elsewhere — is recognised as "still present", not
# "deleted", when comparing removed vs. added signatures in the same file (ADR-0051 §D5 rename
# exclusion). Route findings key on method+path since the handler name is not in the signature.
function pub_name(s,    t){
  if (match(s, /^export[ \t]+(function|const|class|default[ \t]+function)[ \t]+/)) {
    t = substr(s, RSTART+RLENGTH)
    if (match(t, /^[A-Za-z_$][A-Za-z0-9_$]*/)) return substr(t, RSTART, RLENGTH)
    return ""
  }
  if (match(s, /^public[ \t]+(class|struct|func|static)[ \t]+/)) {
    t = substr(s, RSTART+RLENGTH)
    if (match(t, /^[A-Za-z_][A-Za-z0-9_]*/)) return substr(t, RSTART, RLENGTH)
    return ""
  }
  if (match(s, /^def[ \t]+/)) {
    t = substr(s, RSTART+RLENGTH)
    if (match(t, /^[A-Za-z][A-Za-z0-9_]*\(/)) return "def:" substr(t, RSTART, RLENGTH-1)
    return ""
  }
  if (match(s, /^func[ \t]+/)) {
    t = substr(s, RSTART+RLENGTH)
    if (match(t, /^[A-Z][A-Za-z0-9_]*\(/)) return "func:" substr(t, RSTART, RLENGTH-1)
    return ""
  }
  if (match(s, /^(app|router)\.(get|post|put|delete|patch)\([ \t]*['"][^'"]*['"]/))
    return "route:" substr(s, RSTART, RLENGTH)
  return ""
}
function is_public_sym(s){ return pub_name(s) != "" }

# swallowed-error: catch/except/rescue open. Callers pass a LEFT-TRIMMED copy of the added line —
# these patterns are anchored to (optional "}" then) start-of-content, not start-of-line, so an
# indented `    except Exception: pass` still matches.
function is_catch_open(s){
  return (s ~ /(^|[ \t}])catch[ \t]*\(/) || (s ~ /^except[^:]*:/) || (s ~ /^rescue\b/)
}
function is_catch_empty_oneline(s){
  return (s ~ /catch[ \t]*\([^)]*\)[ \t]*\{[ \t]*\}/) || (s ~ /^except[^:]*:[ \t]*pass[ \t]*$/)
}
function is_log_or_rethrow(s){
  return (s ~ /(log|Log|console\.|print|logger|Logger|raise|throw|panic)/)
}
function is_catch_close(s){
  return (s ~ /^\}[ \t]*$/) || (s ~ /^end[ \t]*$/)
}

# literal-assertion-added: an assertion whose compared value is a literal (>=2 chars/digits —
# the interval-gated part; requires AWKGUARD_LITERAL_OK).
function is_literal_assert(s){
  if (!(s ~ /assert|expect\(|XCTAssert|EXPECT_|ASSERT_|require\.|should|assertEqual|toBe\(/)) return 0
  if (s ~ /(==|,)[ \t]*-?[0-9]{2,}([^0-9]|$)/) return 1
  if (s ~ /(==|,)[ \t]*-?[0-9]+\.[0-9]{2,}/) return 1
  if (s ~ /(==|,)[ \t]*"[^"]{2,}"/) return 1
  if (s ~ /(==|,)[ \t]*'"'"'[^'"'"']{2,}'"'"'/) return 1
  return 0
}

function flush(){
  if(file!="" && testf){
    if(deleted) print "WEAKENED\t" file "\tdeleted-test-file"
    else {
      if(skipadd>0)            print "WEAKENED\t" file "\tskip/xfail-added"
      if(asrt_rm>asrt_add)     print "WEAKENED\t" file "\tassert-removed (" asrt_rm ">" asrt_add ")"
      if(defrm>0 && defadd==0) print "WEAKENED\t" file "\ttest-removed-or-commented"
    }
  }
  if(file!="" && !deleted){
    # deleted-public-symbol: for each removed signature not matched by an identical added
    # signature in the same file (a pure move, excluded per ADR-0051 §D5), report it.
    for(i=1;i<=rm_n;i++){
      if(!(rm_sig[i] in add_sig_seen))
        print "SUSPECT\t" file "\tdeleted-public-symbol\t" rm_ln[i]
    }
  }
}

function close_test(){
  if(in_test && !test_saw_assert && !test_excluded)
    print "SUSPECT\t" file "\tzero-assertion-test\t" test_start_ln
  in_test=0; test_saw_assert=0; test_body_n=0; test_excluded=0; test_start_ln=0
}

function close_catch(){
  # Same finding whether the body was truly empty (catch_body_n==0) or had content but no
  # log/rethrow — ADR-0051 D1 makes no distinction ("empty, or neither a log nor a rethrow").
  if(catch_active && !catch_has_logthrow)
    print "SUSPECT\t" file "\tswallowed-error\t" catch_start_ln
  catch_active=0; catch_has_logthrow=0; catch_body_n=0; catch_start_ln=0; catch_window=0
}

/^diff --git / {
  flush(); close_test(); close_catch()
  file=""; testf=0; deleted=0; skipadd=0; asrt_rm=0; asrt_add=0; defrm=0; defadd=0
  oldln=0; newln=0
  rm_n=0; delete rm_sig; delete rm_ln; delete add_sig_seen
  in_test=0; test_saw_assert=0; test_body_n=0; test_excluded=0; test_start_ln=0
  catch_active=0; catch_has_logthrow=0; catch_body_n=0; catch_start_ln=0; catch_window=0
  next
}
/^deleted file mode/ { deleted=1; next }
/^\+\+\+ / { p=$2; sub(/^b\//,"",p); if(p!="/dev/null") file=p; testf=is_test(file); next }
/^--- /    { if(file==""){ p=$2; sub(/^a\//,"",p); file=p; testf=is_test(file) } next }
/^@@ /     {
  if (match($0, /-[0-9]+/)) oldln = substr($0, RSTART+1, RLENGTH-1) + 0
  if (match($0, /\+[0-9]+/)) newln = substr($0, RSTART+1, RLENGTH-1) + 0
  next
}
{
  if(file=="") next
  line=$0
  c = substr(line,1,1)
  if(c=="-" && substr(line,1,3)!="---"){
    b=substr(line,2); cur_ln=oldln; oldln++
    if(testf){
      if(is_assert_tok(b)) asrt_rm++
      if(is_test_def(b)) defrm++
    }
    if(is_public_sym(b)){ rm_n++; rm_sig[rm_n]=pub_name(b); rm_ln[rm_n]=cur_ln }
  } else if(c=="+" && substr(line,1,3)!="+++"){
    a=substr(line,2); cur_ln=newln; newln++
    if(testf){
      if(is_assert_tok(a)) asrt_add++
      if(is_test_def(a)) defadd++
      if(is_skip_add(a)) skipadd++

      # zero-assertion-test state machine (added test bodies only). A one-line def with an
      # inline assert (`def test_x(): assert True`) must count on the SAME line that opens it —
      # this branch does not fall through to the body-scan branch below.
      if(is_test_def(a)){
        close_test()
        in_test=1; test_saw_assert=(is_assert_tok(a) ? 1 : 0)
        test_body_n=0; test_excluded=0; test_start_ln=cur_ln
      } else if(in_test){
        stripped=a; gsub(/^[ \t]+/,"",stripped); gsub(/[ \t]+$/,"",stripped)
        if(stripped!="" && stripped !~ /^(#|\/\/|\*)/){
          if(is_assert_tok(a)) test_saw_assert=1
          test_body_n++
          if(test_body_n==1){
            if(stripped ~ /^[A-Za-z_][A-Za-z0-9_.]*\([^)]*\)[ \t;]*$/ && !is_assert_tok(a))
              test_excluded=1
          } else {
            test_excluded=0
          }
        }
      }
    }
    if(is_public_sym(a)) add_sig_seen[pub_name(a)]=1

    # literal-assertion-added: SHIPS DISABLED BY DEFAULT (see header, ADR-0051 §D5) — gated on
    # LIT_ENABLED, independent of the awk-capability gate AWKGUARD_LITERAL_OK. Buffered globally,
    # only emitted if an impl (non-test) file also changed somewhere in the diff (ADR-0051 §D1).
    if(testf && LIT_ENABLED && AWKGUARD_LITERAL_OK && is_literal_assert(a)){
      lit_n++; lit_file[lit_n]=file; lit_ln[lit_n]=cur_ln
    }

    # swallowed-error: only newly-introduced (added) catch/except/rescue blocks.
    a_lt=a; gsub(/^[ \t]+/,"",a_lt)
    if(is_catch_open(a_lt)){
      close_catch()
      if(is_catch_empty_oneline(a_lt)){
        # §D5 exclusion applies here too: a trailing comment on the same line explains the swallow.
        if(!(a_lt ~ /(#|\/\/)/)) print "SUSPECT\t" file "\tswallowed-error\t" cur_ln
      } else {
        catch_active=1; catch_has_logthrow=0; catch_body_n=0; catch_start_ln=cur_ln; catch_window=0
      }
    } else if(catch_active){
      catch_window++
      if(is_catch_close(a_lt)){
        close_catch()
      } else {
        stripped=a_lt; gsub(/[ \t]+$/,"",stripped)
        if(stripped!=""){
          catch_body_n++
          if(is_log_or_rethrow(a)) catch_has_logthrow=1
          # ADR-0051 §D5 exclusion: a comment inside the catch body explaining the intentional
          # swallow, matching the house convention for deliberate no-ops elsewhere in this repo.
          if(stripped ~ /^(#|\/\/)/) catch_has_logthrow=1
        }
        if(catch_window>=6) close_catch()  # bounded look-ahead — bail out, no flag (known
                                            # limitation: an indentation-scoped except/rescue
                                            # body longer than 6 added lines with no closing
                                            # brace is never flagged — false negative, not a
                                            # false positive, by design)
      }
    }
  } else {
    # context line: advances both counters, and can legitimately close an open catch/test scope
    # captured only from added lines above — context lines never open/close our state machines.
    oldln++; newln++
  }
  if(!testf) { if(!(file in impl_seen)){ impl_seen[file]=1; g_impl_changed=1 } }
}
END{
  flush(); close_test(); close_catch()
  if(g_impl_changed){
    for(i=1;i<=lit_n;i++) print "SUSPECT\t" lit_file[i] "\tliteral-assertion-added\t" lit_ln[i]
  }
}
AWKEOF

_scan_input="$TMPD/in.diff"
cat >"$_scan_input"

_out=$("$AWK" -v LIT_ENABLED="$([ "$LIT_ENABLED" = "1" ] && echo 1 || echo 0)" \
  -v AWKGUARD_LITERAL_OK="$([ "$AWKGUARD_LITERAL" -eq 1 ] && echo 0 || echo 1)" \
  -f "$TMPD/scan.awk" <"$_scan_input")

if [ "$AWKGUARD_LITERAL" -eq 1 ]; then
  _guard_line="AWKGUARD	literal-assertion-added	interval-syntax-unsupported"
  if [ -n "$_out" ]; then
    printf '%s\n%s\n' "$_out" "$_guard_line"
  else
    printf '%s\n' "$_guard_line"
  fi
else
  if [ -z "$_out" ]; then
    echo "CLEAN"
  else
    printf '%s\n' "$_out"
  fi
fi
exit 0
