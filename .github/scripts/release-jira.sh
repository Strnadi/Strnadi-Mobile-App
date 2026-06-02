#!/usr/bin/env bash
set -euo pipefail

jira_project_keys="${JIRA_PROJECT_KEYS:-APP}"
target_status="${JIRA_TARGET_STATUS:-To Test}"
branch_name="${BRANCH_NAME:-${GITHUB_REF_NAME:-}}"
release_version="${JIRA_RELEASE_VERSION:-}"
deployment_stage="${DEPLOYMENT_STAGE:-release_candidate}"

if [[ "$deployment_stage" != "release_candidate" ]]; then
  echo "Jira release-candidate update skipped for deployment stage: ${deployment_stage}."
  exit 0
fi

if [[ "$branch_name" != release/* && -z "$release_version" ]]; then
  echo "Jira release-candidate update skipped because this is not a release branch."
  exit 0
fi

if [[ -z "${JIRA_BASE_URL:-}" || -z "${JIRA_USER_EMAIL:-}" || -z "${JIRA_API_TOKEN:-}" ]]; then
  echo "Jira credentials are not configured. Skipping release issue transitions."
  exit 0
fi

project_pattern="$(printf '%s' "$jira_project_keys" | tr ',' '|' | tr -d '[:space:]')"
jira_key_pattern="(${project_pattern})-[0-9]+"

if [[ -z "$release_version" ]]; then
  release_version="${branch_name#release/}"
  if [[ "$release_version" =~ ^${jira_key_pattern}[-/](.+)$ ]]; then
    release_version="${BASH_REMATCH[2]}"
  fi
fi

if [[ -z "$release_version" ]]; then
  echo "::error::Could not determine Jira release version from branch '${branch_name}'."
  exit 1
fi

project_list="$(
  printf '%s' "$jira_project_keys" |
    tr ',' '\n' |
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
    awk 'NF { printf "%s\"%s\"", sep, $0; sep = "," }'
)"

jql="project in (${project_list}) AND fixVersion = \"${release_version}\" AND issuetype in (Feature, Story, Task, Bug) ORDER BY key"

echo "Finding Jira issues for release ${release_version}."
issues_response="$(
  curl -sS \
    -u "${JIRA_USER_EMAIL}:${JIRA_API_TOKEN}" \
    -H "Accept: application/json" \
    --get \
    --data-urlencode "jql=${jql}" \
    --data-urlencode "fields=summary,status" \
    --data-urlencode "maxResults=100" \
    "${JIRA_BASE_URL%/}/rest/api/3/search"
)"

issue_keys="$(printf '%s' "$issues_response" | jq -r '.issues[].key')"

if [[ -z "$issue_keys" ]]; then
  echo "No Jira issues found for fixVersion '${release_version}'."
  exit 0
fi

comment_text="${JIRA_COMMENT_BODY:-Release ${release_version} has been deployed from ${branch_name} and is ready for QA testing.

Workflow run: ${DEPLOYMENT_LOG_URL:-}}"
comment_payload="$(jq -n --arg text "$comment_text" '{
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

while IFS= read -r issue_key; do
  [[ -n "$issue_key" ]] || continue

  curl -sS \
    -u "${JIRA_USER_EMAIL}:${JIRA_API_TOKEN}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    --data "$comment_payload" \
    "${JIRA_BASE_URL%/}/rest/api/3/issue/${issue_key}/comment" \
    >/dev/null

  transitions="$(
    curl -sS \
      -u "${JIRA_USER_EMAIL}:${JIRA_API_TOKEN}" \
      -H "Accept: application/json" \
      "${JIRA_BASE_URL%/}/rest/api/3/issue/${issue_key}/transitions"
  )"
  transition_id="$(
    printf '%s' "$transitions" |
      jq -r --arg target "$target_status" '
        .transitions[]
        | select((.name | ascii_downcase) == ($target | ascii_downcase) or (.to.name | ascii_downcase) == ($target | ascii_downcase))
        | .id
      ' |
      head -n 1
  )"

  if [[ -z "$transition_id" ]]; then
    echo "::warning::${issue_key} was commented, but no transition to '${target_status}' is available."
    continue
  fi

  transition_payload="$(jq -n --arg id "$transition_id" '{ transition: { id: $id } }')"
  curl -sS \
    -u "${JIRA_USER_EMAIL}:${JIRA_API_TOKEN}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    --data "$transition_payload" \
    "${JIRA_BASE_URL%/}/rest/api/3/issue/${issue_key}/transitions" \
    >/dev/null

  echo "Updated ${issue_key}: commented and transitioned to ${target_status}."
done <<< "$issue_keys"
