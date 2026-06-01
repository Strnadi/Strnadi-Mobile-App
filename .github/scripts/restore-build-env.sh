#!/usr/bin/env bash
set -euo pipefail

: "${BUILD_ENV_JSON_BASE64:?Set the BUILD_ENV_JSON_BASE64 GitHub secret.}"

base64_decode() {
  if printf '' | base64 --decode >/dev/null 2>&1; then
    base64 --decode
  else
    base64 -D
  fi
}

printf '%s' "$BUILD_ENV_JSON_BASE64" | base64_decode > build.env.json
jq empty build.env.json
