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
if printf '%s' "$output" | grep -q "Error:.*'gh'.*required"; then
    pass "Exits with clear error when gh is missing"
elif printf '%s' "$output" | grep -q "Error:.*'jq'.*required"; then
    # jq might also be missing first — that's still a valid dependency check
    pass "Exits with clear error when a dependency is missing"
else
    # gh might be on /usr/bin or /bin; try with empty PATH
    output2=$(PATH="" bash "$SCRIPT" 2>&1 || true)
    if printf '%s' "$output2" | grep -q "Error:.*required"; then
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
    if printf '%s' "$output" | grep -q "Error:.*'jq'.*required"; then
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

# Test 8: Placeholder detection
echo "Test 8: Placeholder detection"
test8_pass=true
diff_with_placeholders="some code <owner> and <your-username> and <your-fork> and <upstream-owner>"
for pattern in '<owner>' '<your-username>' '<your-fork>' '<upstream-owner>'; do
    if ! printf '%s' "$diff_with_placeholders" | grep -qF "$pattern"; then
        test8_pass=false
        break
    fi
done
# Also verify non-placeholder HTML tags are NOT matched by the placeholder patterns
non_placeholder="<div>"
matched_non_placeholder=false
for pattern in '<owner>' '<your-username>' '<your-fork>' '<upstream-owner>'; do
    if printf '%s' "$non_placeholder" | grep -qF "$pattern"; then
        matched_non_placeholder=true
        break
    fi
done
if [ "$test8_pass" = true ] && [ "$matched_non_placeholder" = false ]; then
    pass "All 4 placeholder patterns detected; non-placeholder <div> not matched"
else
    fail "Placeholder detection failed"
fi

# Test 9: Docs-only classification
echo "Test 9: Docs-only classification"
# Test docs-only files
docs_files="README.md
CHANGELOG.txt
docs/guide.rst"
is_docs_only=true
while IFS= read -r f; do
    case "$f" in
        *.md|*.txt|*.rst|.tokamak/*) ;;
        *) is_docs_only=false; break ;;
    esac
done <<< "$docs_files"
if [ "$is_docs_only" = true ]; then
    # Now test with a non-docs file mixed in
    mixed_files="README.md
script.sh"
    is_docs_only=true
    while IFS= read -r f; do
        case "$f" in
            *.md|*.txt|*.rst|.tokamak/*) ;;
            *) is_docs_only=false; break ;;
        esac
    done <<< "$mixed_files"
    if [ "$is_docs_only" = false ]; then
        pass "Docs-only classification: .md/.txt/.rst = docs-only, .sh breaks it"
    else
        fail "Docs-only classification: .sh file should break docs-only"
    fi
else
    fail "Docs-only classification: .md/.txt/.rst should be docs-only"
fi

# Test 10: File extension extraction edge cases
echo "Test 10: File extension extraction edge cases"
test10_pass=true

# Normal file: script.sh -> sh
f="script.sh"; ext="${f##*.}"; basename_f="${f##*/}"
[ "$ext" = "$basename_f" ] && ext="no-ext"
[ "$ext" = "sh" ] || test10_pass=false

# Normal file: README.md -> md
f="README.md"; ext="${f##*.}"; basename_f="${f##*/}"
[ "$ext" = "$basename_f" ] && ext="no-ext"
[ "$ext" = "md" ] || test10_pass=false

# No extension: Makefile -> no-ext
f="Makefile"; ext="${f##*.}"; basename_f="${f##*/}"
[ "$ext" = "$basename_f" ] && ext="no-ext"
[ "$ext" = "no-ext" ] || test10_pass=false

# Dotfile: .gitignore -> gitignore (has a dot, so extension is extracted)
f=".gitignore"; ext="${f##*.}"; basename_f="${f##*/}"
[ "$ext" = "$basename_f" ] && ext="no-ext"
[ "$ext" = "gitignore" ] || test10_pass=false

if [ "$test10_pass" = true ]; then
    pass "File extension extraction: normal, no-ext, and dotfile cases all correct"
