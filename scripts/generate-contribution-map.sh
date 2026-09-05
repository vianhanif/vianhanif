#!/usr/bin/env bash
set -euo pipefail

AUTHOR="vianhanif"
CUTOFF_YEAR="${CUTOFF_YEAR:-2020}"
CUTOFF_DATE="${CUTOFF_YEAR}-01-01"
README_FILE="README.md"
START_MARKER='<!-- OSS-MAP:START -->'
END_MARKER='<!-- OSS-MAP:END -->'

# Fetch data
open_json=$(gh search prs --author "$AUTHOR" --limit 200 --state open --json number,title,url,repository,state,createdAt,closedAt)
merged_json=$(gh search prs --author "$AUTHOR" --limit 200 --state closed --merged --json number,title,url,repository,state,createdAt,closedAt)

# Count external PRs (owner != AUTHOR); merged additionally respects cutoff year
open_count=$(echo "$open_json" | jq '[ .[] | select(.repository.nameWithOwner | split("/")[0] != "vianhanif") ] | length')
merged_count=$(echo "$merged_json" | jq --arg cut "$CUTOFF_DATE" '[ .[] | select((.repository.nameWithOwner | split("/")[0]) != "vianhanif") | select(.closedAt != null and .closedAt >= $cut) ] | length')
repo_count=$(jq -s --arg cut "$CUTOFF_DATE" '
  [ .[0][] | select((.repository.nameWithOwner | split("/")[0]) != "vianhanif") | .repository.nameWithOwner ] +
  [ .[1][] | select((.repository.nameWithOwner | split("/")[0]) != "vianhanif") | select(.closedAt != null and .closedAt >= $cut) | .repository.nameWithOwner ]
  | unique | length
' <(echo "$open_json") <(echo "$merged_json"))

updated=$(date -u +%Y-%m-%d)
body="**Open PRs:** ${open_count}\n\n**Merged PRs:** ${merged_count}\n\n_${repo_count} external repositories · updated ${updated}_"

# Splice into README
grep -qF "$START_MARKER" "$README_FILE" || { echo "Error: Start marker not found" >&2; exit 1; }
grep -qF "$END_MARKER" "$README_FILE" || { echo "Error: End marker not found" >&2; exit 1; }

body_file=$(mktemp)
{
    printf '%b\n' "$body"
} > "$body_file"

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
