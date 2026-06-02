#!/usr/bin/env bash
set -euo pipefail

: "${GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64:?Set the GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64 GitHub secret.}"

base64_decode() {
  if printf '' | base64 --decode >/dev/null 2>&1; then
    base64 --decode
  else
    base64 -D
  fi
}

printf '%s' "$GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64" | base64_decode > android/play-store-service-account.json
jq empty android/play-store-service-account.json
chmod 600 android/play-store-service-account.json
