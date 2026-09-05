#!/usr/bin/env bash
set -euo pipefail

AUTHOR="${AUTHOR:-vianhanif}"
LLM_URL="${LLM_URL:-https://9router.vianhanif.link/v1}"
LLM_MODEL="${LLM_MODEL:-General}"
README_FILE="README.md"
START_MARKER='<!-- AI-UPDATE:START -->'
END_MARKER='<!-- AI-UPDATE:END -->'

if [[ -z "${LLM_API_KEY:-}" ]]; then
  echo "Warning: LLM_API_KEY unset — sending request without auth" >&2
fi

# Collect recent work: last 30 events, trimmed to compact JSON
events=$(gh api "users/${AUTHOR}/events?per_page=30" \
  | jq '[ .[] | {type, created_at, repo: .repo.name, payload: {action: .payload.action, ref: .payload.ref, ref_type: .payload.ref_type, commits: [.payload.commits[]? | {message, sha}] | .[0:5]}} ]')

context=$(jq -Rs --arg a "$AUTHOR" '
  "Recent GitHub activity for \($a):\n" + . ' <<< "$events")

prompt='You are a GitHub profile summarizer. Write 3-6 markdown bullets summarizing the user'\''s most recent open source work from the activity JSON. Lead with what they are working on, note PRs/repos touched, keep it factual, no greetings. Output ONLY the bullets, one per line, starting with "-".'

# Call LLM (OpenAI-compatible chat completions)
auth=()
[[ -n "${LLM_API_KEY:-}" ]] && auth=(-H "Authorization: Bearer ${LLM_API_KEY}")
content=$(curl -fsS "${LLM_URL}/chat/completions" "${auth[@]}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg m "$LLM_MODEL" --arg sys "$prompt" --arg user "$context" \
    '{model: $m, messages: [{role: "system", content: $sys}, {role: "user", content: $user}], temperature: 0.4}')" \
  | jq -r '.choices[0].message.content')

grep -qF "$START_MARKER" "$README_FILE" || { echo "Error: Start marker not found" >&2; exit 1; }
grep -qF "$END_MARKER" "$README_FILE" || { echo "Error: End marker not found" >&2; exit 1; }

body_file=$(mktemp)
printf '## 🤖 AI Activity Digest\n\n%s\n' "$content" > "$body_file"

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
echo "AI digest updated"