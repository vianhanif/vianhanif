#!/usr/bin/env bash
set -euo pipefail

# ponytail: events-based counting; upgrade to commit-level API if more precision needed

AUTHOR="${AUTHOR:-vianhanif}"
README_FILE="README.md"
START_MARKER='<!-- OSS-MAP:START -->'
END_MARKER='<!-- OSS-MAP:END -->'

# Fetch recent events (last 100), keep contribution-type events only, extract external repos (owner != AUTHOR)
events=$(gh api "users/${AUTHOR}/events?per_page=100")
external_repos=$(echo "$events" | jq -r --arg a "$AUTHOR" '
  [ .[] | select(.type == "PushEvent" or .type == "PullRequestEvent" or .type == "IssuesEvent" or .type == "IssueCommentEvent" or .type == "PullRequestReviewEvent" or .type == "ForkEvent") | .repo.name | select(startswith($a + "/") | not) ] | unique | sort | .[]')

repo_count=$(echo "$external_repos" | grep -c . || true)

if [[ $repo_count -eq 0 ]]; then
  body='<sub>🗺️ No recent external contributions.</sub>'
else
  # Format repo list: owner/repo -> repo (linked)
  repo_links=$(echo "$external_repos" | while read -r r; do
    name=${r##*/}
    echo "[${name}](https://github.com/${r})"
  done | paste -sd, - | sed 's/,/, /g')
  body="<sub>🗺️ Active in ${repo_count} external repo(s): ${repo_links}</sub>"
fi

# Splice into README
grep -qF "$START_MARKER" "$README_FILE" || { echo "Error: Start marker not found" >&2; exit 1; }
grep -qF "$END_MARKER" "$README_FILE" || { echo "Error: End marker not found" >&2; exit 1; }

body_file=$(mktemp)
printf '%s\n' "$body" > "$body_file"

tmp_readme=$(mktemp)
awk -v s="$START_MARKER" -v e="$END_MARKER" -v body="$body_file" '
  BEGIN{ins=0}
  $0==s {print; while((getline line < body)>0) print line; close(body); ins=1; skip=1; next}
  $0==e && ins {ins=0; print; next}
  ins {next}
  {print}
' "$README_FILE" > "$tmp_readme" || { echo "Error: README splice failed" >&2; rm -f "$tmp_readme" "$body_file"; exit 1; }

mv "$tmp_readme" "$README_FILE"
rm "$body_file"
echo "Contribution map updated"
