#!/bin/bash
# dependency-scan v1.0 — new-dependency reporter (issue #100; ADR-0046).
#
# CONTRACT (ADR-0046 §D1/§D2). This is a REPORTER: it never decides policy.
#   stdin   a unified diff
#   stdout  NEWDEP<TAB><package><TAB><manifest>   (empty means no findings)
#   stderr  one summary line per run, always; plus an explicit `inert` line when the diff
#           contains no recognised dependency manifest
#   exit 0  the scan ran; findings may or may not be on stdout
#   exit 2  invalid invocation (unknown flag, missing or unreadable argument)
# Exit 0 WITH findings is the contract and is pinned by a test. It is what lets issue #108 run
# this identical script fail-closed in CI while the commit path stays advisory for NEWDEP.
#
# WHY `added MINUS removed`, NEVER `added` (ADR-0046 §D8).
# A lockfile reorder produces `+` lines for packages that were already installed, and a version
# bump produces a `+` and a `-` for the same package. Reporting `added` would fire on both, and a
# gate that cries wolf on every no-op `npm install` gets ignored, which is worse than no gate. So
# package names are collected from added lines AND from removed lines, per manifest type, and only
# the set difference is reported. One decision, three of the SPEC's edge cases.
#
# WHY NO ALLOW LIST MEANS "REPORT EVERYTHING".
# The conservative direction for a reporter, and the reason this script never has to read an ADR
# to learn what was authorised. `--allow <file>` (one package name per line) or, absent that,
# `.claude/allowed-deps.txt` in the CURRENT DIRECTORY — resolved from the caller's cwd, not from
# this script's location, because the allow list belongs to the project being scanned.
#
# NO START-UP PROBE, DELIBERATELY, unlike the sibling secret-scan.sh. That probe exists because
# every rule there uses ERE interval syntax ({16}), which a pre-2019 awk treats as literal braces,
# silently matching nothing. Not one pattern below uses an interval, so there is no capability to
# probe. Anyone adding a `{n}` quantifier here must add the probe with it — otherwise the rule is
# inert on an old awk and this script reports a clean diff.
#
# No git, no jq, no hook payload, no external tool beyond POSIX: issue #108 needs this runnable
# from a plain shell in a target project's CI, with no agent present.
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="dependency-scan"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: dependency-scan.sh --diff [--allow <file>]     unified diff on stdin

Output (stdout): NEWDEP<TAB><package><TAB><manifest>, one line per newly added package.
Allow list: --allow <file>, else ./.claude/allowed-deps.txt if it exists, else empty
            (one name per line; "#" comments and blank lines ignored; exact, case-sensitive).
Exit: 0 scan completed (with or without findings) | 2 bad invocation.
EOF
}

MODE=""; ALLOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --diff)
      [ -n "$MODE" ] && { usage "--diff given twice"; exit 2; }
      MODE="diff"; shift ;;
    --allow)
      [ $# -ge 2 ] || { usage "--allow needs a file argument"; exit 2; }
      ALLOW="$2"
      [ -r "$ALLOW" ] || { usage "cannot read allow file: $ALLOW"; exit 2; }
      shift 2 ;;
    *) usage "unknown argument: $1"; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { usage "--diff is required"; exit 2; }

# Default allow path, resolved from the caller's working directory (never from $0's directory).
if [ -z "$ALLOW" ] && [ -r ".claude/allowed-deps.txt" ]; then
  ALLOW=".claude/allowed-deps.txt"
fi

TMPD=$(mktemp -d) || { printf '%s: cannot create a temp directory\n' "$SELF" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

cat >"$TMPD/diff"

# --- the extraction table (ADR-0046 §D8). Adding an ecosystem is one mtype() row plus one ex_*()
# function; the main loop never changes.
cat >"$TMPD/deps.awk" <<'AWKEOF'
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }

# The tail after the LAST occurrence of sep; the whole string when sep never occurs.
function after_last(s, sep,   i, out) {
  out = s; i = index(out, sep)
  while (i > 0) { out = substr(out, i + length(sep)); i = index(out, sep) }
  return out
}

