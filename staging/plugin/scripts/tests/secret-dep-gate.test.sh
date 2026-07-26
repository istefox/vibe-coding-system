#!/bin/bash
# secret-dep-gate.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash secret-dep-gate.test.sh
#
# Covers issue #100 / ADR-0046: content-based secret detection (secret-scan.sh) and, from Task 4
# onward, the dependency gate (dependency-scan.sh).
#
# THE FALSE-POSITIVE CORPUS IS THIS REPOSITORY.
# Section D runs the scanner over `git ls-files` and fails if any CONTENT rule fires. That is not a
# style preference: this tree already carries seven 40-hex GitHub Actions SHA pins and a 60-hex fake
# trust hash, and the measurement that decided ADR-0046 §D3 was that a naive "looks like base64"
# pattern ([A-Za-z0-9+/]{32,}) matches ordinary prose here, because `/` is in the base64 alphabet and
# every absolute path in every ADR qualifies. Rules are anchored on a vendor prefix or a keyword.
# Entropy scoring is banned by the ADR, and section B is the evidence for why.
#
# EVERY POSITIVE FIXTURE IS BUILT BY CONCATENATION AT RUN TIME (ADR-0046 §D11, plan PF4).
# No key-shaped literal appears whole in this file. Two reasons, and the weaker one is the one that
# would otherwise rot: this file's own NAME contains `secret`, so the filename rule claims it and it
# is never content-scanned by section D. That protection disappears the day the filename rule is
# narrowed, so the concatenation discipline stands on its own.
#
# THE FILENAME DIFFERS FROM THE SPEC ON PURPOSE (ADR-0046 §D13, plan PF1).
# The SPEC names `tests/secrets-dep-gate.test.sh`. `protect-files.sh` is a PreToolUse hook whose
# PROTECTED list contains the substring `secrets`, so that path is unwritable by any agent on this
# machine — the ADR's own first filename was denied, which is how the constraint was found. Every
# filename in this feature uses the singular `secret`. The `docs-ci.yml` registry entry must use the
# singular name too, or CI fails on a missing file.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
SCAN="$SCRIPTS/secret-scan.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
TAB=$(printf '\t')
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

OUT=""; RC=0
run_files() { OUT=$(bash "$SCAN" --files "$1" 2>"$TMP/err"); RC=$?; }
run_diff()  { OUT=$(bash "$SCAN" --diff <"$1" 2>"$TMP/err"); RC=$?; }

# mklist <name> <path>... -> prints the list-file path
mklist() {
  _l="$TMP/list_$1"; : >"$_l"; shift
  for _p in "$@"; do printf '%s\n' "$_p" >>"$_l"; done
  printf '%s' "$_l"
}
cnt()     { printf '%s' "$1" | grep -c . ; }
hasrule() { printf '%s' "$OUT" | grep -q "${TAB}$1\$"; }

# --- fixture material, assembled so no literal here is itself a finding ------------------------
AK="AKIA"                                     # prefix only; the rule needs 16 more characters
SUF1="QWERTYUIOPASDFGH"; SUF2="ZXCVBNMASDFGHJKL"; SUF3="ABCDEFGHIJKLMNOP"
SUF4="1234567890ABCDEF"; SUF5="MNBVCXZLKJHGFDSA"
V40="ABCDEFGHIJ"; V40="${V40}KLMNOPQRST"; V40="${V40}UVWXYZabcd"; V40="${V40}0123456789"
PEM1="-----BEGIN "; PEM2="RSA PRIVATE"; PEM3=" KEY-----"
GH="ghp"; GH="${GH}_"; GH="${GH}abcdefghij0123456789ABCDEFGHIJ012345"
JWT="eyJ"; JWT="${JWT}hbGciOiJIUzI1NiJ9."; JWT="${JWT}eyJ"
JWT="${JWT}zdWIiOiIxMjM0NTY3ODkwIn0."; JWT="${JWT}dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk"
S18="Kj9mN2pQrS"; S18="${S18}4tV6wX8y"       # 18 chars, not a placeholder, not hex
H40="8f4b7c2e9a1d6053f2b8c4e7a903d1f6b5c8e2a7"
H60="deadbeefcafefeedfacedeadbeefcafefeedfacedeadbeefcafefeedface"
H64="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
B44="AAAAAAAAAABBBBBBBBBBCCCCCCCCCCDDDDDDDDDDEEEE"

