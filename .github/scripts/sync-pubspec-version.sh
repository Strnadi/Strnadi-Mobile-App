#!/usr/bin/env bash
set -euo pipefail

branch_name="${BRANCH_NAME:-${GITHUB_REF_NAME:-}}"
deployment_stage="${DEPLOYMENT_STAGE:-}"
output_file="${GITHUB_OUTPUT:-/dev/null}"
version_changed=false
release_version=""
deploy_sha_output=""

write_output() {
  printf '%s=%s\n' "$1" "$2" >> "$output_file"
}

write_outputs() {
  write_output version_changed "$version_changed"
  write_output release_version "$release_version"
  write_output deploy_sha "$deploy_sha_output"
}

deploy_sha() {
  git rev-parse HEAD
}

if [[ "$branch_name" != release/* ]]; then
  deploy_sha_output="$(deploy_sha)"
  write_outputs
  echo "Pubspec version sync skipped for branch '${branch_name}' and stage '${deployment_stage}'."
  exit 0
fi

if [[ "$deployment_stage" != "internal" && "$deployment_stage" != "release_candidate" ]]; then
  deploy_sha_output="$(deploy_sha)"
  write_outputs
  echo "Pubspec version sync skipped for release promotion stage '${deployment_stage}'."
  exit 0
fi

release_ref="${branch_name#release/}"
release_version="$release_ref"

if [[ "$release_ref" =~ ^[A-Z][A-Z0-9]+-[0-9]+[-/](.+)$ ]]; then
  release_version="${BASH_REMATCH[1]}"
fi

if [[ ! "$release_version" =~ ^[0-9]+(\.[0-9]+){1,3}([.-][A-Za-z0-9]+)*$ ]]; then
  echo "::error::Could not derive a valid app version from release branch '${branch_name}'."
  exit 1
fi

target_pubspec_version="${release_version}+${release_version}"
current_pubspec_version="$(
  sed -nE 's/^[[:space:]]*version:[[:space:]]*([^[:space:]]+).*$/\1/p' pubspec.yaml |
    head -n 1
)"

if [[ "$current_pubspec_version" == "$target_pubspec_version" ]]; then
  deploy_sha_output="$(deploy_sha)"
  write_outputs
  echo "pubspec.yaml already uses version ${target_pubspec_version}."
  exit 0
fi

PUBSPEC_VERSION="$target_pubspec_version" perl -0pi -e 's/^version:.*$/version: $ENV{PUBSPEC_VERSION}/m' pubspec.yaml

if git diff --quiet -- pubspec.yaml; then
  deploy_sha_output="$(deploy_sha)"
  write_outputs
  echo "pubspec.yaml did not change."
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add pubspec.yaml
git commit -m "Sync pubspec version to ${release_version} [skip ci]"
git push origin "HEAD:${branch_name}"

version_changed=true
deploy_sha_output="$(deploy_sha)"
write_outputs
echo "Updated pubspec.yaml from ${current_pubspec_version} to ${target_pubspec_version}."
