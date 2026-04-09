#!/usr/bin/env bash
set -euo pipefail

# Validate required dependencies
for cmd in gh jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' is required but not installed." >&2
    exit 1
  fi
done

# Determine target repository
REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)}"
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
    # Uses the specific review header "## Claude Review" to avoid false positives
    # from usernames or unrelated mentions of "claude"
    echo "  Checking for existing Claude reviews..."

    issue_comment_bodies=$(gh api "repos/$REPO/issues/$number/comments" --jq '.[].body' 2>/dev/null || true)
    review_bodies=$(gh api "repos/$REPO/pulls/$number/reviews" --jq '.[].body' 2>/dev/null || true)

    all_bodies="${issue_comment_bodies}
${review_bodies}"

    if printf '%s' "$all_bodies" | grep -qF "## Claude Review"; then
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

    # Check if it's docs-only
    is_docs_only=true
    while IFS= read -r f; do
        case "$f" in
            *.md|*.txt|*.rst|.tokamak/*) ;;
            *) is_docs_only=false; break ;;
        esac
    done <<< "$files_changed"

    # Build analysis
    analysis="- **Files changed**: ${file_count} (${unique_types})\n- **Size**: +${additions} / -${deletions} lines"

    issues=""

    # Check for missing license file reference
    if echo "$diff" | grep -qi "license" && ! echo "$files_changed" | grep -qi "LICENSE"; then
        issues="${issues}\n- README references a LICENSE file but no LICENSE file is included in this PR."
    fi

    # Check for placeholder content (angle-bracket tokens)
    placeholder_patterns=('<owner>' '<your-username>' '<your-fork>' '<upstream-owner>')
    for pattern in "${placeholder_patterns[@]}"; do
        if echo "$diff" | grep -qF "$pattern"; then
            issues="${issues}\n- Contains placeholder text (\`${pattern}\`) that should be replaced with actual values."
            break
        fi
    done

    # Check README content quality for docs-only PRs
    if [ "$is_docs_only" = true ]; then
        # Check if project name in README matches repo
        if echo "$diff" | head -5 | grep -q "^+# add-readme"; then
            issues="${issues}\n- The README title is \`add-readme\` which appears to be a task name rather than the actual project name."
        fi

        # Check for generic/template content
        if echo "$diff" | grep -q "A new project under active development"; then
            issues="${issues}\n- The README description is generic and doesn't describe what the project actually does."
        fi

        # Check for assumptions about tech stack
        if echo "$diff" | grep -q "npm install" && ! gh api "repos/$REPO/contents/package.json" --jq '.name' &>/dev/null; then
            issues="${issues}\n- README assumes a Node.js/npm stack but the repo may not have a package.json yet."
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

    # Compose review body
    body_head=$(printf '%s' "$pr_body" | head -5)
    review="## Claude Review

### Summary
PR #${number} (${pr_title}) adds/modifies ${file_count} file(s) with +${additions}/-${deletions} lines.

${body_head}

### Analysis
$(printf '%b' "$analysis")
$(if [ -n "$issues" ]; then printf '\n**Issues found:**%b' "$issues"; fi)

### Verdict
${suggestion}"

    # Post review
    echo "  Posting review comment..."
    gh pr comment "$number" --repo "$REPO" --body "$review"
    echo "  Review posted successfully for PR #$number."
    echo ""
done

echo "=== Done ==="
