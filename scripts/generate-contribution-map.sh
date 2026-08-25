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

# Helper function to generate sections
render_section() {
    local json="$1" state="$2" label="$3" date_verb="$4"
    
    local count
    count=$(echo "$json" | jq -r --arg cut "$CUTOFF_DATE" --arg state "$state" '
        [ .[] | select(.repository.nameWithOwner | split("/")[0] != "vianhanif") | select($state != "merged" or (.closedAt != null and .closedAt >= $cut)) ] | length
    ')

    if [ "$count" -eq 0 ]; then
        echo "_No $label external pull requests right now._"
        return
    fi

    local repo_count
    repo_count=$(echo "$json" | jq -r --arg cut "$CUTOFF_DATE" --arg state "$state" '
        [ .[] | select(.repository.nameWithOwner | split("/")[0] != "vianhanif") | select($state != "merged" or (.closedAt != null and .closedAt >= $cut)) ] 
        | map(.repository.nameWithOwner) | unique | length
    ')

    echo "_**${count}** external ${label} pull request(s) across ${repo_count} repositories._"
    echo ""

    echo "$json" | jq -r --arg cut "$CUTOFF_DATE" --arg state "$state" --arg verb "$date_verb" '
        [ .[] | select(.repository.nameWithOwner | split("/")[0] != "vianhanif") | select($state != "merged" or (.closedAt != null and .closedAt >= $cut)) ]
        | sort_by(.repository.nameWithOwner, .createdAt)
        | group_by(.repository.nameWithOwner)
        | .[]
        | "### " + .[0].repository.nameWithOwner + " (" + (length|tostring) + " " + $state + ")\n" +
          (map("- [" + .repository.nameWithOwner + "] " + .title + " (#" + (.number|tostring) + ") — " + .url + " (" + $verb + " " + (if $state=="open" then .createdAt[:10] else .closedAt[:10] end) + ")") | join("\n"))
    '
}

# Generate bodies
body_open=$(render_section "$open_json" "open" "open" "opened")
body_merged=$(render_section "$merged_json" "merged" "merged" "merged")

# Splice into README
grep -qF "$START_MARKER" "$README_FILE" || { echo "Error: Start marker not found" >&2; exit 1; }
grep -qF "$END_MARKER" "$README_FILE" || { echo "Error: End marker not found" >&2; exit 1; }

body_file=$(mktemp)
{
    echo "$body_open"
    echo ""
    echo "$body_merged"
} > "$body_file"

tmp_readme=$(mktemp)
awk -v s="$START_MARKER" -v e="$END_MARKER" -v body="$body_file" '
  BEGIN{ins=0}
  $0==s {print; while((getline line < body)>0) print line; close(body); ins=1; skip=1; next}
  $0==e && ins {ins=0; print; next}
  ins {next}
  {print}
' "$README_FILE" > "$tmp_readme"

mv "$tmp_readme" "$README_FILE"
rm "$body_file"
