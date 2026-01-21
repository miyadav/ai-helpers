#!/bin/bash
# Basic overlap detection for ai-helpers PRs
# This script performs lightweight checks for obvious overlaps.
# For detailed semantic analysis, run: /utils:review-ai-helpers-overlap

set -e

REPO="openshift-eng/ai-helpers"
PR_NUMBER="${1}"
BASE_SHA="${2}"

if [ -z "$PR_NUMBER" ] || [ -z "$BASE_SHA" ]; then
  echo "Usage: $0 <pr_number> <base_sha>"
  exit 1
fi

echo "Checking PR #${PR_NUMBER} for overlaps..."
echo ""

# Get changed files in this PR
CHANGED_FILES=$(git diff --name-only "$BASE_SHA" HEAD -- 'plugins/' 'agents/' '.claude/hooks/' | \
  grep -E '(^plugins/.*/commands/.*\.md$|^plugins/.*/skills/.*/SKILL\.md$|^agents/.*\.md$|^\.claude/hooks/.*\.(sh|py)$)' || true)

if [ -z "$CHANGED_FILES" ]; then
  echo "No ai-helpers changes detected (commands, skills, agents, or hooks)."
  echo "This check only applies to ai-helpers contributions."
  exit 0
fi

echo "Changed files:"
echo "$CHANGED_FILES"
echo ""

# Extract component names and keywords from changed files
declare -A component_names
declare -A component_types

while IFS= read -r file; do
  if [[ "$file" =~ ^plugins/([^/]+)/commands/([^/]+)\.md$ ]]; then
    plugin="${BASH_REMATCH[1]}"
    command="${BASH_REMATCH[2]}"
    component_names["$file"]="${plugin}:${command}"
    component_types["$file"]="command"
  elif [[ "$file" =~ ^plugins/([^/]+)/skills/([^/]+)/SKILL\.md$ ]]; then
    plugin="${BASH_REMATCH[1]}"
    skill="${BASH_REMATCH[2]}"
    component_names["$file"]="${plugin}:${skill}"
    component_types["$file"]="skill"
  elif [[ "$file" =~ ^agents/([^/]+)\.md$ ]]; then
    agent="${BASH_REMATCH[1]}"
    component_names["$file"]="$agent"
    component_types["$file"]="agent"
  elif [[ "$file" =~ ^\.claude/hooks/([^/]+)\.(sh|py)$ ]]; then
    hook="${BASH_REMATCH[1]}"
    component_names["$file"]="$hook"
    component_types["$file"]="hook"
  fi
done <<< "$CHANGED_FILES"

# Fetch open PRs
echo "Fetching open PRs..."
OPEN_PRS=$(gh pr list --repo "$REPO" --state open --json number,title,files --limit 100)

# Check for overlaps
overlaps_found=0
overlap_report=""

for file in "${!component_names[@]}"; do
  name="${component_names[$file]}"
  type="${component_types[$file]}"

  echo "Checking ${type}: ${name}"

  # Check other open PRs for similar files
  similar_prs=$(echo "$OPEN_PRS" | jq -r --arg pr "$PR_NUMBER" --arg file "$file" '
    .[] | select(.number != ($pr | tonumber)) |
    select(.files[]?.path == $file) |
    "  - PR #\(.number): \(.title)"
  ')

  if [ -n "$similar_prs" ]; then
    overlaps_found=1
    overlap_report+="**${type}: ${name}**\n"
    overlap_report+="File: \`${file}\`\n"
    overlap_report+="Overlapping PRs:\n${similar_prs}\n\n"
  fi

  # Check for similar command/skill names in other PRs
  basename=$(basename "$file" | sed 's/\.[^.]*$//')
  similar_names=$(echo "$OPEN_PRS" | jq -r --arg pr "$PR_NUMBER" --arg basename "$basename" '
    .[] | select(.number != ($pr | tonumber)) |
    select(.files[]?.path | test($basename)) |
    "  - PR #\(.number): \(.title) (file: \(.files[] | select(.path | test($basename)) | .path))"
  ')

  if [ -n "$similar_names" ]; then
    overlaps_found=1
    if [[ "$overlap_report" != *"${type}: ${name}"* ]]; then
      overlap_report+="**${type}: ${name}**\n"
      overlap_report+="Potentially similar names found:\n${similar_names}\n\n"
    fi
  fi
done

# Output results
if [ $overlaps_found -eq 1 ]; then
  echo ""
  echo "⚠️  Potential overlaps detected!"
  echo ""
  echo -e "$overlap_report"
  echo "**Next Steps:**"
  echo "1. Review the overlapping PRs listed above"
  echo "2. Consider collaboration or consolidation if appropriate"
  echo "3. For detailed semantic analysis, run locally: \`/utils:review-ai-helpers-overlap\`"
  echo ""

  # Save report for GitHub Actions to use
  cat > /tmp/overlap-report.md <<EOF
## ⚠️ Potential Overlap Detected

This PR may overlap with existing open PRs. Please review:

$overlap_report

**Recommendations:**
- Review the PRs listed above to check for duplication
- Consider collaborating on existing PRs if goals align
- If your approach is different, document how it differs
- Run \`/utils:review-ai-helpers-overlap\` locally for detailed semantic analysis

**Note:** This is an automated basic check. It may flag false positives. The full overlap command provides semantic matching for more accurate results.
EOF

  exit 1
else
  echo "✓ No obvious overlaps detected with other open PRs"
  echo ""
  echo "**Recommendation:** Still run \`/utils:review-ai-helpers-overlap\` locally for semantic overlap analysis."
  exit 0
fi