# The text before the last "@", preserving a leading "@" for a scoped package.
function before_last_at(s,   lead, k, p) {
  lead = ""
  if (substr(s, 1, 1) == "@") { lead = "@"; s = substr(s, 2) }
  p = 0
  for (k = length(s); k >= 1; k--) if (substr(s, k, 1) == "@") { p = k; break }
  if (p < 2) return ""
  return lead substr(s, 1, p - 1)
}

function mtype(b) {
  if (b == "package.json")                              return "npm-manifest"
  if (b == "package-lock.json" || b == "npm-shrinkwrap.json") return "npm-lock"
  if (b == "yarn.lock")                                 return "yarn"
  if (b == "pnpm-lock.yaml")                            return "pnpm"
  if (b ~ /^requirements.*\.txt$/)                      return "pip"
  if (b == "pyproject.toml")                            return "pyproject"
  if (b == "Pipfile" || b == "Pipfile.lock")            return "pipfile"
  if (b == "poetry.lock")                               return "poetry"
  if (b == "Package.swift")                             return "swiftpm"
  if (b == "Package.resolved")                          return "swiftpm-lock"
  if (b == "Podfile")                                   return "cocoapods"
  if (b == "Podfile.lock")                              return "cocoapods-lock"
  return ""
}

# A manifest key that can never be a package name. Without this, a `"version": "1.0.1"` bump in a
# package.json reports a package called `version`, and `"node": ">=18"` inside `engines` reports
# one called `node` — both are the shape `"<key>": "<version-ish>"` and no amount of value
# matching separates them. The list is deliberately short: an unknown key is treated as a package,
# which is the conservative direction for a reporter.
BEGIN {
  split("name version description main module browser types typings license homepage author " \
        "repository bugs keywords packageManager type private url requires-python readme " \
        "python node npm", _nd, " ")
  for (_i in _nd) NOTDEP[_nd[_i]] = 1
}

