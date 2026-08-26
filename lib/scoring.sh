#!/usr/bin/env bash
# scoring.sh — score a hand of 21 (blackjack).
#
# A hand is a space-separated list of card ranks: 2-10, J, Q, K, A.
# Face cards are worth 10. An ace is worth 11 unless that would bust the
# hand, in which case it drops to 1 — and a hand may hold several aces, so
# the demotion is applied one ace at a time rather than all at once.
#
# This file is a LIBRARY: it is meant to be sourced, so it deliberately does
# not call `set -e`. Doing so at the top level silently turns errexit on in
# whatever shell sources it, which is not the library's decision to make — the
# test harness sets `set -uo pipefail` on purpose and had errexit switched on
# behind its back. Portability: no bash-4 syntax, so this works under the
# bash 3.2 that ships with macOS.

# upper echoes its argument uppercased. `tr` rather than ${x^^}, which is
# bash 4+ and dies with "bad substitution" on stock macOS /bin/bash.
_scoring_upper() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

# card_value echoes the base value of a single rank, treating an ace as 11.
card_value() {
    case "$(_scoring_upper "$1")" in
        A)          echo 11 ;;
        K|Q|J|10)   echo 10 ;;
        2|3|4|5|6|7|8|9) echo "$1" ;;
        *)          echo "scoring: unknown rank '$1'" >&2; return 1 ;;
    esac
}

# score_hand echoes the best total for a hand, or 0 if the hand busts.
# An empty hand is rejected rather than scored: 0 already means "bust", and
# returning it for no cards makes the two indistinguishable to a caller.
score_hand() {
    local hand="$1" total=0 aces=0 card value
    local -a cards

    # read -ra, not `for card in $1`: an unquoted expansion is subject to
    # PATHNAME EXPANSION, so a rank that happens to be a glob was resolved
    # against the working directory. In a directory containing a file named
    # `7`, `score_hand '* 8'` scored a hand nobody dealt instead of reporting
    # an unknown rank.
    read -ra cards <<< "$hand"
    if [ "${#cards[@]}" -eq 0 ]; then
        echo "scoring: empty hand" >&2
        return 1
    fi

    for card in "${cards[@]}"; do
        value=$(card_value "$card") || return 1
        total=$((total + value))
        [ "$(_scoring_upper "$card")" = A ] && aces=$((aces + 1))
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

# is_blackjack succeeds for a two-card hand worth 21.
#
# The score is captured BEFORE it is compared. Inlining the substitution meant
# an invalid hand produced `[ "" -eq 21 ]`, which bash rejects with "integer
# expression expected" and status 2 — leaking a diagnostic on stderr and
# breaking the status-1 contract score_hand documents for its own error paths.
is_blackjack() {
    local hand="$1" score
    local -a cards
    read -ra cards <<< "$hand"
    score=$(score_hand "$hand") || return 1
    [ "${#cards[@]}" -eq 2 ] && [ "$score" -eq 21 ]
}

# dealer_action echoes the house action for the dealer's hand: "hit" while the
# hand totals 16 or less, "stand" at 17 or more (the dealer stands on all 17s).
dealer_action() {
    local hand="$1" score
    score=$(score_hand "$hand") || return 1
    if [ "$score" -le 16 ]; then
        echo hit
    else
        echo stand
    fi
}

# dealer_should_hit succeeds when the dealer must draw another card.
# House rule: hit on 16 or less, and hit on a soft 17 (a 17 using an ace as 11).
dealer_should_hit() {
    local hand=$1
    local total=$(score_hand $hand)

    if [ $total -le 16 ]; then
        return 0
    fi

    if [ "$total" = 17 ] && [[ $hand == A* ]]; then
        return 0
    fi

    return 1
}