# ==============================================================================================
# A. Content rules fire. One fixture per rule, scanned through --files.
# ==============================================================================================
printf 'aws_id_field = %s%s\n' "$AK" "$SUF1"                 >"$TMP/a1.txt"
run_files "$(mklist a1 "$TMP/a1.txt")"
hasrule aws-access-key-id && ok "A1: aws-access-key-id fires" \
  || bad "A1: aws-access-key-id not reported — got: $OUT"

# A7 rides on A1's run: a reporter exits 0 even when it found something (ADR-0046 §D2, plan PF6).
[ "$RC" -eq 0 ] && ok "A7: exit 0 on a run that produced findings (reporter contract)" \
  || bad "A7: exit $RC on a run with findings — must be 0"

printf 'aws_secret_access_key = "%s"\n' "$V40"               >"$TMP/a2.txt"
run_files "$(mklist a2 "$TMP/a2.txt")"
hasrule aws-secret-access-key && ok "A2: aws-secret-access-key fires" \
  || bad "A2: aws-secret-access-key not reported — got: $OUT"

printf '%s%s%s\n' "$PEM1" "$PEM2" "$PEM3"                    >"$TMP/a3.txt"
run_files "$(mklist a3 "$TMP/a3.txt")"
hasrule private-key-block && ok "A3: private-key-block fires" \
  || bad "A3: private-key-block not reported — got: $OUT"

printf 'Authorization: token %s\n' "$GH"                     >"$TMP/a4.txt"
run_files "$(mklist a4 "$TMP/a4.txt")"
hasrule github-token && ok "A4: github-token fires" \
  || bad "A4: github-token not reported — got: $OUT"

printf 'Bearer %s\n' "$JWT"                                  >"$TMP/a5.txt"
run_files "$(mklist a5 "$TMP/a5.txt")"
hasrule jwt && ok "A5: jwt fires (both segments must start with the JSON-object prefix)" \
  || bad "A5: jwt not reported — got: $OUT"

printf 'api_key = "%s"\n' "$S18"                             >"$TMP/a6.txt"
run_files "$(mklist a6 "$TMP/a6.txt")"
hasrule assigned-secret && ok "A6: assigned-secret fires on a non-placeholder value" \
  || bad "A6: assigned-secret not reported — got: $OUT"

# ==============================================================================================
# B. The false-positive corpus, in miniature. Every fixture must produce ZERO output.
# Each of these is a real shape that exists in this repository or in a target project.
# ==============================================================================================
neg() { # neg <label> <fixture-path>
  run_files "$(mklist "neg_$(basename "$1")" "$2")"
  if [ "$(cnt "$OUT")" -eq 0 ] && [ "$RC" -eq 0 ]; then ok "$1"
  else bad "$1 — expected no finding, rc=$RC, got: $OUT"; fi
}

printf 'uses: actions/checkout@%s\n' "$H40"                  >"$TMP/b1.txt"
neg "B1: a GitHub Actions 40-hex SHA pin is not a secret" "$TMP/b1.txt"

printf "printf '%s\\\\t/never/exists/Proj_Linux\\\\n' > \"\$TRUST_FILE\"\\n" "$H60" >"$TMP/b2.txt"
neg "B2: the 60-hex fake trust hash in run-hook-tests.sh is not a secret" "$TMP/b2.txt"

# Two lines: the plan's `checksum` case, plus a keyworded digest — the second is what actually
# exercises the pure-hex exclusion, since `checksum` is not a keyword at all.
printf 'checksum = "%s"\ntoken_sha256 = "%s"\n' "$H64" "$H64" >"$TMP/b3.txt"
neg "B3: a 64-hex SHA-256 digest is excluded, keyword or not" "$TMP/b3.txt"

