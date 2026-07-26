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

# ==============================================================================================
# E. dependency-scan.sh — a package present in the diff that was not there before (ADR-0046 §D8).
# Every fixture is a unified diff built here and piped in on stdin. The script never invokes git:
# the caller supplies the diff, which is what lets issue #108 run this identical script in a
# target project's CI with no agent present.
#
# The load-bearing rule is ADDED MINUS REMOVED, not ADDED. A lockfile reorder emits `+` lines for
# packages that were already installed and a version bump emits a `+` and a `-` for the same
# package; both must be silent, or the commit gate cries wolf on every `npm install` that changed
# nothing. E3/E4/E5 are that rule from three directions.
# ==============================================================================================
DEP="$SCRIPTS/dependency-scan.sh"
DOUT=""; DRC=0
# run_dep <diff-file> [extra args...]
run_dep() { _df="$1"; shift; DOUT=$(bash "$DEP" --diff "$@" <"$_df" 2>"$TMP/derr"); DRC=$?; }
hasdep() { printf '%s' "$DOUT" | grep -q "^NEWDEP${TAB}$1${TAB}$2\$"; }
# dneg <label> <diff-file> [extra args...] — expects zero findings AND a completed run.
# The rc check is not decoration: without it every negative assertion in this section would pass
# while the script is still missing, and the RED half of Task 4 would prove nothing.
dneg() {
  _lbl="$1"; _df="$2"; shift 2
  run_dep "$_df" "$@"
  if [ "$(cnt "$DOUT")" -eq 0 ] && [ "$DRC" -eq 0 ]; then ok "$_lbl"
  else bad "$_lbl — expected no finding, rc=$DRC, got: $DOUT"; fi
}

cat >"$TMP/e1.diff" <<'EOF'
diff --git a/package.json b/package.json
--- a/package.json
+++ b/package.json
@@ -5,6 +5,7 @@
   "dependencies": {
     "express": "^4.18.0",
+    "left-pad": "^1.3.0"
   }
EOF
run_dep "$TMP/e1.diff"
hasdep left-pad package.json && ok "E1: npm manifest — an added dependency is reported" \
  || bad "E1: expected NEWDEP left-pad package.json — got: $DOUT"

# E11a rides on E1's run: a reporter exits 0 even when it found something (ADR-0046 §D2, PF6).
[ "$DRC" -eq 0 ] && ok "E11a: exit 0 on a run that produced findings (reporter contract)" \
  || bad "E11a: exit $DRC on a run with findings — must be 0"

cat >"$TMP/e2.diff" <<'EOF'
diff --git a/package-lock.json b/package-lock.json
--- a/package-lock.json
+++ b/package-lock.json
@@ -40,6 +40,10 @@
     "node_modules/express": {
       "version": "4.18.0"
     },
+    "node_modules/left-pad": {
+      "version": "1.3.0",
+      "resolved": "https://registry.npmjs.org/left-pad/-/left-pad-1.3.0.tgz"
+    },
EOF
run_dep "$TMP/e2.diff"
if [ "$(cnt "$DOUT")" -eq 1 ] && hasdep left-pad package-lock.json; then
  ok "E2: npm lockfile — one NEWDEP for the added node_modules entry"
else bad "E2: expected exactly one NEWDEP naming left-pad — got: $DOUT"; fi

