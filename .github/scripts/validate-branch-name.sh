#!/usr/bin/env bash
set -euo pipefail

branch_name="${BRANCH_NAME:-}"
jira_project_keys="${JIRA_PROJECT_KEYS:-APP}"
pr_title="${PR_TITLE:-}"

if [[ -z "$branch_name" ]]; then
  echo "::error::BRANCH_NAME is required."
  exit 1
fi

project_pattern="$(printf '%s' "$jira_project_keys" | tr ',' '|' | tr -d '[:space:]')"
jira_key_pattern="(${project_pattern})-[0-9]+"

case "$branch_name" in
  main|development)
    exit 0
    ;;
  feature/*)
    if [[ ! "$branch_name" =~ ^feature/${jira_key_pattern}([-/].+)?$ ]]; then
      echo "::error::Feature branches must use feature/<JIRA-KEY>-short-description, for example feature/APP-24-fix-spacing."
      exit 1
    fi
    ;;
  release/*)
    release_pattern="^release/(([0-9]+\\.[0-9]+\\.[0-9]+([.-][A-Za-z0-9]+)*)|(${jira_key_pattern}([-/].+)?))$"
    if [[ ! "$branch_name" =~ $release_pattern ]]; then
      echo "::error::Release branches must use release/<version> or release/<JIRA-KEY>-<version>, for example release/1.6.0 or release/APP-24-1.6.0."
      exit 1
    fi
    ;;
  *)
    echo "::error::Branch must be main, development, feature/<JIRA-KEY>-short-description, or release/<version>."
    exit 1
    ;;
esac

if [[ "$branch_name" == feature/* && -n "$pr_title" && ! "$pr_title" =~ $jira_key_pattern ]]; then
  echo "::error::Pull request titles must include a Jira issue key, for example APP-24 Fix spacing."
  exit 1
fi

commit_subjects=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  commit_range="HEAD"

  if [[ -n "${BASE_BRANCH:-}" ]]; then
    base_ref="origin/${BASE_BRANCH}"
    if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
      commit_range="${base_ref}..HEAD"
    fi
  fi

  commit_subjects="$(git log --format='%H%x09%s' "$commit_range" || true)"

  if [[ "$branch_name" == feature/* && -n "$commit_subjects" ]]; then
    if ! printf '%s' "$commit_subjects" | grep -Eq "$jira_key_pattern"; then
      echo "::error::At least one feature branch commit subject must include a Jira issue key so Jira can link deployments."
      exit 1
    fi
  fi
fi

source_text="${branch_name} ${PR_TITLE:-} ${PR_BODY:-} ${commit_subjects}"
jira_keys="$(printf '%s' "$source_text" | grep -Eo "$jira_key_pattern" | sort -u | tr '\n' ' ' || true)"

if [[ "$branch_name" == feature/* && -z "${jira_keys// /}" ]]; then
  echo "::error::Feature branches must include a Jira issue key from project(s): ${jira_project_keys}."
  exit 1
fi

if [[ -z "${JIRA_BASE_URL:-}" || -z "${JIRA_USER_EMAIL:-}" || -z "${JIRA_API_TOKEN:-}" || -z "${jira_keys// /}" ]]; then
  echo "Branch naming passed. Jira key existence check skipped."
  exit 0
fi

for jira_key in $jira_keys; do
  status_code="$(
    curl -sS \
      -u "${JIRA_USER_EMAIL}:${JIRA_API_TOKEN}" \
      -H "Accept: application/json" \
      -o /dev/null \
      -w "%{http_code}" \
      "${JIRA_BASE_URL%/}/rest/api/3/issue/${jira_key}"
  )"

  if [[ "$status_code" != "200" ]]; then
    echo "::error::Jira issue ${jira_key} was not found or is not accessible. Jira returned HTTP ${status_code}."
    exit 1
  fi
done

echo "Branch naming passed and Jira issue key(s) exist: ${jira_keys}"