# package.json — "<name>": "<version-ish>". The value must look like a version range or a
# supported protocol. Requiring the COLON on npm:/workspace:/file:/link: matters: without it
# a `"test": "npm test"` line in the `scripts` block reads as a package named `test`.
function ex_npm_manifest(s,   seg, name, rest, val) {
  if (!match(s, /^[ \t]*"[^"]+"[ \t]*:[ \t]*"[^"]*"/)) return ""
  seg = substr(s, RSTART, RLENGTH)
  if (!match(seg, /"[^"]+"/)) return ""
  name = substr(seg, RSTART + 1, RLENGTH - 2)
  rest = substr(seg, RSTART + RLENGTH)
  if (!match(rest, /"[^"]*"/)) return ""
  val = substr(rest, RSTART + 1, RLENGTH - 2)
  if (name in NOTDEP) return ""
  if (val ~ /^[~^><=*0-9]/) return name
  if (val ~ /^(npm:|workspace:|file:|link:|portal:|git\+|git:|github:|https?:)/) return name
  return ""
}

# package-lock.json / npm-shrinkwrap.json — "node_modules/<name>": {
# after_last() is what makes a nested dependency ("node_modules/a/node_modules/b") resolve to b.
function ex_npm_lock(s,   key) {
  if (!match(s, /"node_modules\/[^"]+"[ \t]*:[ \t]*\{/)) return ""
  key = substr(s, RSTART, RLENGTH)
  if (!match(key, /"[^"]+"/)) return ""
  key = substr(key, RSTART + 1, RLENGTH - 2)
  return after_last(key, "node_modules/")
}

# yarn.lock — a `<name>@<range>:` header line (possibly several ranges, comma-separated).
function ex_yarn(s,   t) {
  t = trim(s)
  if (t !~ /:$/) return ""
  sub(/:$/, "", t)
  gsub(/"/, "", t)
  if (index(t, ",") > 0) t = trim(substr(t, 1, index(t, ",") - 1))
  return before_last_at(t)
}

# pnpm-lock.yaml — /<name>/<version>: (v6 and earlier) or <name>@<version>: (v9).
function ex_pnpm(s,   t, k, p) {
  t = trim(s)
  if (t !~ /:$/) return ""
  sub(/:$/, "", t)
  gsub(/'/, "", t); gsub(/"/, "", t)
  if (substr(t, 1, 1) == "/") {
    t = substr(t, 2)
    p = 0
    for (k = length(t); k >= 1; k--) if (substr(t, k, 1) == "/") { p = k; break }
    if (p > 1) return substr(t, 1, p - 1)
    return ""
  }
  return before_last_at(t)
}

# requirements*.txt — the name ends at the first of = < > ~ ! [ space ; #
function ex_pip(s,   t) {
  t = trim(s)
  if (t == "") return ""
  if (substr(t, 1, 1) == "#" || substr(t, 1, 1) == "-") return ""
  if (match(t, /[=<>~![ \t;#]/)) t = substr(t, 1, RSTART - 1)
  t = trim(t)
  if (t !~ /^[A-Za-z0-9._-]+$/) return ""
  return t
}

# pyproject.toml — a quoted PEP 508 array element, or a bare `<name> = "<version>"` key.
function ex_pyproject(s,   t, name) {
  t = trim(s)
  if (substr(t, 1, 1) == "\"") {
    if (!match(t, /^"[A-Za-z0-9._-]+/)) return ""
    name = substr(t, RSTART + 1, RLENGTH - 1)
    return (name in NOTDEP) ? "" : name
  }
  if (!match(t, /^[A-Za-z0-9._-]+[ \t]*=[ \t]*["{]/)) return ""
  match(t, /^[A-Za-z0-9._-]+/)
  name = substr(t, RSTART, RLENGTH)
  return (name in NOTDEP) ? "" : name
}

# Pipfile — <name> = "<spec>" or <name> = {…};  Pipfile.lock — "<name>": {
function ex_pipfile(s,   t, name) {
  t = trim(s)
  if (substr(t, 1, 1) == "\"") {
    if (!match(t, /^"[A-Za-z0-9._-]+"[ \t]*:[ \t]*\{/)) return ""
    match(t, /^"[A-Za-z0-9._-]+"/)
    name = substr(t, RSTART + 1, RLENGTH - 2)
    return (name in NOTDEP) ? "" : name
  }
  if (!match(t, /^[A-Za-z0-9._-]+[ \t]*=[ \t]*["{*]/)) return ""
  match(t, /^[A-Za-z0-9._-]+/)
  name = substr(t, RSTART, RLENGTH)
  return (name in NOTDEP) ? "" : name
}

# poetry.lock — the `name = "<name>"` line of a [[package]] block.
function ex_poetry(s,   t) {
  t = trim(s)
  if (!match(t, /^name[ \t]*=[ \t]*"[^"]+"/)) return ""
  if (!match(t, /"[^"]+"/)) return ""
  return substr(t, RSTART + 1, RLENGTH - 2)
}

# Package.swift — the last path component of a .package(url: "…") URL, ".git" stripped.
function ex_swiftpm(s,   u) {
  if (s !~ /\.package\(/) return ""
  if (!match(s, /url:[ \t]*"[^"]+"/)) return ""
  u = substr(s, RSTART, RLENGTH)
  if (!match(u, /"[^"]+"/)) return ""
  u = substr(u, RSTART + 1, RLENGTH - 2)
  sub(/\/+$/, "", u)
  u = after_last(u, "/")
  sub(/\.git$/, "", u)
  return u
}

# Package.resolved — "identity" : "<name>"
function ex_swiftpm_lock(s,   t) {
  if (!match(s, /"identity"[ \t]*:[ \t]*"[^"]+"/)) return ""
  t = substr(s, RSTART, RLENGTH)
  sub(/^"identity"[ \t]*:[ \t]*/, "", t)
  return substr(t, 2, length(t) - 2)
}

# Podfile — pod 'Name', '~> 1.0'
function ex_cocoapods(s,   t) {
  if (!match(s, /(^|[ \t])pod[ \t]+["'][^"']+["']/)) return ""
  t = substr(s, RSTART, RLENGTH)
  if (!match(t, /["'][^"']+["']/)) return ""
  return substr(t, RSTART + 1, RLENGTH - 2)
}

# Podfile.lock — "  - Alamofire (5.6.4)"
function ex_cocoapods_lock(s,   t, p) {
  t = trim(s)
  if (!match(t, /^- [A-Za-z0-9._\/+-]+ \(/)) return ""
  t = substr(t, 3)
  p = index(t, " (")
  if (p < 2) return ""
  return substr(t, 1, p - 1)
}

function extract(ty, s) {
  if (ty == "npm-manifest")    return ex_npm_manifest(s)
  if (ty == "npm-lock")        return ex_npm_lock(s)
  if (ty == "yarn")            return ex_yarn(s)
  if (ty == "pnpm")            return ex_pnpm(s)
  if (ty == "pip")             return ex_pip(s)
  if (ty == "pyproject")       return ex_pyproject(s)
  if (ty == "pipfile")         return ex_pipfile(s)
  if (ty == "poetry")          return ex_poetry(s)
  if (ty == "swiftpm")         return ex_swiftpm(s)
  if (ty == "swiftpm-lock")    return ex_swiftpm_lock(s)
  if (ty == "cocoapods")       return ex_cocoapods(s)
  if (ty == "cocoapods-lock")  return ex_cocoapods_lock(s)
  return ""
}

/^diff --git /  { apath = ""; type = ""; base = ""; next }
/^--- /         { p = $2; sub(/^a\//, "", p); apath = p; next }
/^\+\+\+ /      {
  p = $2; sub(/^b\//, "", p)
  # A deleted file has "+++ /dev/null"; its packages are still needed on the removed side.
  cur = (p == "/dev/null") ? apath : p
  type = ""; base = ""
  if (cur != "" && cur != "/dev/null") {
    base = after_last(cur, "/")
    type = mtype(base)
    if (type != "" && !(cur in seenman)) { seenman[cur] = 1; nman++ }
  }
  next
}
/^@@ /          { next }
{
  if (type == "") next
  c = substr($0, 1, 1)
  if (c != "+" && c != "-") next
  name = extract(type, substr($0, 2))
  if (name == "") next
  k = type SUBSEP name
  if (c == "+") { if (!(k in added)) { added[k] = 1; amf[k] = base; nadd++ } }
  else          { removed[k] = 1 }
}
END {
  if (allowfile != "") {
    while ((getline l < allowfile) > 0) {
      sub(/#.*/, "", l); l = trim(l)
      if (l != "") allow[l] = 1
    }
    close(allowfile)
  }
  nnew = 0
  for (k in added) {
    if (k in removed) continue
    split(k, parts, SUBSEP)
    if (parts[2] in allow) continue
    printf "NEWDEP\t%s\t%s\n", parts[2], amf[k]
    nnew++
  }
  # Counts go to a file, not to /dev/stderr: stdout is piped into sort, and a summary written
  # from inside awk would have to compete with it.
  print (nman + 0), (nadd + 0), nnew > statsfile
}
AWKEOF

awk -v allowfile="$ALLOW" -v statsfile="$TMPD/stats" -f "$TMPD/deps.awk" \
  <"$TMPD/diff" >"$TMPD/raw" 2>/dev/null

# Sorted, so finding order is deterministic and testable: awk's `for (k in arr)` order is
# unspecified and does vary. LC_ALL=C keeps the order locale-independent too.
LC_ALL=C sort -u "$TMPD/raw" >"$TMPD/found"
[ -s "$TMPD/found" ] && cat "$TMPD/found"

N_MAN=0; N_ADD=0; N_NEW=0
if [ -s "$TMPD/stats" ]; then
  read -r N_MAN N_ADD N_NEW <"$TMPD/stats"
fi

# The summary always goes to stderr, on every run (ADR-0046 §D5): stdout stays a clean
# machine-readable channel for #108's `wc -l`, and a CI log still shows the script ran.
if [ "$N_MAN" -eq 0 ]; then
  printf '%s: no recognised dependency manifest in the diff — inert\n' "$SELF" >&2
fi
printf '%s: %d manifest(s) in diff, %d added, %d new package(s)\n' \
  "$SELF" "$N_MAN" "$N_ADD" "$N_NEW" >&2
exit 0
