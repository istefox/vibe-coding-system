# instructions-loaded-canon.sh — shared path canonicalization, sourced by
# instructions-loaded-log.sh and instructions-loaded-verify.sh. Not executable on its own.
#
# Extracted rather than duplicated (repo rule 6): the writer and the verifier answer ONE
# question — "what path is this, really?" — and a divergence between their two answers would be
# a query that can never match a record it should, which is the exact failure this feature exists
# to prevent. sync-manual-steps.test.sh's build_home_skills fixture (see its own history) is what
# happens when the same JSON blob is copied instead of shared: it silently drifted two hooks
# behind for two features before anyone noticed.
#
# LIMIT, stated: `pwd -P` resolves symlinks in the DIRECTORY chain only. A symlinked LEAF is not
# resolved — macOS `realpath` is not guaranteed present and bash 3.2 has no built-in substitute.
# The direction of failure is a false negative (two spellings of one file compare unequal), which
# is the safe direction for this feature: it never reports a load that did not happen.
#
# Bash 3.2 clean: no associative arrays, no mapfile, no process substitution.

_il_canon() {
  _p="$1"
  [ -n "$_p" ] || return 1
  case "$_p" in "~/"*) _p="$HOME/${_p#\~/}" ;; esac
  case "$_p" in */) _p="${_p%/}" ;; esac
  _d=$(dirname "$_p")
  _b=$(basename "$_p")
  _rd=$(cd "$_d" 2>/dev/null && pwd -P) || return 1
  case "$_rd" in
    /) printf '/%s\n' "$_b" ;;
    *) printf '%s/%s\n' "$_rd" "$_b" ;;
  esac
}

# Portable stat/hash helpers: GNU form (`-c`) tried first, BSD form (`-f`) as fallback. This order
# is required, not cosmetic: GNU `stat -f` means "report on the FILESYSTEM", not the file, and it
# EXITS 0 while printing an unrelated multi-line block instead of a number — the `||` fallback
# never fires, and a size/mtime consumer downstream gets garbage instead of an integer. BSD's
# `stat -c` fails cleanly (exit 1, "illegal option") on macOS, so trying `-c` first is safe on both
# platforms; trying `-f` first is silently wrong on Linux (confirmed in CI, PR #515, 2026-08-28:
# `_fsize` returned a `df`-style block, and every assertion consuming it either mis-parsed as
# `0` or fed the block into `date` as a bogus epoch).
_fmtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf ''; }
_fsize()  { stat -c %s "$1" 2>/dev/null || stat -f %z "$1" 2>/dev/null || printf ''; }
_fsha()   { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }

_iso_of_epoch() {
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

_epoch_of_iso() {
  # Accepts YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ. BSD `date -j`, GNU `date -d` fallback.
  case "$1" in
    ????-??-??T??:??:??Z)
      date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null ;;
    ????-??-??)
      date -u -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null ;;
    *) printf '' ;;
  esac
}
