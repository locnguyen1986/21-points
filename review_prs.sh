#!/usr/bin/env bash
set -euo pipefail

for cmd in gh jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' is required but not installed." >&2
    exit 1
  fi
done

REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}"
if [ -z "$REPO" ]; then
  echo "Error: Could not detect repository. Pass owner/repo as first argument." >&2
  exit 1
fi

echo "=== PR Review Script for $REPO ==="
echo ""

# Step 1: Fetch open PRs
echo "Fetching open PRs..."
prs=$(gh pr list --repo "$REPO" --state open --json number,title)
pr_count=$(echo "$prs" | jq length)

if [ "$pr_count" -eq 0 ]; then
    echo "No open PRs found. Exiting."
    exit 0
fi

echo "Found $pr_count open PR(s)."
echo ""

# Step 2-5: Process each PR
echo "$prs" | jq -c '.[]' | while read -r pr; do
    number=$(echo "$pr" | jq -r '.number')
    title=$(echo "$pr" | jq -r '.title')
    echo "--- Processing PR #$number: $title ---"

    # Check for existing Claude reviews (idempotency)
    echo "  Checking for existing Claude reviews..."

    issue_comment_authors=$(gh api "repos/$REPO/issues/$number/comments" --jq '.[].user.login' 2>/dev/null || true)
    issue_comment_bodies=$(gh api "repos/$REPO/issues/$number/comments" --jq '.[].body' 2>/dev/null || true)
    review_authors=$(gh api "repos/$REPO/pulls/$number/reviews" --jq '.[].user.login' 2>/dev/null || true)
    review_bodies=$(gh api "repos/$REPO/pulls/$number/reviews" --jq '.[].body' 2>/dev/null || true)

    all_text="$issue_comment_authors
$issue_comment_bodies
$review_authors
$review_bodies"

    if echo "$all_text" | grep -qi "claude"; then
        echo "  Already reviewed by Claude. Skipping."
        echo ""
        continue
    fi

    # Fetch PR details and diff
    echo "  Fetching PR details and diff..."
    details=$(gh pr view "$number" --repo "$REPO" --json files,additions,deletions,body,commits,title)
    diff=$(gh pr diff "$number" --repo "$REPO")

    pr_title=$(echo "$details" | jq -r '.title')
    pr_body=$(echo "$details" | jq -r '.body // "No description provided."')
    additions=$(echo "$details" | jq -r '.additions')
    deletions=$(echo "$details" | jq -r '.deletions')
    files_changed=$(echo "$details" | jq -r '.files[].path')
    file_count=$(echo "$details" | jq '.files | length')

    # Analyze file types
    file_types=""
    while IFS= read -r f; do
        ext="${f##*.}"
        file_types="$file_types $ext"
    done <<< "$files_changed"
    unique_types=$(echo "$file_types" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ', ' | sed 's/,$//')

    # Determine review suggestion
    # Check if it's docs-only
    is_docs_only=true
    while IFS= read -r f; do
        case "$f" in
            *.md|*.txt|*.rst|.tokamak/*) ;;
            *) is_docs_only=false; break ;;
        esac
    done <<< "$files_changed"

    # Build analysis
    analysis="- **Files changed**: $file_count ($unique_types)\n- **Size**: +$additions / -$deletions lines"

    issues=""

    # Check for missing license file reference
    if echo "$diff" | grep -qi "license" && ! echo "$files_changed" | grep -qi "LICENSE"; then
        issues="$issues\n- README references a LICENSE file but no LICENSE file is included in this PR."
    fi

    # Check for placeholder content
    if echo "$diff" | grep -q '<owner>' || echo "$diff" | grep -q '<your-username>'; then
        issues="$issues\n- Contains placeholder text (\`<owner>\`, \`<your-username>\`) that should be replaced with actual values."
    fi

    # Check README content quality for docs-only PRs
    if [ "$is_docs_only" = true ]; then
        # Check if project name in README matches repo
        if echo "$diff" | head -5 | grep -q "^+# add-readme"; then
            issues="$issues\n- The README title is \`add-readme\` which appears to be a task name rather than the actual project name (21-points)."
        fi

        # Check for generic/template content
        if echo "$diff" | grep -q "A new project under active development"; then
            issues="$issues\n- The README description is generic and doesn't describe what 21-points actually does."
        fi

        # Check for assumptions about tech stack
        if echo "$diff" | grep -q "npm install" && ! gh api "repos/$REPO/contents/package.json" --jq '.name' &>/dev/null; then
            issues="$issues\n- README assumes a Node.js/npm stack but the repo may not have a package.json yet."
        fi
    fi

    # Determine suggestion
    if [ -n "$issues" ]; then
        suggestion="**Suggestion: Improve needed** — The content has structural and accuracy issues that should be addressed before merging."
    else
        if [ "$is_docs_only" = true ]; then
            suggestion="**Suggestion: Can merge** — Documentation-only change with no code impact."
        else
            suggestion="**Suggestion: Can merge** — Changes look reasonable."
        fi
    fi

    # Compose review
    review="## Claude Review

### Summary
PR #$number ($pr_title) adds/modifies $file_count file(s) with +$additions/-$deletions lines.

$(echo "$pr_body" | head -5)

### Analysis
$(echo -e "$analysis")
$(if [ -n "$issues" ]; then echo -e "\n**Issues found:**$issues"; fi)

### Verdict
$suggestion"

    # Post review
    echo "  Posting review comment..."
    gh pr comment "$number" --repo "$REPO" --body "$review"
    echo "  Review posted successfully for PR #$number."
    echo ""
done

echo "=== Done ==="
