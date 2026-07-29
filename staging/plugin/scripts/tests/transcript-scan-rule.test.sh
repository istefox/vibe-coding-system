#!/bin/bash
# transcript-scan-rule.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash transcript-scan-rule.test.sh
#
# Covers issue #193 (ADR-0077): the CLASS-level guard for the self-arming marker pattern.
#
# THE RULE
#   A hook that extracts a marker from a subagent transcript must read only the FIRST `user`
#   entry, or declare in its own source why it does not.
#
# WHY. Tool results are `user` entries. A full scan therefore cannot distinguish the dispatch
# prompt from a file the agent READ, and the population most likely to read a marker-bearing file
# is agents working on the hook system itself. Issue #127 is what that cost: an architect briefed
# to read write-scope-enforce.sh's own source pulled the literal grep pattern into its transcript
# and bound itself to the scope `[^`, deadlocking a chain.
#
# WHY A CLASS GUARD AND NOT THREE MORE PINS. #127 fixed one hook and audited three, and every guard
# it left is instance-level: write-scope-enforce E4 anchors `head -1` in THAT hook, test-write-scope
# TB7/TB8 the same pair in THAT one, agent-write-scope F1 asserts THAT one reads no transcript.
# Nothing asserted the rule. ADR-0067 is the standing precedent for what happens next: a rule
# recorded in three places and pinned on two specific skills was violated on a THIRD by issue #56,
# because nothing checked the class. F6 of skill-text-corrections.test.sh closed it by deriving the
# population at run time. This is that instrument, one layer down.
#
# DIRECTION (rule 5 of .claude/context.md). The derivation is deliberately BROAD — every script that
# so much as mentions a transcript — and narrowing happens through DECLARED exemptions in the source.
# That way a new file is in the population by default and must say something; a narrow derivation
# would quietly not see it, which is #127's own failure mode applied to its own guard.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# The exemption marker, built at run time so this file does not match its own search (rule 12 —
# PTB5/PTB6's lesson: a scan whose needle is a literal counts itself).
MARK="transcript-""scan-exempt"

# --- the derivation, in one place, used by the sweep and by both self-tests ------------------
# population <dir> -> every *.sh that references a transcript at all
population() {
  for _f in "$1"/*.sh; do
    [ -f "$_f" ] || continue
    grep -q 'transcript_path\|\.jsonl' "$_f" 2>/dev/null && printf '%s\n' "$_f"
  done
}
# compliant <file> -> the FIRST pipe stage after the jq read of `user` entries is `head -1`.
#
# Anchored on POSITION, not on the presence of the string: extraction pipelines routinely END in a
# second, unrelated `head -1`, and a neighbourhood grep matches a non-compliant hook too — that
# mistake was made and caught once already, in write-scope-enforce.test.sh E4.
#
# It must also survive BOTH shapes the two compliant hooks actually use, and a first draft did not:
# write-scope-enforce.sh puts `| head -1` on its own continuation line, test-write-scope.sh writes
# the whole pipeline on one line, and a predicate that only looked at the NEXT line reported the
# second as non-compliant. The class guard's first run found that — a predicate written against one
# syntactic shape, which is the same mistake one level up from the rule it enforces.
#
# The jq PROGRAM contains its own `|` (`select(...) | tostring`), so the scan starts after the
# program's closing quote rather than at the first pipe character in the line.
compliant() {
  _line=$(grep -n 'select(.type=="user")' "$1" 2>/dev/null \
    | grep -v ':[[:space:]]*#' | head -1 | cut -d: -f1)
  [ -n "$_line" ] || return 1
  _seg=$(sed -n "${_line},$((_line + 1))p" "$1" | tr '\n' ' ' | sed 's/\\ / /g')
  _rest=${_seg#*\'}          # past the jq program's opening quote
  _rest=${_rest#*\'}         # past its closing quote — every remaining | is a real pipe
  case "$_rest" in *\|*) : ;; *) return 1 ;; esac
  _stage=$(printf '%s' "$_rest" | sed 's/^[^|]*|[[:space:]]*//' | sed 's/[[:space:]]*$//')
  case "$_stage" in "head -1"*) return 0 ;; esac
  return 1
}
exempt() { grep -q "^#[[:space:]]*${MARK}:" "$1" 2>/dev/null; }

# =====================================================================================
# T. The sweep. Every file in the population either complies or declares.
POP=$(population "$SCRIPTS")
N=$(printf '%s\n' "$POP" | sed '/^$/d' | wc -l | tr -d ' ')

# T0: the count guard. A derivation that matches nothing reports nothing, and a silent zero reads
# exactly like full coverage — the pairs-completeness self-test-2 lesson and the ADR-0043 direction
# lesson, both of which this file exists to apply.
if [ "$N" -ge 8 ]; then
  ok "T0: the derivation found $N transcript-touching scripts (count guard: >= 8)"
else
  bad "T0: derivation found only $N scripts — every assertion below would pass vacuously"
fi

_viol=""
for _f in $POP; do
  compliant "$_f" && continue
  exempt "$_f" && continue
  _viol="$_viol $(basename "$_f")"
done
if [ -z "$_viol" ]; then
  ok "T1: every transcript-touching script either reads the first user entry or declares why not"
else
  bad "T1: neither compliant nor declared —$_viol"
fi

