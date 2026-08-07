#!/usr/bin/env bash
# scoring.sh — score a hand of 21 (blackjack).
#
# A hand is a space-separated list of card ranks: 2-10, J, Q, K, A.
# Face cards are worth 10. An ace is worth 11 unless that would bust the
# hand, in which case it drops to 1 — and a hand may hold several aces, so
# the demotion is applied one ace at a time rather than all at once.

set -euo pipefail

# card_value echoes the base value of a single rank, treating an ace as 11.
card_value() {
    case "${1^^}" in
        A)          echo 11 ;;
        K|Q|J|10)   echo 10 ;;
        2|3|4|5|6|7|8|9) echo "$1" ;;
        *)          echo "scoring: unknown rank '$1'" >&2; return 1 ;;
    esac
}

# score_hand echoes the best total for a hand, or 0 if the hand busts.
score_hand() {
    local total=0 aces=0 card value
    for card in $1; do
        value=$(card_value "$card") || return 1
        total=$((total + value))
        [ "${card^^}" = A ] && aces=$((aces + 1))
    done

    # Demote one ace at a time: A A 9 is 21, not 12 or 31.
    while [ "$total" -gt 21 ] && [ "$aces" -gt 0 ]; do
        total=$((total - 10))
        aces=$((aces - 1))
    done

    if [ "$total" -gt 21 ]; then
        echo 0
    else
        echo "$total"
    fi
}

is_blackjack() {
    local hand="$1"
    local count
    count=$(echo "$hand" | wc -w)
    [ "$count" -eq 2 ] && [ "$(score_hand "$hand")" -eq 21 ]
}
