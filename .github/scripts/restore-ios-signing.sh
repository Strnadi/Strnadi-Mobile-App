#!/usr/bin/env bash
set -euo pipefail

certificate_base64="${IOS_DISTRIBUTION_CERTIFICATE_BASE64:-}"
certificate_password="${IOS_DISTRIBUTION_CERTIFICATE_PASSWORD:-}"
profile_base64="${IOS_APPSTORE_PROVISIONING_PROFILE_BASE64:-}"

if [[ -z "$certificate_base64" && -z "$profile_base64" ]]; then
  echo "No manual iOS signing secrets configured. Using automatic/cloud signing."
  exit 0
fi

: "${IOS_DISTRIBUTION_CERTIFICATE_BASE64:?Set IOS_DISTRIBUTION_CERTIFICATE_BASE64 or remove the partial iOS signing configuration.}"
: "${IOS_DISTRIBUTION_CERTIFICATE_PASSWORD:?Set IOS_DISTRIBUTION_CERTIFICATE_PASSWORD or remove the partial iOS signing configuration.}"
: "${IOS_APPSTORE_PROVISIONING_PROFILE_BASE64:?Set IOS_APPSTORE_PROVISIONING_PROFILE_BASE64 or remove the partial iOS signing configuration.}"

base64_decode() {
  if printf '' | base64 --decode >/dev/null 2>&1; then
    base64 --decode
  else
    base64 -D
  fi
}

signing_dir="${RUNNER_TEMP:-/tmp}/ios-signing"
mkdir -p "$signing_dir"

certificate_path="$signing_dir/distribution.p12"
profile_path="$signing_dir/appstore.mobileprovision"
profile_plist_path="$signing_dir/appstore-profile.plist"
keychain_path="$signing_dir/signing.keychain-db"
keychain_password="$(openssl rand -hex 24)"

printf '%s' "$certificate_base64" | base64_decode > "$certificate_path"
chmod 600 "$certificate_path"

printf '%s' "$profile_base64" | base64_decode > "$profile_path"
chmod 600 "$profile_path"

security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"

existing_keychains="$(security list-keychains -d user | tr -d '"')"
# shellcheck disable=SC2086
security list-keychains -d user -s "$keychain_path" $existing_keychains

security import "$certificate_path" \
  -k "$keychain_path" \
  -P "$certificate_password" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/xcodebuild

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$keychain_password" \
  "$keychain_path"

security cms -D -i "$profile_path" > "$profile_plist_path"
profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$profile_plist_path")"
profile_name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$profile_plist_path")"

profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$profiles_dir"
cp "$profile_path" "$profiles_dir/$profile_uuid.mobileprovision"

{
  printf 'IOS_PROVISIONING_PROFILE_SPECIFIER=%s\n' "$profile_name"
  printf 'IOS_SIGNING_KEYCHAIN_PATH=%s\n' "$keychain_path"
} >> "$GITHUB_ENV"

echo "Installed iOS App Store provisioning profile: $profile_name"