# T2: the two enforcing hooks must be COMPLIANT, never merely exempt. They are the ones that derive
# a scope from a marker, so an exemption on either would be the #127 defect wearing a waiver.
for _n in write-scope-enforce test-write-scope; do
  _p="$SCRIPTS/$_n.sh"
  if compliant "$_p"; then
    ok "T2: $_n.sh reads only the first user entry (compliant, not exempt)"
  else
    bad "T2: $_n.sh no longer restricts to the first user entry — #127 is reintroduced"
  fi
done

# T3: and neither may hold an exemption. A file that is both would let a later edit drop the
# head -1 and still pass T1 on the strength of a stale waiver.
for _n in write-scope-enforce test-write-scope; do
  if exempt "$SCRIPTS/$_n.sh"; then
    bad "T3: $_n.sh carries an exemption — an enforcing hook must comply, not declare"
  else
    ok "T3: $_n.sh holds no exemption"
  fi
done

# T4: an exemption must carry a REASON, not just the marker. A bare waiver is an exemption list by
# another name, and the whole point of putting it in the source is that it says something.
_thin=""
for _f in $POP; do
  exempt "$_f" || continue
  _r=$(grep "^#[[:space:]]*${MARK}:" "$_f" | head -1 | sed "s/^#[[:space:]]*${MARK}:[[:space:]]*//")
  [ "${#_r}" -ge 40 ] || _thin="$_thin $(basename "$_f")(${#_r})"
done
[ -z "$_thin" ] && ok "T4: every exemption carries a reason of substance" \
                || bad "T4: thin or empty exemption reasons —$_thin"

# T5: the exemption lives in the SOURCE, never in this file. An exemption list keyed by filename is
# the identity-based waiver ADR-0069's PTD deliberately refused: it does not travel when the file is
# renamed or copied, and it lets a test author excuse a hook without touching it.
if grep -qE '^[[:space:]]*(EXEMPT|WAIVED|SKIP)_(FILES|LIST)=' "$0"; then
  bad "T5: this test carries its own exemption list — the waiver must live in the hook"
else
  ok "T5: no filename-keyed exemption list in the test itself"
fi

# =====================================================================================
# Z. Self-tests. The derivation and the predicates must actually catch a violator, or T1 is a
# sentence that always passes. Both directions, on synthetic files, in a directory of their own.
mkdir -p "$TMP/z"

# Z1: a NEW non-compliant hook is flagged. This is the case the whole file exists for: someone adds
# a marker-driven hook, scans every user entry, and declares nothing.
cat > "$TMP/z/rogue.sh" <<'ROGUE'
#!/bin/bash
# a new hook that scans the whole transcript for its marker and declares nothing
TP=$(jq -r '.transcript_path' )
SCOPE=$(jq -r 'select(.type=="user") | tostring' "$TP" \
  | grep -o 'you may edit ONLY [^ ]*' | head -1)
ROGUE
_z1=""
for _f in $(population "$TMP/z"); do
  compliant "$_f" && continue
  exempt "$_f" && continue
  _z1="$_z1 $(basename "$_f")"
done
case "$_z1" in *rogue.sh*) ok "Z1: a new full-scan hook with no declaration IS flagged" ;;
  *) bad "Z1: the rogue file was not flagged — the sweep cannot catch what it exists to catch" ;;
esac

# Z2: and the same file becomes acceptable once it complies. Without this, Z1 would also pass
# against a predicate that flags everything, including the compliant hooks (rule 8, the positive
# twin — and the reason T2 is not sufficient on its own: T2 names two files, this tests the rule).
cat > "$TMP/z/fixed.sh" <<'FIXED'
#!/bin/bash
TP=$(jq -r '.transcript_path' )
SCOPE=$(jq -r 'select(.type=="user") | tostring' "$TP" \
  | head -1 \
  | grep -o 'you may edit ONLY [^ ]*' | head -1)
FIXED
compliant "$TMP/z/fixed.sh" && ok "Z2: the same hook passes once the head -1 stage is added" \
                            || bad "Z2: a compliant hook is reported non-compliant — the predicate over-flags"

# Z3: a declared exemption is accepted, and ONLY when the marker is a real declaration. A file that
# merely mentions the phrase in prose must not be excused — the #127 lesson turned on itself.
printf '#!/bin/bash\n# %s: a genuine reason, long enough to be a reason and not a shrug\nTP=x.jsonl\n' \
  "$MARK" > "$TMP/z/declared.sh"
printf '#!/bin/bash\n# we should think about whether %s applies here one day\nTP=x.jsonl\n' \
  "$MARK" > "$TMP/z/musing.sh"
if exempt "$TMP/z/declared.sh" && ! exempt "$TMP/z/musing.sh"; then
  ok "Z3: only a line-anchored declaration counts; a passing mention in prose does not"
else
  bad "Z3: exemption detection accepts prose (declared=$(exempt "$TMP/z/declared.sh" && echo y || echo n) musing=$(exempt "$TMP/z/musing.sh" && echo y || echo n))"
fi

# Z4: the derivation itself must not silently return nothing. A glob matching no files reports no
# violations, which is indistinguishable from full compliance — the failure shape this whole file
# is about, applied to its own machinery.
mkdir -p "$TMP/empty"
_e=$(population "$TMP/empty" | sed '/^$/d' | wc -l | tr -d ' ')
[ "$_e" -eq 0 ] && ok "Z4: an empty directory derives an empty population (T0 is what catches that)" \
                || bad "Z4: population() invented $_e entries from an empty directory"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
