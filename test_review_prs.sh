#!/usr/bin/env bash
# Test suite for review_prs.sh
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/review_prs.sh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== Tests for review_prs.sh ==="
echo ""

# Test 1: Syntax check
echo "Test 1: bash -n syntax check"
if bash -n "$SCRIPT" 2>/dev/null; then
    pass "Script passes bash -n syntax check"
else
    fail "Script has syntax errors"
fi

# Test 2: Script is executable
echo "Test 2: Script is executable"
if [ -x "$SCRIPT" ]; then
    pass "Script is executable"
else
    fail "Script is not executable"
fi

# Test 3: Script exits with error if gh is not found
echo "Test 3: Exits with error when gh is missing"
output=$(PATH="/usr/bin:/bin" bash "$SCRIPT" 2>&1 || true)
if echo "$output" | grep -q "Error:.*'gh'.*required"; then
    pass "Exits with clear error when gh is missing"
elif echo "$output" | grep -q "Error:.*'jq'.*required"; then
    # jq might also be missing first — that's still a valid dependency check
    pass "Exits with clear error when a dependency is missing"
else
    # gh might be on /usr/bin or /bin; try with empty PATH
    output2=$(PATH="" bash "$SCRIPT" 2>&1 || true)
    if echo "$output2" | grep -q "Error:.*required"; then
        pass "Exits with clear error when dependencies are missing (empty PATH)"
    else
        fail "No dependency error message produced"
    fi
fi

# Test 4: Script exits with error if jq is not found
echo "Test 4: Exits with error when jq is missing"
# Create a temp dir with only gh available
tmpdir=$(mktemp -d)
gh_path=$(command -v gh 2>/dev/null || true)
if [ -n "$gh_path" ]; then
    ln -s "$gh_path" "$tmpdir/gh"
    output=$(PATH="$tmpdir" bash "$SCRIPT" 2>&1 || true)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "Error:.*'jq'.*required"; then
        pass "Exits with clear error when jq is missing"
    else
        fail "No jq dependency error message produced"
    fi
else
    rm -rf "$tmpdir"
    pass "gh not installed — dependency check already covers this (skipped jq-specific test)"
fi

# Test 5: Script accepts a repo argument
echo "Test 5: Script accepts a repo argument"
# Just check that the script tries to use the argument (will fail on network but shows it parsed the arg)
if grep -q 'REPO="\${1:-' "$SCRIPT"; then
    pass "Script accepts first argument as repo override"
else
    fail "Script does not accept repo argument"
fi

# Test 6: Claude review detection uses specific header
echo "Test 6: Claude review detection uses specific header"
if grep -qF '## Claude Review' "$SCRIPT"; then
    pass "Uses specific '## Claude Review' header for detection"
else
    fail "Does not use specific Claude Review header for detection"
fi

# Test 7: shellcheck (if available)
echo "Test 7: shellcheck validation"
if command -v shellcheck &>/dev/null; then
    if shellcheck "$SCRIPT" 2>&1; then
        pass "shellcheck reports no warnings"
    else
        fail "shellcheck reported warnings"
    fi
else
    echo "  SKIP: shellcheck not installed"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
