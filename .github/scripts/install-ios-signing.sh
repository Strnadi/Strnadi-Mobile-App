#!/usr/bin/env bash
set -euo pipefail

: "${IOS_DISTRIBUTION_CERTIFICATE_BASE64:?Set the IOS_DISTRIBUTION_CERTIFICATE_BASE64 GitHub secret.}"
: "${IOS_DISTRIBUTION_CERTIFICATE_PASSWORD:?Set the IOS_DISTRIBUTION_CERTIFICATE_PASSWORD GitHub secret.}"
: "${IOS_PROVISIONING_PROFILE_BASE64:?Set the IOS_PROVISIONING_PROFILE_BASE64 GitHub secret.}"
: "${IOS_KEYCHAIN_PASSWORD:?Set the IOS_KEYCHAIN_PASSWORD GitHub secret.}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required.}"
: "${GITHUB_ENV:?GITHUB_ENV is required.}"

certificate_path="$RUNNER_TEMP/ios_distribution.p12"
profile_path="$RUNNER_TEMP/ios_profile.mobileprovision"
profile_plist_path="$RUNNER_TEMP/ios_profile.plist"
keychain_path="$RUNNER_TEMP/app-signing.keychain-db"

base64_decode() {
  if printf '' | base64 --decode >/dev/null 2>&1; then
    base64 --decode
  else
    base64 -D
  fi
}

printf '%s' "$IOS_DISTRIBUTION_CERTIFICATE_BASE64" | base64_decode > "$certificate_path"
printf '%s' "$IOS_PROVISIONING_PROFILE_BASE64" | base64_decode > "$profile_path"

security create-keychain -p "$IOS_KEYCHAIN_PASSWORD" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$IOS_KEYCHAIN_PASSWORD" "$keychain_path"
security import "$certificate_path" \
  -P "$IOS_DISTRIBUTION_CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$keychain_path"
security list-keychains -d user -s "$keychain_path" login.keychain-db login.keychain
security set-key-partition-list -S apple-tool:,apple: -s -k "$IOS_KEYCHAIN_PASSWORD" "$keychain_path"

mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
security cms -D -i "$profile_path" > "$profile_plist_path"

profile_uuid=$(/usr/libexec/PlistBuddy -c "Print UUID" "$profile_plist_path")
profile_name=$(/usr/libexec/PlistBuddy -c "Print Name" "$profile_plist_path")

cp "$profile_path" "$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"

{
  printf 'IOS_PROVISIONING_PROFILE_NAME=%s\n' "$profile_name"
  printf 'IOS_PROVISIONING_PROFILE_UUID=%s\n' "$profile_uuid"
} >> "$GITHUB_ENV"

printf 'Installed iOS provisioning profile: %s\n' "$profile_name"
