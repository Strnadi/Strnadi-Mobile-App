#!/usr/bin/env bash
set -euo pipefail

: "${ANDROID_KEYSTORE_BASE64:?Set the ANDROID_KEYSTORE_BASE64 GitHub secret.}"
: "${ANDROID_KEYSTORE_PASSWORD:?Set the ANDROID_KEYSTORE_PASSWORD GitHub secret.}"
: "${ANDROID_KEY_PASSWORD:?Set the ANDROID_KEY_PASSWORD GitHub secret.}"
: "${ANDROID_KEY_ALIAS:?Set the ANDROID_KEY_ALIAS GitHub secret.}"
: "${GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64:?Set the GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64 GitHub secret.}"

base64_decode() {
  if printf '' | base64 --decode >/dev/null 2>&1; then
    base64 --decode
  else
    base64 -D
  fi
}

printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64_decode > android/upload-keystore.jks
chmod 600 android/upload-keystore.jks

{
  printf 'storePassword=%s\n' "$ANDROID_KEYSTORE_PASSWORD"
  printf 'keyPassword=%s\n' "$ANDROID_KEY_PASSWORD"
  printf 'keyAlias=%s\n' "$ANDROID_KEY_ALIAS"
  printf 'storeFile=../upload-keystore.jks\n'
} > android/key.properties
chmod 600 android/key.properties

printf '%s' "$GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64" | base64_decode > android/play-store-service-account.json
jq empty android/play-store-service-account.json
chmod 600 android/play-store-service-account.json