printf '%s\n' "$B44"                                         >"$TMP/b4.txt"
neg "B4: a bare 44-char base64 blob with no keyword is not a secret" "$TMP/b4.txt"

printf 'see /Users/stefanoferri/Developer/vibe-coding-system/SPEC.md for detail\n' >"$TMP/b5.txt"
neg "B5: an absolute path ending in SPEC.md (the case that killed the entropy design)" "$TMP/b5.txt"

printf 'Authorization: Bearer ${GITHUB_TOKEN}\n'             >"$TMP/b6.txt"
neg "B6: a Bearer header reading an env var is not a definition" "$TMP/b6.txt"

# These three DO match the raw assigned-secret pattern and are cleared by the placeholder
# exclusion. Their presence here is the evidence that the exclusion list does its job.
printf 'api_key = "your-api-key-here"\npassword = "changeme"\ntoken = "xxxxxxxxxxxxxxxxxx"\n' \
  >"$TMP/b7.txt"
neg "B7: placeholder values (your-…, changeme, xxxx…) are excluded" "$TMP/b7.txt"

printf 'token = os.environ["GITHUB_TOKEN"]\n'                >"$TMP/b8.txt"
neg "B8: an env read defines nothing" "$TMP/b8.txt"

# ==============================================================================================
# C. Structure and modes.
# ==============================================================================================
mkdir -p "$TMP/c1"
printf 'HELLO=world\n' >"$TMP/c1/.env"
run_files "$(mklist c1 "$TMP/c1/.env")"
if printf '%s' "$OUT" | grep -q ":0${TAB}filename-pattern\$"; then
  ok "C1: filename-pattern fires on .env and reports line 0"
else bad "C1: expected a filename-pattern finding at line 0 — got: $OUT"; fi

mkdir -p "$TMP/c2"
printf '%s%s\n%s\napi_key = "%s"\n' "$AK" "$SUF2" "$GH" "$S18" >"$TMP/c2/.env"
run_files "$(mklist c2 "$TMP/c2/.env")"
if [ "$(cnt "$OUT")" -eq 1 ] && hasrule filename-pattern; then
  ok "C2: a filename match is reported once, not twice — content is not scanned"
else bad "C2: expected exactly one filename-pattern line — got: $OUT"; fi

printf '# header\n%s%s\n%s%s\n%s%s\n%s%s\n%s%s\n' \
  "$AK" "$SUF1" "$AK" "$SUF2" "$AK" "$SUF3" "$AK" "$SUF4" "$AK" "$SUF5" >"$TMP/c3.txt"
run_files "$(mklist c3 "$TMP/c3.txt")"
if [ "$(cnt "$OUT")" -eq 1 ] && printf '%s' "$OUT" | grep -q ":2${TAB}aws-access-key-id\$"; then
  ok "C3: one line per (file, rule), at the first occurrence"
else bad "C3: expected a single finding at line 2 — got: $OUT"; fi

printf 'binary fixture ' >"$TMP/c4.bin"
head -c 4 /dev/zero >>"$TMP/c4.bin"
printf '%s%s\n' "$AK" "$SUF3" >>"$TMP/c4.bin"
run_files "$(mklist c4 "$TMP/c4.bin")"
if [ "$(cnt "$OUT")" -eq 0 ] && [ "$RC" -eq 0 ]; then
  ok "C4: a binary file is skipped, not scanned, and does not error"
else bad "C4: binary fixture produced rc=$RC out: $OUT"; fi

run_files "$(mklist c5 "$TMP/does-not-exist.txt")"
if [ "$(cnt "$OUT")" -eq 0 ] && [ "$RC" -eq 0 ]; then
  ok "C5: a listed path that does not exist is skipped, exit stays 0"
else bad "C5: missing path produced rc=$RC out: $OUT"; fi

: >"$TMP/list_empty"
run_files "$TMP/list_empty"
if [ "$(cnt "$OUT")" -eq 0 ] && [ "$RC" -eq 0 ]; then
  ok "C6: an empty file list produces no stdout, exit 0, and does not hang"
else bad "C6: empty list produced rc=$RC out: $OUT"; fi

