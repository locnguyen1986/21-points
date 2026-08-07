#!/usr/bin/env bash
# Tests for lib/scoring.sh
set -uo pipefail
# shellcheck source=../lib/scoring.sh
. "$(dirname "$0")/../lib/scoring.sh"

# The library must not have switched errexit on behind our back — this suite
# counts failures rather than aborting on the first one.
case "$-" in
    *e*) echo "FAIL: sourcing lib/scoring.sh enabled errexit in the test shell"; exit 1 ;;
esac

pass=0; fail=0
check() {
    local desc="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
        printf '  ok   %-42s %s\n' "$desc" "$got"; pass=$((pass+1))
    else
        printf '  FAIL %-42s got=%s want=%s\n' "$desc" "$got" "$want"; fail=$((fail+1))
    fi
}

check "number cards"          15 "$(score_hand '7 8')"
check "face cards"            20 "$(score_hand 'K Q')"
check "ace high"              21 "$(score_hand 'A K')"
check "ace demoted once"      21 "$(score_hand 'A 9 A')"
check "two aces stay low"     12 "$(score_hand 'A A')"
check "three aces and an 8"   21 "$(score_hand 'A A A 8')"
check "bust returns zero"      0 "$(score_hand 'K Q 5')"
check "lowercase accepted"    21 "$(score_hand 'a k')"

# Error paths: non-zero status AND nothing on stdout, so a caller that ignores
# the status still cannot mistake the result for a score.
out=$(score_hand 'X' 2>/dev/null); rc=$?
check "unknown rank status"    1 "$rc"
check "unknown rank stdout"   "" "$out"
out=$(score_hand '' 2>/dev/null); rc=$?
check "empty hand status"      1 "$rc"
check "empty hand stdout"     "" "$out"

# Pathname expansion: a rank that is a glob must not be resolved against the
# working directory. Run from a directory containing a file named `7`.
tmp=$(mktemp -d); (cd "$tmp" && touch 7)
out=$(cd "$tmp" && score_hand '* 8' 2>/dev/null); rc=$?
check "glob rank rejected"     1 "$rc"
rm -rf "$tmp"

is_blackjack 'A K' && check "blackjack detected" yes yes || check "blackjack detected" yes no
is_blackjack 'A 9 A' && check "three cards not blackjack" no yes || check "three cards not blackjack" no no

echo
echo "passed ${pass}, failed ${fail}"
[ "$fail" -eq 0 ]