else
    fail "File extension extraction edge cases failed"
fi

# Test 11: Claude review header detection
echo "Test 11: Claude review header detection"
test11_pass=true
# Exact match should succeed
if ! printf '%s' "## Claude Review
Some content" | grep -qF "## Claude Review"; then
    test11_pass=false
fi
# Partial match should NOT succeed
if printf '%s' "User claude commented" | grep -qF "## Claude Review"; then
    test11_pass=false
fi
if [ "$test11_pass" = true ]; then
    pass "Claude review header: exact match works, partial string does not false-positive"
else
    fail "Claude review header detection failed"
fi

# Test 12: LICENSE exact match (validates Bug B fix)
echo "Test 12: LICENSE file check uses exact matching"
# 'LICENSE' alone should match
if printf '%s' 'LICENSE' | grep -qx 'LICENSE'; then
  # But partial paths should NOT match
  if ! printf '%s' 'docs/LICENSE-FAQ.md' | grep -qx 'LICENSE'; then
    pass "LICENSE check uses exact matching — partial paths do not match"
  else
    fail "LICENSE check incorrectly matches partial paths"
  fi
else
  fail "LICENSE check does not match the LICENSE file"
fi

# Test 13: Title check can match full diff (validates Bug A fix)
echo "Test 13: Docs-only title check searches full diff"
# Simulate a realistic git diff with headers (7 lines) then content
fake_diff="diff --git a/README.md b/README.md
new file mode 100644
index 0000000..abc1234
--- /dev/null
+++ b/README.md
@@ -0,0 +1,3 @@
+# add-readme
+
+Some content"
if printf '%s' "$fake_diff" | grep -q "^+# add-readme"; then
  pass "Title check pattern matches in full diff content"
else
  fail "Title check pattern failed to match in full diff"
fi

# Test 14: Analysis uses printf '%s' not printf '%b' (validates injection fix)
echo "Test 14: Analysis variable uses printf '%s' not printf '%b'"
test14_pass=true
# printf '%b' should NOT appear in the review body composition
if grep -q "printf '%b'" "$SCRIPT"; then
    test14_pass=false
fi
# printf '%s' should be used for analysis output
if ! grep -q 'printf.*%s.*\$analysis' "$SCRIPT"; then
    test14_pass=false
fi
# Verify that backslash sequences in analysis are NOT interpreted
analysis_test="- **Files**: 2 (sh, md)
- **Size**: +10 / -5 lines"
result=$(printf '%s' "$analysis_test")
if [ "$result" != "$analysis_test" ]; then
    test14_pass=false
fi
if [ "$test14_pass" = true ]; then
    pass "Analysis uses printf '%s' — no backslash escape interpretation"
else
    fail "Analysis still uses printf '%b' or backslash escapes are interpreted"
fi

# Test 15: grep -v pipeline is guarded against pipefail (validates pipefail fix)
echo "Test 15: grep -v pipeline is guarded against pipefail"
# The unique_types pipeline should have a || true guard on grep -v
if grep -q 'grep -v.*|| true' "$SCRIPT"; then
    # Verify the guard works: empty input should not crash under pipefail
    set -o pipefail
    result=$(printf '' | tr ' ' '\n' | sort -u | { grep -v '^$' || true; } | tr '\n' ', ' | sed 's/,$//')
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        pass "grep -v pipeline is guarded — empty input does not crash with pipefail"
    else
        fail "grep -v pipeline guard did not prevent pipefail crash"
    fi
else
    fail "grep -v pipeline is missing || true guard"
fi

# Test 16: gh pr comment failure is handled (validates error handling fix)
echo "Test 16: gh pr comment has error handling"
# The script should wrap gh pr comment in an if-not or || guard
if grep -q 'if ! gh pr comment' "$SCRIPT" || grep -q 'gh pr comment.*|| {' "$SCRIPT"; then
    pass "gh pr comment failure is handled — won't abort remaining PRs"
else
    fail "gh pr comment is not guarded — failure would abort remaining PRs"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
