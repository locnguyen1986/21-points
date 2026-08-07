#!/usr/bin/env bash
# Tests for lib/scoring.sh
set -uo pipefail
# shellcheck source=../lib/scoring.sh
. "$(dirname "$0")/../lib/scoring.sh"

pass=0; fail=0
check() {
    local desc="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
        printf '  ok   %-40s %s\n' "$desc" "$got"; pass=$((pass+1))
    else
        printf '  FAIL %-40s got=%s want=%s\n' "$desc" "$got" "$want"; fail=$((fail+1))
    fi
}

check "number cards"          15 "$(score_hand '7 8')"
check "face cards"            20 "$(score_hand 'K Q')"
check "ace high"              21 "$(score_hand 'A K')"
check "ace demoted once"      21 "$(score_hand 'A 9 A')"
check "two aces stay low"     12 "$(score_hand 'A A')"
check "bust returns zero"      0 "$(score_hand 'K Q 5')"
check "lowercase accepted"    21 "$(score_hand 'a k')"

is_blackjack 'A K' && check "blackjack detected" yes yes || check "blackjack detected" yes no
is_blackjack 'A 9 A' && check "three cards not blackjack" no yes || check "three cards not blackjack" no no

echo
echo "passed ${pass}, failed ${fail}"
[ "$fail" -eq 0 ]