cat >"$TMP/c7.diff" <<EOF
diff --git a/src/config.py b/src/config.py
index 1111111..2222222 100644
--- a/src/config.py
+++ b/src/config.py
@@ -10,3 +10,4 @@ def load():
     first_context
     second_context
+api_key = "$S18"
     third_context
EOF
run_diff "$TMP/c7.diff"
if printf '%s' "$OUT" | grep -q "src/config.py:12${TAB}assigned-secret\$"; then
  ok "C7: --diff reports the new-file line number from the @@ header, not the diff offset"
else bad "C7: expected src/config.py:12 — got: $OUT"; fi

cat >"$TMP/c8.diff" <<EOF
diff --git a/src/config.py b/src/config.py
--- a/src/config.py
+++ b/src/config.py
@@ -5,4 +5,3 @@
     kept_context
-api_key = "$S18"
     more_context
EOF
run_diff "$TMP/c8.diff"
if [ "$(cnt "$OUT")" -eq 0 ] && [ "$RC" -eq 0 ]; then
  ok "C8: --diff ignores removed lines carrying a key"
else bad "C8: removed line was reported — rc=$RC out: $OUT"; fi

# C14 — the filename rule in --diff mode. C1/C2 only cover --files, and the diff front end runs its
# own pass over the `+++` paths, so without this the diff-mode half of §D7 is untested code.
# Written after the implementation and GREEN on its first run: a coverage pin, not fix evidence.
cat >"$TMP/c14.diff" <<EOF
diff --git a/config/.env b/config/.env
new file mode 100644
--- /dev/null
+++ b/config/.env
@@ -0,0 +1,2 @@
+api_key = "$S18"
+DEBUG=1
EOF
run_diff "$TMP/c14.diff"
if [ "$(cnt "$OUT")" -eq 1 ] && printf '%s' "$OUT" | grep -q "config/.env:0${TAB}filename-pattern\$"; then
  ok "C14: --diff applies the filename rule and suppresses that file's content findings"
else bad "C14: expected one filename-pattern line for config/.env — got: $OUT"; fi

OUT=$(bash "$SCAN" --nonsense 2>"$TMP/err"); RC=$?
if [ "$RC" -eq 2 ] && [ -s "$TMP/err" ]; then
  ok "C9: an unknown flag exits 2 with usage on stderr"
else bad "C9: expected exit 2 + stderr, got rc=$RC err=$(cat "$TMP/err" 2>/dev/null)"; fi

run_files "$(mklist c10 "$TMP/b1.txt" "$TMP/b4.txt")"
if grep -qE 'secret-scan: [0-9]+ file\(s\) listed, [1-9][0-9]* scanned' "$TMP/err"; then
  ok "C10: a clean run still prints the stderr summary with a non-zero scanned count"
else bad "C10: missing or zero-count summary — err=$(cat "$TMP/err" 2>/dev/null)"; fi

printf '%s%s\n' "$AK" "$SUF4" >"$TMP/co:lon.txt"
run_files "$(mklist c11 "$TMP/co:lon.txt")"
if [ "$(cnt "$OUT")" -eq 0 ] && [ "$RC" -eq 0 ] && grep -q 'co:lon' "$TMP/err"; then
  ok "C11: a colon-bearing path is skipped with a stderr warning, not mis-parsed"
else bad "C11: rc=$RC out=$OUT err=$(cat "$TMP/err" 2>/dev/null)"; fi

# C13 — stderr carries the summary and NOTHING else. Found the hard way: `n=$(grep -c . f || echo 0)`
# emits "0\n0" when the file is empty, because grep -c prints 0 AND exits 1, so the fallback fires
# too. That produced a `printf: invalid number` on every clean run and fed a two-line string into
# arithmetic. C10's regex still matched, so only an exact-shape assertion catches it.
run_files "$(mklist c13 "$TMP/b1.txt" "$TMP/b4.txt")"
if [ "$(cnt "$(cat "$TMP/err")")" -eq 1 ] \
   && grep -qE '^secret-scan: [0-9]+ file\(s\) listed, [0-9]+ scanned, [0-9]+ skipped, [0-9]+ finding\(s\)$' "$TMP/err"; then
  ok "C13: a clean run's stderr is exactly the one summary line, no shell noise"
