#!/usr/bin/env bash
set -euo pipefail

jira_project_keys="${JIRA_PROJECT_KEYS:-APP}"
project_pattern="$(printf '%s' "$jira_project_keys" | tr ',' '|' | tr -d '[:space:]')"
jira_key_pattern="(${project_pattern})-[0-9]+"
source_text="${JIRA_KEYS:-} ${BRANCH_NAME:-} ${PR_TITLE:-} ${PR_BODY:-} ${GITHUB_REF_NAME:-}"
jira_keys="$(printf '%s' "$source_text" | grep -Eo "$jira_key_pattern" | sort -u | tr '\n' ' ' || true)"

if [[ -z "${jira_keys// /}" ]]; then
  echo "No Jira issue keys found. Nothing to comment."
  exit 0
fi

if [[ -z "${JIRA_BASE_URL:-}" || -z "${JIRA_USER_EMAIL:-}" || -z "${JIRA_API_TOKEN:-}" ]]; then
  echo "Jira credentials are not configured. Skipping Jira comment."
  exit 0
fi

comment_body="${JIRA_COMMENT_BODY:-}"
if [[ -z "$comment_body" ]]; then
  comment_body="GitHub update for ${GITHUB_REPOSITORY:-repository}: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}"
fi

payload="$(jq -n --arg text "$comment_body" '{
  body: {
    type: "doc",
    version: 1,
    content: [
      {
        type: "paragraph",
        content: [
          {
            type: "text",
            text: $text
          }
        ]
      }
    ]
  }
}')"

for jira_key in $jira_keys; do
  curl -sS \
    -u "${JIRA_USER_EMAIL}:${JIRA_API_TOKEN}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    "${JIRA_BASE_URL%/}/rest/api/3/issue/${jira_key}/comment" \
    >/dev/null

  echo "Commented on ${jira_key}."
done