# E3 — the reorder case. Same package set on both sides, different order: added minus removed is
# empty. `added` alone would report both packages here.
cat >"$TMP/e3.diff" <<'EOF'
diff --git a/package-lock.json b/package-lock.json
--- a/package-lock.json
+++ b/package-lock.json
@@ -40,8 +40,8 @@
-    "node_modules/alpha": {
-    "node_modules/beta": {
+    "node_modules/beta": {
+    "node_modules/alpha": {
EOF
dneg "E3: a lockfile reorder with no new package produces no output" "$TMP/e3.diff"

cat >"$TMP/e4.diff" <<'EOF'
diff --git a/package.json b/package.json
--- a/package.json
+++ b/package.json
@@ -5,7 +5,7 @@
   "dependencies": {
-    "left-pad": "^1.3.0"
+    "left-pad": "^1.3.1"
   }
EOF
dneg "E4: a version bump is not a new package" "$TMP/e4.diff"

cat >"$TMP/e5.diff" <<'EOF'
diff --git a/package.json b/package.json
--- a/package.json
+++ b/package.json
@@ -5,7 +5,6 @@
   "dependencies": {
-    "left-pad": "^1.3.0"
   }
EOF
dneg "E5: a removal with no matching addition produces no output" "$TMP/e5.diff"

cat >"$TMP/e6.diff" <<'EOF'
diff --git a/requirements.txt b/requirements.txt
--- a/requirements.txt
+++ b/requirements.txt
@@ -1,2 +1,3 @@
 fastapi==0.110.0
+requests==2.31.0
 uvicorn==0.29.0
EOF
run_dep "$TMP/e6.diff"
hasdep requests requirements.txt && ok "E6: Python — an added pinned requirement is reported" \
  || bad "E6: expected NEWDEP requests requirements.txt — got: $DOUT"

cat >"$TMP/e7.diff" <<'EOF'
diff --git a/Package.resolved b/Package.resolved
--- a/Package.resolved
+++ b/Package.resolved
@@ -10,6 +10,11 @@
     {
+      "identity" : "swift-algorithms",
+      "kind" : "remoteSourceControl",
+      "location" : "https://github.com/apple/swift-algorithms.git"
+    },
+    {
       "identity" : "swift-collections",
EOF
run_dep "$TMP/e7.diff"
hasdep swift-algorithms Package.resolved && ok "E7: Swift — an added Package.resolved identity is reported" \
  || bad "E7: expected NEWDEP swift-algorithms Package.resolved — got: $DOUT"

# E8 — the allow file. Comment and blank lines are ignored, so a human can annotate it; without
# that, the first `# authorised by ADR-xxxx` line would silently become a package name.
printf '# authorised by the plan\n\nleft-pad\n' >"$TMP/allow_e8"
dneg "E8: --allow suppresses a listed package; comments and blanks are ignored" \
  "$TMP/e1.diff" --allow "$TMP/allow_e8"

# E9 — the default allow path, resolved from the CURRENT DIRECTORY, not from the script's location.
mkdir -p "$TMP/e9/.claude"
printf 'left-pad\n' >"$TMP/e9/.claude/allowed-deps.txt"
DOUT=$(cd "$TMP/e9" && bash "$DEP" --diff <"$TMP/e1.diff" 2>"$TMP/derr"); DRC=$?
if [ "$(cnt "$DOUT")" -eq 0 ] && [ "$DRC" -eq 0 ]; then
  ok "E9: .claude/allowed-deps.txt in the working directory is read when --allow is absent"
else bad "E9: default allow path not honoured — rc=$DRC, got: $DOUT"; fi

# E10 — the SPEC's inert case. Stated on stderr rather than inferred from silence, which is the
# same ADR-0043 lesson that put the awk probe in secret-scan.sh: "reported nothing" and "found
# nothing" must not look alike.
cat >"$TMP/e10.diff" <<'EOF'
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -1,2 +1,3 @@
 # Project
+A new line of prose.
EOF
run_dep "$TMP/e10.diff"
if [ "$(cnt "$DOUT")" -eq 0 ] && [ "$DRC" -eq 0 ] && grep -q 'inert' "$TMP/derr"; then
  ok "E10: a diff with no recognised manifest is inert, and says so on stderr"
else bad "E10: rc=$DRC out=$DOUT err=$(cat "$TMP/derr" 2>/dev/null)"; fi

DOUT=$(bash "$DEP" --nonsense <"$TMP/e1.diff" 2>"$TMP/derr"); DRC=$?
if [ "$DRC" -eq 2 ] && [ -s "$TMP/derr" ]; then
  ok "E11b: an unknown flag exits 2 with usage on stderr"
else bad "E11b: expected exit 2 + stderr, got rc=$DRC err=$(cat "$TMP/derr" 2>/dev/null)"; fi

# E12 — deterministic order. awk's `for (k in arr)` iteration order is unspecified, so without an
# explicit sort the finding order varies between runs and any downstream assertion is flaky.
cat >"$TMP/e12.diff" <<'EOF'
diff --git a/package.json b/package.json
--- a/package.json
+++ b/package.json
@@ -5,6 +5,9 @@
   "dependencies": {
+    "zeta": "^1.0.0",
+    "alpha": "^2.0.0",
+    "middle-pkg": "^3.0.0",
     "express": "^4.18.0"
   }
EOF
E12_WANT=$(printf 'NEWDEP\talpha\tpackage.json\nNEWDEP\tmiddle-pkg\tpackage.json\nNEWDEP\tzeta\tpackage.json')
run_dep "$TMP/e12.diff"; E12_A="$DOUT"
run_dep "$TMP/e12.diff"; E12_B="$DOUT"
if [ "$E12_A" = "$E12_WANT" ] && [ "$E12_B" = "$E12_WANT" ]; then
  ok "E12: output is sorted and identical across two runs of the same input"
else bad "E12: expected the sorted triple, got run1: $E12_A"; fi

# ==============================================================================================
# F. commit/SKILL.md Step 1 wiring (ADR-0046 §D9).
#
# THESE ARE THE FIRST ASSERTIONS THIS FILE HAS EVER HAD. Nothing tested commit/SKILL.md before
# issue #100, which is exactly why the wiring gets pinned here: three skills invoke it
# (`concept-to-code` Step 7, `project-init`, `autopilot-build --autopilot`), so a silent edit to
# its Step 1 changes behaviour on an unattended path with nothing to catch it.
#
# Static prose anchors, deliberately. The file is instructions for a model, not runnable code, so
# there is nothing to execute; the assertions pin the phrases a reader must not be able to delete
# by accident. They will need updating if the prose is reworded — that cost is the point.
# ==============================================================================================
COMMITMD="$STAGING/plugin/skills/commit/SKILL.md"
STEP1="$TMP/commit_step1.txt"
awk '/^### Step 1 —/{f=1} /^### Step 2 —/{f=0} f' "$COMMITMD" >"$STEP1"

if [ -s "$STEP1" ]; then
  ok "F0: Step 1 of commit/SKILL.md is extractable (the anchor the F section reads)"
else
  bad "F0: could not extract Step 1 from $COMMITMD — every F assertion below is meaningless"
fi

if grep -q 'secret-scan\.sh' "$STEP1" && grep -q 'dependency-scan\.sh' "$STEP1"; then
  ok "F1: Step 1 calls both reporters by name"
else bad "F1: Step 1 does not reference secret-scan.sh and dependency-scan.sh"; fi

# F2 — the resolution order AND the fallback. The fallback is the non-regression floor: on a
# machine that has not run sync-to-claude.sh the scripts do not exist, and Step 1 must then behave
# exactly as it did before this feature rather than skipping the filename check as well.
if grep -q 'CLAUDE_PLUGIN_ROOT' "$STEP1" \
   && grep -q '\$HOME/\.claude/hooks' "$STEP1" \
   && grep -qi 'neither resolves' "$STEP1" \
   && grep -qi 'filename check' "$STEP1"; then
  ok "F2: Step 1 resolves CLAUDE_PLUGIN_ROOT → \$HOME/.claude/hooks and documents the fallback"
else bad "F2: missing resolution order or the neither-resolves fallback in Step 1"; fi

# F3 — the unattended policy. `autopilot-build` skips Step 4, so the Step 4 gate cannot be what
# stops a secret there; Step 1 has to say so itself, in the direction that fails safe.
if grep -qi 'autopilot' "$STEP1" \
   && grep -qE 'SECRET.*abort|abort.*SECRET' "$STEP1" \
   && grep -qE 'NEWDEP.*(proceed|never)' "$STEP1"; then
  ok "F3: Step 1 states the autopilot policy — SECRET aborts, NEWDEP does not"
else bad "F3: Step 1 does not state the unattended SECRET-aborts / NEWDEP-proceeds policy"; fi

# F4 — ANTI-WEAKENING PIN, AND AN ALWAYS-PASS FORWARD GUARD. It passes before and after Task 6,
# so it is never evidence that the wiring works; it is a regression pin. ADR-0046 forbids this
# feature from narrowing any existing guardrail, and the cheapest way to "fix" a noisy filename
# rule is to quietly trim one of these four patterns.
G1='- **NEVER commit `.env`, secrets, API keys** — if `git status` shows suspicious files (`.env`,'
G2='  `*secret*`, `*credential*`, `*.pem`), stop and warn the user before proceeding.'
F4OK=1
# -e is required, not stylistic: the bullet begins with "- ", and `grep -qF "$G1"` reads that as
# an option and fails on every file. Caught because F4 is supposed to be green on arrival.
grep -qF -e "$G1" "$COMMITMD" || F4OK=0
grep -qF -e "$G2" "$COMMITMD" || F4OK=0
grep -qF '`.env`' "$STEP1"        || F4OK=0
grep -qF '`*secret*`' "$STEP1"    || F4OK=0
grep -qF '`*credential*`' "$STEP1" || F4OK=0
grep -qF '`*.pem`' "$STEP1"       || F4OK=0
if [ "$F4OK" -eq 1 ]; then
  ok "F4: the invariant guardrail bullet and Step 1's four filename patterns are intact (forward guard)"
else bad "F4: a guardrail bullet or a Step 1 filename pattern was weakened — restore it, do not edit this assertion"; fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