else bad "C13: stderr is not a single well-formed summary line — err=$(cat "$TMP/err" 2>/dev/null)"; fi

# C12 — the ADR-0043 lesson on a different substrate. An awk without ERE interval support does not
# error on {16}; it treats the braces as literals and every rule silently matches nothing. A check
# that reports nothing is indistinguishable from a check that found nothing, so the script must
# refuse to run rather than return a clean-looking empty result.
printf '#!/bin/bash\nexit 0\n' >"$TMP/fakeawk"; chmod +x "$TMP/fakeawk"
OUT=$(SECRET_SCAN_AWK="$TMP/fakeawk" bash "$SCAN" --files "$TMP/list_a1" 2>"$TMP/err"); RC=$?
if [ "$RC" -eq 3 ] && [ "$(cnt "$OUT")" -eq 0 ] && [ -s "$TMP/err" ]; then
  ok "C12: an awk that fails the interval probe exits 3 with stderr and no stdout"
else bad "C12: expected exit 3 + empty stdout, got rc=$RC out=$OUT"; fi

# ==============================================================================================
# D. The repository itself as the false-positive corpus.
# ==============================================================================================
git -C "$REPO" ls-files 2>/dev/null | sed "s|^|$REPO/|" >"$TMP/corpus_list"
CORPUS_N=$(cnt "$(cat "$TMP/corpus_list")")

# D0 — teeth. A corpus assertion that cannot fail proves nothing, so plant a fixture in the list
# and require it to be reported. If D0 is red, D1's green means nothing.
printf '%s%s\n' "$AK" "PLANTEDKEY123456" >"$TMP/planted.txt"
cp "$TMP/corpus_list" "$TMP/corpus_plus"
printf '%s\n' "$TMP/planted.txt" >>"$TMP/corpus_plus"
run_files "$TMP/corpus_plus"
if printf '%s' "$OUT" | grep -q "planted.txt:1${TAB}aws-access-key-id\$"; then
  ok "D0: a planted key inside the corpus list IS reported (the check has teeth)"
else bad "D0: planted key not reported — the corpus check is vacuous. Got: $OUT"; fi

# D1 — the real corpus. ALWAYS-PASS FORWARD GUARD once Task 2 is correct: this is a regression pin,
# not evidence that the scanner works. That evidence is sections A, B and D0.
# Three guards against a vacuous pass, all required: a non-empty list, a run that actually
# completed, and a stderr summary showing files were really read.
run_files "$TMP/corpus_list"
D1_SUMMARY=$(cat "$TMP/err" 2>/dev/null)
NONFN=$(printf '%s' "$OUT" | grep -v "${TAB}filename-pattern\$" | grep -c .)
if [ "$CORPUS_N" -lt 1 ]; then
  bad "D1: the corpus file list is EMPTY — git ls-files returned nothing, so this proves nothing"
elif [ "$RC" -ne 0 ]; then
  bad "D1: the scan did not complete (rc=$RC) — an empty finding list here is not a clean result"
elif ! printf '%s' "$D1_SUMMARY" | grep -qE 'secret-scan: [0-9]+ file\(s\) listed, [1-9][0-9]* scanned'; then
  bad "D1: no summary showing a non-zero scanned count — err=$D1_SUMMARY"
elif [ "$NONFN" -ne 0 ]; then
  bad "D1: content rules fired on the repository's own tracked files:
$(printf '%s' "$OUT" | grep -v "${TAB}filename-pattern\$")
Fix the FILE (split the literal), never the assertion and never the rule."
else
  ok "D1: no content rule fires on $CORPUS_N tracked files (forward guard)"
fi

# D2 — informational, deliberately not asserted on: the filename-rule set grows with every document
# named after this feature, and pinning it would turn a documentation commit into a red test.
echo "---- D2: filename-pattern findings in the corpus (context only, not asserted)"
printf '%s' "$OUT" | grep "${TAB}filename-pattern\$" | sed 's|^|     |'
echo "---- D2: end"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
